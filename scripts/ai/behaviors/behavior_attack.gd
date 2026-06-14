extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Attack

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _Scorer = preload("res://scripts/ai/scoring/target_scorer.gd")
const _AO = preload("res://scripts/ai/scoring/attack_opportunity.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")

func _init() -> void: order = 20; behavior_id = "attack"; category = "attack"

func evaluate(view, profile = null) -> Dictionary:
	if view.unit == null or view.unit.weapon == null:
		return { "score": 0.0, "action": null }
	if profile != null and profile.should_delay_for_allies(view):
		return { "score": 0.0, "action": null }
	if profile != null and profile.uses_offensive_target_selection(view):
		var pick: Dictionary = _AO.pick(view, profile)
		if pick.get("phase") == "attack" and pick.get("action") != null:
			var scale: float = db_scale()
			return {"score": float(pick.get("score", 0.0)) * scale, "action": pick.action}
	var candidates = _collect_attack_candidates(view, profile)
	if candidates.is_empty(): return { "score": 0.0, "action": null }
	var best = candidates[0]
	for a in candidates:
		if a.score > best.score:
			best = a
	var db = _cfg()
	var scale: float = db.attack_utility_scale() if db else 100.0
	var score: float = best.score * scale
	var et: int = int(view.faction_brain.get("enemy_total", 99))
	if et > 0 and et <= 2:
		score *= 1.55
	if et == 1:
		score *= 1.35
	return { "score": score, "action": best }


static func db_scale() -> float:
	var db = _cfg()
	return db.attack_utility_scale() if db else 100.0

static func _cfg(): return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null

static func _collect_attack_candidates(view, profile = null) -> Array:
	var unit = view.unit
	if unit == null or unit.weapon == null: return []
	var rmin: int = unit.weapon.range_min; var rmax: int = unit.weapon.range_max
	if unit.stats.ap < unit.get_weapon_ap_cost(): return []
	var focus_units: Array = view.faction_brain.get("focus_marks", [])
	var candidates: Array = []
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty(): modes = ["slash"]
	for target in view.alive_enemies:
		var dist: int = _HC.distance(unit.axial_pos, target.axial_pos)
		if dist < rmin or dist > rmax: continue
		var in_focus: bool = target in focus_units
		for mode in modes:
			var opt: Dictionary = {"enemy_total": int(view.faction_brain.get("enemy_total", 99))}
			if mode != "":
				opt["mode"] = mode
			var s: float = _Scorer.score(unit, target, opt, in_focus)
			if profile != null:
				s *= profile.target_mult()
			if s > 0.0:
				candidates.append(_AT.attack(target, mode, s, "atk→%s(%s)" % [target.get_unit_name(), mode]))
	# 注意：不在此生成"走+打"候选——进攻型目标优选走 AIAttackOpportunity；否则 Engage 补位。
	return candidates
