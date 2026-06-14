extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Advance

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _U = preload("res://scripts/core/Unit.gd")

func _init() -> void: order = 11; behavior_id = "advance"; category = "attack"


func evaluate(view, profile = null) -> Dictionary:
	var unit = view.unit
	if unit == null or unit.hex_grid == null:
		return { "score": 0.0, "action": null }
	if profile != null and profile.should_delay_for_allies(view):
		return { "score": 0.0, "action": null }
	if can_attack_now(view):
		return { "score": 0.0, "action": null }
	if has_move_attack_setup(view):
		return { "score": 0.0, "action": null }
	var ap: int = unit.stats.ap
	if ap < _U.AP_PER_HEX:
		return { "score": 0.0, "action": null }
	var atk_ap: int = unit.get_weapon_ap_cost()
	var faction: int = unit.get_faction()
	var reachable = unit.hex_grid.get_reachable(unit.axial_pos, ap / _U.AP_PER_HEX, faction)
	if reachable.is_empty():
		return { "score": 0.0, "action": null }
	var wr: int = _attack_range(unit)
	var move_budget: int = max_move_ap_for_attack(view)
	var best = { "score": 0.0, "action": null }
	var cap: int = min(reachable.size(), _ES.candidate_cap())
	for i in range(cap):
		var dest = reachable[i]
		var path = unit.hex_grid.find_path(unit.axial_pos, dest, unit.axial_pos, faction)
		if path.is_empty():
			continue
		if is_reach_weapon(unit):
			var nd_check: int = nearest_enemy_distance_at(view, dest)
			if nd_check < preferred_engagement_distance(unit):
				continue
		var score: float = 0.0
		if ap >= atk_ap and can_attack_after_move(ap, path, atk_ap):
			var r = _ES.score_path(view, path, wr, profile)
			score = r.score
			if move_ap_cost(path) > move_budget:
				score -= 50.0
		elif ap < atk_ap:
			# 残 AP 无法本回合攻击：禁止纯 proximity 前压，仅允许 setup 净收益
			if is_reach_weapon(unit):
				score = _ES.score_reach_approach_path(view, path, profile)
			else:
				score = _ES.score_setup_path(view, path, profile)
			if score <= 0.0:
				continue
		else:
			var r = _ES.score_path(view, path, wr, profile)
			score = r.score
			if move_ap_cost(path) > move_budget:
				score -= 50.0
		if score > best.score:
			best = { "score": score, "action": _AT.move(path, score, "adv→%s" % dest) }
	if best.score > 0.0:
		var db = _cfg()
		best.score += db.behavior_baseline(behavior_id) if db else 35
		if profile != null:
			best.score += profile.frontline_push_bonus(view)
	return best


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null


static func _already_in_range(view) -> bool:
	var u = view.unit
	if u.weapon == null:
		return false
	for e in view.alive_enemies:
		var d: int = _HC.distance(u.axial_pos, e.axial_pos)
		if d >= u.weapon.range_min and d <= u.weapon.range_max:
			return true
	return false


static func _attack_range(unit) -> int:
	if unit.weapon == null:
		return 1
	return unit.weapon.range_max
