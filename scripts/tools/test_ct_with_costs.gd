extends SceneTree
##
## test_ct_with_costs.gd — 验证方案 B+C：软上限 + 武器 WT cost 是否还能让快单位"一回合动 N 次"
##
## 核心问题：在我们的设计下，能否出现"高速单位连续行动 3+ 次"？
##

const CT_TH := 100
const SOFT_HIGH := 130   # 软上限
const SOFT_LOW := 50

# 把 raw init 套软上限 → 实际累加值
func _eff(raw: int) -> int:
	var v: int = raw
	if v > SOFT_HIGH:
		v = SOFT_HIGH + (v - SOFT_HIGH) / 2
	return max(SOFT_LOW, v)


func _initialize() -> void:
	print("=== Soft cap 后的有效 init 对照 ===")
	for raw in [60, 80, 100, 120, 130, 150, 180, 240, 300]:
		print("  raw=%d → eff=%d" % [raw, _eff(raw)])

	print()
	print("=== 测试 1：极端高速 240 vs 普通 100 vs 慢 60 (无 cost 区分，全扣 100) ===")
	_simulate({"快240": 240, "中100": 100, "慢60": 60}, 24, {"快240": 100, "中100": 100, "慢60": 100})

	print()
	print("=== 测试 2：同上但加 WT cost——快单位用重武器 (扣 130)，慢单位用快武器 (扣 80) ===")
	# 注意：这是反向设计——快单位倾向用轻武器，慢单位倾向用重武器
	# 这里反着测：看"快+重武器"是否被压制
	_simulate({"快240+重130": 240, "中100+普100": 100, "慢60+快80": 60}, 24,
		{"快240+重130": 130, "中100+普100": 100, "慢60+快80": 80})

	print()
	print("=== 测试 3：现实场景——刺客 init=150 用匕首 (扣 90)，重骑兵 init=70 用战锤 (扣 130) ===")
	# 这是 TO 经典——快+轻武器 vs 慢+重武器
	_simulate({"刺客150+匕首90": 150, "重骑兵70+锤130": 70}, 16,
		{"刺客150+匕首90": 90, "重骑兵70+锤130": 130})

	print()
	print("=== 测试 4：能否出现「连动 3 次」？快=200 慢=80，全扣 100 ===")
	# 检查最坏情况下的连续动作
	_simulate({"飞毛腿200": 200, "其他80": 80}, 20, {"飞毛腿200": 100, "其他80": 100})

	print()
	print("=== 测试 5：测 4 加上 soft cap 后 ===")
	_simulate({"飞毛腿200(soft)": 200, "其他80": 80}, 20,
		{"飞毛腿200(soft)": 100, "其他80": 100}, true)

	quit()


func _simulate(units: Dictionary, max_actions: int, costs: Dictionary, use_soft_cap: bool = true) -> void:
	var ct: Dictionary = {}
	for n in units.keys():
		ct[n] = 0
	var actions: Array[String] = []
	var ticks: int = 0
	# 用于检查最大连续动作长度
	var max_streak: int = 1
	var cur_streak: int = 1
	while actions.size() < max_actions and ticks < 5000:
		var ready: Array = []
		for n in ct.keys():
			if ct[n] >= CT_TH:
				ready.append(n)
		if ready.is_empty():
			for n in ct.keys():
				var inc: int = _eff(units[n]) if use_soft_cap else units[n]
				ct[n] = ct[n] + inc
			ticks += 1
			continue
		ready.sort_custom(func(a, b): return ct[a] > ct[b])
		var pick = ready[0]
		ct[pick] -= costs[pick]   # 关键：用各自的 WT cost
		actions.append(pick)
		# 连续动作检测
		if actions.size() >= 2 and actions[-1] == actions[-2]:
			cur_streak += 1
			max_streak = max(max_streak, cur_streak)
		else:
			cur_streak = 1
	print("行动序列前 16: ", actions.slice(0, 16))
	var counts: Dictionary = {}
	for n in units.keys():
		counts[n] = 0
	for a in actions:
		counts[a] += 1
	for n in units.keys():
		print("  %s init=%d cost=%d → 行动 %d 次 (%.0f%%)" % [
			n, units[n], costs[n], counts[n], float(counts[n]) / float(max_actions) * 100.0
		])
	print("  最长连动次数: %d" % max_streak)
