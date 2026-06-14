extends Node
##
## test_ai_m0_scene.gd — AI M0 决策单测（--scene 模式，autoload 已就绪）
## ./tools/run_tests.sh --full
##

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _AIAgent = preload("res://scripts/ai/ai_agent.gd")
const _AIWorldView = preload("res://scripts/ai/world_view.gd")
const _AISimExecutor = preload("res://scripts/ai/sim_executor.gd")
const _BehaviorDefend = preload("res://scripts/ai/behaviors/behavior_defend.gd")
const _AIProfile = preload("res://scripts/ai/ai_profile.gd")
const _AIBreath = preload("res://scripts/ai/behaviors/behavior_breath.gd")
const _AIWait = preload("res://scripts/ai/behaviors/behavior_wait.gd")
const _AIAttack = preload("res://scripts/ai/behaviors/behavior_attack.gd")
const _AIBehavior = preload("res://scripts/ai/behaviors/behavior_base.gd")
const _AIAdvance = preload("res://scripts/ai/behaviors/behavior_advance.gd")
const _ActionScorer = preload("res://scripts/ai/scoring/action_scorer.gd")
const _SurroundCost = preload("res://scripts/ai/scoring/surround_cost.gd")

const TEST_SEED: int = 424242

var pass_count: int = 0
var fail_count: int = 0
var _saved_deterministic: bool = false


func _ready() -> void:
	await get_tree().process_frame
	print("=== AI M0 决策单测 ===\n")
	_load_ai_scripts()
	_ensure_weapon_db()
	_enable_deterministic()

	_t_engage_when_out_of_range()
	_t_attack_when_in_range()
	_t_engage_attack_chain()
	_t_spear_prefers_range_two_approach()
	_t_spear_no_facehug_when_two_steps_no_attack()
	_t_spear_attacks_at_range_two()
	_t_spear_holds_at_range_two_low_ap()
	_t_engage_skips_when_in_range()
	_t_wait_blocked_in_range()
	_t_wait_blocked_exhausted()
	_t_wait_blocked_surrounded()
	_t_defend_blocked_move_attack_setup()
	_t_guard_heavy_prefers_engage_over_defend()
	_t_heavy_guard_pushes_when_behind_ally()
	_t_defend_allowed_low_hit()
	_t_wait_allowed_low_hit_in_range()
	_t_wait_blocked_far_neutral()
	_t_wait_allowed_far_ranged_advantage()
	_t_deterministic_repeatable()
	_t_breath_when_low_stamina_far()
	_t_high_hit_kill_favors_attack()
	_t_low_hit_kill_not_forced()
	_t_breath_guard_heavy_adjacent()
	_t_breath_guard_heavy_surrounded()
	_t_breath_after_wait_recovery()
	_t_no_ap_waste_when_no_defer()
	_t_no_end_turn_with_leftover_ap()
	_t_scout_defers_until_ally_contact()
	_t_skirmisher_no_wait_when_level_with_frontline()
	_t_no_move_with_net_negative_oa()
	_t_prefer_adjacent_over_reposition()
	_t_prefer_soft_target_when_adjacent()
	_t_guard_prefer_adjacent_over_reposition()
	_t_guard_prefer_soft_target_when_adjacent()
	_t_setup_move_toward_wounded()
	_t_adjacent_2h_oa_blocks_meaningless_move()
	_t_dagger_in_range_low_ap_no_oa_step()
	_t_ability_in_best_ap_spend_when_short()
	_t_breath_excluded_when_ap_not_full()
	_t_preempt_beats_adjacent_enemy_leftover_ap()
	_t_preempt_skipped_when_already_first()
	_t_preempt_blocked_when_would_exhaust()
	_t_heavy_guard_adjacent_low_ap_no_meaningless_oa()
	_t_heavy_guard_switch_soft_target_may_move()
	_t_spear_adjacent_low_ap_no_advance_facehug()
	_t_spear_adjacent_far_target_thin_setup_end()
	_t_spear_wait_resume_low_ap_end()
	_t_defer_penalizes_adjacent_reach_micro_setup()
	_t_oa_penalty_scales_with_own_armor()
	_t_swap_setup_exempt_from_defer()
	_t_surround_penalty_blocks_pocket_without_harvest()
	_t_deep_surround_kill_still_worth_charge()

	_restore_deterministic()
	print("\n──────── 总结 ────────")
	print("PASS %d / FAIL %d" % [pass_count, fail_count])
	get_tree().quit(1 if fail_count > 0 else 0)


func _load_ai_scripts() -> void:
	load("res://scripts/ai/ai_action.gd")
	load("res://scripts/ai/behaviors/behavior_base.gd")
	load("res://scripts/ai/scoring/target_scorer.gd")
	load("res://scripts/ai/scoring/engage_scorer.gd")
	load("res://scripts/ai/scoring/action_scorer.gd")
	load("res://scripts/ai/scoring/self_state_score.gd")
	load("res://scripts/ai/scoring/surround_cost.gd")
	load("res://scripts/ai/scoring/attack_opportunity.gd")
	load("res://scripts/ai/behaviors/behavior_wait.gd")
	load("res://scripts/ai/behaviors/behavior_retreat.gd")
	load("res://scripts/ai/behaviors/behavior_advance.gd")
	load("res://scripts/ai/behaviors/behavior_disengage.gd")
	load("res://scripts/ai/behaviors/behavior_defend.gd")
	load("res://scripts/ai/behaviors/behavior_engage.gd")
	load("res://scripts/ai/behaviors/behavior_attack.gd")
	load("res://scripts/ai/behaviors/behavior_breath.gd")
	load("res://scripts/ai/behaviors/behavior_preempt.gd")
	load("res://scripts/ai/behaviors/behavior_ability.gd")
	load("res://scripts/ai/ai_profile.gd")
	load("res://scripts/ai/sim_executor.gd")
	_ensure_ai_config_db()


