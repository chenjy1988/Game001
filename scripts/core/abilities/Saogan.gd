extends "res://scripts/core/abilities/Ability.gd"
class_name AbilitySaogan
##
## 扫杆逼退 — 双手矛/马槊技能（class-system §5.10）
##
## 横扫长杆压位：对相邻目标造成中等伤害并击退 1 格。
## - kind:      HYBRID（攻击 + 位移）
## - targeting: SINGLE_ENEMY，相邻
## - ai_hint:   priority="positioning"，能把敌人推开是 reposition 价值的核心
##

const _MovementSpec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _AbilEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")
const _AtkResult = preload("res://scripts/core/abilities/AbilityResult.gd")


func _init() -> void:
	id = "sao_gan"
	display_name = "扫杆逼退"
	kind = _AbilEnums.Kind.HYBRID
	targeting = _AbilEnums.Targeting.SINGLE_ENEMY
	ap_cost = 5
	range_hexes = 1
	weapon_filter = ["spear", "modao"]   # 双手矛/陌刀
	mutex_group = "attack"
	ai_hint = {
		"priority": "positioning",
		"prefers": "near_terrain_hazard",  # 击退到悬崖/水/火
		"risk": "low",
		"situational": 8.0,
	}


func gather_movement_specs(user, targets: Array, _context: Dictionary) -> Array:
	if targets.is_empty():
		return []
	# 击退 1 格；撞到障碍/单位时停下
	return [
		_MovementSpec.push(targets[0], user.axial_pos, 1, 0)
	]


## HYBRID：先打伤害再位移（位移由 apply 默认流程处理）
func apply(user, target = null, context: Dictionary = {}) -> Dictionary:
	if not can_use(user, target):
		return _fail_use(user, target)

	spend_resources(user, context)
	if user.weapon != null:
		user.stats.spend_stamina(_DamageSystem.calculate_attack_stamina_cost(user))

	# 1) 伤害（中等：×0.7 武器伤）
	var options: Dictionary = {
		"ability": id,
		"ability_damage_mult": 0.7,
	}
	if user.weapon != null and not user.weapon.attack_modes.is_empty():
		options["mode"] = user.weapon.attack_modes[0]
	var dmg_result: Dictionary = _DamageSystem.execute_attack(user, target, options)
	user._apply_attack_result(user, target, dmg_result)
	user.face_toward(target.axial_pos)
	user.attacked.emit(user, target, dmg_result)

	# 2) 位移（默认 apply 流程的位移钩子）
	var movements: Array = gather_movement_specs(user, [target], context)
	var move_results: Array = apply_movement_specs(user, movements, context)

	user.stats_changed.emit(user)

	dmg_result[_AtkResult.OK] = true
	dmg_result[_AtkResult.ABILITY_ID] = id
	dmg_result[_AtkResult.KIND] = kind
	dmg_result["movements"] = move_results
	return dmg_result
