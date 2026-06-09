extends EditorScript

func _run() -> void:
	print("\n=== TurnScheduler G1 Unit Tests (Editor Mode) ===\n")

	# 直接调用 TurnScheduler 的静态测试函数
	var result = TurnScheduler.run_unit_tests()

	print("\n=== Test Summary ===")
	print("All Tests Passed: %s\n" % ["✅ YES" if result else "❌ NO"])

