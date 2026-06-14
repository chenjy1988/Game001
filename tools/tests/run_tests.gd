extends SceneTree
##
## Project health + fast unit checks. Heavier suites live in scripts/tools/.
## Run via: tools/run_tests.sh

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Game001 run_tests ===")

	var weapon_db: Node = get_root().get_node_or_null("WeaponArmorDB")
	_assert_true(weapon_db != null, "WeaponArmorDB autoload present")
	if weapon_db != null:
		if weapon_db.call("get_weapon", "modao") == null:
			weapon_db.call("_load_weapons")
			weapon_db.call("_load_armors")
		_assert_true(weapon_db.call("get_weapon", "modao") != null, "weapons.json loads modao")

	var job_db: Node = get_root().get_node_or_null("JobDB")
	_assert_true(job_db != null, "JobDB autoload present")

	_assert_true(TurnScheduler.run_unit_tests(), "TurnScheduler.run_unit_tests()")
	_assert_true(_run_ability_framework_tests(), "Ability framework smoke")

	if _failures > 0:
		printerr("tests failed: ", _failures)
		quit(1)
		return

	print("tests passed")
	quit(0)


func _run_ability_framework_tests() -> bool:
	var ab = load("res://scripts/core/AbilityLibrary.gd").basic_attack()
	if ab == null or ab.id != "basic_attack":
		return false
	var UnitScript = load("res://scripts/core/Unit.gd")
	var atk = UnitScript.new()
	atk.stats = Stats.new()
	atk.stats.ap = 9
	atk.stats.faction = 0
	atk.axial_pos = Vector2i.ZERO
	var weapon_db: Node = get_root().get_node_or_null("WeaponArmorDB")
	if weapon_db != null:
		atk.weapon = weapon_db.call("get_weapon", "sword")
	var dst = UnitScript.new()
	dst.stats = Stats.new()
	dst.stats.faction = 1
	dst.axial_pos = Vector2i(1, 0)
	if not ab.can_use(atk, dst):
		return false
	var r: Dictionary = atk.attack_target(dst, "slash")
	return r.has("hit_chance") and atk.stats.ap < 9


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  [PASS] ", message)
		return
	_failures += 1
	printerr("  [FAIL] ", message)
