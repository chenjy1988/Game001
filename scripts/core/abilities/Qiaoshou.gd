extends "res://scripts/core/abilities/Ability.gd"
class_name AbilityQiaoshou
##
## 巧手 — 通用主动技（class-system §5.4）
##
## 无消耗切换主武器（背包内已装武器二选一）。
## - kind:      UTILITY
## - targeting: SELF
## - 前提：必须装备了 offhand_weapon（副手武器）才有可切换对象
##

const _AbilEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")


func _init() -> void:
	id = "qiao_shou"
	display_name = "巧手"
	kind = _AbilEnums.Kind.UTILITY
	targeting = _AbilEnums.Targeting.SELF
	ap_cost = 0
	range_hexes = 0
	mutex_group = ""
	ai_hint = {
		"priority":    "default",
		"prefers":     "",
		"risk":        "low",
		"situational": 0.5,
	}


func _extra_can_use(user, _target) -> bool:
	if user == null:
		return false
	# 必须有副手武器才能切换
	return user.offhand_weapon != null


func apply(user, _target = null, _context: Dictionary = {}) -> Dictionary:
	if not can_use(user, null):
		return _fail_use(user, null)

	spend_resources(user, {})
	_swap_weapons(user)

	_on_ability_finished(user, [], [], {})
	return _Result.success(id, kind, {
		_Result.TARGETS: [user],
		_Result.EFFECTS_APPLIED: [],
	})


static func _swap_weapons(user) -> void:
	if user == null or user.offhand_weapon == null:
		return
	var tmp = user.weapon
	user.weapon = user.offhand_weapon
	user.offhand_weapon = tmp

	# 日志
	print("[巧手] %s 切换主武器: %s → %s" % [
		user.get_display_name() if user.has_method("get_display_name") else "",
		str(tmp.display_name) if tmp != null and "display_name" in tmp else "",
		str(user.weapon.display_name) if user.weapon != null and "display_name" in user.weapon else "",
	])

	user.stats_changed.emit(user)
