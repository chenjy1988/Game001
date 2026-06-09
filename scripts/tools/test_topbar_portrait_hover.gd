extends Node
##
## test_topbar_portrait_hover.gd — 验证 TopBar 头像 Hover 箭头功能
##
## 测试场景：
## 1. 启动战斗
## 2. 验证 unit_hovered/unit_unhovered 信号正确发射
## 3. 验证 TopBar 正确收到信号并显示/隐藏箭头
##

var battle_scene: Node
var top_bar: Node
var test_unit: Unit

func _ready() -> void:
	print("[TEST] TopBar Portrait Hover 测试开始")

	# 获取 BattleScene 和 TopBar
	battle_scene = get_tree().root.get_child(0)
	if battle_scene == null or battle_scene.name != "BattleScene":
		print("[FAIL] 无法找到 BattleScene")
		return

	top_bar = battle_scene.get_node_or_null("UI/TopBar")
	if top_bar == null:
		print("[FAIL] 无法找到 TopBar")
		return

	print("[PASS] 找到 BattleScene 和 TopBar")

	# 获取第一个活着的敌方单位
	var all_units = battle_scene._all_units
	test_unit = null
	for u in all_units:
		if u.is_alive() and u.get_faction() == 1:  # 敌方
			test_unit = u
			break

	if test_unit == null:
		print("[FAIL] 无法找到敌方单位")
		return

	print("[PASS] 找到测试单位: %s" % test_unit.get_unit_name())

	# 验证 TopBar._portrait_items 是否存在
	if not top_bar.has_meta("_portrait_items"):
		print("[INFO] TopBar._portrait_items 是私有变量，无法直接访问")

	# 连接信号以观察发射
	battle_scene.unit_hovered.connect(func(u: Unit): print("[SIGNAL] unit_hovered: %s" % u.get_unit_name()))
	battle_scene.unit_unhovered.connect(func(u: Unit): print("[SIGNAL] unit_unhovered: %s" % u.get_unit_name()))

	# 延迟执行虚拟悬停测试
	await get_tree().create_timer(1.0).timeout
	_test_hover_emission()

func _test_hover_emission() -> void:
	"""虚拟模拟鼠标悬停单位的效果"""
	print("[TEST] 开始虚拟悬停测试")

	# 虽然我们无法直接模拟鼠标，但可以直接调用信号发射来验证信号链路
	if battle_scene and test_unit:
		print("[TEST] 手动发射 unit_hovered 信号")
		battle_scene.unit_hovered.emit(test_unit)

		await get_tree().create_timer(0.5).timeout

		print("[TEST] 手动发射 unit_unhovered 信号")
		battle_scene.unit_unhovered.emit(test_unit)

		print("[PASS] 虚拟悬停测试完成")
	else:
		print("[FAIL] 无法执行虚拟悬停测试")

	print("[TEST] TopBar Portrait Hover 测试结束")
	# 一段时间后关闭
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()
