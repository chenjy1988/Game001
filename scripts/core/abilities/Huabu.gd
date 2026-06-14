extends "res://scripts/core/abilities/Ability.gd"
class_name AbilityHuabu
##
## 滑步 — 通用辅助技（class-system §5.4）
##
## 移动 1 格不触发借机（本回合仍可攻击）。
## - kind:      UTILITY
## - targeting: NONE（落点由 context.target_tile 提供）
## - ai_hint:   priority="positioning"，AI 自动作为 reposition 候选
##
## 与"突击冲锋"区别：滑步是脱战，不附带攻击；冲锋是冲入再打。
##

const _MovementSpec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _AbilEnums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")


func _init() -> void:
	id = "hua_bu"
	display_name = "滑步"
	kind = _AbilEnums.Kind.UTILITY
	targeting = _AbilEnums.Targeting.NONE
	ap_cost = 2
	range_hexes = 1
	ai_hint = {
		"priority": "positioning",
		"prefers": "in_zoc",         # 被 ZoC 缠住时用
		"risk": "low",                # 不触发借机
		"situational": 6.0,
	}


func _extra_can_use(user, _target) -> bool:
	# 落点存在 + 1 格内 + 无人占据
	if user == null or user.hex_grid == null:
		return false
	# 落点由 UI/AI 注入；这里只校验类自身可用性
	return true


func gather_movement_specs(user, _targets: Array, context: Dictionary) -> Array:
	if user == null:
		return []
	var dest = context.get("target_tile", null)
	# AI 缺省：取距离最近敌人最近的相邻空格
	if dest == null:
		dest = _pick_default_dest(user)
	if dest == null:
		return []
	return [
		_MovementSpec.teleport(user, dest, true, false)
	]


static func _pick_default_dest(user):
	# 取 6 邻格里最接近最近敌人的空格
	var grid = user.hex_grid
	if grid == null:
		return null
	var best_dest = null
	var best_score: float = INF
	for d in range(6):
		var nb: Vector2i = _HexCoord.neighbor(user.axial_pos, d)
		if not grid._hexes.has(nb): continue
		if grid.get_occupant(nb) != null: continue
		# 越接近最近敌人越好
		var min_dist: int = 99
		for occ in grid._occupants.values():
			if occ == null or occ == user or not occ.is_alive(): continue
			if occ.get_faction() == user.get_faction(): continue
			min_dist = mini(min_dist, _HexCoord.distance(nb, occ.axial_pos))
		var score: float = float(min_dist)
		if score < best_score:
			best_score = score
			best_dest = nb
	return best_dest
