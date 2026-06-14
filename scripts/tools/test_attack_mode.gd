## test_attack_mode.gd - 验证攻击模式选择是否正确影响伤害
## 跑法：/Applications/Godot.app/Contents/MacOS/Godot --path . --script scripts/tools/test_attack_mode.gd --headless
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
		stats.init_runtime()

		var db: Node = Engine.get_main_loop().get_root().get_node_or_null("WeaponArmorDB")
		if weapon_id != "" and db != null:
			weapon = db.call("get_weapon", weapon_id)
		if armor_id != "" and db != null:
			armor = db.call("get_armor", armor_id)


var pass_count: int = 0
var fail_count: int = 0


func _initialize() -> void:
	print("=== Attack Mode Integration Test ===\n")

	# autoload の _ready 在 SceneTree --script 模式下排在 _initialize 之后才执行
	# 手动触发让 WeaponArmorDB 现在就可用
	var db: Node = get_root().get_node_or_null("WeaponArmorDB")
	if db != null and db.call("get_weapon", "modao") == null:
		db.call("_load_weapons")
		db.call("_load_armors")

	test_attack_mode_slash()
	test_attack_mode_pierce()

	print("\n=== Results ===")
	print("PASS: %d / FAIL: %d" % [pass_count, fail_count])
	print("[ATTACK_MODE_TEST] All tests completed")

	quit(0)


func test_attack_mode_slash() -> void:
	print("\n=== Test 1: Slash Mode ===")

	var attacker = TestUnit.new("陌刀手", 60, 30, 100, "modao", "plate_armor", 40)
	var defender = TestUnit.new("敌方", 30, 15, 100, "dagger", "leather_armor", 30)

	var options = {"mode": "slash"}
	var result = DamageSystem.execute_attack(attacker, defender, options)

	print("Mode: slash")
	print("  armor_mult (expected 1.0): %f" % result.get("armor_mult", 0.0))
	print("  base_pen (expected 0.10): %f" % result.get("base_pen", 0.0))
	print("  weight_modifier (expected ~2.667 for modao): %f" % result.get("weight_modifier", 0.0))
	print("  penetration_rate (expected ~0.267): %f" % result.get("penetration_rate", 0.0))
	print("  total_damage: %d" % result.get("final_damage", 0))
	print("  armor_damage: %d" % result.get("armor_damage", 0))

	# 检查 armor_mult 是否为 Slash 的正确值
	var armor_mult = result.get("armor_mult", 0.0)
	if _approx(armor_mult, 1.0, 0.01):
		print("✓ PASS: armor_mult = 1.0 for slash")
		pass_count += 1
	else:
		print("✗ FAIL: armor_mult should be 1.0, got %f" % armor_mult)
		fail_count += 1

	# 检查 base_pen 是否为 Slash 的正确值
	var base_pen = result.get("base_pen", 0.0)
	if _approx(base_pen, 0.10, 0.01):
		print("✓ PASS: base_pen = 0.10 for slash")
		pass_count += 1
	else:
		print("✗ FAIL: base_pen should be 0.10, got %f" % base_pen)
		fail_count += 1


func test_attack_mode_pierce() -> void:
	print("\n=== Test 2: Pierce Mode ===")

	var attacker = TestUnit.new("陌刀手", 60, 30, 100, "modao", "plate_armor", 40)
	var defender = TestUnit.new("敌方", 30, 15, 100, "dagger", "leather_armor", 30)

	var options = {"mode": "pierce"}
	var result = DamageSystem.execute_attack(attacker, defender, options)

	print("Mode: pierce")
	print("  armor_mult (expected 0.7): %f" % result.get("armor_mult", 0.0))
	print("  base_pen (expected 0.15): %f" % result.get("base_pen", 0.0))
	print("  weight_modifier (expected ~2.667 for modao): %f" % result.get("weight_modifier", 0.0))
	print("  penetration_rate (expected ~0.40): %f" % result.get("penetration_rate", 0.0))
	print("  total_damage: %d" % result.get("final_damage", 0))
	print("  armor_damage: %d" % result.get("armor_damage", 0))

	# 检查 armor_mult 是否为 Pierce 的正确值
	var armor_mult = result.get("armor_mult", 0.0)
	if _approx(armor_mult, 0.7, 0.01):
		print("✓ PASS: armor_mult = 0.7 for pierce")
		pass_count += 1
	else:
		print("✗ FAIL: armor_mult should be 0.7, got %f" % armor_mult)
		fail_count += 1

	# 检查 base_pen 是否为 Pierce 的正确值
	var base_pen = result.get("base_pen", 0.0)
	if _approx(base_pen, 0.15, 0.01):
		print("✓ PASS: base_pen = 0.15 for pierce")
		pass_count += 1
	else:
		print("✗ FAIL: base_pen should be 0.15, got %f" % base_pen)
		fail_count += 1


func _approx(a: float, b: float, tol: float = 0.01) -> bool:
	return abs(a - b) <= tol
