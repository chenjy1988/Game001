extends Resource
class_name Ability

const _Enums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _Result = preload("res://scripts/core/abilities/AbilityResult.gd")
const _Unit = preload("res://scripts/core/Unit.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")
##
## Ability.gd — 战斗能力基类（Resource）
##
## 扩展约定：
##   - ATTACK / HYBRID 子类 override apply() 或 _apply_attack()
##   - BUFF / DEBUFF / UTILITY 走默认 apply()：解析目标 → gather_effect_specs → 挂效果
##   - 效果实例化在 Unit.apply_effect_spec()，I0 后迁入 CombatEffectContainer
##

@export var id: String = ""
@export var display_name: String = ""
@export var kind: int = _Enums.Kind.ATTACK
@export var targeting: int = _Enums.Targeting.SINGLE_ENEMY
@export var ap_cost: int = 0                    ## 0 = 子类动态（普攻读武器）
@export var stamina_cost_extra: int = 0
@export var weapon_filter: PackedStringArray = []  ## 空 = 不限
@export var mutex_group: String = ""            ## 如 "attack"：一次行动仅一种攻击类
@export var range_hexes: int = 0                ## 0 = 仅看武器射程 / 子类 override

## AI 提示：声明能力在战斗评分中的定位（AI 不认技能名，只看此字段）。
##   priority:  "kill" | "armor_break" | "debuff" | "buff" | "positioning" | "default"
##   prefers:   "low_hp" | "armored" | "clustered" | "isolated"
##   risk:      "high" | "medium" | "low" （ZoC 容忍度）
##   situational: 额外固定分加成
## 未来加新技能只需填此字段，AI 评分代码零改动。
var ai_hint: Dictionary = {
	"priority":    "default",
	"prefers":     "",
	"risk":        "medium",
	"situational": 0.0,
}

## 能力标签：供 PassiveHookRegistry 条件匹配（如 "displacement" 让身法精通生效）
@export var tags: PackedStringArray = PackedStringArray()

## 心智负载：跨职业继承时消耗 Wisdom 心智容量
## 本职技能负载待定（当前 weight=0 为占位）；继承自旧职业 >0
## 分级参考：T1 10~15 / T2 20~30 / T3 40~50 / T4 60+
## 详见 design/class-system.md §十二「本职记忆与旧艺负载」
@export var weight: int = 0


func has_tag(tag: String) -> bool:
	return tag in tags


func requires_target() -> bool:
	return targeting not in [
		_Enums.Targeting.NONE,
		_Enums.Targeting.SELF,
		_Enums.Targeting.ALL_ALLIES,
		_Enums.Targeting.ALL_ENEMIES,
	]


func requires_enemy_target() -> bool:
	return targeting in [
		_Enums.Targeting.SINGLE_ENEMY,
		_Enums.Targeting.ENEMIES_IN_RANGE,
		_Enums.Targeting.ALL_ENEMIES,
	]


func requires_ally_target() -> bool:
	return targeting in [
		_Enums.Targeting.SINGLE_ALLY,
		_Enums.Targeting.ALL_ALLIES,
		_Enums.Targeting.ALLIES_IN_RANGE,
	]


func can_use(user:_Unit, target:_Unit = null) -> bool:
	if user == null or not user.is_alive():
		return false
	if user.stats.ap < get_ap_cost(user):
		return false
	if stamina_cost_extra > 0 and user.stats != null:
		if user.stats.stamina < stamina_cost_extra:
			return false
	if not weapon_filter.is_empty() and user.weapon != null:
		if user.weapon.id not in weapon_filter:
			return false
	if requires_target() and target == null:
		return false
	if target != null:
		if not _is_valid_target(user, target):
			return false
		if targeting in [
			_Enums.Targeting.SINGLE_ALLY,
			_Enums.Targeting.SINGLE_ENEMY,
			_Enums.Targeting.SINGLE_ANY,
		]:
			var dist: int = _HexCoord.distance(user.axial_pos, target.axial_pos)
			if dist > get_range(user):
				return false
	return _extra_can_use(user, target)


func _extra_can_use(_user:_Unit, _target:_Unit) -> bool:
	return true


func get_ap_cost(user:_Unit) -> int:
	if ap_cost > 0:
		return ap_cost
	return 0


func get_range(user:_Unit) -> int:
	if range_hexes > 0:
		return range_hexes
	if kind == _Enums.Kind.ATTACK and user != null and user.weapon != null:
		return user.weapon.attack_range
	return 99


func build_damage_options(_user:_Unit, _context: Dictionary) -> Dictionary:
	return {}


## 子类声明本能力要挂的 Buff/Debuff（可多个目标、混合极性）
func gather_effect_specs(user:_Unit, targets: Array, context: Dictionary) -> Array:
	return []


## 子类声明本能力要施加的位移（推/拉/换/瞬/冲）
## 由 MovementSystem.execute() 统一执行，不扣 AP / 气力
func gather_movement_specs(_user:_Unit, _targets: Array, _context: Dictionary) -> Array:
	return []


