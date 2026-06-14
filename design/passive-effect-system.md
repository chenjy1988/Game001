# 被动技能系统设计（PassiveEffect Registry + Hooks）

> Phase 2.5 P1+ 设计文档。  
> 目标：让 18 职业 ~50 个被动技能（铁骨 / 气海回旋 / 借势合击 / 不屈 / 健壮 / 身法精通 / 鹰眼 / 摧锋陷阵 …）能用**统一注册 + 钩子**机制实装，避免散写 if/else。  
> 配套阅读：[`design/ai-decision-logic.md`](ai-decision-logic.md) / [`design/ability-system.md`](ability-system.md) / [`design/ability-data-driven-guide.md`](ability-data-driven-guide.md)。

---

## 一、为什么需要专门的被动系统

### 1.1 主动技能 vs 被动技能的本质区别

| 维度 | 主动技能（Active Ability） | 被动技能（Passive Effect） |
|---|---|---|
| **触发** | 玩家/AI 选择并消耗 AP | 自动条件触发（攻击时 / 受击时 / 移动时 / 永久） |
| **入口** | `Unit.use_ability()` | DamageSystem / Ability / Movement 内部钩子 |
| **生命周期** | 一次性结算 | 战斗中持久（除非被驱散） |
| **数据形态** | `Ability` 实例 | **修正描述符**（CombatModifier 子类型） |
| **AI 关注** | 候选池 + 评分 | 间接通过修正后的数值评估 |

### 1.2 当前已有的"被动样品"

项目已经为 Phase 2 实装了 3 个被动样品，但**散落在各处**：

| 已有"被动" | 实现位置 | 问题 |
|---|---|---|
| 气力档 (fresh/tired/exhausted) | `CombatModifier.stamina_tier_for()` | 写死在 Unit.get_active_debuffs() 里 |
| 手拙 (clumsy) | `CombatModifier.clumsy()` | 装备非熟练武器时手动塞 |
| 缴械 (disarmed) | `CombatModifier.disarmed()` | 由 status-effects 状态机塞 |

这套已经验证了 fold 思路有效（命中/防御/伤害修正能正确生效），但**缺少注册系统 + 触发条件抽象**——再加 5 个被动就要在 `get_active_debuffs()` 里堆 5 个 if。

### 1.3 设计目标

1. **声明式**：被动技能像 Ability 一样，能用 JSON / Resource 描述，不写过程代码
2. **可叠加**：复用现有 `CombatModifier` fold 管线（已被 DamageSystem 验证）
3. **可触发**：支持「永久」「条件触发」「事件触发」三类
4. **可扩展**：未来加新钩子（移动 AP、武器气力、暴击伤害…）只在一处声明
5. **AI 友好**：被动产生的数值修正自动被 AI 评估系统读到

---

## 二、整体架构

```
┌──────────────────────────────────────────────────────────────┐
│  PassiveLibrary（注册中心，类似 AbilityLibrary）             │
│  └── data/passives.json + .gd 子类（特殊触发逻辑）           │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼ Unit.passives = ["jie_shi_he_ji", "ye_zhan_ba_fang", ...]
┌──────────────────────────────────────────────────────────────┐
│  Unit （持有当前激活的被动 id 列表）                         │
│  ├── has_passive(id)                                         │
│  ├── add_passive(id) / remove_passive(id)                    │
│  └── get_active_passives() → Array[PassiveEffect]            │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼ 评估
┌──────────────────────────────────────────────────────────────┐
│  PassiveEffect（被动描述符，扩展 CombatModifier）            │
│  ├── 静态字段：hit_pct / defense_flat / damage_mult ...     │
│  ├── 触发条件：trigger_when（永久 / HP < 30% / 装甲 ≥ 30 …）│
│  └── 钩子声明：hooks（armor_damage_mult / movement_ap_mod …）│
└──────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
    DamageSystem        Ability/Movement    Special Hooks
    （命中/伤害）        （AP/气力）         （暴击/位移规则）
```

**核心思想**：PassiveEffect = CombatModifier + 触发条件 + 扩展钩子。  
不重新发明轮子，只在现有 fold 管线基础上加一层「按条件激活」的注册器。

---

## 三、数据层设计

### 3.1 `data/passives.json` Schema

