# 能力扩展指南（侵入性最小做法）

> **回答一个问题**：我有一堆未来要加的技能（冲撞、移形、换位、护盾、复活、嘲讽…），  
> 怎么加？要改几个地方？AI 要不要重写？

---

## TL;DR

```
✅ 已具备：声明式骨架（kind / targeting / ai_hint / EffectSpec）
✅ 已具备：AI 不认技能名，只看 ai_hint → 加新 buff/debuff 零侵入
⚠️  缺口：位移类（冲撞/移形/换位）没有标准化的「移动效果」层

→ 一次性补一个 MovementSpec 抽象层，之后加位移技能也是「填资源 + 评分提示」。
```

---

## 一、当前能力系统的扩展能力（已实现）

### 1.1 声明式技能骨架

加一个**纯 buff/debuff 类技能**目前需要做的事：

```gdscript
# scripts/core/abilities/specific/AbilityRallyCry.gd
extends Ability
class_name AbilityRallyCry

func _init():
    id = "rally_cry"
    display_name = "战吼"
    kind = _Enums.Kind.BUFF
    targeting = _Enums.Targeting.ALLIES_IN_RANGE
    ap_cost = 4
    range_hexes = 2
    ai_hint = {
        "priority": "buff",
        "prefers": "clustered",     # 队友越聚越合算
        "risk": "low",
        "situational": 5.0,
    }

func gather_effect_specs(user, targets, context):
    var specs = []
    for t in targets:
        specs.append(AbilityEffectSpec.buff("rallied", t, user, 2))
    return specs
```

**就这么多**。没有改 AI 代码、没有改 BattleScene、没有改 DamageSystem。

### 1.2 AI 自动识别（已经接好的链路）

```
AI 决策时：
  for ability in unit.get_available_abilities():
      score = base_score(ability) × ai_hint_multiplier(ability.ai_hint, target_state)
      candidates.append(USE_ABILITY(ability, target, score))

  → AI 不认"战吼"这个名字，看到 ai_hint.priority=="buff" + prefers=="clustered"
  → 自动给"队友聚集时使用"加分
```

加新 buff/debuff 永远只是**填表**——这部分扩展性是 OK 的。

---

## 二、当前缺口：位移类技能（你举的例子）

### 2.1 为什么位移类不一样

| 类型 | 改什么 | 当前抽象层 |
|---|---|---|
| 普攻 | HP / 护甲 / 状态 | `DamageSystem.execute_attack` ✅ |
| Buff/Debuff | EffectStats fold | `EffectSpec` + `CombatEffect` ✅ |
| **位移** | **axial_pos**（坐标） | **没有标准化层** ❌ |

冲撞、移形、换位、击退、突进、拉拽——它们的共同点是**改 unit.axial_pos**，但每个技能的：
- 触发方式（主动用 / 攻击附带）
- 移动规则（强制 / 可选 / 路径限制）
- 失败处理（撞墙 / 撞队友 / 出界）

都不一样。如果每个都自己写 `unit.axial_pos = xxx`，代码会散得一塌糊涂。

### 2.2 你举的两个例子分析

**冲撞（Bash / Knockback）**
```
触发：主动技 + 攻击附带（命中后击退）
规则：目标沿 攻击者→目标 方向后退 1 格
失败：后方有单位 → 双方各受 8 伤害（连锁规则可选）
     后方有墙   → 不位移，目标受额外 5 伤
```

**移形（Phase Step）**
```
触发：主动技
规则：选 1 个 3 格内空格，瞬移过去
特殊：无视 ZoC（不触发借机攻击）
     无视障碍（穿墙、穿单位）
失败：目标格被占 → 技能不可用
```

这两个技能差异极大，但**抽象一致**：「把某个单位移动到某个格子，按某种规则」。

---

## 三、推荐补丁：MovementSpec 抽象层

### 3.1 设计

参考 `EffectSpec` 的成功，给位移做一个**声明式描述**：

