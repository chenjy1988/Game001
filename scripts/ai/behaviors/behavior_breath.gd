extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Breath

const _AT = preload("res://scripts/ai/_ai_action.gd")

func _init() -> void:
	order = 17
	behavior_id = "breath"
	category = "defend"


func evaluate(view, profile = null) -> Dictionary:
	if not can_spend_breath_now(view):
		return { "score": 0.0, "action": null }
	var util: float = compute_breath_recovery_utility(view, profile)
	if util <= 0.0:
		return { "score": 0.0, "action": null }

	var opp: Dictionary = best_attack_utility(view, profile, false)

	var db = _cfg()
	var opp_weight: float = db.breath_attack_opportunity_weight() if db else 1.0
	var score: float = util - float(opp.get("utility", 0.0)) * opp_weight
	if score <= 0.0:
		return { "score": 0.0, "action": null }

	return {
		"score": score,
		"action": _AT.ability("breath_regulation", null, {}, score, "breath_recovery_utility"),
	}


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