```jsonc
{
  "_doc": "被动技能数据驱动定义。复杂触发逻辑请退化为 .gd 子类。",

  // ───── 永久被动（学了就一直生效）─────
  "jian_zhuang": {
    "id": "jian_zhuang",
    "display_name": "健壮",
    "kind": "permanent",                    // permanent / conditional / triggered
    "modifiers": {
      "hp_max_pct": 0.25,                   // HP 上限 +25%
      "wound_threshold_pct": -0.33          // 伤势检定阈值 -33%
    },
    "ai_hint": { "category": "tank" }
  },

  // ───── 条件被动（满足条件时才生效）─────
  "tie_gu": {
    "id": "tie_gu",
    "display_name": "铁骨",
    "kind": "conditional",
    "trigger_when": "self.total_armor_weight >= 30",
    "modifiers": {
      "armor_damage_mult": 0.85             // 受击时护甲伤害 ×0.85
    },
    "mutex_with": ["qi_hai_hui_xuan"],      // 与气海回旋互斥
    "ai_hint": { "category": "tank" }
  },

  "qi_hai_hui_xuan": {
    "id": "qi_hai_hui_xuan",
    "display_name": "气海回旋",
    "kind": "conditional",
    "trigger_when": "self.total_armor_weight < 30",
    "trigger_phase": "on_take_hit",         // 仅受击时生效（不是永久）
    "stamina_cost_per_trigger": 5,           // 每次触发耗 5 气
    "modifiers": {
      // 公式较复杂，用 formula 字段（GenericPassive 内置 mini-DSL）
      "damage_taken_pct_formula": "min(0.20 + (20 - armor_weight) * 0.01 + (stamina / max(1, armor_weight^2)), 0.60)"
    },
    "mutex_with": ["tie_gu"],
    "ai_hint": { "category": "tank" }
  },

  "bu_qu": {
    "id": "bu_qu",
    "display_name": "不屈",
    "kind": "conditional",
    "trigger_when": "self.hp_ratio < 0.30",
    "modifiers": {
      "defense_flat": 10.0,                 // Defense +10
      "resolve_flat": 15.0                  // Resolve +15
    }
  },

  // ───── 事件触发被动（特定事件发生时一次性触发）─────
  "shan_ji": {
    "id": "shan_ji",
    "display_name": "闪击",
    "kind": "triggered",
    "trigger_event": "on_dodge_success",   // 闪避成功后
    "action": {
      "type": "counter_attack",
      "damage_mult": 0.5
    }
  },

  "chu_jue": {
    "id": "chu_jue",
    "display_name": "处决",
    "kind": "triggered",
    "trigger_event": "on_kill",
    "action": {
      "type": "restore_ap",
      "amount": 4,
      "limit_per_turn": 1
    }
  },

  // ───── 钩子型被动（修改特定公式）─────
  "shen_fa_jing_tong": {
    "id": "shen_fa_jing_tong",
    "display_name": "身法精通",
    "kind": "permanent",
    "hooks": [
      {
        "hook": "ability_ap_cost",
        "condition": "ability.has_tag('displacement')",
        "modifier": { "delta": -1, "min": 1 }
      },
      {
        "hook": "ability_stamina_cost",
        "condition": "ability.has_tag('displacement')",
        "modifier": { "mult": 0.8 }
      }
    ]
  },

  "jie_shi_he_ji": {
    "id": "jie_shi_he_ji",
    "display_name": "借势合击",
    "kind": "permanent",
    "hooks": [
      {
        "hook": "self_overwhelm_bonus",     // 仅改持有者自己的围攻系数
        "condition": "context.overwhelm_count >= 1",
        "modifier": { "per_ally": 0.08, "cap": 0.24 }  // 替代默认 0.05/0.20
      }
    ],
    "ai_hint": { "category": "low_melee_rescue" }
  },

  // ───── 受击侧被动 ─────
  "ye_zhan_ba_fang": {
    "id": "ye_zhan_ba_fang",
    "display_name": "野战八方",
    "kind": "permanent",
    "hooks": [
      {
        "hook": "incoming_overwhelm_bonus", // 攻击者打你时，对方的围攻加值清零
        "modifier": { "set": 0.0 }
      }
    ]
  }
}
```

### 3.2 字段约定

| 字段 | 必填 | 含义 |
|---|---|---|
| `id` | ✅ | 全局唯一 id |
| `display_name` | ✅ | UI 显示名 |
| `kind` | ✅ | `permanent` / `conditional` / `triggered` 三选一 |
| `trigger_when` | conditional 必填 | 条件表达式（白名单关键字） |
| `trigger_event` | triggered 必填 | 事件名（`on_kill` / `on_dodge_success` / ...） |
| `trigger_phase` | 可选 | 限定触发阶段（`on_take_hit` / `on_attack` / 等） |
| `modifiers` | 可选 | 静态修正字段（fold 进 CombatModifier） |
| `hooks` | 可选 | 自定义钩子修正（特殊公式） |
| `mutex_with` | 可选 | 互斥被动 id 列表（`tie_gu` ⇄ `qi_hai_hui_xuan`） |
| `stamina_cost_per_trigger` | 可选 | 每次触发的气力成本 |
| `ai_hint` | 可选 | AI 评估提示（`category: tank/dps/support/...`） |

---

## 四、代码层设计

### 4.1 文件结构

```
scripts/core/passives/
  PassiveEffect.gd          # 被动效果基类（扩展 CombatModifier）
  GenericPassive.gd         # 数据驱动通用被动
  PassiveLibrary.gd         # 注册中心（仿 AbilityLibrary）
  PassiveCondition.gd       # 触发条件求值器（mini DSL）
  PassiveHookRegistry.gd    # 钩子注册中心
  
scripts/core/passives/specials/
  PassiveQiHaiHuiXuan.gd    # 气海回旋（公式复杂，.gd 子类）
  PassiveChuJue.gd          # 处决（事件回调，.gd 子类）
  PassiveShanJi.gd          # 闪击（闪避反击，.gd 子类）
  ...

data/passives.json           # 数据驱动被动配置
```

