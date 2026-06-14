# 数据驱动技能指南（Ability Data-Driven Guide）

> 适用于 Phase 2.5 之后的所有非 ATTACK 类技能。  
> 设计目标：90% 的技能用 JSON 描述（5~30 行），10% 特殊技能才落 .gd 子类。

---

## 一、何时用 JSON、何时用 .gd

### ✅ 用 JSON（首选）

满足以下**任一**条件：

- 仅施加 **位移**（推/拉/换/瞬/冲，5 种 Movement Kind 之一）
- 仅施加 **状态效果**（Buff / Debuff / Neutral，对齐 `data/effects.json`）
- 二者组合 + 简单的施法约束（武器、相邻、Move 比较）

### ⚠️ 退化为 .gd 子类

满足以下**任一**条件：

| 场景 | 原因 | 例子 |
|---|---|---|
| 走 DamageSystem 完整管线 | 攻击伤害需要派生武器属性 / 命中流程 | `BasicAttack` |
| 命中后回调（动态伤害公式 / 连锁触发） | JSON 无法描述函数式逻辑 | 骑乘冲锋每格 +8% 伤；督战斩杀敌后给队友 morale |
| 自定义 `_extra_can_use` 复杂条件 | 拼写 DSL 比写 GDScript 还累 | 长虹贯日要求直线穿透多目标 |
| 非标准 Targeting | 现有 9 种 Targeting 无法覆盖 | 扇形 AOE / 直线穿透 / 对自身+前方友军 |
| 施法过程多阶段（充能、读条、二次确认） | 状态机在 .gd 中实现更清晰 | 长读条法术 |

> **判断口诀**：能用「位移 × 效果 × 简单约束」描述的，全部走 JSON。  
> 一旦你想在 JSON 里加 `if/else` 或函数调用，立刻退化为 .gd 子类。

---

## 二、JSON Schema 完整字段

```jsonc
{
  // ─── 基础字段（必填）───
  "id":           "<unique_id>",          // 与 data/effects.json 的 id 同名空间，必须全局唯一
  "display_name": "<中文名>",
  "kind":         "UTILITY"|"BUFF"|"DEBUFF"|"HYBRID",  // ATTACK 不能用 JSON
  "targeting":    "<TargetingEnum>",      // 见 §三

  // ─── 资源消耗（按需）───
  "ap_cost":            4,                // 默认 0；0 = 子类动态
  "stamina_cost_extra": 0,                // 默认 0
  "range":              1,                // 0 = 走武器射程；其他 = 固定射程
  "weight":             0,                // 心智负载：跨职业继承时的 Wisdom 消耗
                                          //   0   = 当前占位（本职负载待定）
                                          //   10~15 = T1 基础被动/小位移
                                          //   20~30 = T2 核心战术主动
                                          //   40~50 = T3 跨兵种大招/质变被动
                                          //   60+  = T4 稀有终极技能
                                          // 详见 class-system.md §十二

  // ─── 限制（按需）───
  "weapon_filter":      ["short_spear"],  // 空 = 不限武器
  "mutex_group":        "attack",         // 与普攻互斥（每行动一次攻击类）
  "constraints": [                         // _extra_can_use 表达式（逐条 AND）
    "self.move >= target.move",
    "target.adjacent_to_self",
    "self.weapon_kind == short_spear"
  ],

  // ─── 位移规格（可选）───
  "movement": {
    "kind":           "PUSH"|"PULL"|"SWAP"|"TELEPORT"|"DASH",
    "distance":       1,                  // PUSH/PULL/DASH 用
    "ignore_zoc":     false,              // 是否免疫借机
    "ignore_terrain": false,              // 仅 TELEPORT
    "on_block":       "STOP"|"DAMAGE"|"CHAIN_PUSH",
    "on_block_damage": 0
  },

  // ─── 效果规格（可选，可多个）───
  // 给目标挂效果
  "effects": [
    { "type": "debuff", "id": "taunted",   "duration": 2 },
    { "type": "debuff", "id": "stunned",   "duration": 1, "stacks": 1 }
  ],

  // 给自己挂效果（如「镇阵」自己 rooted+displacement_immune）
  "self_effects": [
    { "type": "buff",   "id": "rooted",              "duration": 1 },
    { "type": "buff",   "id": "displacement_immune", "duration": 1 }
  ],

  // ─── AI 评分提示（可选）───
  "ai_hint": {
    "priority":    "kill"|"armor_break"|"debuff"|"buff"|"positioning"|"default",
    "prefers":     "low_hp"|"armored"|"clustered"|"isolated"|"low_hp_ally"|"near_terrain_hazard"|"...",
    "risk":        "low"|"medium"|"high",
    "situational": 5.0                    // 额外固定分加成
  }
}
```

### EffectSpec 子字段（`effects` / `self_effects` 的元素）

```jsonc
{
  "type":     "buff" | "debuff" | "neutral",  // 默认 debuff
  "id":       "<effect_id>",                  // 必填，对齐 data/effects.json
  "duration": 2,                              // 默认 1；-1 = 战斗结束
  "stacks":   1,                              // 默认 1
  "refresh":  true,                           // 已存在时是否刷新（默认 true）
  "params":   { "...": "..." }                // 透传给 CombatEffect（如 dot 倍率）
}
```

### MovementSpec 子字段（`movement`）

各 Kind 的必填项：

| Kind | 必填 | 可选 | 说明 |
|---|---|---|---|
| `PUSH` | `distance` | `on_block_damage`, `on_block` | 推方向 = `user → target`，自动算落点 |
| `PULL` | `distance` | `ignore_zoc` | 拉方向 = `target → user`，最多到 user 相邻 |
| `SWAP` | — | `ignore_zoc` | 与目标互换（仅 SINGLE_ALLY） |
| `TELEPORT` | — | `ignore_zoc`, `ignore_terrain` | 落点由 UI/AI 在 context.target_tile 提供 |
| `DASH` | — | `ignore_zoc` | 落点同上；路径由 MovementSystem 计算 |

