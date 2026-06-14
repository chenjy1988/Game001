extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Ability

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _AbilityLibrary = preload("res://scripts/core/AbilityLibrary.gd")
const _Enums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _AIBehavior = preload("res://scripts/ai/behaviors/behavior_base.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")

func _init() -> void:
	order = 18
	behavior_id = "ability"
	category = "support"


func evaluate(view, profile = null) -> Dictionary:
	var unit = view.unit
	if unit == null or unit.stats == null or unit.stats.ap <= 0:
		return { "score": 0.0, "action": null }
	if unit.has_meta("_ai_job_ability_used") and unit.get_meta("_ai_job_ability_used"):
		return { "score": 0.0, "action": null }
	# 能直接攻击且期望收益足够时，让位给 Attack（避免移形/包扎空转 AP）
	if _AIBehavior.can_attack_now(view):
		var opp_now: Dictionary = best_attack_utility(view, profile, false)
		if float(opp_now.get("utility", 0.0)) > 12.0:
			return { "score": 0.0, "action": null }
	var ids: Array = _job_ability_ids(unit)
	if ids.is_empty():
		return { "score": 0.0, "action": null }

	var best = { "score": 0.0, "action": null }
	for ab_id in ids:
		var ab = _AbilityLibrary.get_by_id(String(ab_id))
		if ab == null:
			continue
		var pick: Dictionary = _score_ability(view, profile, ab)
		if float(pick.get("score", 0.0)) > float(best.get("score", 0.0)):
			best = pick

	if best.get("action") == null:
		return { "score": 0.0, "action": null }
	var db = _cfg()
	if db:
		best.score += db.behavior_baseline(behavior_id)
	return best


static func _job_ability_ids(unit) -> Array:
	if unit == null:
		return []
	if unit.has_method("get_job_ability_ids"):
		return unit.get_job_ability_ids()
	return []


static func _score_ability(view, profile, ab) -> Dictionary:
	var unit = view.unit
	var hint: Dictionary = ab.ai_hint if ab.ai_hint is Dictionary else {}
	var situational: float = float(hint.get("situational", 0.0))
	var category_mult: float = _category_mult(String(hint.get("priority", "default")))

	var best_target = null
	var best_score: float = 0.0
	for cand in _candidate_targets(view, ab):
		if not ab.can_use(unit, cand):
			continue
		var ts: float = situational + _target_bias(view, hint, cand)
		if ts > best_score:
			best_score = ts
			best_target = cand

	if best_target == null and ab.targeting == _Enums.Targeting.SELF:
		if ab.can_use(unit, unit):
			best_target = unit
			best_score = situational

	if best_target == null:
		return { "score": 0.0, "action": null }

	var score: float = best_score * category_mult * 8.0
	var opp_weight: float = 0.85
	var db = _cfg()
	if db:
		opp_weight = db.breath_attack_opportunity_weight()
	# AP 不够攻：与 setup 走位 / 攻击机会综合比较，而非只看 attack
	if _AIBehavior.can_attack_now(view):
		var opp: Dictionary = best_attack_utility(view, profile, false)
		score -= float(opp.get("utility", 0.0)) * opp_weight
	else:
		var alt_u: float = maxf(
			float(best_attack_utility(view, profile, true).get("utility", 0.0)),
			_ES.estimate_best_path_utility(view, profile),
		)
		score -= alt_u * opp_weight
	if score <= 0.0:
		return { "score": 0.0, "action": null }
	if profile != null:
		score *= profile.behavior_mult("ability", unit)
	return {
		"score": score,
		"action": _AT.ability(ab.id, best_target, {}, score, "abil→%s" % ab.id),
	}


static func _candidate_targets(view, ab):
	var out: Array = []
	var unit = view.unit
	match ab.targeting:
		_Enums.Targeting.SELF:
			out.append(unit)
		_Enums.Targeting.SINGLE_ENEMY, _Enums.Targeting.SINGLE_ANY:
			for e in view.alive_enemies:
				out.append(e)
		_Enums.Targeting.SINGLE_ALLY:
			for a in view.alive_allies:
				out.append(a)
			if not out.has(unit):
				out.append(unit)
		_:
			for e in view.alive_enemies:
				out.append(e)
	return out


static func _target_bias(view, hint: Dictionary, target) -> float:
	var prefers: String = String(hint.get("prefers", ""))
	if prefers == "low_hp_ally" and target.stats != null:
		var ratio: float = float(target.stats.hp) / float(max(1, target.stats.max_hp))
		return (1.0 - ratio) * 20.0
	if prefers == "low_hp" and target.stats != null:
		var r: float = float(target.stats.hp) / float(max(1, target.stats.max_hp))
		return (1.0 - r) * 15.0
	if prefers == "in_zoc":
		for e in view.alive_enemies:
			if _HC.distance(view.unit.axial_pos, e.axial_pos) == 1:
				return 10.0
	return 0.0


static func _category_mult(priority: String) -> float:
	match priority:
		"kill", "armor_break":
			return 1.3
		"debuff":
			return 1.1
		"buff":
			return 1.0
		"positioning":
			return 0.95
		_:
			return 0.85


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
