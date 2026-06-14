extends RefCounted
##
## 战斗效果基类 — 由 CombatEffectContainer 调度生命周期与 fold

var id: String = ""
var display_name: String = ""
var order: int = 0
var is_stacking: bool = false
var show_in_ui: bool = true
var turns_remaining: int = -1
var source = null


func on_added(_container) -> void:
	pass


func on_removed() -> void:
	pass


func on_refresh() -> void:
	pass


func on_combat_started() -> void:
	pass


func on_combat_finished() -> void:
	pass


func on_turn_started() -> void:
	pass


func on_turn_ended() -> void:
	pass


func on_update(_stats) -> void:
	pass


func on_after_update(_stats) -> void:
	pass


func is_expired() -> bool:
	return turns_remaining == 0


func to_ui_entry() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"turns_remaining": turns_remaining,
	}
