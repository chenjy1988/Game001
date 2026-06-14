extends "res://scripts/core/abilities/Ability.gd"
class_name GenericAbility
##
## GenericAbility — 数据驱动通用技能
##
## 90% 的技能（位移 / Buff / Debuff / 简单 Hybrid）只是 EffectSpec + MovementSpec 的不同组合，
## 不需要单独 .gd 文件。本类从 JSON 配置一次性构造完整能力。
##
## 真正需要 .gd 子类的场景（≈ 10%）：
##   - ATTACK 类（走 DamageSystem 完整管线 → BasicAttack.gd）
##   - 命中后回调（如骑乘冲锋每格 +8% 伤）
##   - 自定义 _extra_can_use（条件复杂、不易表达成 JSON）
##   - 多目标差异化效果（穿透扇形等非标准 targeting）
##
## JSON Schema（详见 design/ability-data-driven-guide.md）：
## {
##   "id": "tui_zhuang",
##   "display_name": "推撞",
##   "kind": "UTILITY",                       # ATTACK 不走此类
##   "targeting": "SINGLE_ENEMY",
##   "ap_cost": 4,
##   "stamina_cost_extra": 0,
##   "range": 1,
##   "weapon_filter": [],
##   "mutex_group": "attack",
##
##   # 位移规格（可选）—— 详见 AbilityMovementSpec.from_dict()
##   "movement": {
##     "kind": "PUSH",
##     "distance": 1,
##     "on_block_damage": 0
##   },
##
##   # 效果规格（可选，可多个）—— 详见 AbilityEffectSpec.from_dict()
##   "effects": [
##     { "type": "debuff", "id": "taunted", "duration": 2 }
##   ],
##
##   # 自身效果（施法时自动给 user 也挂一个，可选）
##   "self_effects": [
##     { "type": "buff", "id": "rooted", "duration": 1 }
##   ],
##
##   # 简单 can_use 表达式（可选，逐条 AND）
##   "constraints": [
##     "self.move >= target.move",     # 推撞需要 user.move ≥ target.move
##     "target.adjacent_to_self"       # 目标必须相邻
##   ],
##
##   # AI 评分提示（无则用基类默认）
##   "ai_hint": {
##     "priority": "positioning",
##     "prefers": "near_terrain_hazard",
##     "risk": "low",
##     "situational": 5.0
##   }
## }
##

const _AbilEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _MovementSpec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _EffectSpec = preload("res://scripts/core/abilities/AbilityEffectSpec.gd")

## 原始配置，存档以便调试
var _config: Dictionary = {}

## 解析后的子结构（缓存避免每次施法重解析）
var _movement_cfg: Dictionary = {}
var _effects_cfg: Array = []
var _self_effects_cfg: Array = []
var _constraints: Array = []
var _allow_self: bool = false
var _remove_effects_cfg: Array = []
var _wisdom_count_cfg: Dictionary = {}


# ──────────── 工厂 ────────────

static func from_dict(cfg: Dictionary):
	# 用 load() + new()，避免 class_name 在 static 函数中的解析问题
	var script := load("res://scripts/core/abilities/GenericAbility.gd")
	var a = script.new()
	a._load_config(cfg)
	return a


func _load_config(cfg: Dictionary) -> void:
	_config = cfg.duplicate(true)

	# 基础字段
	id            = String(cfg.get("id", ""))
	display_name  = String(cfg.get("display_name", id))
	kind          = _parse_kind(cfg.get("kind", "UTILITY"))
	targeting     = _parse_targeting(cfg.get("targeting", "SELF"))
	ap_cost       = int(cfg.get("ap_cost", 0))
	stamina_cost_extra = int(cfg.get("stamina_cost_extra", 0))
	range_hexes   = int(cfg.get("range", 0))
	mutex_group   = String(cfg.get("mutex_group", ""))

	var wf: Variant = cfg.get("weapon_filter", [])
	weapon_filter = PackedStringArray(wf) if wf is Array else PackedStringArray()

	# AI hint（仅覆盖给定字段，未给的保留基类默认）
	var hint: Variant = cfg.get("ai_hint", null)
	if hint is Dictionary:
		for k in hint:
			ai_hint[k] = hint[k]

	# 子结构
	_movement_cfg = cfg.get("movement", {}) if cfg.get("movement") is Dictionary else {}
	_effects_cfg  = cfg.get("effects", []) if cfg.get("effects") is Array else []
	_self_effects_cfg = cfg.get("self_effects", []) if cfg.get("self_effects") is Array else []
	_constraints  = cfg.get("constraints", []) if cfg.get("constraints") is Array else []
	_allow_self   = bool(cfg.get("allow_self", false))
	_remove_effects_cfg = cfg.get("remove_effects", []) if cfg.get("remove_effects") is Array else []
	_wisdom_count_cfg = cfg.get("wisdom_count", {}) if cfg.get("wisdom_count") is Dictionary else {}
	weight        = int(cfg.get("weight", 0))  ## 心智负载（§十二 本职记忆与旧艺负载）


