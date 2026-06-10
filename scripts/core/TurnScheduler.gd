extends RefCounted
class_name TurnScheduler
##
## TurnScheduler.gd — 行动顺序计算系统
##
## 根据 Initiative + Fatigue 联合排序规则计算行动顺序，
## 支持 2 轮行动条预览和先发制人技能的虚拟+40 Init 预览。
##
## 核心规则：
##   - |Init差| > 5：按 Init 排序，不考虑气力
##   - |Init差| ≤ 5：score = init + (fatigue_ratio × 5)，高 score 优先行动
##   - fatigue_ratio = current_fatigue / max_stamina，范围 [0.0, 1.0]
##


# ────────────────────────────────────────────────────────────
# 核心计算：回合顺序
# ────────────────────────────────────────────────────────────

## 根据 Init + Fatigue 联合规则排序单位
## include_fatigue_modifier: true 时，|Init差| ≤ 5 的单位按 fatigue_ratio 加权；
##                          false 时纯按 Init 排序（用于 debug / 特殊场景）
static func calculate_turn_order(units: Array[Unit], include_fatigue_modifier: bool = true) -> Array[Unit]:
	var result: Array[Unit] = units.duplicate()

	# 计算每个单位的排序得分
	var scores: Dictionary = {}  # unit -> score
	for unit in result:
		scores[unit] = _calculate_sort_score(unit, units, include_fatigue_modifier)

	# 按得分降序排序
	result.sort_custom(func(a: Unit, b: Unit) -> bool:
		return scores[a] > scores[b]
	)

	return result


## 计算单位的排序得分（内部辅助函数）
## 与 TurnManager._eff_init 保持一致：base_initiative - fatigue - armor_weight/4 - weapon_weight/4 + preempt_bonus
## 这样预览和实际排序结果完全一致
static func _calculate_sort_score(unit: Unit, _all_units: Array[Unit], _include_fatigue_modifier: bool = true) -> float:
	if not unit or not unit.stats:
		return 0.0

	# 与 TurnManager._eff_init 完全一致的公式
	var aw: int = unit.armor.weight if unit.armor else 0
	var ww: int = 0
	if unit.weapon and unit.weapon.has_method("get") and "weight" in unit.weapon:
		ww = int(unit.weapon.weight)
	elif unit.weapon:
		ww = int(unit.weapon.weight)
	var base_init: float = float(unit.stats.base_initiative - unit.stats.fatigue)
	base_init -= float(floor(float(aw) / 4.0))
	base_init -= float(floor(float(ww) / 4.0))
	if unit.preempt_active:
		base_init += float(unit.preempt_initiative_bonus)
	return max(1.0, base_init)


## 生成 N 轮的行动条预览（返回 TimelineEntry 数组，用于 TopBar 渲染）
## current_round: 当前回合序号（通常为 0）
## rounds_to_show: 要显示的回合数（通常为 2）
static func generate_timeline_preview(units: Array[Unit], current_round: int = 0, rounds_to_show: int = 2) -> Array:
	var timeline: Array = []

	# 每个回合的行动顺序相同（暂不考虑 Initiative 动态变化）
	var ordered_units: Array[Unit] = calculate_turn_order(units, true)

	var y_offset: float = 0.0
	var y_step: float = 60.0  # 每个头像间隔 60 px（供 UI 参考）

	for round_idx in range(current_round, current_round + rounds_to_show):
		for order_idx in range(ordered_units.size()):
			var unit: Unit = ordered_units[order_idx]
			var entry: TimelineEntry = TimelineEntry.new(
				round_idx,
				order_idx,
				unit,
				y_offset + order_idx * y_step
			)
			timeline.append(entry)

	return timeline


