extends Node
## test_movement_intent.gd — Phase 2.5 P0 冒烟测试（场景模式）
##
## 验证：
##   1. AbilityMovementSpec 工厂方法（push/pull/swap 落点计算）
##   2. MovementSystem 执行（PUSH 推到边缘 + SWAP 互换）
##   3. AIIntentWeights 5 维权重计算（基础职业 + 状态修正）
##   4. 样品技能 Tuizhuang / Huanwei / Chaofeng 通过 Ability 链路工作
##
## 启动：通过 scenes/tools/TestMovementIntent.tscn 跑
##

const _Unit = preload("res://scripts/core/Unit.gd")
const _Stats = preload("res://scripts/core/Stats.gd")
const _HexGrid = preload("res://scripts/core/HexGrid.gd")
const _Spec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _Movement = preload("res://scripts/core/MovementSystem.gd")
const _AbilityLibrary = preload("res://scripts/core/AbilityLibrary.gd")
const _IntentWeights = preload("res://scripts/ai/intent_weights.gd")
const _Result = preload("res://scripts/core/abilities/AbilityResult.gd")
const _JobClass = preload("res://scripts/core/JobClass.gd")


class TestUnit extends _Unit:
	func _init(u_name: String, faction: int = 0) -> void:
		stats = _Stats.new()
		stats.unit_name = u_name
		stats.melee_skill = 60
		stats.defense = 30
		stats.max_hp = 60
		stats.hp = 60
		stats.ap = 9
		stats.faction = faction
		stats.init_runtime()
		axial_pos = Vector2i.ZERO


var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	print("=== Movement + IntentWeights Smoke Test ===\n")
	_test_spec_factory()
	_test_movement_push()
	_test_movement_swap()
	_test_movement_blocked_by_edge()
	_test_intent_weights_basic_jobs()
	_test_intent_weights_hp_modifier()
	_test_ability_tuizhuang()
	_test_ability_huanwei()
	_test_ability_chaofeng()
	print("\n=== %d passed, %d failed ===" % [_pass, _fail])
	get_tree().quit(_fail)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] %s" % msg)
	else:
		_fail += 1
		push_error("[FAIL] %s" % msg)


# ─────────────── 测试用例 ───────────────

func _test_spec_factory() -> void:
	# PUSH：从 (0,0) 把 (1,0) 的 target 推 1 格 → 落点应为 (2,0)
	var fake_target := TestUnit.new("T")
	fake_target.axial_pos = Vector2i(1, 0)
	var s = _Spec.push(fake_target, Vector2i(0, 0), 1, 0)
	_ok(s.kind == _Spec.Kind.PUSH, "spec.kind == PUSH")
	_ok(s.dest == Vector2i(2, 0), "push dest correct (was %s)" % str(s.dest))

	# PULL：(2,0) 拉向 (0,0) 1 格 → 落点应为 (1,0)
	var t2 := TestUnit.new("T2")
	t2.axial_pos = Vector2i(2, 0)
	var s2 = _Spec.pull(t2, Vector2i(0, 0), 1)
	_ok(s2.dest == Vector2i(1, 0), "pull dest correct (was %s)" % str(s2.dest))

	# SWAP
	var a := TestUnit.new("A")
	var b := TestUnit.new("B")
	var s3 = _Spec.swap(a, b)
	_ok(s3.unit == a and s3.partner == b, "swap binds unit/partner")

	fake_target.queue_free()
	t2.queue_free()
	a.queue_free()
	b.queue_free()


func _test_movement_push() -> void:
	var grid: _HexGrid = _make_grid()
	var attacker := TestUnit.new("A", 0)
	var target := TestUnit.new("T", 1)
	add_child(attacker); add_child(target)
	_place(grid, attacker, Vector2i(0, 0))
	_place(grid, target, Vector2i(1, 0))

	var spec = _Spec.push(target, attacker.axial_pos, 1, 0)
	var r: Dictionary = _Movement.execute(spec, grid)
	_ok(r.get("ok"), "push ok")
	_ok(target.axial_pos == Vector2i(2, 0), "target moved to (2,0), got %s" % str(target.axial_pos))
	_ok(grid.get_occupant(Vector2i(2, 0)) == target, "occupant updated at new pos")
	_ok(grid.get_occupant(Vector2i(1, 0)) == null, "old pos cleared")
	_cleanup_grid(grid, [attacker, target])


func _test_movement_swap() -> void:
	var grid: _HexGrid = _make_grid()
	var a := TestUnit.new("A", 0)
	var b := TestUnit.new("B", 0)
	add_child(a); add_child(b)
	_place(grid, a, Vector2i(0, 0))
	_place(grid, b, Vector2i(1, 0))

	var spec = _Spec.swap(a, b)
	var r: Dictionary = _Movement.execute(spec, grid)
	_ok(r.get("ok"), "swap ok")
	_ok(a.axial_pos == Vector2i(1, 0), "A moved to B's pos")
	_ok(b.axial_pos == Vector2i(0, 0), "B moved to A's pos")
	_ok(grid.get_occupant(Vector2i(0, 0)) == b and grid.get_occupant(Vector2i(1, 0)) == a, "occupants swapped")
	_cleanup_grid(grid, [a, b])