### 4.2 PassiveEffect 基类（扩展 CombatModifier）

```gdscript
# scripts/core/passives/PassiveEffect.gd
extends RefCounted
class_name PassiveEffect

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")

## 与 CombatModifier 同语义的字段（可直接 fold 进 DamageSystem）
var id: String = ""
var display_name: String = ""

# ── fold 字段（与 CombatModifier 1:1 对齐）──
var hit_pct: float = 0.0
var defense_flat: float = 0.0
var defense_pct: float = 0.0
var damage_mult_min: float = 1.0
var damage_mult_max: float = 1.0
var stamina_cost_mult: float = 1.0
# 新增 fold 字段
var armor_damage_mult: float = 1.0       ## 受击时护甲伤害倍率（铁骨）
var damage_taken_mult: float = 1.0       ## 受击 HP 伤害倍率（镇阵 / 气海回旋）
var hp_max_pct: float = 0.0              ## HP 上限 % 修正（健壮）
var resolve_flat: float = 0.0            ## Resolve flat 修正（不屈）
var wound_threshold_pct: float = 0.0     ## 伤势阈值修正（健壮）

# ── 触发条件 ──
var kind: String = "permanent"           ## permanent / conditional / triggered
var condition_expr: String = ""          ## conditional 用
var trigger_event: String = ""           ## triggered 用
var trigger_phase: String = ""           ## 可选限定阶段
var stamina_cost_per_trigger: int = 0
var mutex_with: Array = []

# ── 钩子（自定义公式）──
var hooks: Array = []                    ## 每项 = { hook: String, condition: String, modifier: Dictionary }

# ── 元信息 ──
var source: String = ""                  ## job / weapon_jp / trait
var ai_hint: Dictionary = {}


## 当前是否激活（在给定 unit + context 下）
func is_active(unit, context: Dictionary = {}) -> bool:
    if kind == "permanent":
        return true
    if kind == "conditional":
        return PassiveCondition.eval(condition_expr, unit, context)
    if kind == "triggered":
        return false  # 由事件触发，不进 fold
    return false


## 转为 CombatModifier（让现有 DamageSystem fold 直接消费）
func to_combat_modifier() -> CombatModifier:
    var m = _CombatModifier.new()
    m.id = id
    m.display_name = display_name
    m.hit_pct = hit_pct
    m.defense_flat = defense_flat
    m.defense_pct = defense_pct
    m.damage_mult_min = damage_mult_min
    m.damage_mult_max = damage_mult_max
    m.stamina_cost_mult = stamina_cost_mult
    return m


## 触发事件回调（triggered kind 用；override in subclass）
func on_event(event_name: String, unit, context: Dictionary) -> Dictionary:
    return {}
```

### 4.3 PassiveLibrary（注册中心）

```gdscript
# scripts/core/passives/PassiveLibrary.gd
extends RefCounted
class_name PassiveLibrary

const _GenericPassive = preload("res://scripts/core/passives/GenericPassive.gd")
const PASSIVES_JSON_PATH := "res://data/passives.json"

static var _by_id: Dictionary = {}
static var _initialized: bool = false


static func get_by_id(passive_id: String):
    _ensure_loaded()
    return _by_id.get(passive_id, null)


static func ids() -> Array:
    _ensure_loaded()
    return _by_id.keys()


static func reload() -> void:
    _by_id.clear()
    _initialized = false
    _ensure_loaded()


# ──── 私有 ────

static func _ensure_loaded() -> void:
    if _initialized: return
    _initialized = true
    _register_native()
    _load_from_json(PASSIVES_JSON_PATH)


static func _register_native() -> void:
    # 复杂逻辑被动，写 .gd 子类
    var qhhx = preload("res://scripts/core/passives/specials/PassiveQiHaiHuiXuan.gd").new()
    _by_id[qhhx.id] = qhhx
    
    var cj = preload("res://scripts/core/passives/specials/PassiveChuJue.gd").new()
    _by_id[cj.id] = cj
    # ...其他 special


static func _load_from_json(path: String) -> void:
    if not FileAccess.file_exists(path): return
    var f = FileAccess.open(path, FileAccess.READ)
    var parsed = JSON.parse_string(f.get_as_text())
    if not (parsed is Dictionary): return
    for k in parsed.keys():
        if String(k).begins_with("_"): continue
        var cfg = parsed[k]
        if not (cfg is Dictionary): continue
        if not cfg.has("id"): cfg["id"] = String(k)
        var p = _GenericPassive.from_dict(cfg)
        if p != null:
            _by_id[p.id] = p
```

### 4.4 PassiveCondition（mini DSL 求值器）

