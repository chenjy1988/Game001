## test_1ap_bug.gd — 验证1 AP时自动切单位的问题
## 跑法：在编辑器中挂到某个场景执行，或用 godot CLI 跑
extends SceneTree

class TestUnit extends Unit:
	func _init(name: String, melee_skill: int = 60, defense_val: int = 30, max_hp: int = 60,
			weapon_id: String = "", armor_id: String = "", wisdom: int = 30) -> void:
		stats = Stats.new()
		stats.unit_name = name
		stats.melee_skill = melee_skill
		stats.defense = defense_val
		stats.melee_defense = defense_val
		stats.max_hp = max_hp
		stats.wisdom = wisdom
		stats.faction = 0
		stats.init_runtime(0)

		var db: Node = Engine.get_main_loop().get_root().get_node_or_null("WeaponArmorDB")
		if weapon_id != "" and db != null:
			weapon = db.call("get_weapon", weapon_id)
		if armor_id != "" and db != null:
			armor = db.call("get_armor", armor_id)


func _initialize() -> void:
	print("=== 1 AP Bug Test ===\n")

	# 手动加载武器/护甲数据
	var db: Node = get_root().get_node_or_null("WeaponArmorDB")
	if db != null and db.call("get_weapon", "dagger") == null:
		db.call("_load_weapons")
		db.call("_load_armors")

	# 创建一个单位并设置 AP 为 1
	var unit = TestUnit.new("测试单位", 60, 30, 60, "dagger", "leather_armor", 30)
	get_root().add_child(unit)

	# 假设基础 AP = 9，扣掉 8，剩 1 AP
	unit.stats.ap = 1

	print("初始状态：")
	print("  AP: %d" % unit.stats.ap)
	print("  weapon.ap_cost: %d" % unit.weapon.ap_cost)
	print("  Unit.AP_PER_HEX: %d" % Unit.AP_PER_HEX)
	print()

	# 检查 BattleScene 的自动结束回合条件
	var cond1: bool = unit.stats.ap < Unit.AP_PER_HEX
	var cond2: bool = unit.stats.ap < unit.weapon.ap_cost
	print("自动结束回合条件检查：")
	print("  ap < AP_PER_HEX? %s (1 < 2 = %s)" % ["是" if cond1 else "否", cond1])
	print("  ap < weapon.ap_cost? %s (1 < 3 = %s)" % ["是" if cond2 else "否", cond2])
	print("  AND 结果（既动不了也打不出）? %s" % ["是" if cond1 and cond2 else "否", cond1 and cond2])
	print()

	# 如果条件为真，就会 end_turn（即切到下一个角色）
	if cond1 and cond2:
		print("✗ BUG CONFIRMED: 1 AP 时会自动 end_turn() 导致切换到下一个角色")
	else:
		print("✓ OK: 1 AP 时不会自动结束回合")

	print()
	print("[1AP_BUG_TEST] 测试完成")
	quit(0)
