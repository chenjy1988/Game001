extends Node
##
## test_turn_scheduler_g1.gd — TurnScheduler 单元测试
##
## 在 BattleScene 内运行，以确保所有依赖都已加载
##

func _ready() -> void:
	# 这个脚本应该在 BattleScene 中挂载，或单独放在一个测试场景中
	print("\n[TurnScheduler G1 Unit Tests]\n")

	# 直接调用静态方法（TurnScheduler extends RefCounted，纯静态工具）
	var result = TurnScheduler.run_unit_tests()

	print("\n[TurnScheduler G1] Overall Result: %s\n" % [
		"✅ ALL TESTS PASSED" if result else "❌ SOME TESTS FAILED"
	])

	get_tree().quit()