```gdscript
# scripts/core/abilities/AbilityMovementSpec.gd
extends RefCounted
class_name AbilityMovementSpec

enum Kind {
    TELEPORT,        # 瞬移：忽略路径、ZoC、障碍（移形、滑步、战术跳跃）
    PUSH,            # 击退：单向推（推撞、扫杆逼退、冲锋推退）
    PULL,            # 拉拽：单向拉（擒拿拉拽）
    SWAP,            # 换位：两单位互换（换位）
    DASH,            # 突进：沿路径移动，触发 ZoC（突击冲锋、骑乘冲锋）
}

# 通用字段
var kind: int = Kind.TELEPORT
var unit = null                   # 被移动的单位（自己/友/敌）
var dest: Vector2i                # 目标格（TELEPORT/SWAP 直填；PUSH/PULL/DASH 由系统算）
var distance: int = 1             # 推/拉/冲锋的格数
var ignore_zoc: bool = false      # 是否免疫借机攻击
var ignore_terrain: bool = false  # 是否无视地形阻挡（仅 TELEPORT）

# 撞击规则（PUSH/PULL/DASH）
var on_block: int = OnBlock.STOP  # 撞墙/单位时如何处理
var on_block_damage: int = 0      # 撞击伤害
var on_block_chain: bool = false  # 撞到单位时连锁后排

enum OnBlock { STOP, DAMAGE, CHAIN_PUSH }

# 配对单位（SWAP）
var partner = null                # 与 unit 互换的另一单位

# ── 工厂方法 ──
static func teleport(unit, dest, ignore_zoc=true, ignore_terrain=true):
    var s := new()
    s.kind = Kind.TELEPORT
    s.unit = unit; s.dest = dest
    s.ignore_zoc = ignore_zoc
    s.ignore_terrain = ignore_terrain
    return s

static func push(target, from_pos, distance=1, on_block_damage=0):
    var s := new()
    s.kind = Kind.PUSH
    s.unit = target
    s.distance = distance
    s.on_block_damage = on_block_damage
    s.dest = _compute_push_dest(target.axial_pos, from_pos, distance)
    return s

static func pull(target, to_pos, distance=1, ignore_zoc=true):
    var s := new()
    s.kind = Kind.PULL
    s.unit = target
    s.distance = distance
    s.ignore_zoc = ignore_zoc
    s.dest = _compute_pull_dest(target.axial_pos, to_pos, distance)
    return s

static func swap(unit_a, unit_b, ignore_zoc=true):
    var s := new()
    s.kind = Kind.SWAP
    s.unit = unit_a
    s.partner = unit_b
    s.ignore_zoc = ignore_zoc
    return s

static func dash(unit, dest, ignore_zoc=false):
    var s := new()
    s.kind = Kind.DASH
    s.unit = unit; s.dest = dest
    s.ignore_zoc = ignore_zoc
    return s
```

### 3.2 一个 MovementSystem 处理所有位移

```gdscript
# scripts/core/MovementSystem.gd
class_name MovementSystem

static func execute(spec: AbilityMovementSpec, hex_grid) -> Dictionary:
    match spec.kind:
        Kind.TELEPORT:  return _do_teleport(spec, hex_grid)
        Kind.PUSH:      return _do_push(spec, hex_grid)
        Kind.PULL:      return _do_pull(spec, hex_grid)
        Kind.SWAP:      return _do_swap(spec, hex_grid)
        Kind.DASH:      return _do_dash(spec, hex_grid)
    return { ok: false, reason: "unknown_kind" }
```

### 3.3 Ability 基类增加位移钩子

```gdscript
# Ability.gd 加一个虚函数
func gather_movement_specs(user, targets, context) -> Array:
    return []

# 默认 apply() 流程加一步
func apply(user, target, context):
    ...
    var movements = gather_movement_specs(user, targets, context)
    for m in movements:
        MovementSystem.execute(m, user.hex_grid)
    var specs = gather_effect_specs(...)  # 已有
    ...
```

### 3.4 与现有规则的边界处理（落地必看）

| 项目规则 | 与 MovementSpec 的交互 |
|---|---|
| **ZoC / 借机攻击** | `ignore_zoc=true` 跳过；`false` 走现有 `OAManager` 触发逻辑 |
| **镇阵 §5.3.1（rooted）** | 持有 `displacement_immune` 状态的单位 → MovementSpec 直接 `{ ok: false, reason: "rooted" }`，不位移 |
| **悬崖 / 水泽 / 火墙** | `MovementSystem` 落点检测 → 触发 `terrain-system.md` 的环境效果（坠落伤害 / 减速 / 火焰伤害） |
| **撞墙 / 撞单位（PUSH）** | `on_block` 决定：STOP（停在前一格）/ DAMAGE（双方各受伤）/ CHAIN_PUSH（连锁后排） |
| **目标格被占（TELEPORT）** | `_extra_can_use` 失败，技能无法使用（按 `Ability.can_use()` 现有逻辑） |
| **冲锋路径（DASH）** | 路径上有单位 → 在前一格停住 + 触发攻击（突击冲锋）/ 中断（被架枪反制） |
| **气海回旋 / 不屈 等被动** | 不影响位移本身；位移完成后由 fold 重新结算受击规则 |
| **Telemetry** | `MovementSystem.execute()` 写 `combat_log`：`[movement] type=push unit=A from=(2,3) to=(2,4) blocked=false` |
| **AP 消耗时机** | Ability 的 `spend_resources()` 已扣 AP；MovementSpec **不再扣 AP**（只改坐标） |
| **气力** | 同上，不在 MovementSpec 层处理；走 Ability 的 `stamina_cost_extra` |

