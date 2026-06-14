# 战斗效果系统 v1.0（CombatEffectContainer）

> **参考**：Battle Brothers `skills/skill_container.nut` + `skills/skill.nut`（本地 `~/Downloads/scripts/`，禁止入库）。
>
> **定位**：统一承载 Buff / Debuff / 伤势 / 天赋 / 装备被动 / **部分**性格数值修正；与战术 AI（`ai-system.md`）、性格结算钩子（`personality-system.md` §2.2）**解耦**。
>
> **状态效果清单 SoT**：`status-effects.md`（本文只定义**代码架构**如何承载表中条目）。

---

## 一、从 BB 借什么、不借什么

### 1.1 BB 的两层模型（复述）

| 层 | BB | 含义 |
|---|---|---|
| **存储** | `SkillContainer.m.Skills[]` | 每个 Trait / Effect / Injury / Perk 是**独立实例**，各有 `TurnsLeft`、`RageStacks` 等 |
| **结算** | `update()` → `CurrentProperties` | 从 `BaseProperties` clone，按 `Order` 遍历 `onUpdate`，**折叠成一份快照** |
| **情境** | `buildPropertiesForUse/Defense/BeingHit` | 命中瞬间再 fold 一层，供单次攻击/防御使用 |

**不是**把所有 buff 合成一个对象；是 **多实例 + 有序折叠**。

### 1.2 本作取舍

| 借鉴 | 不借鉴（Phase 2~3） |
|---|---|
| 容器 + 有序 fold + 分阶段钩子 | 武器/普攻做成 Skill（仍用 `WeaponData` + `Ability`） |
| `IsStacking` / 同 ID 刷新 | Generator 分帧评估、Heat 寻路 |
| `BusyStack` 防重入 | 80+ Behavior 级复杂联动 |
| Trait/Injury 与 Buff 同一基类 | Trait 直接改 AI（性格 v2.0 已禁止） |

---

## 二、设计目标

1. **单一入口**：`DamageSystem` / `Unit` / UI **只读**折叠后的 `EffectiveCombatStats`，不在各处 `if has_buff("dazed")`。
2. **生命周期集中**：回合开始/结束、战斗开始/结束、添加/移除，全走容器回调。
3. **与现有代码衔接**：演进 `CombatModifier.gd`，不推翻 `Stats.gd` 基础面板。
4. **性格双轨**：
   - **数值型**（如将来「蛮力：MeleeSkill-5」）→ `CombatEffect` 子类，`on_update` 写入快照；
   - **结算型**（好色、贪财）→ 仍走 `PersonalityDB.apply_combat_hooks()`，**不**进容器 fold 链（避免 AI/结算缠在一起）。
5. **可测**：容器 + fold 纯 `RefCounted`，`BattleSimHarness` 可无场景单测。

---

## 三、总体架构

```
┌─ Unit ─────────────────────────────────────────────────────────┐
│  stats: Stats              # 基础面板（装备+等级，战斗外也可读）   │
│  effect_container: CombatEffectContainer                      │
└───────────────────────────────┬──────────────────────────────┘
                                │
        ┌───────────────────────┴───────────────────────┐
        ▼                                               ▼
 CombatEffect[]（存储层）                    EffectiveCombatStats（快照层）
  - DazedEffect                               由 fold() 生成，只读
  - BleedingEffect                            UI / AI(WorldView) / DamageSystem 读此
  - ShieldWallEffect
  - PermanentInjuryEffect
  - ClumsyEffect（派生，可无实例）
        │
        │  fold 时机
        ▼
 on_container_dirty()  →  rebuild_effective()
   ① base ← Stats 导出
   ② 派生效果（气力档、手拙）inject
   ③ foreach effect by order: on_update(base)
   ④ foreach effect by order: on_after_update(base)
   → effective_stats 缓存

 命中/被瞄/受伤前（情境 fold，不污染缓存）：
   ctx ← effective_stats.clone()
   foreach: on_attack(ctx) / on_defend(ctx) / on_before_hit(ctx)
```

### 3.1 与现有模块关系