```gdscript
# scripts/core/passives/PassiveCondition.gd
extends RefCounted
class_name PassiveCondition

## 极简表达式求值器，仿 GenericAbility._eval_constraint
## 支持有限的关键字组合，复杂条件请退化为 .gd 子类
##
## 支持的关键字：
##   self.hp_ratio < 0.30 / >= 0.50 / ...
##   self.total_armor_weight >= 30 / < 20
##   self.total_weight < N
##   self.weapon_kind == "<x>"
##   context.overwhelm_count >= N
##   context.is_charge / context.is_critical / context.is_first_attack

static func eval(expr: String, unit, context: Dictionary) -> bool:
    var s: String = expr.strip_edges()
    if s.is_empty():
        return true
    
    # HP 比例
    if "self.hp_ratio" in s:
        var ratio: float = unit.stats.hp / float(max(1, unit.stats.max_hp))
        return _eval_compare(s, "self.hp_ratio", ratio)
    
    # 总甲重
    if "self.total_armor_weight" in s:
        var w: int = _calc_armor_weight(unit)
        return _eval_compare(s, "self.total_armor_weight", float(w))
    
    # 总负重
    if "self.total_weight" in s:
        var w: int = unit.get_total_weight()
        return _eval_compare(s, "self.total_weight", float(w))
    
    # 围攻人数
    if "context.overwhelm_count" in s:
        var n: int = int(context.get("overwhelm_count", 0))
        return _eval_compare(s, "context.overwhelm_count", float(n))
    
    # 武器类型
    if "self.weapon_kind ==" in s:
        var want: String = _extract_string_literal(s)
        if unit.weapon == null: return false
        return String(unit.weapon.kind) == want
    
    # 布尔事件
    if s == "context.is_charge":
        return bool(context.get("is_charge", false))
    if s == "context.is_critical":
        return bool(context.get("is_critical", false))
    if s == "context.is_first_attack":
        return bool(context.get("is_first_attack", false))
    
    push_warning("[PassiveCondition] unknown expr: %s" % s)
    return false


static func _eval_compare(expr: String, key: String, value: float) -> bool:
    var rest: String = expr.replace(key, "").strip_edges()
    # rest = ">= 30" / "< 0.30"
    var op: String = ""
    var num_str: String = ""
    for prefix in [">=", "<=", "==", "!=", ">", "<"]:
        if rest.begins_with(prefix):
            op = prefix
            num_str = rest.substr(prefix.length()).strip_edges()
            break
    if op.is_empty():
        return false
    var threshold: float = num_str.to_float()
    match op:
        ">=": return value >= threshold
        "<=": return value <= threshold
        ">":  return value > threshold
        "<":  return value < threshold
        "==": return abs(value - threshold) < 0.001
        "!=": return abs(value - threshold) >= 0.001
    return false


static func _calc_armor_weight(unit) -> int:
    var w: int = 0
    if unit.armor != null and "weight" in unit.armor:
        w += int(unit.armor.weight)
    if unit.shield != null and "weight" in unit.shield:
        w += int(unit.shield.weight)
    return w


static func _extract_string_literal(expr: String) -> String:
    var idx: int = expr.find("\"")
    if idx < 0: return ""
    var rest: String = expr.substr(idx + 1)
    var end: int = rest.find("\"")
    if end < 0: return ""
    return rest.substr(0, end)
```

### 4.5 GenericPassive（数据驱动通用被动）

```gdscript
# scripts/core/passives/GenericPassive.gd
extends "res://scripts/core/passives/PassiveEffect.gd"
class_name GenericPassive

static func from_dict(cfg: Dictionary):
    var script := load("res://scripts/core/passives/GenericPassive.gd")
    var p = script.new()
    p._load_config(cfg)
    return p


func _load_config(cfg: Dictionary) -> void:
    id            = String(cfg.get("id", ""))
    display_name  = String(cfg.get("display_name", id))
    kind          = String(cfg.get("kind", "permanent"))
    condition_expr = String(cfg.get("trigger_when", ""))
    trigger_event = String(cfg.get("trigger_event", ""))
    trigger_phase = String(cfg.get("trigger_phase", ""))
    stamina_cost_per_trigger = int(cfg.get("stamina_cost_per_trigger", 0))
    mutex_with = cfg.get("mutex_with", [])
    hooks = cfg.get("hooks", [])
    ai_hint = cfg.get("ai_hint", {})
    
    # 解析 modifiers 字段到对应 fold 字段
    var mods: Dictionary = cfg.get("modifiers", {}) if cfg.get("modifiers") is Dictionary else {}
    if mods.has("hit_pct"):              hit_pct = float(mods["hit_pct"])
    if mods.has("defense_flat"):         defense_flat = float(mods["defense_flat"])
    if mods.has("defense_pct"):          defense_pct = float(mods["defense_pct"])
    if mods.has("damage_mult"):          
        damage_mult_min = float(mods["damage_mult"])
        damage_mult_max = damage_mult_min
    if mods.has("damage_mult_min"):      damage_mult_min = float(mods["damage_mult_min"])
    if mods.has("damage_mult_max"):      damage_mult_max = float(mods["damage_mult_max"])
    if mods.has("stamina_cost_mult"):    stamina_cost_mult = float(mods["stamina_cost_mult"])
    if mods.has("armor_damage_mult"):    armor_damage_mult = float(mods["armor_damage_mult"])
    if mods.has("damage_taken_mult"):    damage_taken_mult = float(mods["damage_taken_mult"])
    if mods.has("hp_max_pct"):           hp_max_pct = float(mods["hp_max_pct"])
    if mods.has("resolve_flat"):         resolve_flat = float(mods["resolve_flat"])
    if mods.has("wound_threshold_pct"):  wound_threshold_pct = float(mods["wound_threshold_pct"])
```

