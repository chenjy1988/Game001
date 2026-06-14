extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Preempt

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _ES = preload("res://scripts/ai/scoring/engage_scorer.gd")

func _init() -> void:
	order = 16
	behavior_id = "preempt"
	category = "support"


func evaluate(view, profile = null) -> Dictionary:
	if not can_spend_preempt_now(view) or not is_leftover_ap_for_preempt(view):
		return { "score": 0.0, "action": null }

	var util: float = compute_preempt_initiative_utility(view)
	if util <= 0.0:
		return { "score": 0.0, "action": null }

	var score: float = util
	var opp_weight: float = 0.85
	var db = _cfg()
	if db:
		opp_weight = db.breath_attack_opportunity_weight()
	if can_attack_now(view):
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
		score *= profile.behavior_mult("preempt", view.unit)
	if db:
		score += db.behavior_baseline(behavior_id)
	return {
		"score": score,
		"action": _AT.ability("preempt", null, {}, score, "preempt_initiative"),
	}


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