| 模块 | 关系 |
|---|---|
| `Stats.gd` | **Base** 来源：`to_combat_base()` 导出整数/浮点战斗基线 |
| `CombatModifier.gd` | **过渡期保留**；M1 起标记 `@deprecated`，逻辑迁入 `EffectiveCombatStats` |
| `DamageSystem.gd` | 读 `unit.get_effective_stats()`；情境 fold 在 `resolve_attack()` 内 |
| `personality-system.md` | 钩子仍在 `BattleScene` 伤害/死亡**之后**；数值性格走 Effect |
| `ai-system.md` | `WorldView` 快照含 `effective_stats` 子集，AI **不**读 Effect 列表 |
| `status-effects.md` | 每条 Buff/Debuff/伤势 = 一个 `CombatEffect` 子类或派生规则 |

---

## 四、核心类型

### 4.1 `EffectiveCombatStats`（折叠快照）

`scripts/core/EffectiveCombatStats.gd` — `RefCounted`，**无状态工具快照**。

```gdscript
# 字段分组（与 DamageSystem / UI 对齐）
var melee_skill: int
var defense: float
var hit_pct: float          # 加减百分点，汇总后 clamp
var damage_mult: float      # 连乘，默认 1.0
var damage_vs_head_mult: float
var init_bonus: int
var max_stamina_mult: float
var stamina_cost_mult: float
var can_counter: bool = true
var can_opportunity_attack: bool = true
var can_weapon_attack: bool = true
var skip_turn: bool = false
# …按 status-effects.md 扩展

func clone() -> EffectiveCombatStats
func apply_hit_pct(delta: float) -> void
func apply_damage_mult(mult: float) -> void   # *=
```

**规则**：

- 派生效果（气力档）在 fold 时**注入**，不必占 `effects[]` 槽位。
- 士气档（`morale_shaken` 等）Phase 3 前可由 `MoraleSystem` 写一个虚拟 `MoraleEffect` 实例。

### 4.2 `CombatEffect`（基类）

`scripts/core/effects/CombatEffect.gd` — `RefCounted`。

```gdscript
class_name CombatEffect

var id: String
var display_name: String
var order: int = 0           # 越小越早 on_update（对齐 BB SkillOrder）
var is_stacking: bool = false
var show_in_ui: bool = true
var turns_remaining: int = -1   # -1 = 非回合制 / 由子类管

# ── 生命周期（容器调用）──
func on_added(_container: CombatEffectContainer) -> void: pass
func on_removed() -> void: pass
func on_refresh() -> void: pass      # 同 ID 非 stacking 重复添加

func on_combat_started() -> void: pass
func on_combat_finished() -> void: pass
func on_turn_started() -> void: pass
func on_turn_ended() -> void: pass
func on_wait_turn() -> void: pass

# ── 折叠钩子 ──
func on_update(_stats: EffectiveCombatStats) -> void: pass
func on_after_update(_stats: EffectiveCombatStats) -> void: pass

# ── 情境钩子（单次攻击/防御，不改缓存）──
func on_attack(_stats: EffectiveCombatStats, _ctx: AttackContext) -> void: pass
func on_defend(_stats: EffectiveCombatStats, _ctx: AttackContext) -> void: pass
func on_before_damage_received(_stats: EffectiveCombatStats, _hit: HitInfo) -> void: pass

# ── 非数值行为（DoT 等不走 on_update）──
func on_turn_end_tick() -> void: pass   # 流血/燃烧扣血
```

`AttackContext` / `HitInfo`：与 `DamageSystem` 现有结果字典对齐的轻量 struct，避免循环依赖。

### 4.3 `CombatEffectContainer`

`scripts/core/CombatEffectContainer.gd` — 挂于 `Unit`，**每单位一个**。

```gdscript
class_name CombatEffectContainer

var _owner: Unit
var _effects: Array[CombatEffect] = []
var _pending_add: Array[CombatEffect] = []
var _busy: int = 0
var _effective: EffectiveCombatStats
var _dirty: bool = true

func add(effect: CombatEffect) -> void
func remove_by_id(id: String) -> void
func has_id(id: String) -> bool
func query(filter: int) -> Array[CombatEffect]   # 位标志：BUFF | DEBUFF | INJURY | …

func get_effective() -> EffectiveCombatStats      # 懒 rebuild
func rebuild_effective() -> void

func build_for_attack(attacker_ctx) -> EffectiveCombatStats
func build_for_defense(defender_ctx) -> EffectiveCombatStats
func build_for_being_hit(hit_ctx) -> EffectiveCombatStats

# 回合/战斗调度（由 BattleScene / TurnManager 调用）
func notify_turn_started() -> void
func notify_turn_ended() -> void
func notify_combat_started() -> void
func notify_combat_finished() -> void
```

