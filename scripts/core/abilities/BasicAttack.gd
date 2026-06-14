extends "res://scripts/core/abilities/Ability.gd"
class_name BasicAttackAbility
##
## BasicAttack.gd — 武器普攻（所有职业默认攻击路径）
##

const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")
const _AtkEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _AtkResult = preload("res://scripts/core/abilities/AbilityResult.gd")


func _init() -> void:
	id = "basic_attack"
	display_name = "普攻"
	kind = _AtkEnums.Kind.ATTACK
	targeting = _AtkEnums.Targeting.SINGLE_ENEMY
	mutex_group = "attack"
	ai_hint = { "priority": "default", "prefers": "", "risk": "medium", "situational": 0.0 }


func get_ap_cost(user:_Unit) -> int:
	if user == null:
		return 999
	return user.get_weapon_ap_cost()


func can_use(user:_Unit, target:_Unit = null) -> bool:
	if user.weapon == null:
		return false
	return super.can_use(user, target)


func build_damage_options(user:_Unit, context: Dictionary) -> Dictionary:
	var mode: String = context.get("attack_mode", "")
	if mode.is_empty() and user.weapon != null:
		if not user.weapon.attack_modes.is_empty():
			mode = user.weapon.attack_modes[0]
		else:
			mode = user.weapon.damage_type
	var options: Dictionary = {
		"ability": id,
		"mastery_dmg": 0.9 if user.has_unfamiliar_weapon() else 1.0,
	}
	if not mode.is_empty():
		options["mode"] = mode
	# Phase 2.5：职业技能通过 context 注入 ability_damage_mult 等
	for key in ["ability_damage_mult", "ability_hit_modifier", "force_head_chance",
			"force_body_only", "mastery_crit_bonus", "trait_damage_bonus",
			"double_grip", "ignore_armor", "hp_only", "is_opportunity_attack"]:
		if context.has(key):
			options[key] = context[key]
	return options


func apply(user:_Unit, target:_Unit = null, context: Dictionary = {}) -> Dictionary:
	if not can_use(user, target):
		return _fail_use(user, target)

	spend_resources(user, context)
	user.stats.spend_stamina(_DamageSystem.calculate_attack_stamina_cost(user))

	var options: Dictionary = build_damage_options(user, context)
	var result: Dictionary = _DamageSystem.execute_attack(user, target, options)

	var defend_fat: int = _Unit.apply_defend_stamina_cost(target)
	if defend_fat > 0:
		result["defend_stamina"] = defend_fat

	_Unit._apply_attack_result(user, target, result)
	user.face_toward(target.axial_pos)
	user.stats_changed.emit(user)
	user.attacked.emit(user, target, result)

	if result.get("hit", false) and target.is_alive() \
			and not result.get("is_opportunity_attack", false):
		user._try_pincer_attack(target)

	result[_AtkResult.OK] = true
	result[_AtkResult.ABILITY_ID] = id
	result[_AtkResult.KIND] = kind
	result[_AtkResult.PRIMARY] = result.duplicate(true)
	return result
