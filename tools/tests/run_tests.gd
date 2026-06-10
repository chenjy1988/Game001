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

	if _failures > 0:
		printerr("tests failed: ", _failures)
		quit(1)
		return

	print("tests passed")
	quit(0)


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  [PASS] ", message)
		return
	_failures += 1
	printerr("  [FAIL] ", message)