**叠加规则**（对齐 BB）：

| 情况 | 行为 |
|---|---|
| 同 `id`，`is_stacking == false` | `on_refresh()`，不新增实例 |
| 同 `id`，`is_stacking == true` | 允许多实例（多层流血） |
| `rebuild` 重入 | `_busy++`，新 effect 进 `_pending_add`，当前 pass 结束后合并 |

**派生效果**（无实例）在 `rebuild_effective()` 固定步骤注入：

```gdscript
DerivedEffects.apply_stamina_tier(_owner.stats, base)
DerivedEffects.apply_clumsy_if(_owner, base)
```

### 4.4 `Unit` 对外 API（收敛）

```gdscript
# Unit.gd — 替换 get_active_debuffs() 散落逻辑
func get_effect_container() -> CombatEffectContainer
func get_effective_stats() -> EffectiveCombatStats

func get_status_for_ui() -> Array   # 供状态栏：effect.query(UI_VISIBLE)

# 兼容层（M1 后 @deprecated）
func get_active_debuffs() -> Array:
    return get_status_for_ui()
```

`DamageSystem` 改为：

```gdscript
var atk_stats = attacker.get_effect_container().build_for_attack(ctx)
var def_stats = target.get_effect_container().build_for_defense(ctx)
# 命中/伤害公式读 atk_stats / def_stats
```

---

## 五、效果分类与落点

| 类型 | 基类 | 数据 | 示例 |
|---|---|---|---|
| **时效 Buff/Debuff** | `CombatEffect` | 硬编码或 `data/effects.json` | 眩晕、缴械、迟缓 |
| **DoT** | `CombatEffect` + `on_turn_end_tick` | `data/effects.json` | 流血、燃烧、毒 |
| **士气档** | `MoraleEffect` | `MoraleSystem` 写入 | 动摇、惊惧、崩溃 |
| **永久伤势** | `PermanentInjuryEffect` | `data/injuries.json` | 断指、瘸腿 |
| **天赋 Trait** | `TraitEffect` | `data/traits.json`（Phase 3） | 矮小等先天（每人 **1～2**，非 JP） |
| **性格（数值）** | `TraitEffect` 或专用子类 | `personalities.json` 的 `stat_mods` | 若将来有常驻 -5 命中 |
| **性格（结算）** | **不进容器** | `personalities.json` 的 `hooks` | 好色、贪财 |
| **JP 被动 / 技能点** | `PassiveEffect` 或 Perk 注册表 | `class-system` / JP 树 | 身轻如燕、bow_mastery、双武器精通 |
| **装备/职业被动** | `PassiveEffect` | `WeaponData` / `JobClass` | 蓄力、破甲消耗型 |
| **能力 Active（瞬时）** | **不进容器** | `Ability` UTILITY | 吐纳、先发制人（改资源/AP，无持续回合） |
| **能力施加的 Buff/Debuff** | `CombatEffect` | `Ability.gather_effect_specs()` → `Unit.apply_effect_spec()` | 眩晕、战吼、涂毒、恐惧 |

**武器普攻**不注册为 Effect；`Ability` 执行时通过 `AttackContext.attack_mode` 让相关 Passive（如「蓄力」）在 `on_attack` 消费。

**Ability ↔ Effect 桥接**（详见 `ability-system.md` §三）：

1. 能力只产出 `AbilityEffectSpec`（`effect_id`、**敌/友 target**、`turns`、`polarity`）。
2. `Unit.apply_effect_spec()` → I0 后 `EffectDB.create_from_spec()` → `CombatEffectContainer.add()`。
3. 友方 buff 与敌方 debuff **同一容器、同一 fold 链**；AI 读 `EffectiveCombatStats` 快照，不读 Ability 列表。

---

## 六、数据驱动（JSON）

Phase 2.5 起，`data/effects.json` 描述**可复用** debuff 模板；脚本子类只处理特殊逻辑。

```json
{
  "effects": [
    {
      "id": "dazed",
      "display_name": "眩晕",
      "order": 200,
      "stacking": false,
      "removed_after_battle": true,
      "on_update": {
        "damage_mult": 0.75,
        "init_bonus_pct": -0.25,
        "max_stamina_mult": 0.75
      },
      "default_turns": 2
    },
    {
      "id": "bleeding",
      "display_name": "流血",
      "stacking": true,
      "dot": { "type": "hp_pct", "value": 0.05, "turns": 2 }
    }
  ]
}
```