### 4.6 Unit 集成

```gdscript
# scripts/core/Unit.gd 增量

# ──── 新增字段 ────
var passives: PackedStringArray = PackedStringArray()  ## 已学被动 id 列表


func has_passive(passive_id: String) -> bool:
    return passive_id in passives


func add_passive(passive_id: String) -> void:
    if not has_passive(passive_id):
        passives.append(passive_id)
        _resolve_passive_mutex(passive_id)


func remove_passive(passive_id: String) -> void:
    var idx: int = passives.find(passive_id)
    if idx >= 0:
        passives.remove_at(idx)


## 当前激活的 PassiveEffect 列表（含条件判定，不含 triggered 类）
func get_active_passives(context: Dictionary = {}) -> Array:
    var result: Array = []
    for pid in passives:
        var p = PassiveLibrary.get_by_id(pid)
        if p == null: continue
        if p.kind == "triggered": continue
        if p.is_active(self, context):
            result.append(p)
    return result


## 修改 get_active_debuffs：把激活的 PassiveEffect 也 fold 进去
func get_active_debuffs() -> Array:
    var debuffs: Array = []
    if stats:
        debuffs.append(_CombatModifier.stamina_tier_for(stats))
    # 装备非熟练武器 → 手拙
    if _is_weapon_clumsy():
        debuffs.append(_CombatModifier.clumsy())
    # 激活的被动转 CombatModifier 加入 fold
    for p in get_active_passives({}):
        debuffs.append(p.to_combat_modifier())
    return debuffs


func _resolve_passive_mutex(new_pid: String) -> void:
    var p = PassiveLibrary.get_by_id(new_pid)
    if p == null: return
    for mid in p.mutex_with:
        remove_passive(String(mid))
```

### 4.7 钩子注册中心（PassiveHookRegistry）

部分被动需要修改**特定公式**（不是简单 fold），用钩子机制：

```gdscript
# scripts/core/passives/PassiveHookRegistry.gd
extends RefCounted
class_name PassiveHookRegistry

## 钩子白名单（增加新钩子在此注册）
const HOOK_TYPES: Array = [
    "ability_ap_cost",            # 修改 Ability.get_ap_cost
    "ability_stamina_cost",       # 修改 Ability.get_fatigue_cost
    "self_overwhelm_bonus",       # 修改自己作为攻击者时的围攻系数
    "incoming_overwhelm_bonus",   # 修改自己作为受击者时对方围攻系数
    "movement_oa_immune",         # 移动是否免疫借机
    "crit_damage_mult",           # 暴击伤害倍率
    "armor_break_chance",         # 卸甲触发率
    "kill_restore_ap",            # 击杀回 AP
]


## 调用入口：返回所有匹配 hook_type + 条件的被动钩子 modifier 列表
static func collect(unit, hook_type: String, context: Dictionary) -> Array:
    var result: Array = []
    for p in unit.get_active_passives(context):
        for hook in p.hooks:
            if not (hook is Dictionary): continue
            if String(hook.get("hook", "")) != hook_type: continue
            var cond: String = String(hook.get("condition", ""))
            if not cond.is_empty() and not PassiveCondition.eval(cond, unit, context):
                continue
            result.append(hook.get("modifier", {}))
    return result
```

### 4.8 DamageSystem 接入（最少改动）

```gdscript
# scripts/core/DamageSystem.gd 增量

static func compute_hit_bonus(attacker, target, options: Dictionary = {}) -> float:
    var bonus: float = 0.0
    var allies: int = count_overwhelm_allies(attacker, target)
    
    # ── 围攻系数：先看是否被「借势合击」覆盖（攻方）
    var per_ally: float = OVERWHELM_PER_ALLY
    var cap: float = OVERWHELM_MAX
    var atk_hooks = PassiveHookRegistry.collect(attacker, "self_overwhelm_bonus", 
        { "overwhelm_count": allies })
    for h in atk_hooks:
        if h.has("per_ally"): per_ally = float(h["per_ally"])
        if h.has("cap"):      cap      = float(h["cap"])
    
    var attacker_overwhelm: float = min(float(allies) * per_ally, cap)
    
    # ── 受击侧：看「野战八方」是否清零
    var def_hooks = PassiveHookRegistry.collect(target, "incoming_overwhelm_bonus", {})
    for h in def_hooks:
        if h.has("set"):
            attacker_overwhelm = float(h["set"])  # 通常 = 0
    
    bonus += attacker_overwhelm
    # ... 其余原逻辑（高地、ability_hit_modifier 等）
    return bonus


# 受击伤害计算时，叠 armor_damage_mult / damage_taken_mult
static func _apply_damage_passive_mods(target, armor_dmg: int, hp_dmg: int) -> Dictionary:
    var armor_mult: float = 1.0
    var hp_mult: float = 1.0
    for raw in target.get_active_debuffs():  # 已包含 fold 后的 passive
        if raw is _CombatModifier:
            # CombatModifier 还没有 armor_damage_mult / damage_taken_mult 字段
            # 需要扩展 CombatModifier 加这两个字段（或单独走 PassiveEffect 列表）
            pass
    return { "armor": armor_dmg, "hp": hp_dmg }
```

