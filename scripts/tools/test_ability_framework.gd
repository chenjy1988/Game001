## test_ability_framework.gd — C1 Ability 框架冒烟
extends SceneTree

const _Unit = preload("res://scripts/core/Unit.gd")
const _Ability = preload("res://scripts/core/abilities/Ability.gd")
const _AbilityLibrary = preload("res://scripts/core/AbilityLibrary.gd")
const _Enums = preload("res://scripts/core/abilities/AbilityEnums.gd")
const _EffectSpec = preload("res://scripts/core/abilities/AbilityEffectSpec.gd")
const _Result = preload("res://scripts/core/abilities/AbilityResult.gd")

const TestDebuffAbility = preload("res://scripts/tools/TestDebuffAbility.gd")
const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")

class TestUnit extends _Unit:
	func _init(u_name: String, weapon_id: String = "sword") -> void:
		stats = Stats.new()
		stats.unit_name = u_name
		stats.melee_skill = 60
		stats.defense = 30
		stats.max_hp = 60
		stats.ap = 9
		stats.faction = 0
		stats.init_runtime()
		axial_pos = Vector2i.ZERO
		var db: Node = Engine.get_main_loop().get_root().get_node_or_null("WeaponArmorDB")
		if db != null:
			weapon = db.call("get_weapon", weapon_id)


var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Ability Framework Test ===\n")
	_test_basic_attack_can_use()
	_test_attack_target_delegates()
	_test_defend_stamina_on_being_attacked()
	_test_ap_gate()
	_test_debuff_applies_to_enemy()
	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	quit(_fail)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] %s" % msg)
	else:
		_fail += 1
		push_error("[FAIL] %s" % msg)


func _test_basic_attack_can_use() -> void:
	var ab = _AbilityLibrary.basic_attack()
	_ok(ab.id == "basic_attack", "basic_attack id")
	_ok(ab.mutex_group == "attack", "mutex_group attack")
	var atk := TestUnit.new("A")
	var dst := TestUnit.new("B")
	dst.stats.faction = 1
	dst.axial_pos = Vector2i(1, 0)
	_ok(ab.can_use(atk, dst), "can_use in range")


func _test_attack_target_delegates() -> void:
	var atk := TestUnit.new("A")
	var dst := TestUnit.new("B")
	dst.stats.faction = 1
	dst.axial_pos = Vector2i(1, 0)
	var remain_before: int = dst.stats.remaining_stamina()
	var r: Dictionary = atk.attack_target(dst, "slash")
	_ok(r.has("hit_chance"), "attack_target returns damage result")
	_ok(atk.stats.ap < 9, "AP spent via ability path")
	var defend_cost: int = int(r.get("defend_stamina", 0))
	_ok(defend_cost > 0, "defender pays stamina when attacked")
	_ok(dst.stats.remaining_stamina() == remain_before - defend_cost,
		"defender remaining stamina decreases (was %d cost %d now %d)" % [
			remain_before, defend_cost, dst.stats.remaining_stamina()])


func _test_defend_stamina_on_being_attacked() -> void:
	var dst := TestUnit.new("B")
	dst.stats.faction = 1
	dst.stats.stamina = dst.stats.max_stamina - 10
	var remain_before: int = dst.stats.remaining_stamina()
	var cost: int = _Unit.apply_defend_stamina_cost(dst)
	_ok(cost == _DamageSystem.calculate_defend_stamina_cost(dst), "apply_defend_stamina_cost amount")
	_ok(dst.stats.remaining_stamina() == remain_before - cost,
		"apply_defend_stamina_cost lowers remaining stamina")


func _test_ap_gate() -> void:
	var ab = _AbilityLibrary.basic_attack()
	var atk := TestUnit.new("A")
	atk.stats.ap = 0
	var dst := TestUnit.new("B")
	dst.stats.faction = 1
	dst.axial_pos = Vector2i(1, 0)
	_ok(not ab.can_use(atk, dst), "cannot use at 0 AP")
	var r: Dictionary = atk.use_ability(ab, dst, {})
	_ok(r.get("reason", "") == "cannot_use", "use_ability rejects 0 AP")


func _test_debuff_applies_to_enemy() -> void:
	var ab = TestDebuffAbility.new()
	var atk := TestUnit.new("A")
	var dst := TestUnit.new("B")
	dst.stats.faction = 1
	dst.axial_pos = Vector2i(1, 0)
	var r: Dictionary = atk.use_ability(ab, dst, {})
	_ok(r.get(_Result.OK, false), "debuff ability ok")
	var applied: Array = r.get(_Result.EFFECTS_APPLIED, [])
	_ok(applied.size() == 1, "one debuff spec applied")
	if applied.size() > 0:
		var spec = applied[0]
		_ok(spec.effect_id == "dazed" and spec.target == dst, "dazed on enemy")
		_ok(dst.get_effect_container().has_id("dazed"), "dazed in effect container")