`EffectDB.gd`（autoload 或静态）：`create_effect(id) -> CombatEffect`，优先工厂，复杂条目用 `.gd` 子类 override。

---

## 七、调度时序（与 TurnManager / BattleScene）

```
战斗开始
  └─ foreach unit: effect_container.notify_combat_started()

每回合开始（RoundManager）
  └─ （无全局 effect 事件）

单位 start_turn()
  └─ effect_container.notify_turn_started()
  └─ if effective.skip_turn: 强制结束回合

单位行动结束 end_turn()
  └─ effect_container.notify_turn_ended()
  └─ 递减 turns_remaining；到期 remove_by_id

回合结束（RoundManager）
  └─ foreach unit: on_turn_end_tick()（DoT）
  └─ collect_garbage()

战斗结束
  └─ remove 带 removed_after_battle 的 effect
  └─ notify_combat_finished()（永久伤势保留）
```

**与 `Unit.reset_turn_effects()`**：先发制人等**单回合 Unit 字段**暂保留在 `Unit`；待 `Ability` 框架稳定后迁入 `CombatEffect`（`order` 最高，回合结束 `on_turn_ended` 清除）。

---

## 八、文件结构

```
scripts/core/
  EffectiveCombatStats.gd
  CombatEffectContainer.gd
  DerivedEffects.gd              # 气力档、手拙等无实例规则
  effects/
    CombatEffect.gd              # 基类
    TimedEffect.gd               # JSON 驱动的通用时效
    DotEffect.gd
    MoraleEffect.gd
    PermanentInjuryEffect.gd
    TraitEffect.gd
    instances/                   # 不宜 JSON 化的特例
      ShieldWallEffect.gd
      ChargeEffect.gd
  data/
    EffectDB.gd                  # 读 data/effects.json

data/
  effects.json                   # Phase 2.5
  injuries.json                  # Phase 3
```

---

## 九、实施阶段

| 阶段 | 交付 | 说明 |
|---|---|---|
| **M0** | `EffectiveCombatStats` + `CombatEffectContainer` 骨架 + `DerivedEffects` | `get_effective_stats()` 替代 `get_active_debuffs()` 供 `DamageSystem` 读；行为与现网一致 |
| **M1** | `TimedEffect` + 缴械/眩晕 JSON | `status-effects.md` 中 2~3 个 debuff 实装；UI 读 `query(UI)` |
| **M2** | `DotEffect` + 回合 tick | 流血/燃烧；`BattleScene` 接调度 |
| **M2.5** | 性格钩子 **保持** `PersonalityDB`；可选 `stat_mods` 走 `TraitEffect` | 与 `personality-system.md` 验收清单并行 |
| **M3** | `PermanentInjuryEffect` + `MoraleEffect` | `status-effects.md` 伤势 + 士气五档 |
| **M4** | `TraitEffect` + `PassiveEffect` | `class-system.md` 被动 |

**本期（Phase 2）不阻塞**：M0 可在 DamageSystem 重构时一并接入；完整 Buff 列表仍按 `phase2-plan.md` 推迟到 2.5。

---

## 十、测试

```
scripts/tools/test_combat_effects.gd
```

| 用例 | 断言 |
|---|---|
| 非 stacking 同 ID 添加 | 实例数 = 1，`on_refresh` 被调 |
| stacking 流血 ×2 | DoT 叠两次 |
| fold 顺序 | `order` 小的先加命中，再乘伤害 mult |
| 气力档 + 眩晕 | 命中/伤害叠算与 `CombatModifier` 旧结果一致 |
| `build_for_attack` | 仅本次攻击含蓄力 mult，缓存不变 |
| rebuild 重入 | add  durante rebuild 不崩溃、不丢 effect |
| 战斗结束清理 | `removed_after_battle` 消失，永久伤势保留 |

---

## 十一、文档对齐

| 文档 | 关系 |
|---|---|
| `status-effects.md` | 效果**策划表**；本文是**运行时架构** |
| `personality-system.md` | 结算钩子不进容器；数值性格可走 Effect |
| `ai-system.md` | `WorldView` 读 `effective_stats` 摘要，不读 Effect 列表 |
| `class-system.md` | Ability / Passive 最终注册为 Effect 或 Ability 调用 Effect |
| `phase2-plan.md` | 伤势/大量 Buff 在 2.5；M0 不扩 scope |

---

**文档版本**：v1.0  
**最后更新**：2026-06-12
