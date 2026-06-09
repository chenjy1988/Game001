extends SceneTree
##
## test_ct_scheduler.gd — TurnManager CT 调度的快速自测
##
## 跑法：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --script scripts/tools/test_ct_scheduler.gd --headless
##
## 验证：
##   1. 速度差大（init 120 vs 80 vs 60）时，每"宏观回合"快单位行动次数显著更多
##   2. opposite_across() 给出正确的对侧格
##

func _initialize() -> void:
	print("=== Test 1: CT 调度仿真（不实际跑 TurnManager，复现核心算法） ===")
	_test_ct_simulation()
	print()
	print("=== Test 2: HexCoord.opposite_across（夹击对侧格） ===")
	_test_opposite_across()
	quit()


func _test_ct_simulation() -> void:
	# 三个虚拟单位：A=120 (快), B=80 (中), C=60 (慢)
	var inits := {"A": 120, "B": 80, "C": 60}
	var ct := {"A": 0, "B": 0, "C": 0}
	const THRESHOLD := 100

	var actions: Array[String] = []
	var ticks: int = 0
	while actions.size() < 12 and ticks < 1000:
		# 找 ready
		var ready: Array[String] = []
		for n in ct.keys():
			if ct[n] >= THRESHOLD:
				ready.append(n)
		if ready.is_empty():
			# tick
			for n in ct.keys():
				ct[n] = ct[n] + inits[n]
			ticks += 1
			continue
		# 取 CT 最高
		ready.sort_custom(func(a, b): return ct[a] > ct[b])
		var pick = ready[0]
		ct[pick] -= THRESHOLD
		actions.append(pick)

	print("前 12 个行动序列: ", actions)
	# 统计
	var counts := {"A": 0, "B": 0, "C": 0}
	for a in actions:
		counts[a] += 1
	print("行动次数统计: ", counts)
	print("预期：A 多于 B 多于 C；A:B ≈ 120:80 = 3:2；A:C ≈ 120:60 = 2:1")


func _test_opposite_across() -> void:
	# 中心 hex (0,0)，从右侧 (1,0) 方向攻击它，对侧应该是 (-1,0)
	var from := Vector2i(1, 0)
	var target := Vector2i(0, 0)
	var opp := HexCoord.opposite_across(from, target)
	print("from=(1,0) target=(0,0) → opposite=", opp, "  期望=(-1,0)")
	assert(opp == Vector2i(-1, 0), "对侧格错误")

	# 从右上 (1,-1) 方向攻击 (0,0)，对侧应该是左下 (-1,1)
	from = Vector2i(1, -1)
	target = Vector2i(0, 0)
	opp = HexCoord.opposite_across(from, target)
	print("from=(1,-1) target=(0,0) → opposite=", opp, "  期望=(-1,1)")
	assert(opp == Vector2i(-1, 1), "对侧格错误")

	# 远程：from=(2,0) target=(0,0)（不相邻），近似走"target 远离 from"
	from = Vector2i(2, 0)
	target = Vector2i(0, 0)
	opp = HexCoord.opposite_across(from, target)
	print("from=(2,0) target=(0,0) → opposite=", opp, "  （远程近似，期望 ~(-1,0)）")
	print("✅ opposite_across 测试通过")