> **关键设计选择**：CombatModifier 当前字段不够，**需扩展 4 个新字段**：  
> `armor_damage_mult / damage_taken_mult / hp_max_pct / wound_threshold_pct`  
> 这些字段在现有气力档/手拙/缴械上都是 1.0/0.0 默认，不影响既有行为。

### 4.9 Ability 接入（身法精通钩子）

```gdscript
# Ability.gd 增量

func get_ap_cost(user) -> int:
    var base: int = _base_ap_cost(user)  # 原来的逻辑
    
    # 钩子：身法精通
    var hooks = PassiveHookRegistry.collect(user, "ability_ap_cost", { "ability": self })
    for h in hooks:
        if h.has("delta"):  base += int(h["delta"])
        if h.has("min"):    base = max(int(h["min"]), base)
    return max(0, base)


## tag 系统：让条件 "ability.has_tag('displacement')" 成立
@export var tags: PackedStringArray = PackedStringArray()


func has_tag(tag: String) -> bool:
    return tag in tags
```

### 4.10 事件触发被动（triggered kind）

```gdscript
# 在 DamageSystem.execute_attack 末尾加：
if did_kill:
    PassiveEventBus.emit("on_kill", attacker, { "victim": target })

# 在 dodge 成功分支：
if did_dodge:
    PassiveEventBus.emit("on_dodge_success", target, { "attacker": attacker })

# scripts/core/passives/PassiveEventBus.gd
extends RefCounted
class_name PassiveEventBus

static func emit(event_name: String, unit, context: Dictionary) -> void:
    for pid in unit.passives:
        var p = PassiveLibrary.get_by_id(pid)
        if p == null or p.kind != "triggered": continue
        if p.trigger_event != event_name: continue
        var result: Dictionary = p.on_event(event_name, unit, context)
        # 处理 result（如还 AP、触发反击等）
        _handle_event_result(unit, result, context)


static func _handle_event_result(unit, result: Dictionary, context: Dictionary) -> void:
    if result.is_empty(): return
    match result.get("type", ""):
        "restore_ap":
            var amt: int = int(result.get("amount", 0))
            if unit.stats != null:
                unit.stats.ap = min(unit.stats.ap + amt, unit.stats.base_ap)
        "counter_attack":
            var attacker = context.get("attacker")
            if attacker != null:
                var mult: float = float(result.get("damage_mult", 0.5))
                DamageSystem.execute_attack(unit, attacker, { "damage_mult": mult })
        "stun":
            # ...其他
            pass
```

---

## 五、典型被动落地流程

### 5.1 流程 A：纯 fold 被动（90%）

**例：不屈** = HP <30% → Defense+10, Resolve+15

1. 在 `data/passives.json` 加配置（已示例）
2. Unit.add_passive("bu_qu")
3. 战斗中 DamageSystem 调 `target.get_active_debuffs()` → 自动包含「不屈」转的 CombatModifier
4. fold 公式 `final_def = base + def_flat + ...` 自动加上 +10

**改动**：1 个 JSON 段，0 行代码。

### 5.2 流程 B：钩子被动（占 7%）

**例：身法精通** = 位移技 AP-1, 气力 ×0.8

1. 在 `data/passives.json` 加配置（hooks 字段，已示例）
2. 给位移类 Ability 打上 `tags: ["displacement"]`
3. Ability.get_ap_cost 自动调用 PassiveHookRegistry.collect
4. 钩子被命中，AP 减 1（最低 1）

**改动**：1 个 JSON 段 + 给 5 个位移技能加 tag。

### 5.3 流程 C：复杂公式被动（占 3%）

**例：气海回旋** = 减伤 = min(20% + (20-甲重)% + 当前气力/甲重², 60%)

1. JSON 描述太复杂 → 写 `.gd` 子类
2. 注册到 `PassiveLibrary._register_native()`
3. 重载 `to_combat_modifier()` 在每次 fold 时动态计算 damage_taken_mult

```gdscript
# PassiveQiHaiHuiXuan.gd
extends PassiveEffect

func _init():
    id = "qi_hai_hui_xuan"
    display_name = "气海回旋"
    kind = "conditional"
    condition_expr = "self.total_armor_weight < 30"
    trigger_phase = "on_take_hit"
    stamina_cost_per_trigger = 5
    mutex_with = ["tie_gu"]


func to_combat_modifier_dynamic(unit) -> CombatModifier:
    # 动态计算 damage_taken_mult
    var armor_w: int = max(1, _calc_armor_weight(unit))
    var stamina: int = max(0, unit.stats.max_stamina - unit.stats.fatigue)
    var reduce: float = 0.20 \
        + (20 - armor_w) * 0.01 \
        + float(stamina) / float(armor_w * armor_w)
    reduce = clamp(reduce, 0.0, 0.60)
    
    var m = CombatModifier.new()
    m.id = id
    m.display_name = display_name
    m.damage_taken_mult = 1.0 - reduce
    return m
```