func _ensure_ai_config_db() -> void:
	if get_tree().root.get_node_or_null("AIConfigDB") != null:
		return
	var db: Node = load("res://scripts/data/AIConfigDB.gd").new()
	db.name = "AIConfigDB"
	get_tree().root.add_child(db)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		pass_count += 1
		print("  [PASS] " + msg)
	else:
		fail_count += 1
		print("  [FAIL] " + msg)


func _ensure_weapon_db() -> void:
	var db: Node = get_tree().root.get_node_or_null("WeaponArmorDB")
	if db == null:
		return
	if db.call("get_weapon", "saber") == null:
		db.call("_load_weapons")
		db.call("_load_armors")


func _enable_deterministic() -> void:
	var db: Node = get_tree().root.get_node_or_null("AIConfigDB")
	if db == null:
		return
	if db.has_method("is_deterministic"):
		_saved_deterministic = db.is_deterministic()
	if db.has_method("set_deterministic"):
		db.set_deterministic(true)


func _restore_deterministic() -> void:
	var db: Node = get_tree().root.get_node_or_null("AIConfigDB")
	if db != null and db.has_method("set_deterministic"):
		db.set_deterministic(_saved_deterministic)


func _make_grid(parent: Node) -> HexGrid:
	var grid := HexGrid.new()
	grid.map_radius = 6
	grid.fog_enabled = false
	grid.skip_obstacle_generation = true
	parent.add_child(grid)
	return grid


func _make_unit(
	unit_name: String,
	faction: int,
	axial: Vector2i,
	weapon_id: String,
	grid: HexGrid,
	ap: int = 9,
) -> Unit:
	var unit := Unit.new()
	var stats := Stats.new()
	stats.unit_name = unit_name
	stats.faction = faction
	stats.max_hp = 60
	stats.hp = 60
	stats.melee_skill = 60
	stats.defense = 10
	stats.melee_defense = 10
	stats.base_initiative = 100
	stats.max_ap = ap
	stats.ap = ap
	stats.max_stamina = 100
	stats.stamina = stats.max_stamina
	stats.move_range = 4
	unit.stats = stats
	unit.weapon = WeaponArmorDB.get_weapon(weapon_id)
	get_tree().root.add_child(unit)
	unit.place_at(axial, grid)
	return unit


func _make_tm(units: Array, current: Unit) -> TurnManager:
	var tm := TurnManager.new()
	get_tree().root.add_child(tm)
	tm.register_units(units)
	tm.start_battle()
	while tm.get_current_unit() != current and tm.is_running():
		var u: Unit = tm.get_current_unit()
		if u == null:
			break
		u.end_turn()
	return tm


func _build_world(
	attacker_pos: Vector2i,
	enemy_positions: Array,
	attacker_ap: int = 9,
) -> Dictionary:
	var grid := _make_grid(get_tree().root)
	var attacker := _make_unit("攻方", 0, attacker_pos, "saber", grid, attacker_ap)
	var enemies: Array = []
	var i: int = 0
	for pos in enemy_positions:
		if pos is Vector2i:
			enemies.append(_make_unit("敌%d" % i, 1, pos, "saber", grid))
			i += 1
	var units: Array = [attacker]
	units.append_array(enemies)
	var tm := _make_tm(units, attacker)
	return {
		"grid": grid,
		"attacker": attacker,
		"enemies": enemies,
		"units": units,
		"tm": tm,
	}


func _teardown(world: Dictionary) -> void:
	for u in world.get("units", []):
		if u is Node and is_instance_valid(u):
			u.free()
	for key in ["tm", "grid"]:
		var n = world.get(key, null)
		if n is Node and is_instance_valid(n):
			n.free()


func _capture(world: Dictionary) -> AIWorldView:
	return _AIWorldView.capture(
		world.attacker,
		world.units,
		world.grid,
		world.tm,
		{},
	)


func _decide(world: Dictionary, seed: int = TEST_SEED):
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + world.attacker.axial_pos.x * 1000 + world.attacker.axial_pos.y
	var agent := _AIAgent.new(world.attacker, rng)
	return agent.decide_next_action(_capture(world))


func _defend_eval(world: Dictionary) -> Dictionary:
	return _BehaviorDefend.new().evaluate(_capture(world))


func _wait_eval(world: Dictionary) -> Dictionary:
	return AIBehavior_Wait.new().evaluate(_capture(world))


func _engage_eval(world: Dictionary) -> Dictionary:
	return AIBehavior_Engage.new().evaluate(_capture(world))


func _t_engage_when_out_of_range() -> void:
	print("[T1] 射程外 → Engage(MOVE)")
	var world := _build_world(Vector2i(0, 0), [Vector2i(4, 0)])
	var action = _decide(world)
	_expect(action.type == _AT.MOVE, "决策应为 MOVE，实际 type=%d" % action.type)
	_expect(not action.payload.get("path", []).is_empty(), "MOVE 应带非空 path")
	_teardown(world)


func _t_attack_when_in_range() -> void:
	print("[T2] 射程内 → Attack")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "决策应为 ATTACK，实际 type=%d" % action.type)
	_expect(action.payload.get("target") == world.enemies[0], "攻击目标应为邻格敌人")
	_teardown(world)


