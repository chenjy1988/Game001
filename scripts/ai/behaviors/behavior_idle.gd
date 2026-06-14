extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Idle

const _AT = preload("res://scripts/ai/_ai_action.gd")

func _init() -> void:
	order = 1000; behavior_id = "idle"; category = "defend"

func evaluate(_view, _profile = null) -> Dictionary:
	return { "score": 1.0, "action": _AT.end_turn("idle") }