---

## 六、Phase 实施路线

### Phase 2.5 P1（基建）
1. ✅ 设计文档（本文）
2. [ ] PassiveEffect / GenericPassive / PassiveLibrary / PassiveCondition / PassiveHookRegistry 5 个基础文件
3. [ ] CombatModifier 扩展 4 字段（armor_damage_mult / damage_taken_mult / hp_max_pct / wound_threshold_pct）
4. [ ] Unit.passives + add/remove/has_passive + get_active_passives
5. [ ] DamageSystem.compute_hit_bonus 接入 self_overwhelm_bonus / incoming_overwhelm_bonus 钩子
6. [ ] data/passives.json 写 4 个示范被动（不屈 / 铁骨 / 借势合击 / 野战八方）
7. [ ] 测试：test_passive_effects.gd 冒烟测试 + sim 回归

### Phase 2.5 P2（钩子扩展）
8. [ ] Ability.get_ap_cost / get_fatigue_cost 接入 ability_ap_cost / ability_stamina_cost 钩子
9. [ ] Ability.tags 系统 + 给 7 个位移技能打 displacement tag
10. [ ] 实装身法精通 / 健壮 (JSON)

### Phase 3（事件 + 复杂被动）
11. [ ] PassiveEventBus + on_kill / on_dodge_success / on_crit 三个事件
12. [ ] 实装处决 / 闪击 / 锐意 / 残忍（混合 JSON + .gd）
13. [ ] PassiveQiHaiHuiXuan / PassiveTieGu 互斥处理
14. [ ] AI 集成：IntentWeights 读 ai_hint.category 对持有 tank 类被动的单位提高 defend 权重

---

## 七、与既有系统的边界

| 系统 | 关系 | 说明 |
|---|---|---|
| **CombatModifier** | 复用 | PassiveEffect.to_combat_modifier() 转出后 fold |
| **Ability** | 钩子注入 | get_ap_cost / get_fatigue_cost 调 PassiveHookRegistry |
| **DamageSystem** | 钩子注入 | compute_hit_bonus / 受击伤害管线插入钩子 |
| **CombatEffect (Phase 3)** | 平行 | CombatEffect = 临时状态（DOT/眩晕/嘲讽）；PassiveEffect = 永久学习的被动技。两套系统，不冲突 |
| **Trait（先天天赋）** | 平行 | Trait = 招募时随机的固定被动；通过 `Unit.passives` 同样接入。Trait id = "trait_*" 命名空间 |
| **JP 系统** | 上游 | Unit.add_passive() 在 JP 投资达标时自动调用 |

---

## 八、单元测试设计

```gdscript
# scripts/tools/test_passive_effects.gd

func _test_buqu_conditional():
    var u = make_unit(hp = 30, max_hp = 100)
    u.add_passive("bu_qu")
    
    # 满血时不激活
    u.stats.hp = 100
    var debuffs = u.get_active_debuffs()
    var has_buqu = debuffs.any(func(m): return m.id == "bu_qu")
    _ok(not has_buqu, "满血时不屈不激活")
    
    # 残血时激活
    u.stats.hp = 25
    debuffs = u.get_active_debuffs()
    has_buqu = debuffs.any(func(m): return m.id == "bu_qu")
    _ok(has_buqu, "HP <30% 时不屈激活")
    
    # final_def 应 +10
    var final_def = compute_defense_breakdown(u, {}).final_def
    _ok(final_def >= u.stats.defense + 10, "不屈 +10 防")


func _test_jieshi_heji_overwhelm_override():
    var atk = make_unit()
    atk.add_passive("jie_shi_he_ji")
    var t = make_unit()
    place_allies_around(t, count = 2)  # 2 友军围攻
    
    var bonus = DamageSystem.compute_hit_bonus(atk, t)
    # 默认 2 友军 → 2 × 0.05 = 0.10
    # 借势合击 → 2 × 0.08 = 0.16
    _ok(abs(bonus - 0.16) < 0.01, "借势合击替代默认围攻系数")


func _test_yezhan_bafang_blocks_overwhelm():
    var t = make_unit()
    t.add_passive("ye_zhan_ba_fang")
    var atk = make_unit()
    place_allies_around(t, count = 3)  # 3 友军
    
    var bonus = DamageSystem.compute_hit_bonus(atk, t)
    # 应被野战八方清零（仅围攻部分）
    _ok(abs(bonus) < 0.01, "野战八方清零围攻加值")


func _test_mutex_passives():
    var u = make_unit()
    u.add_passive("tie_gu")
    u.add_passive("qi_hai_hui_xuan")
    _ok(not u.has_passive("tie_gu"), "学气海回旋时铁骨自动移除")
    _ok(u.has_passive("qi_hai_hui_xuan"), "气海回旋已学")
```

