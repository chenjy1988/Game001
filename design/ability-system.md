# 能力系统 v1.0（Ability Framework）

> **关联**：`class-system.md` §5 职业技能 · `combat-effects-system.md` §五 效果落点 · `phase2-todo.md` C 段  
> **代码**：`scripts/core/abilities/`

---

## 一、职责边界

| 层 | 职责 | 不负责 |
|---|---|---|
| **Ability** | 一次行动的**调度**：目标解析、AP/气力、调用伤害管线或挂效果 | 效果数值 fold（交给 CombatEffect） |
| **CombatEffect** | Buff/Debuff **存储 + 折叠**（`EffectiveCombatStats`） | 选目标、扣 AP |
| **DamageSystem** | 单次攻击命中/伤害 | 持续回合、多目标 buff |

**原则**：能力可以打伤害、可以挂 buff、可以两者兼有（HYBRID）；**敌我双方**都是效果的合法承载者。

---

## 二、类型与目标

### 2.1 `AbilityEnums.Kind`

| Kind | 典型技能 | apply 路径 |
|---|---|---|
| `ATTACK` | 普攻、处决 | 子类 override `apply()` → `DamageSystem` |
| `BUFF` | 战吼、包扎、鼓舞 | 默认 `apply()` → `gather_effect_specs` |
| `DEBUFF` | 眩晕、迟缓、恐惧 | 同上，极性为 DEBUFF |
| `UTILITY` | 吐纳、先发制人、位移 | override 或默认 + 无 Effect |
| `HYBRID` | 涂毒、碎甲眩晕 | override：`DamageSystem` + `gather_effect_specs` |

### 2.2 `AbilityEnums.Targeting`

| Targeting | 说明 |
|---|---|
| `SELF` | 仅自身（吐纳、架枪姿态） |
| `SINGLE_ALLY` / `SINGLE_ENEMY` | 单体友军 / 敌军 |
| `ALL_ALLIES` / `ALL_ENEMIES` | 全场（士气类） |
| `ALLIES_IN_RANGE` / `ENEMIES_IN_RANGE` | 范围内 AOE（战吼、恐惧光环） |
| `LINE_PIERCE_ENEMY` | 单体敌军为主目标（射程常锁定为 1）；沿 `attacker → primary` 六向直线向后 1 格解析次目标敌军（见 `class-system.md` §5.10.1 长虹贯日） |

`resolve_targets()` 从 `context.all_units` 或 `hex_grid.get_all_occupants()` 收集；BattleScene 调用时传入 `all_units` 以保证 AI/玩家一致。

**直线穿透辅助**（`HexCoord`）：

```gdscript
static func extend_along(from_axial: Vector2i, through_axial: Vector2i, steps: int = 1) -> Vector2i:
    var step := through_axial - from_axial
    return through_axial + step * steps
```

---

## 三、效果施加（Buff / Debuff 扩展点）

### 3.1 声明式 `AbilityEffectSpec`

能力子类在 `gather_effect_specs()` 返回规格，**不写 fold 逻辑**：

```gdscript
func gather_effect_specs(user: Unit, targets: Array, context: Dictionary) -> Array:
	var specs: Array = []
	for t in targets:
		specs.append(AbilityEffectSpec.debuff("dazed", t, user, 2))
	return specs
```

字段：`effect_id`、`polarity`（BUFF/DEBUFF/NEUTRAL）、`target`、`source`、`turns`、`stacks`、`params`。

### 3.2 落地链（Phase 2.5）

```
Ability.apply()
  → apply_effect_specs()
    → Unit.apply_effect_spec(spec)   # 当前 stub
      → [I0] CombatEffectContainer.add(EffectDB.create_from_spec(spec))
```

- **友方 buff**、**敌方 debuff** 走同一 API；极性只影响 UI 配色与 AI 估值，不改变容器接口。
- **NEUTRAL**（破绽、标记）供 HYBRID 收割技（剑开天门）在 `query()` 中计数。

### 3.3 HYBRID 示例（涂毒）

```gdscript
func apply(user, target, context):
	if not can_use(user, target): return _fail_use(user, target)
	spend_resources(user, context)
	var dmg := _DamageSystem.execute_attack(user, target, build_damage_options(user, context))
	Unit._apply_attack_result(user, target, dmg)
	var specs := gather_effect_specs(user, [target], context)  # poison on hit
	if dmg.get("hit"):
		apply_effect_specs(user, specs, context)
	return AbilityResult.success(id, kind, { PRIMARY: dmg, ... })
```

---

## 四、返回结构 `AbilityResult`

| 键 | 含义 |
|---|---|
| `ok` | 是否成功 |
| `reason` | 失败原因 |
| `ability_id` / `kind` | 归因 |
| `targets` | 解析后的目标列表 |
| `effects_applied` | 已挂 `AbilityEffectSpec` 列表 |
| `primary` | 主伤害结果（ATTACK 兼容旧 UI / 日志） |

---

## 五、互斥与数据

- `mutex_group == "attack"`：一次行动只能选一个攻击类能力（普攻 vs 职业技能）。
- 效果模板 SoT：`data/effects.json`（I1）；能力定义 Phase 2.5 可先硬编码子类，后迁 `data/abilities.json`。
- **性格结算钩子**不进 Ability；仍走 `PersonalityDB`（见 `personality-system.md`）。

---

## 六、文件结构

```
scripts/core/abilities/
  AbilityEnums.gd          # Targeting / Kind / EffectPolarity
  AbilityEffectSpec.gd     # 声明式 buff/debuff
  AbilityMovementSpec.gd   # 声明式位移（Phase 2.5 P0 新增）
  AbilityResult.gd         # 返回字典键名
  Ability.gd               # 基类：resolve_targets / apply_effect_specs / gather_movement_specs
  BasicAttack.gd           # ATTACK 参考实现
  # Phase 2.5 示例：
  # IntimidatingShout.gd   # ENEMIES_IN_RANGE + debuff morale_shaken
  # Rally.gd               # ALL_ALLIES_IN_RANGE + buff inspired
  # Chongfeng.gd           # HYBRID + DASH（突击冲锋）
  # Huanwei.gd             # UTILITY + SWAP（换位）
  # Tuizhuang.gd           # UTILITY + PUSH（推撞）

scripts/core/MovementSystem.gd  # 位移执行器（Phase 2.5 P0 新增）
```

## 七、扩展指南（Phase 2.5 P0）

加新位移类技能（冲撞、移形、换位、擒拿、骑乘冲锋…）请参考：

- [`design/ability-extension-guide.md`](ability-extension-guide.md)
  - §三 MovementSpec 抽象层设计
  - §四 项目真实位移技能落地示例（10 个）
  - §六 改动清单（5h 补层 + 19 技能 ≈ 1.5 工作日）

加新 buff/debuff 类技能：本文档 §三 `AbilityEffectSpec` 已就绪，仿 `IntimidatingShout` 即可。

---

**版本**：v1.1（2026-06-13）— 增加 MovementSpec 与 ability-extension-guide 索引。
