extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Defend

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")

func _init() -> void: order = 30; behavior_id = "defend"; category = "defend"


func evaluate(view, profile = null) -> Dictionary:
	if view.unit == null:
		return { "score": 0.0, "action": null }
	if profile != null and profile.is_hanging_back(view):
		return { "score": 0.0, "action": null }
	var threat: int = _adjacent_enemies(view)
	if threat < 2:
		return { "score": 0.0, "action": null }
	if view.faction_brain.get("stance", "") == "attack":
		return { "score": 0.0, "action": null }
	if not view.can_wait():
		return { "score": 0.0, "action": null }
	var db = _cfg()
	var score: float = db.behavior_baseline(behavior_id) if db else 50.0
	score += float(threat) * 8.0
	if view.unit.weapon != null and view.unit.get_equipment_block_pts() >= 12:
		score += 15.0
	score += faction_hold_bonus(view, profile)
	score = subtract_attack_opportunity(score, view, profile)
	if score <= 0.0:
		return { "score": 0.0, "action": null }
	return { "score": score, "action": _AT.wait("defend") }


static func _adjacent_enemies(view) -> int:
	var n: int = 0
	var pos = view.unit.axial_pos
	for d in range(6):
		var nb = _HC.neighbor(pos, d)
		var occ = view.get_occupant(nb)
		if occ != null and occ.is_alive() and occ.get_faction() != view.unit.get_faction():
			n += 1
	return n


static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
