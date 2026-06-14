extends "res://scripts/core/abilities/Ability.gd"
class_name AbilityTujichongfeng
##
## 突击冲锋 — 跳荡专属短矛技能（class-system §5.5）
##
## 朝目标方向移动 ≥2 格后攻击。
## - kind:      HYBRID（位移 + 攻击）
## - targeting: SINGLE_ENEMY，3 格内（含助跑）
## - ai_hint:   priority="positioning"，破阵专长
##

const _MovementSpec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _AbilEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")
const _AtkResult = preload("res://scripts/core/abilities/AbilityResult.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")


func _init() -> void:
	id = "tu_ji_chong_feng"
	display_name = "突击冲锋"
	kind = _AbilEnums.Kind.HYBRID
	targeting = _AbilEnums.Targeting.SINGLE_ENEMY
	ap_cost = 6  # 武器 AP + 2，按短矛 4 AP 估
	range_hexes = 3
	weapon_filter = ["javelin"]   # 短矛
	mutex_group = "attack"
	ai_hint = {
		"priority": "positioning",
		"prefers": "armored",
		"risk": "medium",
		"situational": 12.0,
	}


func _extra_can_use(user, target) -> bool:
	if user == null or target == null:
		return false
	# 必须有 ≥2 格直线助跑距离
	var dist: int = _HexCoord.distance(user.axial_pos, target.axial_pos)
	return dist >= 2


func gather_movement_specs(user, targets: Array, _context: Dictionary) -> Array:
	if targets.is_empty():
		return []
	# 冲到目标的相邻格（沿 attacker → target 方向，停在 target 前一格）
	var target = targets[0]
	var dir_idx: int = _HexCoord.approx_direction(user.axial_pos, target.axial_pos)
	var landing: Vector2i = target.axial_pos
	# 退一步：landing = target - dir
	landing = target.axial_pos - _HexCoord.DIRECTIONS[dir_idx]
	return [
		_MovementSpec.dash(user, landing, false)  # 触发 ZoC（不像滑步）
	]


func apply(user, target = null, context: Dictionary = {}) -> Dictionary:
	if not can_use(user, target):
		return _fail_use(user, target)

	spend_resources(user, context)
	user.stats.spend_stamina(_DamageSystem.calculate_attack_stamina_cost(user))

	# 1) 先冲（位移）
	var movements: Array = gather_movement_specs(user, [target], context)
	var move_results: Array = apply_movement_specs(user, movements, context)
	# 冲锋失败（被路径阻挡）→ 不打伤害，能力结束
	if not move_results.is_empty() and not move_results[0].get("ok", false):
		user.stats_changed.emit(user)
		return _AtkResult.fail("dash_failed", id)

	# 2) 再打（伤害 ×1.2）
	var options: Dictionary = {
		"ability": id,
		"ability_damage_mult": 1.2,
	}
	if user.weapon != null and not user.weapon.attack_modes.is_empty():
		options["mode"] = user.weapon.attack_modes[0]
	var dmg_result: Dictionary = _DamageSystem.execute_attack(user, target, options)
	user._apply_attack_result(user, target, dmg_result)
	user.face_toward(target.axial_pos)
	user.attacked.emit(user, target, dmg_result)
	user.stats_changed.emit(user)

	dmg_result[_AtkResult.OK] = true
	dmg_result[_AtkResult.ABILITY_ID] = id
	dmg_result[_AtkResult.KIND] = kind
	dmg_result["movements"] = move_results
	return dmg_result
