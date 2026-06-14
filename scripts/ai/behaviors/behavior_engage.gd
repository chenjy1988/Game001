extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Engage

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
const _AO = preload("res://scripts/ai/scoring/attack_opportunity.gd")
const _AIWorldView = preload("res://scripts/ai/world_view.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _U = preload("res://scripts/core/Unit.gd")

func _init() -> void: order = 10; behavior_id = "engage"; category = "attack"

func evaluate(view, profile = null) -> Dictionary:
	var unit = view.unit
	if unit == null or unit.hex_grid == null: return { "score": 0.0, "action": null }
	if profile != null and profile.should_delay_for_allies(view):
		return { "score": 0.0, "action": null }
	if can_attack_now(view):
		return { "score": 0.0, "action": null }
	var ap: int = unit.stats.ap
	if ap <= 0: return { "score": 0.0, "action": null }
	if ap < _U.AP_PER_HEX:
		return { "score": 0.0, "action": null }

	if profile != null and profile.uses_offensive_target_selection(view):
		var pick: Dictionary = _AO.pick(view, profile)
		if pick.get("phase") == "move" and pick.get("action") != null:
			var out: Dictionary = {
				"score": float(pick.get("score", 0.0)),
				"action": pick.action,
			}
			var db0 = _cfg()
			out.score += db0.behavior_baseline(behavior_id) if db0 else 20.0
			out.score *= _ranged_mult(view)
			if profile != null:
				out.score += profile.frontline_push_bonus(view)
			return out

	var setups: Array = filter_reach_move_attack_setups(view, find_move_attack_setups(view))
	if not setups.is_empty():
		return _best_from_setups(view, profile, setups)

	var atk_ap: int = unit.get_weapon_ap_cost()
	var faction: int = unit.get_faction()
	var reachable = unit.hex_grid.get_reachable(unit.axial_pos, ap / _U.AP_PER_HEX, faction)
	if reachable.is_empty(): return { "score": 0.0, "action": null }
	var wr: int = _attack_range(unit)
	var best = { "score": 0.0, "action": null }
	var cap: int = min(reachable.size(), _ES.candidate_cap())
	for i in range(cap):
		var dest = reachable[i]
		var path = unit.hex_grid.find_path(unit.axial_pos, dest, unit.axial_pos, faction)
		if path.is_empty(): continue
		var r = _ES.score_path(view, path, wr, profile)
		var move_cost: int = move_ap_cost(path)
		if can_attack_after_move(ap, path, atk_ap):
			var nd: int = nearest_enemy_distance_at(view, dest)
			if is_reach_weapon(unit):
				if nd == unit.weapon.range_max:
					r.score += 50.0
				elif nd < unit.weapon.range_max:
					r.score += 8.0
				else:
					r.score += 50.0
			else:
				r.score += 50.0
		else:
			var setup: float = 0.0
			if is_reach_weapon(unit):
				setup = _ES.score_reach_approach_path(view, path, profile)
			else:
				setup = _ES.score_setup_path(view, path, profile)
			if setup <= 0.0 and in_range_ap_short(view):
				setup = _ES.score_residual_reposition(view, path, wr, profile)
			if setup <= 0.0:
				continue
			r.score = setup
		# 长杆：丢弃贴脸落点（偏好评分层已惩罚，此处硬过滤）
		if is_reach_weapon(unit):
			var nd_check: int = nearest_enemy_distance_at(view, dest)
			if nd_check < preferred_engagement_distance(unit):
				continue
		if r.score > best.score:
			best = {"score": r.score, "action": _AT.move(path, r.score, "e→%s" % dest)}
	if best.score > 0.0:
		var db = _cfg()
		best.score += db.behavior_baseline(behavior_id) if db else 20
		best.score *= _ranged_mult(view)
		if profile != null:
			best.score += profile.frontline_push_bonus(view)
	return best


func _best_from_setups(view, profile, setups: Array) -> Dictionary:
	var wr: int = _attack_range(view.unit)
	var best = { "score": 0.0, "action": null }
	for setup in setups:
		var path: Array = setup["path"]
		var dest: Vector2i = setup["dest"]
		var r = _ES.score_path(view, path, wr, profile)
		var nd: int = nearest_enemy_distance_at(view, dest)
		var same_turn_bonus: float = 80.0 - float(setup["move_cost"]) * 2.0
		if is_reach_weapon(view.unit) and nd == view.unit.weapon.range_max:
			same_turn_bonus += 12.0
		elif is_reach_weapon(view.unit) and nd < view.unit.weapon.range_max:
			same_turn_bonus -= 25.0
		r.score += same_turn_bonus
		if r.score > best.score:
			best = {
				"score": r.score,
				"action": _AT.move(path, r.score, "e→%s+(atk)" % dest),
			}
	if best.score > 0.0:
		var db = _cfg()
		best.score += db.behavior_baseline(behavior_id) if db else 20
		best.score *= _ranged_mult(view)
		if profile != null:
			best.score += profile.frontline_push_bonus(view)
	return best


static func _cfg(): return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null

static func _ranged_mult(view) -> float:
	var bal: int = view.ranged_balance()
	if bal == _AIWorldView.RangedBalance.ENEMY_ADVANTAGE:
		return 1.3
	if bal == _AIWorldView.RangedBalance.ALLY_ADVANTAGE:
		return 0.7
	return 1.0

static func _already_in_range(view) -> bool:
	var u = view.unit
	if u.weapon == null: return false
	for e in view.alive_enemies:
		var d: int = _HC.distance(u.axial_pos, e.axial_pos)
		if d >= u.weapon.range_min and d <= u.weapon.range_max:
			return true
	return false

static func _attack_range(unit):
	if unit.weapon == null: return 1
	return unit.weapon.range_max
