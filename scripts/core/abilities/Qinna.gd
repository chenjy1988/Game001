extends "res://scripts/core/abilities/Ability.gd"
class_name AbilityQinna
##
## 擒拿拉拽 — 不良人专属（class-system §六 位移类）
##
## 将相邻或 2 格内目标拉向自身 1-2 格。
## - kind:      UTILITY
## - targeting: SINGLE_ENEMY，2 格内
## - ai_hint:   priority="positioning"，AI 倾向于"把孤立目标拉到围杀圈"
##
## 与推撞区别：擒拿是把人拉过来（聚集），推撞是把人推走（分散）。
##

const _MovementSpec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _AbilEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")


func _init() -> void:
	id = "qin_na"
	display_name = "擒拿拉拽"
	kind = _AbilEnums.Kind.UTILITY
	targeting = _AbilEnums.Targeting.SINGLE_ENEMY
	ap_cost = 3
	range_hexes = 2
	# weapon_filter 留空：通用辅助池，任何武器都能学（设计未限定鞭/绳）
	mutex_group = "attack"
	ai_hint = {
		"priority": "positioning",
		"prefers": "isolated",       # 拉孤立目标进围杀圈
		"risk": "medium",
		"situational": 10.0,
	}


func _extra_can_use(user, target) -> bool:
	if user == null or target == null or user.stats == null or target.stats == null:
		return false
	# 重量限制：目标重量 ≤ 自身 1.5 倍（简化版：HP 比例做近似）
	var user_hp_max: float = float(max(1, user.stats.max_hp))
	var target_hp_max: float = float(max(1, target.stats.max_hp))
	return target_hp_max <= user_hp_max * 1.5


func gather_movement_specs(user, targets: Array, _context: Dictionary) -> Array:
	if targets.is_empty():
		return []
	# 拉 1 格（距离 1 时直接相邻 = 拉到原位旁；距离 2 时拉到相邻）
	var dist: int = preload("res://scripts/core/HexCoord.gd").distance(user.axial_pos, targets[0].axial_pos)
	var pull_dist: int = 1 if dist <= 2 else 2
	return [
		_MovementSpec.pull(targets[0], user.axial_pos, pull_dist, true)
	]