func _test_movement_blocked_by_edge() -> void:
	# 推到地图边缘（推 99 格但 grid 半径 4 → 撞墙停下）
	var grid: _HexGrid = _make_grid()
	var attacker := TestUnit.new("A", 0)
	var target := TestUnit.new("T", 1)
	add_child(attacker); add_child(target)
	_place(grid, attacker, Vector2i(0, 0))
	_place(grid, target, Vector2i(1, 0))

	var spec = _Spec.push(target, attacker.axial_pos, 99, 0)
	var r: Dictionary = _Movement.execute(spec, grid)
	_ok(r.get("ok"), "push (long) ok")
	_ok(r.get("blocked"), "should be blocked by edge")
	_ok(target.axial_pos.x > 1, "target was pushed (final pos %s)" % str(target.axial_pos))
	_cleanup_grid(grid, [attacker, target])


func _test_intent_weights_basic_jobs() -> void:
	# 跳荡：attack 应较高（1.4 基线）
	var u := TestUnit.new("Tiao", 0)
	add_child(u)
	u.job = _make_fake_job("tiaodang")
	var w: Dictionary = _IntentWeights.compute(u, null, null)
	_ok(float(w.get("attack", 0.0)) > 0.5, "tiaodang attack weight > 0.5 (got %.2f)" % w.attack)

	# 弩手：retreat 应高于跳荡
	var u2 := TestUnit.new("Nu", 0)
	add_child(u2)
	u2.job = _make_fake_job("nushou")
	var w2: Dictionary = _IntentWeights.compute(u2, null, null)
	_ok(float(w2.get("retreat", 0.0)) > float(w.get("retreat", 0.0)),
		"nushou retreat (%.2f) > tiaodang retreat (%.2f)" % [w2.retreat, w.retreat])
	u.queue_free(); u2.queue_free()


func _test_intent_weights_hp_modifier() -> void:
	var u := TestUnit.new("U", 0)
	add_child(u)
	u.job = _make_fake_job("tiaodang")
	var w_full: Dictionary = _IntentWeights.compute(u, null, null)
	u.stats.hp = int(u.stats.max_hp * 0.2)  # 进入 critical
	var w_crit: Dictionary = _IntentWeights.compute(u, null, null)
	_ok(float(w_crit.retreat) > float(w_full.retreat) * 1.5,
		"critical retreat (%.2f) >> full retreat (%.2f)" % [w_crit.retreat, w_full.retreat])
	_ok(float(w_crit.attack) < float(w_full.attack),
		"critical attack (%.2f) < full attack (%.2f)" % [w_crit.attack, w_full.attack])
	u.queue_free()


func _test_ability_tuizhuang() -> void:
	var grid: _HexGrid = _make_grid()
	var atk := TestUnit.new("A", 0)
	var dst := TestUnit.new("D", 1)
	add_child(atk); add_child(dst)
	_place(grid, atk, Vector2i(0, 0))
	_place(grid, dst, Vector2i(1, 0))

	var ab = _AbilityLibrary.tuizhuang()
	var r: Dictionary = atk.use_ability(ab, dst, {})
	_ok(r.get(_Result.OK, false), "tuizhuang.apply ok")
	_ok(dst.axial_pos == Vector2i(2, 0), "dst pushed to (2,0), got %s" % str(dst.axial_pos))
	_ok(atk.stats.ap == 9 - 4, "tuizhuang spent 4 AP")
	_cleanup_grid(grid, [atk, dst])


func _test_ability_huanwei() -> void:
	var grid: _HexGrid = _make_grid()
	var a := TestUnit.new("A", 0)
	var b := TestUnit.new("B", 0)
	add_child(a); add_child(b)
	_place(grid, a, Vector2i(0, 0))
	_place(grid, b, Vector2i(1, 0))

	var ab = _AbilityLibrary.huanwei()
	var r: Dictionary = a.use_ability(ab, b, {})
	_ok(r.get(_Result.OK, false), "huanwei.apply ok")
	_ok(a.axial_pos == Vector2i(1, 0) and b.axial_pos == Vector2i(0, 0),
		"swap success: A %s, B %s" % [str(a.axial_pos), str(b.axial_pos)])
	_cleanup_grid(grid, [a, b])


func _test_ability_chaofeng() -> void:
	var grid: _HexGrid = _make_grid()
	var atk := TestUnit.new("A", 0)
	var dst := TestUnit.new("D", 1)
	add_child(atk); add_child(dst)
	_place(grid, atk, Vector2i(0, 0))
	_place(grid, dst, Vector2i(1, 0))

	var ab = _AbilityLibrary.chaofeng()
	var r: Dictionary = atk.use_ability(ab, dst, {})
	_ok(r.get(_Result.OK, false), "chaofeng.apply ok")
	var applied: Array = r.get(_Result.EFFECTS_APPLIED, [])
	_ok(applied.size() == 1, "chaofeng effect applied")
	if applied.size() > 0:
		_ok(applied[0].effect_id == "taunted" and applied[0].target == dst,
			"taunted on enemy")
	_cleanup_grid(grid, [atk, dst])


# ─────────────── 辅助 ───────────────

func _make_grid() -> _HexGrid:
	var g: _HexGrid = _HexGrid.new()
	g.map_radius = 4
	g.fog_enabled = false
	g.skip_obstacle_generation = true
	add_child(g)
	return g


func _place(grid: _HexGrid, unit: TestUnit, pos: Vector2i) -> void:
	unit.hex_grid = grid
	unit.axial_pos = pos
	grid.set_occupant(pos, unit)


func _cleanup_grid(grid: _HexGrid, units: Array) -> void:
	for u in units:
		u.queue_free()
	grid.queue_free()


func _make_fake_job(job_id: String):
	var j = _JobClass.new()
	j.id = job_id
	return j
