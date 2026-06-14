extends SceneTree
##
## test_combat_effects.gd — J0 CombatEffectContainer 冒烟
##

const _Unit = preload("res://scripts/core/Unit.gd")
const _Stats = preload("res://scripts/core/Stats.gd")
const _EffectSpec = preload("res://scripts/core/abilities/AbilityEffectSpec.gd")
const _EffectDB = preload("res://scripts/core/EffectDB.gd")

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== CombatEffect Container Test ===\n")
	_test_effect_db_create()
	_test_apply_spec()
	_test_turn_decay()
	_test_derived_stamina()
	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	quit(_fail)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] %s" % msg)
	else:
		_fail += 1
		push_error("[FAIL] %s" % msg)


func _make_unit(u_name: String, faction: int = 0) -> Unit:
	var u := _Unit.new()
	u.stats = _Stats.new()
	u.stats.unit_name = u_name
	u.stats.faction = faction
	u.stats.max_hp = 80
	u.stats.hp = 80
	u.stats.melee_skill = 55
	u.stats.defense = 10
	u.stats.max_stamina = 100
	u.stats.stamina = 100
	u.stats.max_ap = 9
	u.stats.ap = 9
	u.axial_pos = Vector2i.ZERO
	return u


func _test_effect_db_create() -> void:
	var eff = _EffectDB.create_from_spec(_EffectSpec.debuff("dazed", null, null, 2))
	_ok(eff != null and eff.id == "dazed", "EffectDB creates dazed")
	_ok(eff.turns_remaining == 2, "dazed turns from spec")


func _test_apply_spec() -> void:
	var u = _make_unit("T")
	var spec = _EffectSpec.debuff("dazed", u, u, 2)
	_ok(u.apply_effect_spec(spec, u), "apply_effect_spec ok")
	_ok(u.get_effect_container().has_id("dazed"), "container has dazed")
	var eff = u.get_effective_stats()
	_ok(eff.skip_turn, "dazed fold skip_turn")


func _test_turn_decay() -> void:
	var u = _make_unit("T2")
	u.apply_effect_spec(_EffectSpec.debuff("weakened", u, u, 1), u)
	_ok(u.get_effect_container().has_id("weakened"), "weakened added")
	u.get_effect_container().notify_turn_ended()
	_ok(not u.get_effect_container().has_id("weakened"), "weakened expires after 1 turn end")


func _test_derived_stamina() -> void:
	var u = _make_unit("T3")
	u.stats.stamina = int(u.stats.max_stamina * 0.15)
	var eff = u.get_effective_stats()
	_ok(eff.hit_pct < 0.0, "exhausted tier negative hit_pct")
