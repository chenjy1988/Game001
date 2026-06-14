extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Retreat

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _U = preload("res://scripts/core/Unit.gd")

func _init() -> void: order = 8; behavior_id = "retreat"; category = "retreat"


func evaluate(view, profile = null) -> Dictionary:
	var unit = view.unit
	if unit == null or unit.hex_grid == null:
		return { "score": 0.0, "action": null }
	if not _should_retreat(view):
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
		var gain: float = float(min_dist - cur_min)
		var r = _ES.score_path(view, path, 1, profile)
		var score: float = gain * 8.0 + r.score
		if score > best.score:
			best = { "score": score, "action": _AT.move(path, score, "ret→%s" % dest) }

	if best.score > 0.0:
		var db = _cfg()
		best.score += db.behavior_baseline(behavior_id) if db else 60
	return best


static func _should_retreat(view) -> bool:
	var brain: Dictionary = view.faction_brain
	if brain.get("stance", "") == "retreat":
		return true
	var u = view.unit
	if u.stats == null:
		return false
	var hp_ratio: float = float(u.stats.hp) / float(max(1, u.stats.max_hp))
	if hp_ratio < 0.3 and brain.get("power_ratio", 1.0) < 0.85:
		return true
	return false


static func _min_enemy_dist(view, tile: Vector2i) -> int:
	var best: int = 99
	for e in view.alive_enemies:
		best = mini(best, _HC.distance(tile, e.axial_pos))
	return best


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