> **TELEPORT/DASH 的落点哪里来**：施法时由调用方在 `context.target_tile` 传入。  
> UI：玩家点击目标格 → context；  
> AI：`AIBehavior_Reposition` 评估候选落点 → context（Phase 2.5 P1 实现）。

---

## 三、Targeting 枚举

| 取值 | 含义 | 典型技能 |
|---|---|---|
| `NONE` | 无目标（地形覆盖、被动） | 元素地形 |
| `SELF` | 仅自身 | 镇阵、吐纳、蓄力 |
| `SINGLE_ALLY` | 单体友军 | 换位、持盾护卫、振奋 |
| `SINGLE_ENEMY` | 单体敌军 | 推撞、嘲讽、擒拿 |
| `SINGLE_ANY` | 任意存活单位 | 极少用 |
| `ALL_ALLIES` | 全体友军 | 全军鼓舞 |
| `ALL_ENEMIES` | 全体敌军 | 恐惧光环 |
| `ALLIES_IN_RANGE` | 范围内友军 | 振奋军心（含自身）|
| `ENEMIES_IN_RANGE` | 范围内敌军 | AOE debuff |

> **范围**：`range` 字段对 `*_IN_RANGE` 类生效；`get_range(user)` 在 .gd 基类实现。

---

## 四、Constraints 支持的表达式

> 极简关键字匹配，**不是 DSL**。需要更复杂条件 → 退化 .gd 子类。

| 表达式 | 含义 |
|---|---|
| `target.adjacent_to_self` | 目标必须相邻（距离 = 1） |
| `self.move >= target.move` | 自身 Move 不低于目标（推撞约束） |
| `self.weapon_kind == <x>` | 武器类型限制（如 `short_spear`） |
| `self.weapon_id == <x>` | 武器 id 精确匹配 |
| `target.faction != self.faction` | 目标必须是敌人（基类已隐式检查） |

未识别的约束会 `push_warning` 但**保守通过**（避免 typo 一票否决）。

要扩展约束词表：
1. 在 `GenericAbility._eval_constraint()` 加新分支
2. 在本表追加描述
3. 控制总条数 ≤ 10 条；超过即应转 .gd

---

## 五、加技能的标准流程

### 流程 A：JSON 技能（90% 场景）

1. 在 `data/abilities.json` 加一段 JSON
2. 跑 `bash tools/run_tests.sh --quick` 确保不退化
3. 完成

```json
"jia_qiang": {
  "id": "jia_qiang",
  "display_name": "架枪",
  "kind": "BUFF",
  "targeting": "SELF",
  "ap_cost": 3,
  "weapon_filter": ["short_spear", "long_spear"],
  "self_effects": [
    { "type": "buff", "id": "spear_brace", "duration": 1 }
  ],
  "ai_hint": { "priority": "default", "risk": "low", "situational": 8.0 }
}
```

### 流程 B：.gd 子类（10% 场景）

1. `scripts/core/abilities/<Name>.gd` 继承 `Ability`
2. override `_apply_attack` / `_extra_can_use` / `gather_*_specs`
3. `AbilityLibrary._register_native()` 加一行注册
4. 跑测试

> **大多数情况你应该先尝试 JSON 方案**。只有当 JSON 表达不动你的需求时才退化。

---

## 六、与 `data/effects.json` 的关系

- `effects` 字段里的 `id` **必须**对齐 `data/effects.json`（CombatEffect 模板）
- JSON 技能不创造新效果；如果要新效果（例如新 buff `spear_brace`），先在 `effects.json` 注册，再在技能里引用
- 这保证了「同一个状态由谁施加都一致」

---

## 七、与 IntentWeights / AI 的关系

- `ai_hint.priority` 决定 AI 评分时的偏好类型，但**不决定 category**
- AI 的 5 类 category（attack/defend/support/reposition/retreat）由 `Behavior` 定，不是 Ability 定
- 一个技能可以同时被多个 Behavior 候选评估（如「推撞」既是 reposition 候选也可作为 attack 替代）

> 详见 [`design/ai-decision-logic.md`](ai-decision-logic.md)。

---

## 八、调试 / 热重载

```gdscript
# 控制台 / 测试代码
AbilityLibrary.reload()           # 清空缓存重读 JSON
AbilityLibrary.ids()              # 列出所有 id
AbilityLibrary.get("tui_zhuang")  # 按 id 取实例
```

未来可加：开发者快捷键 F12 → AbilityLibrary.reload()。

---

## 九、典型错误清单

| 症状 | 根因 |
|---|---|
| 加的 JSON 技能不出现在 `AbilityLibrary.ids()` | JSON 语法错误 / id 重复 / 文件未保存 |
| 技能能选但效果没生效 | `effects[].id` 拼写错 / `data/effects.json` 没注册该 id |
| 推撞不动 | `constraints` 里 `self.move >= target.move` 失败 |
| AI 永远不选某技能 | `ai_hint.priority` 缺失 / `Behavior` 没把它纳入候选池 |
| 位移技能崩溃 | `kind` 为 `TELEPORT` 但 `context.target_tile` 没传 |

---

**版本**：v1.0（2026-06-13）— Phase 2.5 P0 数据驱动框架落地。  
**文件**：
- 框架：`scripts/core/abilities/GenericAbility.gd`
- 加载：`scripts/core/AbilityLibrary.gd`
- 数据：`data/abilities.json`