**关键原则**：MovementSpec 是 **声明式数据**，`MovementSystem` 是 **纯执行器**。  
所有「该不该位移、有没有借机、撞到怎么办」的判断都集中在 `MovementSystem.execute()` 一处，避免散落在各技能文件里。

---

## 四、补丁后：加项目真实位移技能多简单

下面是 `class-system.md` 中已经设计好的位移类技能，落到补丁后的代码是这样的：

### 4.1 突击冲锋（跳荡 §5.5，HYBRID + DASH）

```gdscript
extends Ability
class_name AbilityChongfeng

func _init():
    id = "tu_ji_chong_feng"
    display_name = "突击冲锋"
    kind = _Enums.Kind.HYBRID          # 移动 + 攻击
    targeting = _Enums.Targeting.SINGLE_ENEMY
    weapon_filter = ["short_spear"]    # 短矛专属
    ap_cost = 0                         # 攻+2，由武器派生
    range_hexes = 4                     # 包含冲锋距离
    ai_hint = {
        "priority":   "positioning",   # AI 走 reposition 评分
        "prefers":    "armored",       # 破阵专长
        "risk":       "medium",
        "situational": 12.0,
    }

func gather_movement_specs(user, targets, context):
    # 朝目标方向走 ≥2 格再到攻击位置
    var dest = _calc_charge_landing(user, targets[0], min_dist=2)
    return [
        AbilityMovementSpec.dash(user, dest, ignore_zoc=false)
    ]

func _apply_attack(user, target, context):
    return DamageSystem.execute_attack(user, target, {})

# 分支 A 制敌：撞墙/单位 → 眩晕（额外 EffectSpec）
func gather_effect_specs(user, targets, context):
    if context.get("hit_wall", false):
        return [AbilityEffectSpec.debuff("stunned", targets[0], user, 1)]
    return []
```

### 4.2 换位（§5.4 通用辅助 + 押衙护卫专用 SWAP）

```gdscript
extends Ability
class_name AbilityHuanwei

func _init():
    id = "huan_wei"
    display_name = "换位"
    kind = _Enums.Kind.UTILITY
    targeting = _Enums.Targeting.SINGLE_ALLY
    ap_cost = 2
    range_hexes = 1                     # 仅相邻友军
    ai_hint = {
        "priority":   "positioning",
        "prefers":    "low_hp_ally",   # 把残血队友换走
        "risk":       "low",            # 不触发借机
        "situational": 8.0,
    }

func gather_movement_specs(user, targets, context):
    var ally = targets[0]
    return [AbilityMovementSpec.swap(user, ally, ignore_zoc=true)]
```

### 4.3 滑步（§5.4 通用，TELEPORT 短距）

```gdscript
extends Ability
class_name AbilityHuabu

func _init():
    id = "hua_bu"
    display_name = "滑步"
    kind = _Enums.Kind.UTILITY
    targeting = _Enums.Targeting.NONE
    ap_cost = 2                         # 学了身法精通则 -1
    range_hexes = 1
    ai_hint = {
        "priority":   "positioning",
        "prefers":    "in_zoc",        # 被 ZoC 缠住时用
        "risk":       "low",
        "situational": 6.0,
    }

func gather_movement_specs(user, targets, context):
    var dest = context.get("target_tile")
    return [AbilityMovementSpec.teleport(user, dest, ignore_zoc=true)]
```

### 4.4 推撞（§六 通用辅助 PUSH）

```gdscript
extends Ability
class_name AbilityTuizhuang

func _init():
    id = "tui_zhuang"
    display_name = "推撞"
    kind = _Enums.Kind.UTILITY
    targeting = _Enums.Targeting.SINGLE_ENEMY
    ap_cost = 4
    range_hexes = 1
    ai_hint = {
        "priority":   "positioning",
        "prefers":    "near_terrain_hazard",  # 推下悬崖/水/火
        "risk":       "low",
        "situational": 5.0,
    }

func _extra_can_use(user, target):
    # 自身 Move ≥ 目标 Move
    return user.stats.move >= target.stats.move

func gather_movement_specs(user, targets, context):
    return [
        AbilityMovementSpec.push(
            targets[0], from_pos=user.axial_pos, distance=1,
            on_block_damage=0  # 撞到则停，无伤
        )
    ]
```