# ──────────── 枚举解析 ────────────

static func _parse_kind(v) -> int:
	if v is int:
		return v
	var s: String = String(v).to_upper()
	match s:
		"ATTACK":  return _AbilEnums.Kind.ATTACK
		"BUFF":    return _AbilEnums.Kind.BUFF
		"DEBUFF":  return _AbilEnums.Kind.DEBUFF
		"UTILITY": return _AbilEnums.Kind.UTILITY
		"HYBRID":  return _AbilEnums.Kind.HYBRID
	return _AbilEnums.Kind.UTILITY


static func _parse_targeting(v) -> int:
	if v is int:
		return v
	var s: String = String(v).to_upper()
	match s:
		"NONE":              return _AbilEnums.Targeting.NONE
		"SELF":              return _AbilEnums.Targeting.SELF
		"SINGLE_ALLY":       return _AbilEnums.Targeting.SINGLE_ALLY
		"SINGLE_ENEMY":      return _AbilEnums.Targeting.SINGLE_ENEMY
		"SINGLE_ANY":        return _AbilEnums.Targeting.SINGLE_ANY
		"ALL_ALLIES":        return _AbilEnums.Targeting.ALL_ALLIES
		"ALL_ENEMIES":       return _AbilEnums.Targeting.ALL_ENEMIES
		"ALLIES_IN_RANGE":   return _AbilEnums.Targeting.ALLIES_IN_RANGE
		"ENEMIES_IN_RANGE":  return _AbilEnums.Targeting.ENEMIES_IN_RANGE
	return _AbilEnums.Targeting.SELF


# ──────────── 约束（_extra_can_use 表达式）────────────

func _extra_can_use(user, target) -> bool:
	if _constraints.is_empty():
		return true
	for c in _constraints:
		if not _eval_constraint(String(c), user, target):
			return false
	return true