## 默认执行：BUFF / DEBUFF / UTILITY；ATTACK 子类应 override apply()
func apply(user:_Unit, target:_Unit = null, context: Dictionary = {}) -> Dictionary:
	if not can_use(user, target):
		return _fail_use(user, target)

	if kind == _Enums.Kind.ATTACK:
		push_warning("Ability.apply: ATTACK kind should override apply(): %s" % id)
		return _Result.fail("not_implemented", id)

	spend_resources(user, context)
	var targets: Array = resolve_targets(user, target, context)
	# 1) 位移先：例如换位/推撞先改变位置，再叠 buff/debuff
	var movements: Array = gather_movement_specs(user, targets, context)
	var moved_results: Array = apply_movement_specs(user, movements, context)
	# 2) 再叠效果
	var specs: Array = gather_effect_specs(user, targets, context)
	var applied: Array = apply_effect_specs(user, specs, context)
	_on_ability_finished(user, targets, applied, context)

	return _Result.success(id, kind, {
		_Result.TARGETS: targets,
		_Result.EFFECTS_APPLIED: applied,
		"movements": moved_results,
	})


## 执行位移规格（统一通过 MovementSystem，便于日后规则集中调整）
func apply_movement_specs(user:_Unit, movements: Array, _context: Dictionary) -> Array:
	if movements.is_empty():
		return []
	var ms = load("res://scripts/core/MovementSystem.gd")
	var grid = user.hex_grid if user != null else null
	var results: Array = []
	for m in movements:
		if m == null:
			continue
		if m.source == null:
			m.source = user
		if m.ability_id == "":
			m.ability_id = id
		var r: Dictionary = ms.execute(m, grid)
		results.append(r)
	return results


func spend_resources(user:_Unit, _context: Dictionary = {}) -> void:
	var cost: int = get_ap_cost(user)
	if cost > 0 and user.stats != null:
		user.stats.spend_ap(cost)
	if stamina_cost_extra > 0 and user.stats != null:
		user.stats.spend_stamina(stamina_cost_extra)


func resolve_targets(user:_Unit, primary:_Unit, context: Dictionary) -> Array:
	match targeting:
		_Enums.Targeting.NONE:
			return []
		_Enums.Targeting.SELF:
			return [user]
		_Enums.Targeting.SINGLE_ALLY, _Enums.Targeting.SINGLE_ENEMY, \
		_Enums.Targeting.SINGLE_ANY:
			return [primary] if primary != null else []
		_Enums.Targeting.ALL_ALLIES:
			return _collect_units(user, true, 0, context)
		_Enums.Targeting.ALL_ENEMIES:
			return _collect_units(user, false, 0, context)
		_Enums.Targeting.ALLIES_IN_RANGE:
			return _collect_units(user, true, get_range(user), context)
		_Enums.Targeting.ENEMIES_IN_RANGE:
			return _collect_units(user, false, get_range(user), context)
	return []


func apply_effect_specs(user:_Unit, specs: Array, _context: Dictionary) -> Array:
	var applied: Array = []
	for item in specs:
		if item == null or not _is_effect_spec(item):
			continue
		var spec = item
		if spec.target == null or not spec.target.is_alive():
			continue
		if spec.source == null:
			spec.source = user
		if spec.target.apply_effect_spec(spec, user):
			applied.append(spec)
	return applied


func _on_ability_finished(user:_Unit, _targets: Array, _applied: Array, _context: Dictionary) -> void:
	user.stats_changed.emit(user)


func _is_valid_target(user:_Unit, target:_Unit) -> bool:
	if target == null or not target.is_alive():
		return false
	match targeting:
		_Enums.Targeting.SELF:
			return target == user
		_Enums.Targeting.SINGLE_ALLY, _Enums.Targeting.ALLIES_IN_RANGE:
			return target.get_faction() == user.get_faction() and target != user
		_Enums.Targeting.SINGLE_ENEMY, _Enums.Targeting.ENEMIES_IN_RANGE:
			return target.get_faction() != user.get_faction()
		_Enums.Targeting.SINGLE_ANY:
			return true
	return true


func _collect_units(user:_Unit, allies: bool, max_range: int, context: Dictionary) -> Array:
	var pool: Array = context.get("all_units", [])
	if pool.is_empty() and user.hex_grid != null:
		pool = user.hex_grid.get_all_occupants()
	var out: Array = []
	for u in pool:
		if u == null or not u.is_alive():
			continue
		var is_ally: bool = u.get_faction() == user.get_faction()
		if allies and not is_ally:
			continue
		if not allies and is_ally:
			continue
		if max_range > 0:
			var dist: int = _HexCoord.distance(user.axial_pos, u.axial_pos)
			if dist > max_range:
				continue
		out.append(u)
	return out


func _is_effect_spec(item) -> bool:
	return item != null and item.get("effect_id") != null and str(item.effect_id) != ""


func _fail_use(user:_Unit, target:_Unit) -> Dictionary:
	if user != null and user.stats != null and user.stats.ap < get_ap_cost(user):
		return _Result.fail("not_enough_ap", id)
	if target != null and user != null and user.weapon != null and requires_enemy_target():
		var dist: int = _HexCoord.distance(user.axial_pos, target.axial_pos)
		if dist > get_range(user):
			return _Result.fail("out_of_range", id)
	return _Result.fail("cannot_use", id)