### 4.5 擒拿拉拽（§六 通用辅助 PULL）

```gdscript
extends Ability
class_name AbilityQinna

func _init():
    id = "qin_na"
    display_name = "擒拿拉拽"
    kind = _Enums.Kind.UTILITY
    targeting = _Enums.Targeting.SINGLE_ENEMY
    weapon_filter = ["rope", "whip"]   # 绳索/鞭
    ap_cost = 3
    range_hexes = 2                     # 拉 1-2 格
    ai_hint = {
        "priority":   "positioning",
        "prefers":    "isolated",      # 拉单个目标进围杀圈
        "risk":       "medium",
        "situational": 10.0,            # 拉到我方 AOE 区
    }

func _extra_can_use(user, target):
    return target.weight() <= user.weight() * 1.5

func gather_movement_specs(user, targets, context):
    return [
        AbilityMovementSpec.pull(
            targets[0], to_pos=user.axial_pos, distance=2,
            ignore_zoc=true
        )
    ]
```

### 4.6 骑乘冲锋（铁骑 §5.6，HYBRID + DASH 长距）

```gdscript
extends Ability
class_name AbilityQichengChongfeng

func _init():
    id = "qi_cheng_chong_feng"
    display_name = "骑乘冲锋"
    kind = _Enums.Kind.HYBRID
    targeting = _Enums.Targeting.SINGLE_ENEMY
    weapon_filter = ["mashuo"]          # 马槊专属
    ap_cost = 5
    range_hexes = 8                     # ≥3 格直线冲锋
    ai_hint = {
        "priority":   "positioning",
        "prefers":    "frontline",     # 撞开盾墙 / 重步兵
        "risk":       "high",           # 被架枪反制
        "situational": 25.0,            # 破阵价值极高
    }

func _extra_can_use(user, target):
    # 必须有 ≥3 格直线助跑
    return _has_straight_line(user, target, min_steps=3)

func gather_movement_specs(user, targets, context):
    var dest = _line_landing(user, targets[0])
    return [AbilityMovementSpec.dash(user, dest, ignore_zoc=false)]

func _apply_attack(user, target, context):
    var dist = _charge_distance(user, target)
    return DamageSystem.execute_attack(user, target, {
        "damage_mult": 1.0 + 0.08 * dist,   # 每格 +8%
        "knockback": 1                       # 命中击退 1 格
    })
```

**改动总结**：
- ✅ 6 个完全不同的位移技能，每个 30~40 行 Resource 文件
- ✅ 复用同一个 `MovementSpec` 抽象 + `MovementSystem` 执行器
- ❌ AI 评分代码：**0 改动**（全部走 `score_positioning`）
- ❌ BattleScene：**0 改动**
- ❌ DamageSystem：**0 改动**（HYBRID 类才调用，且复用现有接口）

---

## 五、AI 自动识别位移类技能

`ai_hint.priority="positioning"` 让 AI 评分系统识别这是个**位移类技能**，自动按以下方式打分（无需为每个技能单独写）：

```gdscript
# scripts/ai/scoring/ability_scorer.gd
static func score_positioning(ability, user, view) -> float:
    var s = 0.0

    # 推/拉敌人 → 推回 ZoC 内 / 推下悬崖 / 推到火圈
    if ability.movement_kind in [PUSH, PULL]:
        for enemy in view.alive_enemies_in_range(user, ability.range):
            s += _evaluate_displacement(user, enemy, ability) # 通用评分

    # 自己瞬移 → 残血逃命 / 进入射程 / 抢高地
    if ability.movement_kind == TELEPORT:
        for tile in view.reachable_tiles(ability.range):
            s = max(s, _evaluate_self_teleport(user, tile, view))

    return s + ability.ai_hint.situational
```

新加技能时**填 `ai_hint`，AI 自动套用通用评分公式**，零改动。

---

## 六、改动清单（一次性补完）

补这一波后，未来加 30 个技能都是「填资源」级别的工作。

### Phase 2.5 P0：能力系统位移层补丁

