extends SceneTree
##
## test_turn_scheduler.gd — 新 TurnManager（AP + 回合制 + 等待）自检
##
## 跑法：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --script scripts/tools/test_turn_scheduler.gd --headless
##
## 验证项：
##   T1. 回合内单位按 effective_initiative 降序行动
##   T2. 顺序预览：[当前] + 本回合剩余 + 下回合预览
##   T3. 等待机制：当前单位 wait → 挪到队尾
##   T4. 等待限 1 次
##   T5. 等待回来不二次 start_turn（AP 不重置）
##   T6. AP 不跨回合保留（下回合开始 AP=max_ap）
##   T7. 死亡单位移出队列；剩单方时 battle_ended
##


# ──────────── 测试辅助：包装真 Unit + start_turn 计数 ────────────
class TestUnit extends Unit:
	var start_turn_count: int = 0
	func _init(name: String, init_val: int, faction_id: int = 0, max_ap: int = 9) -> void:
		stats = Stats.new()
		stats.unit_name = name
		stats.base_initiative = init_val
		stats.max_ap = max_ap
		stats.max_hp = 60
		stats.faction = faction_id
		stats.init_runtime()
	# 不直接重写 start_turn（inner class 多态在 GDScript 里偶尔不可靠），
	# 用独立的辅助方法 + 信号计数代替
	func bump_start_count() -> void:
		start_turn_count += 1


var pass_count: int = 0
var fail_count: int = 0
var t7_winner: int = -2   ## T7 用全局变量代替 lambda 捕获


func _initialize() -> void:
	print("=== 新 TurnManager 自检 (E 段) ===\n")

	_t1_init_order()
	_t2_preview()
	_t3_wait_to_tail()
	_t4_wait_once_only()
	_t5_wait_no_double_start_turn()
	_t6_ap_no_carry()
	_t7_death_removed_from_queue()

	print("\n──────── 总结 ────────")
	print("PASS %d / FAIL %d" % [pass_count, fail_count])
	if fail_count > 0:
		print("❌ 有失败用例")
		quit(1)
	else:
		print("✅ 全部通过")
		quit(0)


# ────────────────────────────── helpers ──────────────────────────────

func _expect(cond: bool, msg: String) -> void:
	if cond:
		pass_count += 1
		print("  [PASS] " + msg)
	else:
		fail_count += 1
		print("  [FAIL] " + msg)


func _make_tm(units: Array) -> TurnManager:
	var tm := TurnManager.new()
	get_root().add_child(tm)
	for u in units:
		get_root().add_child(u)   # Unit 是 Node2D，需要进 SceneTree 触发 _ready
	tm.register_units(units)
	return tm


func _names_of(arr: Array) -> Array:
	var r: Array = []
	for u in arr:
		r.append((u.stats.unit_name if u and u.stats else "null"))
	return r


func _name(u: Unit) -> String:
	return u.stats.unit_name if u and u.stats else "null"


func _cleanup(tm: TurnManager, units: Array) -> void:
	tm.queue_free()
	for u in units:
		u.queue_free()


# ────────────────────────────── tests ──────────────────────────────

func _t1_init_order() -> void:
	print("[T1] 回合内按 init 降序")
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 0)
	var uc := TestUnit.new("C", 70, 1)
	var ud := TestUnit.new("D", 40, 1)
	var units := [ua, ub, uc, ud]
	var tm := _make_tm(units)
	tm.start_battle()

	var seq: Array = []
	for i in range(4):
		var cur: Unit = tm.get_current_unit()
		seq.append(_name(cur))
		cur.end_turn()

	_expect(seq == ["A", "B", "C", "D"], "顺序 A→B→C→D，实际 %s" % str(seq))
	_cleanup(tm, units)


func _t2_preview() -> void:
	print("[T2] get_turn_order_preview 含本回合剩余 + 下回合预览")
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 0)
	var uc := TestUnit.new("C", 70, 1)
	var units := [ua, ub, uc]
	var tm := _make_tm(units)
	tm.start_battle()

	var preview: Array = tm.get_turn_order_preview()
	var names: Array = _names_of(preview)
	_expect(names.size() >= 5, "preview 长度 ≥ 5（本回合 3 + 下回合 ≥ 2），实际 %d (%s)" % [names.size(), str(names)])
	if names.size() >= 3:
		_expect(names[0] == "A" and names[1] == "B" and names[2] == "C",
			"前 3 个应是当前回合 A→B→C，实际 %s" % str(names.slice(0, 3)))
	_cleanup(tm, units)


