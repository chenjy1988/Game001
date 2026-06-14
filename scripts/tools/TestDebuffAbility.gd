extends "res://scripts/core/abilities/Ability.gd"
##
## 单测用 DEBUFF 能力（眩晕）；演示 gather_effect_specs → 敌方挂 debuff
##

const _TestEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _TestEffectSpec = preload("res://scripts/core/abilities/AbilityEffectSpec.gd")


func _init() -> void:
	id = "test_daze"
	display_name = "测试眩晕"
	kind = _TestEnums.Kind.DEBUFF
	targeting = _TestEnums.Targeting.SINGLE_ENEMY
	ap_cost = 2


func gather_effect_specs(user, targets: Array, _context: Dictionary) -> Array:
	var specs: Array = []
	for t in targets:
		specs.append(_TestEffectSpec.debuff("dazed", t, user, 2))
	return specs