## 虚拟应用先发制人 bonus 后的 timeline 预览
## activating_unit: 使用先发制人的单位
## bonus_initiative: +Init 值（通常为 +40）
## rounds_to_show: 显示回合数（通常为 2）
##
## 重要：先发制人不仅加 +Init，还会消耗 fatigue（20/32），
## 而 TurnManager._eff_init 在建队列时使用的是消耗后的 fatigue 值。
## 因此预览必须同步模拟 fatigue 消耗，否则预演顺序与实际不一致。
static func preview_with_preempt_bonus(units: Array[Unit], activating_unit: Unit, bonus_initiative: int = 40, rounds_to_show: int = 2) -> Array:
	# 创建虚拟副本列表（保留原始对象引用，但临时修改数据）
	var virtual_units: Array[Unit] = []
	var original_initiative: int = 0
	var original_fatigue: int = 0

	for unit in units:
		virtual_units.append(unit)
		if unit == activating_unit:
			original_initiative = unit.stats.base_initiative
			original_fatigue = unit.stats.fatigue

	# 临时提升激活者的 Initiative + 模拟 fatigue 消耗
	# 先发制人消耗：1 AP + 20 气力（重甲 ×1.6 = 32）
	# 预演只影响排序，不模拟 AP；但 fatigue 直接影响 effective_initiative
	if activating_unit:
		activating_unit.stats.base_initiative += bonus_initiative
		var fatigue_cost: int = 20
		if activating_unit.is_wearing_heavy_armor():
			fatigue_cost = int(20 * 1.6)  # = 32
		# 模拟使用先发制人后的 fatigue（不超过 max_stamina）
		activating_unit.stats.fatigue = mini(activating_unit.stats.max_stamina, activating_unit.stats.fatigue + fatigue_cost)

	# 计算虚拟排序
	var virtual_ordered: Array[Unit] = calculate_turn_order(virtual_units, true)

	# 恢复激活者原始值
	if activating_unit:
		activating_unit.stats.base_initiative = original_initiative
		activating_unit.stats.fatigue = original_fatigue

	# 转换为 TimelineEntry
	var timeline: Array = []
	var y_offset: float = 0.0
	var y_step: float = 60.0

	for round_idx in range(0, rounds_to_show):
		for order_idx in range(virtual_ordered.size()):
			var unit: Unit = virtual_ordered[order_idx]
			var entry: TimelineEntry = TimelineEntry.new(
				round_idx,
				order_idx,
				unit,
				y_offset + order_idx * y_step
			)
			timeline.append(entry)

	return timeline


# ────────────────────────────────────────────────────────────
# 单元测试（开发用）
# ────────────────────────────────────────────────────────────

## 单元测试：验证行动顺序计算
static func run_unit_tests() -> bool:
	var test_results: Array[bool] = []

	# Test 1: 纯 Init 差 > 5，按 Init 排序
	test_results.append(_test_pure_init_ordering())

	# Test 2: Init 差 ≤ 5，fatigue_ratio 加权
	test_results.append(_test_fatigue_weighted_ordering())

	# Test 3: 混合场景（部分 Init 差 > 5，部分 ≤ 5）
	test_results.append(_test_mixed_ordering())

	# Test 4: Timeline 预览生成
	test_results.append(_test_timeline_generation())

	# Test 5: Preempt bonus 预览
	test_results.append(_test_preempt_preview())

	# 汇总测试结果
	var all_passed: bool = true
	for i in range(test_results.size()):
		var passed: bool = test_results[i]
		all_passed = all_passed and passed
		print("[TurnScheduler Test %d] %s" % [i + 1, "PASS" if passed else "FAIL"])

	return all_passed


static func _test_pure_init_ordering() -> bool:
	# 创建两个单位：Init 100 vs Init 50（差 > 5）
	var unit_a: Unit = Unit.new()
	unit_a.stats = Stats.new()
	unit_a.stats.base_initiative = 100
	unit_a.stats.fatigue = 0
	unit_a.stats.max_stamina = 100

	var unit_b: Unit = Unit.new()
	unit_b.stats = Stats.new()
	unit_b.stats.base_initiative = 50
	unit_b.stats.fatigue = 0
	unit_b.stats.max_stamina = 100

	var ordered: Array[Unit] = calculate_turn_order([unit_a, unit_b], true)

	# 预期：unit_a 在前（Init 高）
	return ordered[0] == unit_a and ordered[1] == unit_b