| # | 文件 | 改动 | 工作量 |
|---|---|---|---|
| 1 | `scripts/core/abilities/AbilityMovementSpec.gd` | 新增（5 种位移类型） | 0.5h |
| 2 | `scripts/core/MovementSystem.gd` | 新增（执行位移规则） | 1h |
| 3 | `scripts/core/abilities/Ability.gd` | 加 `gather_movement_specs()` 钩子 | 0.5h |
| 4 | `scripts/ai/scoring/ability_scorer.gd` | 加 `score_positioning()` | 1h |
| 5 | `scripts/ai/behaviors/behavior_ability.gd` | AI 评分驱动 ability 候选 | 1h |
| 6 | 测试：3~5 个示例技能 | Bash / PhaseStep / Swap | 1.5h |

### Phase 2.5 P1：第一批技能落地（class-system 已设计，用补好的层）

#### 位移类（依赖 MovementSpec 层）

| 技能（来源） | 职业 | 类型 | 工作量 |
|---|---|---|---|
| 突击冲锋（§5.5） | 跳荡 | HYBRID + DASH | 0.5h |
| 换位（§5.4 通用） | 全职业 | UTILITY + SWAP | 0.5h |
| 滑步（§5.4 通用） | 全职业 | UTILITY + TELEPORT | 0.5h |
| 推撞（§六 位移池） | 跳荡/奇兵 | UTILITY + PUSH | 0.5h |
| 擒拿拉拽（§六 位移池） | 不良人 | UTILITY + PULL | 0.5h |
| 战术跳跃（§六 位移池） | 不良人/游侠 | UTILITY + TELEPORT | 0.5h |
| 骑乘冲锋（§5.6） | 铁骑 | HYBRID + DASH | 0.5h |
| 扫杆逼退（§5.10） | 双手矛 | HYBRID + PUSH | 0.5h |
| 冲锋推退（§六） | 长矛/战斧 | HYBRID + PUSH | 0.5h |
| 瞬步惊芒（§5.7 剑系） | 剑使用者 | HYBRID + TELEPORT | 0.5h |

#### 援助类（仅依赖 EffectSpec 层，已就绪）

| 技能 | 职业 | 类型 | 工作量 |
|---|---|---|---|
| 持盾护卫（§5.12） | 跳荡/枪兵/押衙 | BUFF/UTILITY 双分支 | 1h |
| 嘲讽（§5.5） | 跳荡 | DEBUFF | 0.5h |
| 振奋军心（§5.4） | 全职业 | BUFF (AOE) | 0.5h |
| 标记（§5.5） | 斥候 | DEBUFF | 0.5h |
| 包扎（§5.4） | 全职业 | UTILITY | 0.5h |
| 督战斩（§5.6） | 虞候 | HYBRID + 杀敌触发 | 0.5h |

#### 防御类

| 技能 | 职业 | 类型 | 工作量 |
|---|---|---|---|
| 镇阵（§5.3.1） | 跳荡/枪兵/押衙 | BUFF (SELF) + immobilize | 0.5h |
| 架枪（§5.10） | 单手矛 | UTILITY (反应技) | 1h |
| 盾牌格挡（§5.12） | 持盾职业 | BUFF (SELF) | 0.5h |

**补 MovementSpec 层 5h + 19 技能 ≈ 11h ≈ 1.5 工作日落地全套核心技能**。  
之后陌刀手、悍卒、僧兵、诗剑仙等职业的剩余技能都是「填表」级别。

---

## 七、与三角战略的对照

三角战略 30 个角色 × 5~8 技能 = 约 200 个技能数据。如果每个技能要改 AI 代码，绝对崩盘。它们的做法（推断）：

```
能力数据驱动（JSON / Resource）
  ↓
统一执行管线：Damage / Effect / Movement / Field（地形）
  ↓
AI 不识别技能名，看 ai_hint / 元数据自动评分
```

我们的方向一致——**把"技能数量"和"AI 复杂度"解耦**。补完位移层之后，加一个新角色 5 个技能 = 写 5 个 Resource 文件，AI 自适应。

---

## 八、设计要点

| 原则 | 说明 |
|---|---|
| **数据驱动** | 技能用 Resource/JSON 定义，逻辑写在基类 |
| **声明式扩展** | 加技能 = 填 Spec（EffectSpec/MovementSpec），不写流程 |
| **AI 不认名字** | 永远只看 ai_hint，新技能填表即可 |
| **统一管线** | DamageSystem / EffectSystem / MovementSystem 三大执行器 |
| **HYBRID 组合** | 一个技能可以同时打伤害+挂 buff+触发位移，按 Spec 拼接 |

---

**文档版本**: v1.0  
**核心问题**: 加冲撞/移形等技能要改几个地方？  
**核心答案**: 补一次位移抽象层，之后每个技能 ≈ 30 行声明式 Resource。
