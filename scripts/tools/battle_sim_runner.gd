extends SceneTree
##
## 已弃用：请用 ./tools/run_sim.sh（--scene res://scenes/tools/BattleSim.tscn）
## --script 模式下 autoload / CombatPalette 编译顺序有问题。

func _initialize() -> void:
	push_error("Use ./tools/run_sim.sh instead of --script battle_sim_runner.gd")
	quit(1)
