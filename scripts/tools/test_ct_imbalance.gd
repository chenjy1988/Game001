extends SceneTree
##
## test_ct_imbalance.gd — 量化"高速单位优势是否过大"
## 不同 init 比 → 30 步内行动次数比例
##

func _initialize() -> void:
	# 当前游戏的 5 单位实际数据
	print("=== 当前 demo 5 单位（30 步） ===")
	_simulate({
		"阿尔伯特(short_sword/leather)": 105 - 2,   # 105 - floor(8/4)
		"贡多巴德(war_hammer/mail)":      90 - 4,    # 90 - floor(16/4)
		"强盗头目(battle_axe/mail)":      95 - 4,
		"匕首手(dagger/leather)":         115 - 2,
		"矛兵(spear/leather)":            100 - 2,
	}, 30)

	print()
	print("=== 极端对照：240 vs 60（4 倍速度差，FFT 经典灾难场景） ===")
	_simulate({"快": 240, "慢": 60}, 24)

	print()
	print("=== 中等对照：150 vs 100 vs 50（1.5x / 2x / 3x 速度差） ===")
	_simulate({"快150": 150, "中100": 100, "慢50": 50}, 24)

	print()
	print("=== 同 init 同时满 CT 的稳定性 ===")
	_simulate({"A100": 100, "B100": 100, "C100": 100}, 12)

	quit()


func _simulate(units: Dictionary, max_actions: int) -> void:
	var ct: Dictionary = {}
	for n in units.keys():
		ct[n] = 0
	const TH := 100
	var actions: Array[String] = []
	var ticks: int = 0
	while actions.size() < max_actions and ticks < 5000:
		var ready: Array = []
		for n in ct.keys():
			if ct[n] >= TH:
				ready.append(n)
		if ready.is_empty():
			for n in ct.keys():
				ct[n] = ct[n] + units[n]
			ticks += 1
			continue
		ready.sort_custom(func(a, b): return ct[a] > ct[b])
		var pick = ready[0]
		ct[pick] -= TH
		actions.append(pick)
	# 统计
	var counts: Dictionary = {}
	for n in units.keys():
		counts[n] = 0
	for a in actions:
		counts[a] += 1
	print("行动序列前 12: ", actions.slice(0, 12))
	print("总行动次数 (%d 步)：" % max_actions)
	# 算理论比例
	var sum_init: int = 0
	for n in units.keys():
		sum_init += units[n]
	for n in units.keys():
		var actual: int = counts[n]
		var theoretical_pct: float = float(units[n]) / float(sum_init) * 100.0
		var actual_pct: float = float(actual) / float(max_actions) * 100.0
		print("  %s init=%d  actual=%d (%.0f%%)  理论=%.0f%%" % [
			n, units[n], actual, actual_pct, theoretical_pct
		])
