extends Node2D
##
## Main.gd — Demo 入口主菜单
##

@onready var start_button: Button = $UI/StartButton
@onready var quit_button: Button = $UI/QuitButton


func _ready() -> void:
	print("[Game001] Battle Brothers Demo started.")
	print("[Game001] Godot version: ", Engine.get_version_info().string)
	print("[Game001] Phase 1: Initiative-based turn + move/attack + hit/damage/armor pipeline.")
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_on_start_pressed()
			get_viewport().set_input_as_handled()
