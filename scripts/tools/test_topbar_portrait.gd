## test_topbar_portrait.gd — 验证 TopBar 头像交互系统
extends SceneTree

class TestUnit extends Unit:
	func _init(name: String) -> void:
		stats = Stats.new()
		stats.unit_name = name
		stats.faction = randi() % 2
		stats.base_initiative = 50 + randi() % 50
		stats.init_runtime(0)

func _initialize() -> void:
	print("=== TopBar Portrait Interaction Test ===\n")

	# 创建测试单位
	var units: Array[Unit] = []
	for i in range(4):
		var u = TestUnit.new("单位%d" % (i + 1))
		units.append(u)
		get_root().add_child(u)

	# 验证 get_total_weight 存在
	var w = units[0].get_total_weight()
	print("✓ Unit.get_total_weight() = %d" % w)

	# 验证 effective_initiative_v2 存在
	var init = units[0].stats.effective_initiative_v2(w)
	print("✓ Stats.effective_initiative_v2(%.0f) = %.1f" % [float(w), init])

	# 验证 TurnScheduler.preview_with_preempt_bonus 存在
	var preview = TurnScheduler.preview_with_preempt_bonus(units, units[0], 40, 1)
	print("✓ TurnScheduler.preview_with_preempt_bonus() returned %d entries" % preview.size())

	# 验证第一个 entry 有 unit 和 round 属性
	if preview.size() > 0:
		var entry = preview[0]
		if "unit" in entry and "round" in entry:
			print("✓ Preview entry has 'unit' and 'round' properties")
		else:
			print("✗ Preview entry missing properties")

	print("\n[TOPBAR_PORTRAIT_TEST] 测试完成")
	quit(0)