static func _test_fatigue_weighted_ordering() -> bool:
	# 创建两个单位：Init 100 vs Init 97（差 ≤ 5）
	# unit_a：气力充沛（fatigue 0）
	# unit_b：气力枯竭（fatigue 50）
	var unit_a: Unit = Unit.new()
	unit_a.stats = Stats.new()
	unit_a.stats.base_initiative = 100
	unit_a.stats.fatigue = 0
	unit_a.stats.max_stamina = 100

	var unit_b: Unit = Unit.new()
	unit_b.stats = Stats.new()
	unit_b.stats.base_initiative = 97
	unit_b.stats.fatigue = 50
	unit_b.stats.max_stamina = 100

	var ordered: Array[Unit] = calculate_turn_order([unit_a, unit_b], true)

	# 预期：unit_a 依然在前（初始 Init 优势 + 气力充沛）
	return ordered[0] == unit_a


static func _test_mixed_ordering() -> bool:
	# 三单位：A (Init 100, fat 0) / B (Init 99, fat 0) / C (Init 50, fat 0)
	# A vs B: 差 ≤ 5，apply fatigue weight
	# B vs C: 差 > 5，纯 Init 排序
	# 预期：A > B > C

	var unit_a: Unit = Unit.new()
	unit_a.stats = Stats.new()
	unit_a.stats.base_initiative = 100
	unit_a.stats.fatigue = 0
	unit_a.stats.max_stamina = 100

	var unit_b: Unit = Unit.new()
	unit_b.stats = Stats.new()
	unit_b.stats.base_initiative = 99
	unit_b.stats.fatigue = 0
	unit_b.stats.max_stamina = 100

	var unit_c: Unit = Unit.new()
	unit_c.stats = Stats.new()
	unit_c.stats.base_initiative = 50
	unit_c.stats.fatigue = 0
	unit_c.stats.max_stamina = 100

	var ordered: Array[Unit] = calculate_turn_order([unit_c, unit_a, unit_b], true)

	return ordered[0] == unit_a and ordered[1] == unit_b and ordered[2] == unit_c


static func _test_timeline_generation() -> bool:
	var unit_a: Unit = Unit.new()
	unit_a.stats = Stats.new()
	unit_a.stats.base_initiative = 100
	unit_a.stats.fatigue = 0
	unit_a.stats.max_stamina = 100

	var unit_b: Unit = Unit.new()
	unit_b.stats = Stats.new()
	unit_b.stats.base_initiative = 50
	unit_b.stats.fatigue = 0
	unit_b.stats.max_stamina = 100

	var timeline: Array = generate_timeline_preview([unit_a, unit_b], 0, 2)

	# 预期：2 轮 × 2 单位 = 4 条记录
	if timeline.size() != 4:
		return false

	# 验证前两条（第 0 回合）顺序
	if timeline[0].round != 0 or timeline[0].unit != unit_a:
		return false
	if timeline[1].round != 0 or timeline[1].unit != unit_b:
		return false

	# 验证后两条（第 1 回合）顺序相同
	if timeline[2].round != 1 or timeline[2].unit != unit_a:
		return false
	if timeline[3].round != 1 or timeline[3].unit != unit_b:
		return false

	return true


static func _test_preempt_preview() -> bool:
	# 单位 A: Init 100 / 单位 B: Init 98（差 ≤ 5，fatigue 加权决定顺序）
	# 若 B 使用先发制人 +40，应该变成 138，排到 A 前面

	var unit_a: Unit = Unit.new()
	unit_a.stats = Stats.new()
	unit_a.stats.base_initiative = 100
	unit_a.stats.fatigue = 0
	unit_a.stats.max_stamina = 100

	var unit_b: Unit = Unit.new()
	unit_b.stats = Stats.new()
	unit_b.stats.base_initiative = 98
	unit_b.stats.fatigue = 0
	unit_b.stats.max_stamina = 100

	# 获取虚拟预览（B +40 Initiative）
	var preview_timeline: Array = preview_with_preempt_bonus([unit_a, unit_b], unit_b, 40, 1)

	# 预期：预览中 unit_b 应该排在 unit_a 前面
	if preview_timeline.size() < 2:
		return false

	return preview_timeline[0].unit == unit_b and preview_timeline[1].unit == unit_a