func _t3_wait_to_tail() -> void:
	print("[T3] wait_current 把当前单位挪到队尾")
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 0)
	var uc := TestUnit.new("C", 70, 1)
	var units := [ua, ub, uc]
	var tm := _make_tm(units)
	tm.start_battle()

	_expect(_name(tm.get_current_unit()) == "A", "起始当前应是 A")
	_expect(ua.stats.stamina_spent() == 0, "等待前已耗气力应为 0")
	var ok: bool = tm.wait_current()
	_expect(ok, "wait_current 应返回 true")
	_expect(ua.stats.stamina_spent() == TurnManager.WAIT_STAMINA_COST,
		"首次等待应消耗 %d 气力，实际 %d" % [TurnManager.WAIT_STAMINA_COST, ua.stats.stamina_spent()])
	_expect(_name(tm.get_current_unit()) == "B", "wait 后当前应为 B，实际 %s" % _name(tm.get_current_unit()))
	tm.get_current_unit().end_turn()  # B
	_expect(_name(tm.get_current_unit()) == "C", "B 完后应是 C，实际 %s" % _name(tm.get_current_unit()))
	tm.get_current_unit().end_turn()  # C
	_expect(_name(tm.get_current_unit()) == "A", "C 完后应轮回 A（队尾），实际 %s" % _name(tm.get_current_unit()))
	_cleanup(tm, units)


func _t4_wait_once_only() -> void:
	print("[T4] 等待：首次排到队尾，二次视为结束回合")
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 1)   ## 必须有敌方单位，否则 _check_battle_end 提前判负
	var units := [ua, ub]
	var tm := _make_tm(units)
	tm.start_battle()
	# 当前 A，wait → queue=[B,A]，进 B
	_expect(tm.wait_current(), "A 首次 wait 成功")
	# 当前 B，wait → queue=[A,B]，进 A
	_expect(tm.wait_current(), "B 首次 wait 也应成功")
	_expect(_name(tm.get_current_unit()) == "A", "两次 wait 后当前应是 A，实际 %s" % _name(tm.get_current_unit()))
	_expect(tm.wait_current(), "A 第二次 wait 视为结束回合")
	_expect(_name(tm.get_current_unit()) == "B", "A 结束回合后应是 B，实际 %s" % _name(tm.get_current_unit()))
	_cleanup(tm, units)


func _t5_wait_no_double_start_turn() -> void:
	print("[T5] 等待回来不二次重置 AP")
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 1)
	var units := [ua, ub]
	var tm := _make_tm(units)
	tm.start_battle()
	_expect(ua.stats.ap == 9, "A 初始 AP 应 9，实际 %d" % ua.stats.ap)
	ua.stats.ap = 4
	tm.wait_current()
	_expect(_name(tm.get_current_unit()) == "B", "wait 后当前应是 B，实际 %s" % _name(tm.get_current_unit()))
	if tm.get_current_unit() != null:
		tm.get_current_unit().end_turn()
	_expect(_name(tm.get_current_unit()) == "A", "B 完后回到 A")
	_expect(ua.stats.ap == 4, "A 等待回来 AP 应保持 4（不重置），实际 %d" % ua.stats.ap)
	_cleanup(tm, units)


func _t6_ap_no_carry() -> void:
	print("[T6] AP 不跨回合保留")
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 1)
	var units := [ua, ub]
	var tm := _make_tm(units)
	tm.start_battle()
	ua.stats.ap = 4
	ua.end_turn()
	var b := tm.get_current_unit()
	_expect(_name(b) == "B", "A 完后应是 B，实际 %s" % _name(b))
	if b != null:
		b.end_turn()
	_expect(tm.round_num == 2, "应进入第 2 回合，实际 %d" % tm.round_num)
	_expect(_name(tm.get_current_unit()) == "A", "第二回合首单位应是 A")
	_expect(ua.stats.ap == 9, "A 第二回合 AP 应回满 9（不带 4），实际 %d" % ua.stats.ap)
	_cleanup(tm, units)


func _on_t7_battle_ended(winner: int) -> void:
	t7_winner = winner


func _t7_death_removed_from_queue() -> void:
	print("[T7] 死亡单位移出队列；剩单方时 battle_ended")
	t7_winner = -2
	var ua := TestUnit.new("A", 130, 0)
	var ub := TestUnit.new("B", 100, 1)
	var uc := TestUnit.new("C", 70, 1)
	var units := [ua, ub, uc]
	var tm := _make_tm(units)
	tm.battle_ended.connect(_on_t7_battle_ended)
	tm.start_battle()
	# 杀死 B（敌方）
	ub.stats.hp = 0
	ub.unit_died.emit(ub)
	ua.end_turn()
	_expect(tm.get_current_unit() != null and _name(tm.get_current_unit()) == "C",
		"B 死亡后应是 C，实际 %s" % _name(tm.get_current_unit()))
	# 杀掉 C → 友方胜
	uc.stats.hp = 0
	uc.unit_died.emit(uc)
	_expect(t7_winner == 0, "敌方全灭，winner 应为 0，实际 %d" % t7_winner)
	_cleanup(tm, units)