func _t_engage_attack_chain() -> void:
	print("[T3] Engage→Attack 链（移动后能打）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(3, 0)])
	var first = _decide(world)
	_expect(first.type == _AT.MOVE, "第一步应为 MOVE，实际 type=%d" % first.type)
	var executor := _AISimExecutor.new()
	var moved: bool = executor.run(first, world.attacker, world.units, world.grid, world.tm)
	_expect(moved, "同步移动应成功")
	var second = _decide(world)
	_expect(second.type == _AT.ATTACK, "第二步应为 ATTACK，实际 type=%d" % second.type)
	_teardown(world)


func _t_spear_prefers_range_two_approach() -> void:
	print("[T3b] 长矛接敌 → 停 2 格不贴脸")
	var world := _build_world(Vector2i(0, 0), [Vector2i(4, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	var action = _decide(world)
	_expect(action.type == _AT.MOVE, "应为 MOVE，实际 type=%d" % action.type)
	var path: Array = action.payload.get("path", [])
	_expect(not path.is_empty(), "MOVE 应带 path")
	var dest: Vector2i = path[-1]
	var dist: int = _HexCoord.distance(dest, world.enemies[0].axial_pos)
	_expect(dist >= 2, "应停在 2 格或更远，实际 dist=%d dest=%s" % [dist, dest])
	_teardown(world)


func _t_spear_no_facehug_when_two_steps_no_attack() -> void:
	print("[T3d] 长矛 4 格外接敌 → 2 步无法同回合攻 → 仍停 2 格")
	var world := _build_world(Vector2i(0, 0), [Vector2i(4, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.stats.ap = 9
	var action = _decide(world)
	_expect(action.type == _AT.MOVE, "应为 MOVE，实际 type=%d" % action.type)
	var path: Array = action.payload.get("path", [])
	var dest: Vector2i = path[-1]
	var dist: int = _HexCoord.distance(dest, world.enemies[0].axial_pos)
	_expect(dist == 2, "应精确落在 2 格（非贴脸），实际 dist=%d dest=%s" % [dist, dest])
	var mc: int = path.size() * 2
	_expect(
		world.attacker.stats.ap - mc < world.attacker.get_weapon_ap_cost(),
		"前置：2 步移动后 AP 不够同回合攻击",
	)
	_teardown(world)


func _t_spear_attacks_at_range_two() -> void:
	print("[T3c] 长矛 2 格内 → Attack")
	var world := _build_world(Vector2i(0, 0), [Vector2i(2, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "应为 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_spear_holds_at_range_two_low_ap() -> void:
	print("[T3e] 长矛 2 格 AP 不够攻 → 不贴脸，综合评估后收手或 setup")
	var world := _build_world(Vector2i(0, 0), [Vector2i(2, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.stats.ap = 5
	_expect(
		world.attacker.stats.ap < world.attacker.get_weapon_ap_cost(),
		"前置：5 AP 不够 6 AP 攻击",
	)
	var action = _decide(world)
	_expect(
		action.type == _AT.END_TURN or action.type == _AT.MOVE or action.type == _AT.ABILITY,
		"应 end_turn/MOVE/技能，实际 type=%d reason=%s" % [action.type, action.reason],
	)
	if action.type == _AT.MOVE:
		var dest: Vector2i = action.payload.get("path", [])[-1]
		var dist: int = _HexCoord.distance(dest, world.enemies[0].axial_pos)
		_expect(dist >= 2, "残 AP 走位不应贴脸，实际 dist=%d" % dist)
	_teardown(world)


func _t_engage_skips_when_in_range() -> void:
	print("[T4] 已在射程 → Engage 0 分")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	var r: Dictionary = _engage_eval(world)
	_expect(r.score <= 0.0, "Engage 应 0 分，实际 %.1f" % r.score)
	_teardown(world)


func _t_wait_blocked_in_range() -> void:
	print("[T5] 高命中射程内 → 应 Attack 非 Wait")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.melee_skill = 85
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "决策应为 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_wait_blocked_exhausted() -> void:
	print("[T6] 力竭 → Wait 0 分")
	var world := _build_world(Vector2i(0, 0), [Vector2i(4, 0)])
	world.attacker.stats.stamina = 0
	var r: Dictionary = _wait_eval(world)
	_expect(r.score <= 0.0, "力竭 Wait 应 0 分，实际 %.1f" % r.score)
	_teardown(world)


func _t_wait_blocked_surrounded() -> void:
	print("[T7] 被围(>2 邻敌) → Wait 0 分")
	var world := _build_world(Vector2i(0, 0), [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 1),
	])
	var r: Dictionary = _wait_eval(world)
	_expect(r.score <= 0.0, "被围 Wait 应 0 分，实际 %.1f" % r.score)
	_teardown(world)


func _t_defend_blocked_move_attack_setup() -> void:
	print("[T7b] 走+打机会高于 Defend → 应 MOVE 非 Wait")
	var world := _build_world(Vector2i(0, 0), [Vector2i(2, 0)])
	world.attacker.ai_disposition_id = "guard"
	world.attacker.ai_archetype_id = "heavy_infantry"
	var action = _decide(world)
	_expect(action.type != _AT.WAIT, "不应 Wait/Defend，实际 type=%d" % action.type)
	_expect(action.type == _AT.MOVE or action.type == _AT.ATTACK,
		"应 MOVE 或 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_guard_heavy_prefers_engage_over_defend() -> void:
	print("[T7c] 重甲 guard 邻格高命中 → 应 Attack")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.stats.melee_skill = 85
	world.attacker.ai_disposition_id = "guard"
	world.attacker.ai_archetype_id = "heavy_infantry"
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "决策应为 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_heavy_guard_pushes_when_behind_ally() -> void:
	print("[T7f] 重甲 guard 友军更靠前 → 应前压 MOVE 非 Wait")
	var grid := _make_grid(get_tree().root)
	var heavy := _make_unit("重甲头目", 1, Vector2i(0, 0), "battle_axe", grid)
	heavy.ai_archetype_id = "heavy_infantry"
	heavy.ai_disposition_id = "guard"
	heavy.armor = WeaponArmorDB.get_armor("plate_armor")
	var ally := _make_unit("矛兵", 1, Vector2i(2, 0), "spear", grid)
	ally.ai_archetype_id = "infantry"
	var enemy := _make_unit("敌", 0, Vector2i(4, 0), "saber", grid)
	var units: Array = [heavy, ally, enemy]
	var tm := _make_tm(units, heavy)
	var world := {
		"grid": grid, "attacker": heavy, "enemies": [enemy],
		"units": units, "tm": tm,
	}
	var action = _decide(world)
	_expect(action.type == _AT.MOVE, "后排重甲应 MOVE 前压，实际 type=%d" % action.type)
	_teardown(world)


func _t_defend_allowed_low_hit() -> void:
	print("[T7d] 低命中被围 → Defend 可评分")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.stats.melee_skill = 35
	world.attacker.ai_disposition_id = "guard"
	for e in world.enemies:
		e.stats.defense = 55
		e.stats.melee_defense = 55
		e.armor = WeaponArmorDB.get_armor("plate_armor")
	var opp: Dictionary = AIBehavior.best_attack_utility(_capture(world))
	_expect(opp.get("utility", 999.0) < 80.0, "低命中机会成本应较低，utility=%.1f" % opp.get("utility", 0.0))
	var r: Dictionary = _defend_eval(world)
	_expect(r.score > 0.0, "Defend 应 >0，实际 %.1f" % r.score)
	_teardown(world)


func _t_wait_allowed_low_hit_in_range() -> void:
	print("[T7e] 低命中射程内可攻 → Wait 0 分（应 Attack/Defend）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.melee_skill = 35
	world.enemies[0].stats.defense = 55
	world.enemies[0].stats.melee_defense = 55
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	var r: Dictionary = _wait_eval(world)
	_expect(r.score <= 0.0, "接敌可攻时 Wait 应 0 分，实际 %.1f" % r.score)
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "应 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_wait_blocked_far_neutral() -> void:
	print("[T8] NEUTRAL 远距低威胁 → Wait 0 分（应 Engage）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(5, 0)])
	var r: Dictionary = _wait_eval(world)
	_expect(r.score <= 0.0, "NEUTRAL 远距 Wait 应 0 分，实际 %.1f" % r.score)
	_teardown(world)


func _t_wait_allowed_far_ranged_advantage() -> void:
	print("[T8b] ALLY_ADVANTAGE 远距 → Wait 可评分")
	var world := _build_world(Vector2i(0, 0), [Vector2i(5, 0)])
	var bow_ally := _make_unit("弓手", 0, Vector2i(-1, 0), "bow", world.grid)
	world.units.append(bow_ally)
	var r: Dictionary = _wait_eval(world)
	_expect(r.score > 0.0 and r.action != null, "远程优势远距 Wait 应 >0，实际 %.1f" % r.score)
	_teardown(world)


func _t_deterministic_repeatable() -> void:
	print("[T9] deterministic 同局面同决策")
	var world := _build_world(Vector2i(0, 0), [Vector2i(3, 0)])
	var a1 = _decide(world, TEST_SEED)
	var a2 = _decide(world, TEST_SEED)
	_expect(a1.type == a2.type, "两次 type 应相同 (%d vs %d)" % [a1.type, a2.type])
	if a1.type == _AT.MOVE:
		_expect(a1.payload.get("path", []) == a2.payload.get("path", []), "MOVE path 应一致")
	_teardown(world)


func _t_breath_when_low_stamina_far() -> void:
	print("[T10] 气力≤20% 且射程外 → 吐纳")
	var world := _build_world(Vector2i(0, 0), [Vector2i(4, 0)])
	world.attacker.stats.stamina = 15
	var action = _decide(world)
	_expect(action.type == _AT.ABILITY, "决策应为 ABILITY，实际 type=%d" % action.type)
	_expect(action.payload.get("ability_id", "") == "breath_regulation", "应为吐纳调息")
	var executor := _AISimExecutor.new()
	var cont: bool = executor.run(action, world.attacker, world.units, world.grid, world.tm)
	_expect(not cont, "吐纳后应结束本回合循环")
	_expect(world.attacker.stats.stamina == world.attacker.breath_regulation_stamina(),
		"气力应恢复至负重下限")
	_teardown(world)


func _t_high_hit_kill_favors_attack() -> void:
	print("[T11] 高命中残血 → Attack 综合分胜出（非硬拦）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.stamina = 15
	world.attacker.stats.melee_skill = 80
	world.enemies[0].stats.hp = 8
	world.enemies[0].stats.max_hp = 60
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var attack_r: Dictionary = _AIAttack.new().evaluate(view, profile)
	var breath_r: Dictionary = _AIBreath.new().evaluate(view, profile)
	_expect(attack_r.score > breath_r.score, "Attack %.1f 应 > Breath %.1f" % [attack_r.score, breath_r.score])
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "决策应为 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_low_hit_kill_not_forced() -> void:
	print("[T11b] 低命中残血 → 不强制攻击")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.stamina = 15
	world.attacker.stats.melee_skill = 25
	world.enemies[0].stats.hp = 8
	world.enemies[0].stats.max_hp = 60
	world.enemies[0].stats.defense = 55
	world.enemies[0].stats.melee_defense = 55
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	var action = _decide(world)
	_expect(action.type != _AT.ATTACK, "低命中不应强制 ATTACK，实际 type=%d" % action.type)
	_teardown(world)


func _t_breath_guard_heavy_adjacent() -> void:
	print("[T12] 重甲 guard 邻格低气力 → 该场景应吐纳")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.stats.max_stamina = 65
	world.attacker.stats.stamina = 11
	world.attacker.stats.hp = 45
	world.attacker.stats.max_hp = 95
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	var action = _decide(world)
	_expect(action.type == _AT.ABILITY, "决策应为 ABILITY，实际 type=%d" % action.type)
	_expect(action.payload.get("ability_id", "") == "breath_regulation", "应为吐纳调息")
	_teardown(world)


func _t_breath_guard_heavy_surrounded() -> void:
	print("[T13] 被围低气力仍可 Q → 综合分竞争，不强制吐纳")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.stats.max_stamina = 65
	world.attacker.stats.stamina = 11
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	var view := _capture(world)
	_expect(view.can_wait(), "前置：本回合仍可 Q")
	var action = _decide(world)
	_expect(action.type != _AT.END_TURN, "不应空结束，实际 type=%d" % action.type)
	_teardown(world)


func _t_breath_after_wait_recovery() -> void:
	print("[T14] Q 恢复行动后低气力 → 须花 AP（吐纳）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.stats.max_stamina = 65
	world.attacker.stats.stamina = 11
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	var executor := _AISimExecutor.new()
	var wait_action = _AT.wait("setup")
	executor.run(wait_action, world.attacker, world.units, world.grid, world.tm)
	var guard: int = 0
	while world.tm.get_current_unit() != world.attacker and world.tm.is_running():
		guard += 1
		if guard > 16:
			break
		var u: Unit = world.tm.get_current_unit()
		if u == null:
			break
		u.end_turn()
	var action = _decide(world)
	_expect(action.type == _AT.ABILITY, "恢复后应吐纳，实际 type=%d" % action.type)
	_teardown(world)


func _t_no_ap_waste_when_no_defer() -> void:
	print("[T15] 已 Q、低气力 → 不得 Wait/空结束（Defend 防御场景除外）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.stats.max_stamina = 65
	world.attacker.stats.stamina = 11
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	world.tm._waited_this_round[world.attacker] = true
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	_expect(not view.can_wait(), "前置：本回合不可再 Q")
	var spend_u: float = _AIBehavior.best_ap_spend_utility(view, profile)
	_expect(spend_u > 0.0, "前置：应有 AP 花费效用，实际 %.1f" % spend_u)
	var action = _decide(world)
	var allowed: bool = (
		action.type == _AT.ABILITY
		or action.type == _AT.ATTACK
		or action.type == _AT.MOVE
		or (action.type == _AT.WAIT and action.reason == "defend")
	)
	_expect(allowed, "不得 Wait/空转（Defend 除外），实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_no_end_turn_with_leftover_ap() -> void:
	print("[T16] 攻后剩 AP 不够再攻 → 应走位非 end_turn")
	var world := _build_world(Vector2i(0, 0), [Vector2i(2, 0)])
	world.attacker.stats.ap = 3
	var action = _decide(world)
	_expect(
		action.type == _AT.MOVE or action.type == _AT.ABILITY,
		"剩 AP 应 MOVE/ABILITY，实际 type=%d reason=%s" % [action.type, action.reason],
	)
	_teardown(world)


func _t_scout_defers_until_ally_contact() -> void:
	print("[T17] 匕首斥候友军未接敌 → Wait，不抢冲")
	var world := _build_world(Vector2i(-3, 0), [Vector2i(5, 0)])
	world.attacker.ai_archetype_id = "scout"
	world.attacker.weapon = WeaponArmorDB.get_weapon("dagger")
	world.attacker.armor = WeaponArmorDB.get_armor("leather_armor")
	var ally := _make_unit("矛兵", 0, Vector2i(-2, 2), "spear", world.grid)
	ally.ai_archetype_id = "infantry"
	world.units.append(ally)
	var action = _decide(world)
	_expect(action.type == _AT.WAIT, "友军未贴脸应 Wait，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_skirmisher_no_wait_when_level_with_frontline() -> void:
	print("[T17b] 跳荡与矛兵同距于敌 → 不互等，应前压")
	var world := _build_world(Vector2i(0, 0), [Vector2i(5, 0)])
	world.attacker.ai_archetype_id = "skirmisher"
	var ally := _make_unit("矛兵", 0, Vector2i(0, 1), "spear", world.grid)
	ally.ai_archetype_id = "infantry"
	world.units.append(ally)
	var action = _decide(world)
	_expect(action.type != _AT.WAIT, "同距不应 Wait，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_no_move_with_net_negative_oa() -> void:
	print("[T18] 双邻敌 AP 不足再攻 → 不吃 OA 硬走，应 end/wait")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.stats.ap = 3
	var action = _decide(world)
	var ok: bool = action.type == _AT.END_TURN or action.type == _AT.WAIT
	_expect(ok, "无正收益走位应 end/wait，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_prefer_adjacent_over_reposition() -> void:
	print("[T19] 邻格重甲 + 远距脆皮 → 直攻邻格，不走位换目标")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(3, 0)])
	world.attacker.ai_disposition_id = "berserk"
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 80
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 55
	world.enemies[0].stats.head_armor = 20
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 20
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 8
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "应直攻，实际 type=%d" % action.type)
	_expect(action.payload.get("target") == world.enemies[0], "邻格有敌时不应为远距脆皮走位")
	_teardown(world)


func _t_prefer_soft_target_when_adjacent() -> void:
	print("[T20] 双邻敌 → 优先低血低甲")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.ai_disposition_id = "berserk"
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 18
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "应攻击，实际 type=%d" % action.type)
	_expect(action.payload.get("target") == world.enemies[1], "应选低血低甲邻敌")
	_teardown(world)


func _t_guard_prefer_adjacent_over_reposition() -> void:
	print("[T21] guard 邻格重甲 + 远距脆皮 → 直攻邻格，不走位换目标")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(3, 0)])
	world.attacker.ai_disposition_id = "guard"
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 80
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 55
	world.enemies[0].stats.head_armor = 20
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 20
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 8
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "应直攻，实际 type=%d" % action.type)
	_expect(action.payload.get("target") == world.enemies[0], "邻格有敌时不应为远距脆皮走位")
	_teardown(world)


func _t_guard_prefer_soft_target_when_adjacent() -> void:
	print("[T22] guard 双邻敌 → 优先低血低甲")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.ai_disposition_id = "guard"
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 18
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var action = _decide(world)
	_expect(action.type == _AT.ATTACK, "应攻击，实际 type=%d" % action.type)
	_expect(action.payload.get("target") == world.enemies[1], "应选低血低甲邻敌")
	_teardown(world)


func _t_setup_move_toward_wounded() -> void:
	print("[T23] 远距残血 + 侧翼重甲，AP 不够再攻 → 应为下回合贴近残血而 MOVE")
	var world := _build_world(Vector2i(-1, 0), [Vector2i(4, 0), Vector2i(2, 0)])
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 80
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 55
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 12
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var action = _decide(world)
	_expect(action.type == _AT.MOVE, "应贴近残血，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_dagger_in_range_low_ap_no_oa_step() -> void:
	print("[T25] 匕首邻格 AP 不够攻、已在偏好位 → 无 setup 净收益则 end/wait")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("dagger")
	world.attacker.stats.ap = 3
	_expect(
		world.attacker.stats.ap < world.attacker.get_weapon_ap_cost(),
		"前置：3 AP 不够 4 AP 匕首攻击",
	)
	var action = _decide(world)
	var ok: bool = action.type == _AT.END_TURN or action.type == _AT.WAIT
	_expect(ok, "邻格残 AP 应 end/wait，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_ability_in_best_ap_spend_when_short() -> void:
	print("[T26] AP 不够攻 → 技能纳入 best_ap_spend 与 Wait 门控")
	var world := _build_world(Vector2i(0, 0), [Vector2i(3, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("dagger")
	world.attacker.job = JobDB.get_job("chihou")
	world.attacker.stats.ap = 2
	_expect(
		world.attacker.stats.ap < world.attacker.get_weapon_ap_cost(),
		"前置：2 AP 不够 %d AP 攻击" % world.attacker.get_weapon_ap_cost(),
	)
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var spend_u: float = _AIBehavior.estimate_ability_spend_utility(view, profile)
	var best_u: float = _AIBehavior.best_ap_spend_utility(view, profile)
	_expect(best_u >= spend_u, "best_ap_spend 应含技能效用")
	if spend_u > 0.0:
		_expect(
			_AIBehavior.has_ability_spend_option(view, profile),
			"有技能分时应 has_ability_spend_option",
		)
		var action = _decide(world)
		var ok: bool = action.type in [_AT.MOVE, _AT.ABILITY, _AT.ATTACK]
		_expect(ok, "有正收益技能/走位时不应空转 end，实际 type=%d" % action.type)
	_teardown(world)


func _t_breath_excluded_when_ap_not_full() -> void:
	print("[T27] AP 不满 → best_ap_spend 不计吐纳")
	var world := _build_world(Vector2i(0, 0), [Vector2i(4, 0)])
	world.attacker.stats.ap = 3
	world.attacker.stats.stamina = 12
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	_expect(not _AIBehavior.can_spend_breath_now(view), "前置：3 AP 不可吐纳")
	var breath_val: float = _AIBehavior.compute_breath_recovery_utility(view, profile)
	_expect(breath_val > 0.0, "前置：低气力时恢复效用应 >0")
	var move_u: float = _AIBehavior.estimate_move_spend_utility(view, profile)
	var abil_u: float = _AIBehavior.estimate_ability_spend_utility(view, profile)
	var best_u: float = _AIBehavior.best_ap_spend_utility(view, profile)
	_expect(best_u == maxf(move_u, abil_u), "AP<9 时 best 应不含吐纳，实际 %.1f" % best_u)
	_teardown(world)


func _t_preempt_beats_adjacent_enemy_leftover_ap() -> void:
	print("[T28] 残 AP 邻格敌更快 → 先发制人抢下回合先手")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.base_initiative = 85
	world.attacker.stats.ap = 1
	world.attacker.stats.stamina = 100
	world.enemies[0].stats.base_initiative = 100
	_expect(
		world.attacker.stats.ap < world.attacker.get_weapon_ap_cost(),
		"前置：1 AP 不够 %d AP 攻击" % world.attacker.get_weapon_ap_cost(),
	)
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var util: float = _AIBehavior.compute_preempt_initiative_utility(view)
	_expect(util > 0.0, "虚拟排序应能超车相邻敌，utility=%.1f" % util)
	var action = _decide(world)
	_expect(action.type == _AT.ABILITY, "应选先发制人，实际 type=%d" % action.type)
	_expect(action.payload.get("ability_id", "") == "preempt", "应为 preempt")
	_teardown(world)


func _t_preempt_skipped_when_already_first() -> void:
	print("[T29] 已比相邻敌更快 → 不发先发制人")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.base_initiative = 120
	world.attacker.stats.ap = 1
	world.attacker.stats.stamina = 100
	world.enemies[0].stats.base_initiative = 80
	var view := _capture(world)
	var util: float = _AIBehavior.compute_preempt_initiative_utility(view)
	_expect(util <= 0.0, "已先手时不应有 preempt 效用，utility=%.1f" % util)
	_teardown(world)


func _t_heavy_guard_switch_soft_target_may_move() -> void:
	print("[T31] 重甲 guard 邻格硬目标 + 侧翼脆皮 → 净收益够可吃 OA 换打")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 2)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 12
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var best_u: float = 0.0
	var reachable = world.attacker.hex_grid.get_reachable(
		world.attacker.axial_pos, world.attacker.stats.ap / 2, world.attacker.get_faction())
	for dest in reachable:
		var path: Array = world.attacker.hex_grid.find_path(
			world.attacker.axial_pos, dest, world.attacker.axial_pos, world.attacker.get_faction())
		if path.is_empty():
			continue
		best_u = maxf(best_u, AIEngageScorer.score_setup_path(view, path, profile))
	_expect(best_u > 0.0, "换打脆皮 setup 效用应 >0，实际 %.1f" % best_u)
	var action = _decide(world)
	var ok: bool = action.type in [_AT.MOVE, _AT.ABILITY, _AT.END_TURN, _AT.WAIT]
	_expect(ok, "合理换打或收手，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_heavy_guard_adjacent_low_ap_no_meaningless_oa() -> void:
	print("[T32] 重甲 guard 仅邻格硬目标、无换打收益 → 不顶 OA 空移")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	var action = _decide(world)
	var ok: bool = action.type in [_AT.END_TURN, _AT.WAIT, _AT.ABILITY]
	_expect(ok, "无换打收益应 end/wait/preempt，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_spear_adjacent_low_ap_no_advance_facehug() -> void:
	print("[T33] 长矛邻格 3AP → Advance/Engage 不落贴脸格")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.stats.ap = 3
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var adv: Dictionary = _AIAdvance.new().evaluate(view, profile)
	var eng: Dictionary = _engage_eval(world)
	_expect(float(adv.get("score", 0.0)) <= 0.0, "Advance 应 0 分，实际 %.1f" % adv.get("score", 0.0))
	_expect(float(eng.get("score", 0.0)) <= 0.0, "Engage 应 0 分，实际 %.1f" % eng.get("score", 0.0))
	_teardown(world)


func _t_spear_adjacent_far_target_thin_setup_end() -> void:
	print("[T34] 长矛邻格硬目标 + 远距脆皮 → 薄 setup 应收手")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(4, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 40
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var action = _decide(world)
	var ok: bool = action.type in [_AT.END_TURN, _AT.ABILITY, _AT.WAIT]
	_expect(ok, "远距薄 setup 应 end/wait/preempt，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_spear_wait_resume_low_ap_end() -> void:
	print("[T35] 长矛已 Q、3AP 邻格 → 不顶 OA 薄 Move")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(4, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.stats.ap = 3
	world.tm._waited_this_round[world.attacker] = true
	world.enemies[0].armor = WeaponArmorDB.get_armor("mail_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 35
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 40
	world.enemies[1].stats.max_hp = 50
	var view := _capture(world)
	_expect(not view.can_wait(), "前置：本回合不可再 Q")
	var action = _decide(world)
	var ok: bool = action.type in [_AT.END_TURN, _AT.ABILITY]
	_expect(ok, "应 end/preempt 非薄 Move，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_defer_penalizes_adjacent_reach_micro_setup() -> void:
	print("[T36] 长矛邻格 3AP → defer 扣薄接近分")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.armor = WeaponArmorDB.get_armor("leather_armor")
	world.attacker.stats.ap = 3
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var best_u: float = 0.0
	var reachable = world.attacker.hex_grid.get_reachable(
		world.attacker.axial_pos, world.attacker.stats.ap / 2, world.attacker.get_faction())
	for dest in reachable:
		var path: Array = world.attacker.hex_grid.find_path(
			world.attacker.axial_pos, dest, world.attacker.axial_pos, world.attacker.get_faction())
		if path.is_empty():
			continue
		best_u = maxf(best_u, AIEngageScorer.score_reach_approach_path(view, path, profile))
	_expect(best_u <= 0.0, "邻格薄接近应被 defer 压至 ≤0，实际 %.1f" % best_u)
	_teardown(world)


func _t_oa_penalty_scales_with_own_armor() -> void:
	print("[T37] OA 惩罚随己方护甲值连续变化（非轻/重甲分类）")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("spear")
	world.attacker.stats.ap = 3
	world.enemies[0].weapon = WeaponArmorDB.get_weapon("battle_axe")
	var path: Array = world.attacker.hex_grid.find_path(
		world.attacker.axial_pos, Vector2i(0, 1), world.attacker.axial_pos, world.attacker.get_faction())
	_expect(not path.is_empty(), "前置：应有侧移路径")
	world.attacker.stats.body_armor = 18
	world.attacker.stats.head_armor = 12
	var view_low := _capture(world)
	var pen_low: float = AIEngageScorer.oa_utility_penalty(view_low, world.attacker, path, null)
	world.attacker.stats.body_armor = 220
	world.attacker.stats.head_armor = 160
	var view_high := _capture(world)
	var pen_high: float = AIEngageScorer.oa_utility_penalty(view_high, world.attacker, path, null)
	_expect(pen_low > 0.0 and pen_high > 0.0, "前置：侧移应触发 OA，低甲=%.1f 高甲=%.1f" % [pen_low, pen_high])
	_expect(pen_low > pen_high, "低护甲 OA 惩罚应 > 高护甲，低=%.1f 高=%.1f" % [pen_low, pen_high])
	_teardown(world)


func _t_swap_setup_exempt_from_defer() -> void:
	print("[T38] 换打脆皮 setup 不因 defer 归零")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 2)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("leather_armor")
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 12
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var best_u: float = 0.0
	var reachable = world.attacker.hex_grid.get_reachable(
		world.attacker.axial_pos, world.attacker.stats.ap / 2, world.attacker.get_faction())
	for dest in reachable:
		var path: Array = world.attacker.hex_grid.find_path(
			world.attacker.axial_pos, dest, world.attacker.axial_pos, world.attacker.get_faction())
		if path.is_empty():
			continue
		best_u = maxf(best_u, AIEngageScorer.score_setup_path(view, path, profile))
	_expect(best_u > 0.0, "换打脆皮 setup 应 >0（defer 豁免），实际 %.1f" % best_u)
	_teardown(world)


func _t_surround_penalty_blocks_pocket_without_harvest() -> void:
	print("[T39] 恶化包围无残血收割 → 大惩罚压过 setup")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 2)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("plate_armor")
	world.attacker.ai_archetype_id = "heavy_infantry"
	world.attacker.ai_disposition_id = "guard"
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 45
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var pocket: Vector2i = Vector2i(0, 1)
	var path_pocket: Array = world.attacker.hex_grid.find_path(
		world.attacker.axial_pos, pocket, world.attacker.axial_pos, world.attacker.get_faction())
	var pocket_u: float = AIEngageScorer.score_setup_path(view, path_pocket, profile)
	var entry: Dictionary = _ActionScorer.compute_entry_costs(view, path_pocket, profile)
	var surround_pen: float = float(entry.get("surround_cost", 0.0))
	_expect(surround_pen > 0.0, "进包围应有 surround 成本，实际 %.1f" % surround_pen)
	_expect(pocket_u <= 0.0, "无收割 setup 净分应 ≤0，实际 %.1f" % pocket_u)
	var action = _decide(world)
	var ok: bool = action.type in [_AT.END_TURN, _AT.WAIT, _AT.ABILITY]
	_expect(ok, "无收割不应 Move 进包围，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_deep_surround_kill_still_worth_charge() -> void:
	print("[T40] 深包围(+2邻敌)可斩杀 → surround 惩罚可控、setup 仍为正")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 2), Vector2i(1, 1)])
	world.attacker.weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.attacker.armor = WeaponArmorDB.get_armor("leather_armor")
	world.attacker.stats.ap = 3
	world.enemies[0].armor = WeaponArmorDB.get_armor("plate_armor")
	world.enemies[0].stats.hp = 70
	world.enemies[0].stats.max_hp = 80
	world.enemies[0].stats.body_armor = 50
	world.enemies[1].armor = WeaponArmorDB.get_armor("leather_armor")
	world.enemies[1].stats.hp = 6
	world.enemies[1].stats.max_hp = 50
	world.enemies[1].stats.body_armor = 6
	world.enemies[2].armor = WeaponArmorDB.get_armor("mail_armor")
	world.enemies[2].stats.hp = 55
	world.enemies[2].stats.max_hp = 60
	world.enemies[2].stats.body_armor = 30
	var profile = _AIProfile.build(world.attacker)
	var view := _capture(world)
	var pocket: Vector2i = Vector2i(0, 1)
	var n0: int = _SurroundCost.adjacent_enemy_count(view, world.attacker.axial_pos)
	var n1: int = _SurroundCost.adjacent_enemy_count(view, pocket)
	_expect(n1 >= n0 + 2, "前置：进 (0,1) 应至少恶化 2 邻敌，n0=%d n1=%d" % [n0, n1])
	var path_pocket: Array = world.attacker.hex_grid.find_path(
		world.attacker.axial_pos, pocket, world.attacker.axial_pos, world.attacker.get_faction())
	var pocket_u: float = AIEngageScorer.score_setup_path(view, path_pocket, profile)
	var entry: Dictionary = _ActionScorer.compute_entry_costs(view, path_pocket, profile)
	var surround_pen: float = float(entry.get("surround_cost", 0.0))
	_expect(surround_pen > 0.0, "深包围应有 surround 成本，实际 %.1f" % surround_pen)
	_expect(pocket_u > 0.0, "可斩杀深包围 setup 净分应 >0，实际 %.1f" % pocket_u)
	_teardown(world)


func _t_preempt_blocked_when_would_exhaust() -> void:
	print("[T30] 先发制人使用后力竭 → 不使用")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0)])
	world.attacker.stats.base_initiative = 85
	world.attacker.stats.ap = 1
	world.attacker.stats.max_stamina = 100
	world.attacker.stats.stamina = 25
	world.enemies[0].stats.base_initiative = 100
	_expect(world.attacker.would_preempt_cause_exhaustion(), "前置：25 气力扣 20 后应进入力竭档")
	var view := _capture(world)
	_expect(not _AIBehavior.can_spend_preempt_now(view), "力竭风险时不应可 spend preempt")
	var util: float = _AIBehavior.compute_preempt_initiative_utility(view)
	_expect(util <= 0.0, "力竭风险时 utility 应为 0，实际 %.1f" % util)
	var action = _decide(world)
	var ok: bool = action.type == _AT.END_TURN or action.type == _AT.WAIT
	_expect(ok, "不应选 preempt，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)


func _t_adjacent_2h_oa_blocks_meaningless_move() -> void:
	print("[T24] 邻格双手战斧双贴，AP 不够再攻 → 不因 proximity 吃 OA")
	var world := _build_world(Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	world.attacker.stats.ap = 3
	world.enemies[0].weapon = WeaponArmorDB.get_weapon("battle_axe")
	world.enemies[1].weapon = WeaponArmorDB.get_weapon("saber")
	var action = _decide(world)
	var ok: bool = action.type == _AT.END_TURN or action.type == _AT.WAIT
	_expect(ok, "双手 OA 过重应 end/wait，实际 type=%d reason=%s" % [action.type, action.reason])
	_teardown(world)
