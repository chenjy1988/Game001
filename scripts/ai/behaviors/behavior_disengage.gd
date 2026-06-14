extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Disengage

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _U = preload("res://scripts/core/Unit.gd")

func _init() -> void: order = 15; behavior_id = "disengage"; category = "reposition"


func evaluate(view, profile = null) -> Dictionary:
	var unit = view.unit
	if unit == null or unit.hex_grid == null or unit.weapon == null:
		return { "score": 0.0, "action": null }
	# 残局收刀：禁止后撤风筝（1v1/2v2 拖回合主因之一）
	var et: int = int(view.faction_brain.get("enemy_total", 99))
	if et > 0 and et <= 2:
		return { "score": 0.0, "action": null }
	if not _is_meleed(view):
		return { "score": 0.0, "action": null }
	# 近战已在射程：AP 不够也应守位/结束，不应撤（脱战仅给远程被贴脸）
	if unit.weapon.weapon_type != "ranged" and in_attack_range(view):
		return { "score": 0.0, "action": null }
	if can_attack_now(view):
		return { "score": 0.0, "action": null }
	var ap: int = unit.stats.ap
	if ap < _U.AP_PER_HEX:
		return { "score": 0.0, "action": null }
	var faction: int = unit.get_faction()
	var reachable = unit.hex_grid.get_reachable(unit.axial_pos, ap / _U.AP_PER_HEX, faction)
	if reachable.is_empty():
		return { "score": 0.0, "action": null }

	var best = { "score": 0.0, "action": null }
	var cap: int = min(reachable.size(), _ES.candidate_cap())
	for i in range(cap):
		var dest = reachable[i]
		var path = unit.hex_grid.find_path(unit.axial_pos, dest, unit.axial_pos, faction)
		if path.is_empty():
			continue
		var min_dist: int = _min_enemy_dist(view, dest)
		var cur_min: int = _min_enemy_dist(view, unit.axial_pos)
		if min_dist <= cur_min:
			continue
		var r = _ES.score_path(view, path, unit.weapon.range_max, profile)
		var score: float = r.score + float(min_dist - cur_min) * 8.0
		if score > best.score:
			best = { "score": score, "action": _AT.move(path, score, "dis→%s" % dest) }

	if best.score > 0.0:
		var db = _cfg()
		best.score += db.behavior_baseline(behavior_id) if db else 55
	return best


static func _is_meleed(view) -> bool:
	var u = view.unit
	for e in view.alive_enemies:
		if e.weapon != null and e.weapon.weapon_type == "ranged":
			continue
		if _HC.distance(u.axial_pos, e.axial_pos) == 1:
			return true
	if u.weapon.weapon_type == "ranged":
		return _adjacent_enemy_count(view) > 0
	return false


static func _adjacent_enemy_count(view) -> int:
	var n: int = 0
	for e in view.alive_enemies:
		if _HC.distance(view.unit.axial_pos, e.axial_pos) == 1:
			n += 1
	return n


static func _min_enemy_dist(view, tile: Vector2i) -> int:
	var best: int = 99
	for e in view.alive_enemies:
		best = mini(best, _HC.distance(tile, e.axial_pos))
	return best


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
