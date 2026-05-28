extends Node2D
##
## Main.gd — Demo 入口场景
##
## 当前仅作为环境验证 + Phase 1 起点。
## 后续会替换为：开始游戏 / 继续 / 设置 的主菜单，并跳转到 BattleScene。
##

func _ready() -> void:
	print("[Game001] Battle Brothers Demo started.")
	print("[Game001] Godot version: ", Engine.get_version_info().string)
	print("[Game001] Phase 1 goal: Initiative-based turn + move/attack + hit/damage/armor pipeline.")


func _unhandled_input(event: InputEvent) -> void:
	# 提供 ESC 退出，方便快速验证
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