---

## 九、设计决策与权衡

### 9.1 为什么不直接重载 CombatEffect 系统

**CombatEffect** = 战斗内临时状态（嘲讽 2 回合、流血 3 回合、眩晕 1 回合）  
**PassiveEffect** = 战斗外学习的永久被动（不屈、铁骨、借势合击）

两者形态相似（都修改命中/防御/伤害），但**生命周期与来源完全不同**：

| 维度 | CombatEffect | PassiveEffect |
|---|---|---|
| 来源 | Ability 施加 | JP 投资学习 |
| 生命周期 | 回合数倒计时 | 整局战斗 |
| 存档位置 | 战斗内瞬时 | Unit 角色档案 |
| 驱散方式 | 包扎 / 倒计时 | 不能驱散（学了就有） |
| AI 判断 | 看 buff/debuff 列表 | 看 unit.passives |

强行合并会让 CombatEffect 系统膨胀。**分两个系统，但 fold 出口共用 CombatModifier**——既保持代码复用，又保持语义清晰。

### 9.2 为什么用 mini DSL 而不是 GDScript expression

GDScript 4 提供 `Expression.parse` 可以执行任意表达式，但：
- 安全：DSL 的关键字白名单可控，不允许 JSON 注入恶意代码
- 可读：`self.hp_ratio < 0.30` 比 `Expression eval` 直观
- 可移植：未来如果改 JSON schema，DSL 接口稳定

代价是要维护一个解析器，但我们的 DSL 关键字 < 15 条，复杂度可控。

### 9.3 为什么钩子机制独立而不是塞进 fold

部分被动（围攻系数替换、AP 减免、暴击伤害倍率）**修改的是公式系数本身**，不是 add/mult 一个静态值。如果硬塞进 fold，会破坏现有 CombatModifier 的简单语义。

钩子机制让这部分逻辑**显式化**：
- 想让暴击伤害 +30% → `hooks: [{ hook: "crit_damage_mult", modifier: { mult: 1.3 } }]`
- DamageSystem 在算暴击时调 `PassiveHookRegistry.collect("crit_damage_mult")`，不污染普通 fold

### 9.4 .gd 子类 vs JSON 的取舍

| 用 JSON | 用 .gd |
|---|---|
| 静态 fold（不屈、铁骨、健壮） | 动态公式（气海回旋） |
| 简单条件（HP < 30%） | 复杂连锁触发（处决：杀人 + 限每回合 1 次 + 还 4 AP） |
| 钩子 modifier 可表达（per_ally: 0.08） | 需要回调函数（闪击：闪避后立刻反击） |

**预估**：~50 个被动里，~40 个 JSON，~10 个 .gd。

---

## 十、文件清单（Phase 2.5 P1 落地）

| 文件 | 类型 | 行数估计 | 说明 |
|---|---|---|---|
| `design/passive-effect-system.md` | 设计 | — | 本文 |
| `scripts/core/passives/PassiveEffect.gd` | 基类 | ~80 | 字段 + is_active + to_combat_modifier |
| `scripts/core/passives/GenericPassive.gd` | 数据 | ~60 | from_dict 工厂 |
| `scripts/core/passives/PassiveLibrary.gd` | 注册 | ~80 | 仿 AbilityLibrary |
| `scripts/core/passives/PassiveCondition.gd` | DSL | ~80 | mini 表达式求值 |
| `scripts/core/passives/PassiveHookRegistry.gd` | 钩子 | ~30 | collect 入口 |
| `scripts/core/passives/PassiveEventBus.gd` | 事件 | ~40 | emit + 内置 result handler |
| `scripts/core/passives/specials/PassiveQiHaiHuiXuan.gd` | 特殊 | ~40 | 复杂公式示例 |
| `scripts/core/CombatModifier.gd` | 修改 | +10 | 加 4 个 fold 字段 |
| `scripts/core/Unit.gd` | 修改 | +30 | passives 字段 + has/add/remove + get_active_passives |
| `scripts/core/DamageSystem.gd` | 修改 | +20 | compute_hit_bonus 钩子点 + 受击钩子点 |
| `scripts/core/abilities/Ability.gd` | 修改 | +15 | get_ap_cost 钩子 + tags 字段 |
| `data/passives.json` | 数据 | — | 起步 4 个被动（不屈/铁骨/借势合击/野战八方） |
| `scripts/tools/test_passive_effects.gd` | 测试 | ~150 | 4 个被动的冒烟用例 |

总计 ~600 行新代码 + ~75 行修改 + 1 份配置 + 1 套测试。预计 **1.5 工作日**完成 Phase 2.5 P1。

---

**版本**：v1.0（2026-06-13）— Phase 2.5 P1 设计稿  
**状态**：架构设计 + 代码骨架，等待 review 后实施  
**关联**：`ai-decision-logic.md`（AI 评估读 ai_hint.category）/ `ability-data-driven-guide.md`（同款 JSON + .gd 退化策略）
