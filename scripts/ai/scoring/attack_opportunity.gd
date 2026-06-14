extends RefCounted
class_name AIAttackOpportunity

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _Scorer = preload("res://scripts/ai/scoring/target_scorer.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
const _Behavior = preload("res://scripts/ai/behaviors/behavior_base.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _ActionScorer = preload("res://scripts/ai/scoring/action_scorer.gd")

## 进攻型目标选择（非 guard 倾向）：比较原地攻 vs 走+打净收益
static func pick(view, profile = null) -> Dictionary:
	var empty: Dictionary = {"score": 0.0, "utility": 0.0, "action": null, "phase": ""}
	if view == null or view.unit == null or view.unit.weapon == null:
		return empty
	if profile != null and not profile.uses_offensive_target_selection(view):
		return empty

	var scale: float = _utility_scale()
	var best_adj: Dictionary = _best_attack_from_tile(view, profile, view.unit.axial_pos, [], scale)
	var best_move: Dictionary = _best_move_attack(view, profile, scale)

	if best_adj.get("action") != null:
		var adj_u: float = float(best_adj.get("utility", 0.0))
		var move_u: float = float(best_move.get("utility", 0.0))
		var close_margin: float = scale * 0.25 if _Behavior.is_reach_weapon(view.unit) else 0.0
		if best_move.get("action") == null or adj_u + close_margin >= move_u:
			best_adj["phase"] = "attack"
			return best_adj

	if best_move.get("action") != null and float(best_move.get("utility", 0.0)) > 0.0:
		best_move["phase"] = "move"
		return best_move

	if best_adj.get("action") != null:
		best_adj["phase"] = "attack"
		return best_adj
	return empty


static func _utility_scale() -> float:
	var db = Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
	return db.attack_utility_scale() if db else 100.0


static func _best_attack_from_tile(
	view,
	profile,
	tile: Vector2i,
	path: Array,
	scale: float,
) -> Dictionary:
	var unit = view.unit
	var rmin: int = unit.weapon.range_min
	var rmax: int = unit.weapon.range_max
	if unit.stats.ap < unit.get_weapon_ap_cost():
		return {"score": 0.0, "utility": 0.0, "action": null}
	var focus_units: Array = view.faction_brain.get("focus_marks", [])
	var et: int = int(view.faction_brain.get("enemy_total", 99))
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]

	var best: Dictionary = {"score": 0.0, "utility": 0.0, "action": null}
	for target in view.alive_enemies:
		var dist: int = _HC.distance(tile, target.axial_pos)
		if dist < rmin or dist > rmax:
			continue
		for mode in modes:
			var opt: Dictionary = {"enemy_total": et}
			if mode != "":
				opt["mode"] = mode
			var ts: float = _Scorer.score(unit, target, opt, target in focus_units)
			if profile != null:
				ts *= profile.target_mult()
			if ts <= 0.0:
				continue
			var utility: float = ts * scale
			if utility > float(best.get("utility", 0.0)):
				var reason: String = "atk→%s(%s)" % [target.get_unit_name(), mode]
				if not path.is_empty():
					reason = "atk→%s(%s) after move" % [target.get_unit_name(), mode]
				best = {
					"score": ts,
					"utility": utility,
					"action": _AT.attack(target, mode, ts, reason),
				}
	return best


static func _best_move_attack(view, profile, scale: float) -> Dictionary:
	var unit = view.unit
	var best: Dictionary = {"score": 0.0, "utility": 0.0, "action": null}
	for setup in _Behavior.filter_reach_move_attack_setups(view, _Behavior.find_move_attack_setups(view)):
		var path: Array = setup.get("path", [])
		var dest: Vector2i = setup.get("dest", Vector2i.ZERO)
		if path.is_empty():
			continue
		var atk_plan: Dictionary = _best_attack_from_tile(view, profile, dest, path, scale)
		if atk_plan.get("action") == null:
			continue
		var ndist: int = _nearest_enemy_dist(view, dest)
		var entry: Dictionary = _ActionScorer.compute_entry_costs(view, path, profile)
		var reach_bonus: float = _Behavior.reach_position_bias(unit, ndist) * scale
		var net_u: float = float(atk_plan.get("utility", 0.0)) \
			- float(entry.get("surround_cost", 0.0)) \
			- float(entry.get("oa_cost", 0.0)) \
			+ float(entry.get("self_state", 0.0)) \
			+ reach_bonus
		var move_score: float = float(atk_plan.get("score", 0.0)) \
			- float(entry.get("surround_cost", 0.0)) / maxf(1.0, scale) \
			- float(entry.get("oa_cost", 0.0)) / maxf(1.0, scale) \
			+ float(entry.get("self_state", 0.0)) / maxf(1.0, scale) \
			+ reach_bonus / maxf(1.0, scale)
		if net_u > float(best.get("utility", 0.0)):
			best = {
				"score": move_score,
				"utility": net_u,
				"action": _AT.move(path, move_score, "e→%s+(atk)" % dest),
			}
	return best


static func _nearest_enemy_dist(view, tile: Vector2i) -> int:
	var best: int = 99
	for e in view.alive_enemies:
		best = mini(best, _HC.distance(tile, e.axial_pos))
	return best


static func _oa_utility_penalty(view, unit, path: Array, profile, _scale: float) -> float:
	return _ES.oa_utility_penalty(view, unit, path, profile)