## 极简表达式求值器：支持有限的、可读的约束。
## 后续若需更复杂条件，建议直接退化为 .gd 子类，不要把这里搞成 DSL 解释器。
func _eval_constraint(expr: String, user, target) -> bool:
	var s: String = expr.strip_edges()

	# 关键字常量
	if s == "target.adjacent_to_self":
		if user == null or target == null:
			return false
		var d: int = _HexCoord.distance(user.axial_pos, target.axial_pos)
		return d == 1

	# self.move >= target.move
	if s == "self.move >= target.move":
		if user == null or target == null:
			return false
		var um: int = int(user.stats.move) if user.stats != null and "move" in user.stats else 4
		var tm: int = int(target.stats.move) if target.stats != null and "move" in target.stats else 4
		return um >= tm

	# self.weapon_kind == "<x>"  例如 "self.weapon_kind == short_spear"
	if s.begins_with("self.weapon_kind ==") or s.begins_with("self.weapon_id =="):
		var parts: PackedStringArray = s.split("==", false, 1)
		if parts.size() == 2 and user != null and user.weapon != null:
			var want: String = parts[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
			var key: String = "kind" if s.begins_with("self.weapon_kind") else "id"
			var got: String = String(user.weapon.get(key)) if user.weapon.get(key) != null else ""
			return got == want

	# target.faction != self.faction（基类已处理，但留作冗余）
	if s == "target.faction != self.faction":
		if user == null or target == null:
			return false
		return user.get_faction() != target.get_faction()

	# 未知约束：保守通过（避免 JSON 拼写错误一票否决；用 push_warning 提示）
	push_warning("[GenericAbility] unknown constraint: %s (id=%s)" % [s, id])
	return true


# ──────────── allow_self ────────────

## SINGLE_ALLY 默认排除自身；设置 "allow_self": true 后允许自愈
func _is_valid_target(user, target) -> bool:
	if target == null or not target.is_alive():
		return false
	if _allow_self and target == user:
		return true
	return super._is_valid_target(user, target)


# ──────────── remove_effects + wisdom_count ────────────

## 当 JSON 配置了 remove_effects 时，override apply() 插入效果移除步骤
func apply(user, target = null, context: Dictionary = {}) -> Dictionary:
	if _remove_effects_cfg.is_empty():
		return super.apply(user, target, context)

	if not can_use(user, target):
		return _fail_use(user, target)

	var t = target if target != null else user
	spend_resources(user, context)

	# 1) 移除效果：Wisdom 决定移除数量
	var count: int = 1
	if not _wisdom_count_cfg.is_empty():
		count = _compute_wisdom_count(user)
	var removed: Array = []
	if t != null and t.has_method("get_effect_container"):
		var container = t.get_effect_container()
		var present: Array = []
		for eff_id in _remove_effects_cfg:
			if container.has_id(String(eff_id)):
				present.append(String(eff_id))
		present.shuffle()
		for eff_id in present.slice(0, min(count, present.size())):
			container.remove_by_id(String(eff_id))
			removed.append(String(eff_id))

	# 2) 继续标准流程（位移 → 效果）
	var targets: Array = resolve_targets(user, target, context)
	var movements: Array = gather_movement_specs(user, targets, context)
	apply_movement_specs(user, movements, context)
	var specs: Array = gather_effect_specs(user, targets, context)
	var applied: Array = apply_effect_specs(user, specs, context)
	_on_ability_finished(user, targets, applied, context)

	return _Result.success(id, kind, {
		_Result.TARGETS: targets,
		_Result.EFFECTS_APPLIED: applied,
		"removed": removed,
		"remove_count": count,
	})


func _compute_wisdom_count(user) -> int:
	var wisdom: int = _get_user_wisdom(user)
	var w: float = clampf(float(wisdom), 30.0, 120.0)
	var norm: float = clampf((w - 30.0) / 70.0, 0.0, 1.0)
	var alpha: float = 1.0 - (0.8 * norm)
	var biased: float = pow(randf(), alpha)
	return clampi(ceili(biased * 4.0), 1, 4)


static func _get_user_wisdom(unit) -> int:
	if unit == null or unit.stats == null:
		return 30
	if "wisdom" in unit.stats:
		return max(0, int(unit.stats.wisdom))
	return 30


# ──────────── 装配位移规格 ────────────

func gather_movement_specs(user, targets: Array, context: Dictionary) -> Array:
	if _movement_cfg.is_empty():
		return []

	var primary = targets[0] if not targets.is_empty() else null
	var dest: Vector2i = Vector2i.ZERO

	# TELEPORT/DASH 需要外部传入 target_tile（UI 选格 / AI 决策）
	if context.has("target_tile"):
		var tt = context["target_tile"]
		if tt is Vector2i:
			dest = tt
		elif tt is Vector2:
			dest = Vector2i(tt)

	var spec = _MovementSpec.from_dict(_movement_cfg, user, primary, dest)
	if spec == null:
		return []
	return [spec]


# ──────────── 装配效果规格 ────────────

func gather_effect_specs(user, targets: Array, _context: Dictionary) -> Array:
	var specs: Array = []

	# 1) 给目标挂效果
	if not _effects_cfg.is_empty():
		for t in targets:
			if t == null or not t.is_alive():
				continue
			for e in _effects_cfg:
				if e is Dictionary:
					specs.append(_EffectSpec.from_dict(e, t, user))

	# 2) 给自己挂效果（如镇阵：rooted + displacement_immune）
	if not _self_effects_cfg.is_empty():
		for e in _self_effects_cfg:
			if e is Dictionary:
				specs.append(_EffectSpec.from_dict(e, user, user))

	return specs


# ──────────── 调试 ────────────

func get_config() -> Dictionary:
	return _config
