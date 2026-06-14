extends RefCounted
class_name BattleSimHarness
##
## 无头战斗仿真（evaluating-gameplay-balance + implementing-gameplay-invariants）
##
## - 不加载 BattleScene / UI / tween
## - 策略：ai（AIAgent）/ pass（立即结束回合）
## - 确定性：每局 `seed(n)` 后跑完整场

# ── preload AI 类型（headless 模式下 class_name 可能尚未注册）──
const _AT = preload("res://scripts/ai/_ai_action.gd")
const _AIAgent = preload("res://scripts/ai/ai_agent.gd")
const _AISimExecutor = preload("res://scripts/ai/sim_executor.gd")
const _AIWorldView = preload("res://scripts/ai/world_view.gd")
const _FactionBrain = preload("res://scripts/ai/faction_brain.gd")
const _UnitScript = preload("res://scripts/core/Unit.gd")
const _StatsScript = preload("res://scripts/core/Stats.gd")
const _HexGrid = preload("res://scripts/core/HexGrid.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _TurnManager = preload("res://scripts/core/TurnManager.gd")

const MAX_ACTIONS: int = 960
const MAX_ACTIONS_PASS: int = 2400
const MAP_RADIUS: int = 9
const I3_AP_UTIL_MIN: float = 0.60  ## §十四：AI 回合 AP 消耗 / 预算
const CONTACT_GAP: int = 2          ## 与 FactionBrain engaged 一致：最近敌我距 ≤2 视为接敌
const STALEMATE_ROUNDS: int = 18    ## 接敌后 N 回合无击杀 → 判和（截磨局）
const STALEMATE_1V1_ROUNDS: int = 12 ## 双方各剩 1 人时更紧熔断

class Telemetry:
	var attacks: int = 0
	var hits: int = 0
	var pincers: int = 0
	var oa_attacks: int = 0
	var kills: int = 0
	var rounds: int = 0
	var ai_unit_turns: int = 0
	var ai_decisions: int = 0
	var ap_budget: int = 0
	var ap_spent: int = 0
	var stall_turns: int = 0
	var behavior_counts: Dictionary = {
		"move": 0, "attack": 0, "wait": 0, "defend": 0, "ability": 0, "end_turn": 0,
	}
	var kill_order: Array = []
	var last_kill_round: int = 0
	var _round_ally_attacked: Dictionary = {}
	var _round_enemy_attacked: Dictionary = {}

	# ── 接敌后分段（最近敌我距 ≤ CONTACT_GAP 的首回合起）──
	var contact_round: int = 0
	var post_contact_ai_unit_turns: int = 0
	var post_contact_ap_budget: int = 0
	var post_contact_ap_spent: int = 0
	var post_contact_stall_turns: int = 0
	var post_contact_ap_unused_turns: int = 0
	var post_contact_defend_turns: int = 0
	var post_contact_hold_turns: int = 0
	var post_contact_behavior_counts: Dictionary = {
		"move": 0, "attack": 0, "wait": 0, "defend": 0, "ability": 0, "end_turn": 0,
	}

	func _post_contact_rates() -> Dictionary:
		var ap_util: float = 0.0
		if post_contact_ap_budget > 0:
			ap_util = float(post_contact_ap_spent) / float(post_contact_ap_budget)
		var stall_rate: float = 0.0
		if post_contact_ai_unit_turns > 0:
			stall_rate = float(post_contact_stall_turns) / float(post_contact_ai_unit_turns)
		var ap_unused_rate: float = 0.0
		var defend_rate: float = 0.0
		var hold_rate: float = 0.0
		if post_contact_ai_unit_turns > 0:
			ap_unused_rate = float(post_contact_ap_unused_turns) / float(post_contact_ai_unit_turns)
			defend_rate = float(post_contact_defend_turns) / float(post_contact_ai_unit_turns)
			hold_rate = float(post_contact_hold_turns) / float(post_contact_ai_unit_turns)
		return {
			"ap_utilization": ap_util,
			"stall_rate": stall_rate,
			"ap_unused_rate": ap_unused_rate,
			"defend_turn_rate": defend_rate,
			"hold_stance_turn_rate": hold_rate,
		}

	func to_dict() -> Dictionary:
		var engaged: int = 0
		for r in _round_ally_attacked.keys():
			if _round_enemy_attacked.has(r):
				engaged += 1
		var engagement_rate: float = 0.0
		if rounds > 0:
			engagement_rate = float(engaged) / float(rounds)
		var stall_rate: float = 0.0
		if ai_unit_turns > 0:
			stall_rate = float(stall_turns) / float(ai_unit_turns)
		var ap_util: float = 0.0
		if ap_budget > 0:
			ap_util = float(ap_spent) / float(ap_budget)  ## 全 AI 单位轮次：(初AP−末AP) 之和 / 初AP 之和
		var pc: Dictionary = _post_contact_rates()
		return {
			"attacks": attacks,
			"hits": hits,
			"pincers": pincers,
			"oa_attacks": oa_attacks,
			"kills": kills,
			"rounds": rounds,
			"ai_unit_turns": ai_unit_turns,
			"ai_decisions": ai_decisions,
			"ap_budget": ap_budget,
			"ap_spent": ap_spent,
			"ap_utilization": ap_util,
			"stall_turns": stall_turns,
			"stall_rate": stall_rate,
			"engagement_rate": engagement_rate,
			"rounds_both_attacked": engaged,
			"behavior_counts": behavior_counts.duplicate(),
			"kill_order": kill_order.duplicate(),
			"post_contact": {
				"contact_round": contact_round,
				"ai_unit_turns": post_contact_ai_unit_turns,
				"ap_budget": post_contact_ap_budget,
				"ap_spent": post_contact_ap_spent,
				"stall_turns": post_contact_stall_turns,
				"ap_unused_turns": post_contact_ap_unused_turns,
				"defend_turns": post_contact_defend_turns,
				"hold_stance_turns": post_contact_hold_turns,
				"behavior_counts": post_contact_behavior_counts.duplicate(),
				"ap_utilization": pc["ap_utilization"],
				"stall_rate": pc["stall_rate"],
				"ap_unused_rate": pc["ap_unused_rate"],
				"defend_turn_rate": pc["defend_turn_rate"],
				"hold_stance_turn_rate": pc["hold_stance_turn_rate"],
			},
		}

	func record_attack(faction: int) -> void:
		if faction == 0:
			_round_ally_attacked[rounds] = true
		else:
			_round_enemy_attacked[rounds] = true

	func record_behavior(action_type: int, reason: String = "", post_contact: bool = false) -> void:
		var bucket: String = ""
		match action_type:
			_AT.MOVE: bucket = "move"
			_AT.ATTACK: bucket = "attack"
			_AT.WAIT:
				bucket = "defend" if reason == "defend" else "wait"
			_AT.ABILITY: bucket = "ability"
			_AT.END_TURN: bucket = "end_turn"
			_: return
		behavior_counts[bucket] = int(behavior_counts.get(bucket, 0)) + 1
		if post_contact:
			post_contact_behavior_counts[bucket] = int(post_contact_behavior_counts.get(bucket, 0)) + 1


var _battle_seed: int = 0  ## 当前战斗种子（供 AI RNG 派生）
var _faction_brains: Dictionary = {}
var _lineup_id: String = "demo"
var _enemy_disposition_override: String = ""


func run(
		tree: SceneTree,
		battle_seed: int,
		ally_policy: String = "ai",
		enemy_policy: String = "ai",
		lineup: String = "demo",
		enemy_disposition: String = "",
) -> Dictionary:
	var cap: int = MAX_ACTIONS_PASS if ally_policy == "pass" else MAX_ACTIONS
	return _run(tree, battle_seed, ally_policy, enemy_policy, cap, lineup, enemy_disposition)


func _run(
		tree: SceneTree,
		battle_seed: int,
		ally_policy: String,
		enemy_policy: String,
		action_cap: int,
		lineup: String = "demo",
		enemy_disposition: String = "",
) -> Dictionary:
	_battle_seed = battle_seed
	_lineup_id = lineup
	_enemy_disposition_override = enemy_disposition
	seed(battle_seed)
	var telemetry := Telemetry.new()
	var world := _build_world(tree, telemetry)
	var tm = world.turn_manager
	var units: Array = world.units
	var grid = world.hex_grid

	var winner: int = -2
	var reason: String = "complete"
	tm.battle_ended.connect(func(w: int) -> void: winner = w)
	tm.round_started.connect(func(_r: int) -> void:
		telemetry.rounds += 1
		_faction_brains = _FactionBrain.compute_all(units, grid)
	)

	tm.register_units(units)
	if _lineup_id == "mirror":
		tm.set_init_tie_seed(_battle_seed)
	tm.start_battle()
	_faction_brains = _FactionBrain.compute_all(units, grid)

	var actions: int = 0
	var contact_made: bool = false
	while tm.is_running() and actions < action_cap:
		var u = tm.get_current_unit()
		if u == null:
			# 同步驱动：最后一击后调度器可能已停但 is_running 尚未刷新
			if not tm.is_running():
				break
			# 一方全灭时不再等待 current_unit
			var mid: Dictionary = _count_survivors(units)
			if mid.ally == 0 or mid.enemy == 0:
				break
			break
		if not contact_made:
			var gap: int = _battle_nearest_gap(units)
			if gap <= CONTACT_GAP:
				contact_made = true
				telemetry.contact_round = telemetry.rounds
		var policy: String = ally_policy if u.get_faction() == 0 else enemy_policy
		_execute_turn(u, units, grid, tm, policy, _faction_brains, telemetry, contact_made)
		actions += 1
		if contact_made and _should_stalemate(telemetry, units):
			reason = "stalemate"
			winner = -1
			break

	if reason != "stalemate":
		if actions >= action_cap:
			reason = "action_cap"
			var surv_cap: Dictionary = _count_survivors(units)
			if surv_cap.enemy == 0 and surv_cap.ally > 0:
				winner = 0
			elif surv_cap.ally == 0 and surv_cap.enemy > 0:
				winner = 1
			else:
				winner = -1
		elif winner == -2:
			var surv_end: Dictionary = _count_survivors(units)
			if surv_end.enemy == 0 and surv_end.ally > 0:
				winner = 0
			elif surv_end.ally == 0 and surv_end.enemy > 0:
				winner = 1
			elif surv_end.ally == 0 and surv_end.enemy == 0:
				winner = -1
			else:
				reason = "stalled"
				winner = -1

	var result := {
		"seed": battle_seed,
		"lineup": _lineup_id,
		"enemy_disposition": _enemy_disposition_override,
		"ally_policy": ally_policy,
		"enemy_policy": enemy_policy,
		"winner": winner,
		"reason": reason,
		"actions": actions,
		"telemetry": telemetry.to_dict(),
		"survivors": _count_survivors(units),
	}
	_teardown_world(world)
	return result


func _build_world(tree: SceneTree, telemetry: Telemetry) -> Dictionary:
	var hex_grid := _HexGrid.new()
	hex_grid.map_radius = MAP_RADIUS
	hex_grid.fog_enabled = false
	hex_grid.skip_obstacle_generation = true
	tree.root.add_child(hex_grid)

	var turn_manager := _TurnManager.new()
	tree.root.add_child(turn_manager)

	var unit_layer := Node2D.new()
	tree.root.add_child(unit_layer)

	var units: Array = _spawn_units(tree, hex_grid, unit_layer)
	for u in units:
		u.attacked.connect(func(attacker, _target, result: Dictionary) -> void:
			telemetry.attacks += 1
			if attacker != null and attacker.has_method("get_faction"):
				telemetry.record_attack(attacker.get_faction())
			if result.get("hit", false):
				telemetry.hits += 1
			if result.get("is_pincer_attack", false):
				telemetry.pincers += 1
			if result.get("is_opportunity_attack", false):
				telemetry.oa_attacks += 1
		)
		u.unit_died.connect(func(dead) -> void:
			telemetry.kills += 1
			telemetry.last_kill_round = telemetry.rounds
			if dead != null:
				telemetry.kill_order.append({
					"name": dead.get_unit_name() if dead.has_method("get_unit_name") else "?",
					"faction": dead.get_faction() if dead.has_method("get_faction") else -1,
					"round": telemetry.rounds,
				})
		)

	return {"hex_grid": hex_grid, "turn_manager": turn_manager, "unit_layer": unit_layer, "units": units}


func _teardown_world(world: Dictionary) -> void:
	for u in world.get("units", []):
		if u is Node and is_instance_valid(u) and u.has_method("get_effect_container"):
			u.get_effect_container().notify_combat_finished()
		if u is Node and is_instance_valid(u):
			u.queue_free()
	for key in ["turn_manager", "hex_grid", "unit_layer"]:
		var n: Node = world.get(key, null)
		if n is Node and is_instance_valid(n):
			n.queue_free()


func _spawn_units(_tree: SceneTree, grid, layer: Node) -> Array:
	if _lineup_id == "mirror":
		return _spawn_mirror_lineup(grid, layer)
	return _spawn_demo_lineup(grid, layer)


func _spawn_demo_lineup(grid, layer: Node) -> Array:
	var units: Array = []
	units.append(_create_from_job(grid, layer, "王五", 0, Vector2i(-4, 1), "tiaodang", "saber", "mail_armor"))
	units.append(_create_from_job(grid, layer, "张三", 0, Vector2i(-3, 2), "qiangbing", "spear", "mail_armor"))
	units.append(_create_from_job(grid, layer, "赵六", 0, Vector2i(-2, 1), "qibing", "saber", "leather_armor"))
	units.append(_create_from_job(grid, layer, "李四", 0, Vector2i(-3, 0), "chihou", "dagger", "leather_armor"))
	units.append(_create_manual(grid, layer, "强盗头目", 1, Vector2i(2, -1), "battle_axe", "mail_armor",
		{"hp": 80, "melee": 55, "def": 15, "init": 95, "archetype": "bandit", "disposition": "berserk"}))
	units.append(_create_manual(grid, layer, "强盗匕首手", 1, Vector2i(3, -2), "dagger", "leather_armor",
		{"hp": 50, "melee": 50, "def": 25, "init": 115, "archetype": "skirmisher", "disposition": "default"}))
	units.append(_create_manual(grid, layer, "强盗矛兵", 1, Vector2i(2, 0), "spear", "leather_armor",
		{"hp": 60, "melee": 50, "def": 15, "init": 100, "archetype": "infantry", "disposition": "default"}))
	units.append(_create_manual(grid, layer, "强盗重甲头目", 1, Vector2i(3, -1), "battle_axe", "plate_armor",
		{"hp": 95, "melee": 52, "def": 18, "init": 72, "wisdom": 22, "stamina": 120,
		"archetype": "heavy_infantry", "disposition": "guard"}))
	for u in units:
		if u != null and u.has_method("face_nearest_enemy"):
			u.face_nearest_enemy(units)
	return units


func _spawn_mirror_lineup(grid, layer: Node) -> Array:
	var cfg: Dictionary = _load_mirror_config()
	var slots: Array = cfg.get("slots", [])
	var ally_pos: Array = cfg.get("ally_positions", [])
	var enemy_pos: Array = cfg.get("enemy_positions", [])
	var ally_disp: String = str(cfg.get("ally_disposition", "disciplined"))
	var enemy_disp: String = _enemy_disposition_override
	if enemy_disp.is_empty():
		enemy_disp = str(cfg.get("enemy_disposition_default", "disciplined"))

	var units: Array = []
	var job_names: PackedStringArray = ["甲", "乙", "丙", "丁"]
	for i in range(mini(4, slots.size())):
		var slot: Dictionary = slots[i]
		var job_id: String = str(slot.get("job", "tiaodang"))
		var pos_a: Vector2i = _pos_from_cfg(ally_pos, i, Vector2i(-3 + i, 1))
		var pos_e: Vector2i = _mirror_axial(pos_a)
		var ally_u = _create_from_job(
			grid, layer, "友%s" % job_names[i], 0, pos_a, job_id,
			str(slot.get("weapon", "saber")), str(slot.get("armor", "leather_armor")),
			ally_disp, str(slot.get("archetype", "")),
		)
		var enemy_u = _create_from_job(
			grid, layer, "敌%s" % job_names[i], 1, pos_e, job_id,
			str(slot.get("weapon", "saber")), str(slot.get("armor", "leather_armor")),
			enemy_disp, str(slot.get("archetype", "")),
		)
		# 同职 Init 相同时，按 seed 交替注册序 + TurnManager tie_seed 公平先手
		if (_battle_seed + i) % 2 == 0:
			units.append(ally_u)
			units.append(enemy_u)
		else:
			units.append(enemy_u)
			units.append(ally_u)
	for u in units:
		if u != null and u.has_method("face_nearest_enemy"):
			u.face_nearest_enemy(units)
	return units


static func _load_mirror_config() -> Dictionary:
	var path: String = "res://data/sim_lineups.json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		var inner = parsed.get("mirror_4v4", {})
		if inner is Dictionary:
			return inner
	return {}


static func _pos_from_cfg(arr: Array, index: int, fallback: Vector2i) -> Vector2i:
	if index >= arr.size():
		return fallback
	var p = arr[index]
	if p is Dictionary:
		return Vector2i(int(p.get("x", fallback.x)), int(p.get("y", fallback.y)))
	return fallback


## 原点对称镜像（axial q,r → −q,−r），镜像局敌我距应对称
static func _mirror_axial(pos: Vector2i) -> Vector2i:
	return Vector2i(-pos.x, -pos.y)


func _create_from_job(grid, layer: Node, unit_name: String, faction: int, axial: Vector2i,
		job_id: String, weapon_id: String, armor_id: String,
		disposition_id: String = "", archetype_override: String = ""):
	var job = JobDB.get_job(job_id)
	var p: Dictionary = job.fixed_stats() if job else {}
	var arch: String = archetype_override if not archetype_override.is_empty() \
		else ArchetypeDB.archetype_for_job(job_id)
	var disp: String = disposition_id
	if disp.is_empty():
		disp = "disciplined" if faction == 0 else "default"
	var params: Dictionary = {
		"hp": p.get("max_hp", 60),
		"melee": p.get("melee_skill", 55),
		"def": p.get("defense", 10),
		"init": p.get("base_initiative", 100),
		"resolve": p.get("resolve", 40),
		"wisdom": p.get("wisdom", 30),
		"move": p.get("move_range", 4),
		"job": job,
		"archetype": arch,
		"disposition": disp,
	}
	return _create_manual(grid, layer, unit_name, faction, axial, weapon_id, armor_id, params)


func _create_manual(grid, layer: Node, unit_name: String, faction: int, axial: Vector2i,
		weapon_id: String, armor_id: String, params: Dictionary):
	var unit = _UnitScript.new()
	var stats = _StatsScript.new()
	stats.unit_name = unit_name
	stats.faction = faction
	stats.max_hp = params.get("hp", 60)
	stats.melee_skill = params.get("melee", 55)
	stats.wisdom = params.get("wisdom", 30)
	stats.defense = params.get("def", 10)
	stats.melee_defense = stats.defense
	stats.base_initiative = params.get("init", 100)
	stats.resolve = params.get("resolve", 40)
	stats.max_stamina = params.get("stamina", 100)
	stats.move_range = params.get("move", 4)
	var db = _item_db()
	var armor = db.get_armor(armor_id) if db else null
	stats.max_head_armor = armor.head_armor
	stats.max_body_armor = armor.body_armor
	unit.stats = stats
	unit.weapon = db.get_weapon(weapon_id) if db else null
	unit.armor = armor
	if params.has("job"):
		unit.job = params["job"]
	if params.has("archetype"):
		unit.ai_archetype_id = str(params["archetype"])
	if params.has("disposition"):
		unit.ai_disposition_id = str(params["disposition"])
	layer.add_child(unit)
	unit.place_at(axial, grid)
	return unit


func _execute_turn(unit, all_units: Array, grid, tm, policy: String, faction_brains: Dictionary = {}, telemetry: Telemetry = null, post_contact: bool = false) -> void:
	if not unit.is_alive():
		if tm.get_current_unit() == unit:
			unit.end_turn()
		return
	if policy == "pass":
		unit.end_turn()
		return

	var attacks_before: int = telemetry.attacks if telemetry else 0
	var ap_at_start: int = unit.stats.ap if unit.stats else 0
	var brain: Dictionary = faction_brains.get(unit.get_faction(), {})
	var view_start = _AIWorldView.capture(unit, all_units, grid, tm, brain)
	var could_fight: bool = _could_fight_this_turn(view_start)
	var turn_had_defend: bool = false
	var turn_had_wait: bool = false

	if telemetry:
		telemetry.ai_unit_turns += 1
		telemetry.ap_budget += ap_at_start
		if post_contact:
			telemetry.post_contact_ai_unit_turns += 1
			telemetry.post_contact_ap_budget += ap_at_start
			if brain.get("stance", "") == "hold":
				telemetry.post_contact_hold_turns += 1

	# ── 新 AI Agent（决策/执行分离）──
	var ai_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if _battle_seed > 0:
		ai_rng.seed = _battle_seed + unit.axial_pos.x * 1000 + unit.axial_pos.y  # 每单位独立流
	var agent = _AIAgent.new(unit, ai_rng)
	var executor = _AISimExecutor.new()
	var guard: int = 0
	while guard < agent._max_actions and unit.is_alive():
		guard += 1
		var view = _AIWorldView.capture(unit, all_units, grid, tm, brain)
		var action = agent.decide_next_action(view)
		if telemetry:
			telemetry.ai_decisions += 1
			telemetry.record_behavior(action.type, action.reason, post_contact)
			if action.type == _AT.WAIT and action.reason == "defend":
				turn_had_defend = true
			if action.type == _AT.WAIT:
				turn_had_wait = true
		if action.type == _AT.END_TURN:
			break
		if action.type == _AT.WAIT:
			executor.run(action, unit, all_units, grid, tm)
			_record_ai_turn_outcome(
				telemetry, unit, ap_at_start, attacks_before, could_fight,
				turn_had_defend, turn_had_wait, post_contact,
			)
			return  # 与 BattleScene 一致：Q 后 TurnManager 已推进，禁止 end_turn
		var cont: bool = executor.run(action, unit, all_units, grid, tm)
		if not cont:
			break
		if not unit.is_alive():
			_record_ai_turn_outcome(
				telemetry, unit, ap_at_start, attacks_before, could_fight,
				turn_had_defend, turn_had_wait, post_contact,
			)
			return

	_record_ai_turn_outcome(
		telemetry, unit, ap_at_start, attacks_before, could_fight,
		turn_had_defend, turn_had_wait, post_contact,
	)

	if tm.get_current_unit() == unit:
		unit.end_turn()


func _record_ai_turn_outcome(
	telemetry: Telemetry,
	unit,
	ap_at_start: int,
	attacks_before: int,
	could_fight: bool,
	turn_had_defend: bool,
	turn_had_wait: bool,
	post_contact: bool,
) -> void:
	if telemetry == null:
		return
	var ap_left: int = unit.stats.ap if unit != null and unit.stats else 0
	var ap_spent_turn: int = maxi(0, ap_at_start - ap_left)
	telemetry.ap_spent += ap_spent_turn
	var attacked: bool = telemetry.attacks > attacks_before
	if could_fight and not attacked and not turn_had_wait:
		telemetry.stall_turns += 1
	if post_contact:
		telemetry.post_contact_ap_spent += ap_spent_turn
		if could_fight and not attacked and not turn_had_wait:
			telemetry.post_contact_stall_turns += 1
		if ap_spent_turn <= 0 and ap_at_start > 0 and not turn_had_wait and not turn_had_defend:
			telemetry.post_contact_ap_unused_turns += 1
		if turn_had_defend:
			telemetry.post_contact_defend_turns += 1


static func _could_fight_this_turn(view) -> bool:
	if view == null or view.unit == null or not view.unit.is_alive():
		return false
	if view.alive_enemies.is_empty():
		return false
	const _AIBehavior = preload("res://scripts/ai/behaviors/behavior_base.gd")
	if _AIBehavior.can_attack_now(view):
		return true
	return _AIBehavior.has_move_attack_setup(view)


static func _battle_nearest_gap(units: Array) -> int:
	var allies: Array = []
	var enemies: Array = []
	for u in units:
		if u == null or not u.is_alive():
			continue
		if u.get_faction() == 0:
			allies.append(u)
		else:
			enemies.append(u)
	if allies.is_empty() or enemies.is_empty():
		return 99
	var best: int = 99
	for a in allies:
		for e in enemies:
			best = mini(best, _HexCoord.distance(a.axial_pos, e.axial_pos))
	return best


static func _merge_behavior_counts(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		dst[k] = int(dst.get(k, 0)) + int(src.get(k, 0))


static func _aggregate_post_contact(results: Array) -> Dictionary:
	var ai_turns: int = 0
	var ap_budget: int = 0
	var ap_spent: int = 0
	var stall_turns: int = 0
	var ap_unused_turns: int = 0
	var defend_turns: int = 0
	var hold_turns: int = 0
	var behavior_total: Dictionary = {
		"move": 0, "attack": 0, "wait": 0, "defend": 0, "ability": 0, "end_turn": 0,
	}
	var contact_rounds: Array = []
	for r in results:
		var pc: Dictionary = r.get("telemetry", {}).get("post_contact", {})
		if pc.is_empty():
			continue
		ai_turns += int(pc.get("ai_unit_turns", 0))
		ap_budget += int(pc.get("ap_budget", 0))
		ap_spent += int(pc.get("ap_spent", 0))
		stall_turns += int(pc.get("stall_turns", 0))
		ap_unused_turns += int(pc.get("ap_unused_turns", 0))
		defend_turns += int(pc.get("defend_turns", 0))
		hold_turns += int(pc.get("hold_stance_turns", 0))
		_merge_behavior_counts(behavior_total, pc.get("behavior_counts", {}))
		var cr: int = int(pc.get("contact_round", 0))
		if cr > 0:
			contact_rounds.append(cr)
	contact_rounds.sort()
	var median_contact_round: float = 0.0
	var m: int = contact_rounds.size()
	if m > 0:
		if m % 2 == 1:
			median_contact_round = float(contact_rounds[m / 2])
		else:
			median_contact_round = (float(contact_rounds[m / 2 - 1]) + float(contact_rounds[m / 2])) / 2.0
	var ap_util: float = float(ap_spent) / float(maxi(1, ap_budget))
	var stall_rate: float = float(stall_turns) / float(maxi(1, ai_turns))
	var ap_unused_rate: float = float(ap_unused_turns) / float(maxi(1, ai_turns))
	var defend_turn_rate: float = float(defend_turns) / float(maxi(1, ai_turns))
	var hold_turn_rate: float = float(hold_turns) / float(maxi(1, ai_turns))
	return {
		"median_contact_round": median_contact_round,
		"ai_unit_turns": ai_turns,
		"ap_budget": ap_budget,
		"ap_spent": ap_spent,
		"ap_utilization": ap_util,
		"stall_turns": stall_turns,
		"stall_rate": stall_rate,
		"ap_unused_turns": ap_unused_turns,
		"ap_unused_rate": ap_unused_rate,
		"defend_turns": defend_turns,
		"defend_turn_rate": defend_turn_rate,
		"hold_stance_turns": hold_turns,
		"hold_stance_turn_rate": hold_turn_rate,
		"behavior_counts": behavior_total,
	}


## 批量汇总（I2 遥测；供 battle_sim_scene / 外部脚本消费）
static func aggregate(results: Array) -> Dictionary:
	var ally_w: int = 0
	var enemy_w: int = 0
	var draws: int = 0
	var n: float = maxf(1.0, float(results.size()))
	var sum_r: float = 0.0
	var sum_a: float = 0.0
	var sum_h: float = 0.0
	var sum_p: float = 0.0
	var sum_eng: float = 0.0
	var sum_stall: float = 0.0
	var sum_ap_util: float = 0.0
	var rounds_vals: Array = []
	var behavior_total: Dictionary = {
		"move": 0, "attack": 0, "wait": 0, "defend": 0, "ability": 0, "end_turn": 0,
	}
	for r in results:
		match r.get("winner", -1):
			0: ally_w += 1
			1: enemy_w += 1
			_: draws += 1
		var t: Dictionary = r.get("telemetry", {})
		var rv: int = int(t.get("rounds", 0))
		sum_r += float(rv)
		rounds_vals.append(rv)
		sum_a += float(t.get("attacks", 0))
		sum_h += float(t.get("hits", 0))
		sum_p += float(t.get("pincers", 0))
		sum_eng += float(t.get("engagement_rate", 0.0))
		sum_stall += float(t.get("stall_rate", 0.0))
		sum_ap_util += float(t.get("ap_utilization", 0.0))
		var bc: Dictionary = t.get("behavior_counts", {})
		for k in behavior_total.keys():
			behavior_total[k] += int(bc.get(k, 0))
	rounds_vals.sort()
	var median_rounds: float = 0.0
	var m: int = rounds_vals.size()
	if m > 0:
		if m % 2 == 1:
			median_rounds = float(rounds_vals[m / 2])
		else:
			median_rounds = (float(rounds_vals[m / 2 - 1]) + float(rounds_vals[m / 2])) / 2.0

	var decisive: int = ally_w + enemy_w
	return {
		"games": results.size(),
		"ally_wins": ally_w,
		"enemy_wins": enemy_w,
		"draws": draws,
		"ally_win_rate": float(ally_w) / n,
		"enemy_win_rate": float(enemy_w) / n,
		"draw_rate": float(draws) / n,
		"decisive_ally_win_rate": float(ally_w) / float(maxi(1, decisive)),
		"avg_rounds": sum_r / n,
		"median_rounds": median_rounds,
		"avg_attacks": sum_a / n,
		"avg_hits": sum_h / n,
		"avg_pincers": sum_p / n,
		"avg_engagement_rate": sum_eng / n,
		"avg_stall_rate": sum_stall / n,
		"avg_ap_utilization": sum_ap_util / n,
		"behavior_counts": behavior_total,
		"post_contact": _aggregate_post_contact(results),
	}


## I3 §十四 门禁（镜像阵容等对称局使用）
static func check_i3_gates(agg: Dictionary, strict: bool = true) -> Dictionary:
	var failures: PackedStringArray = []
	var warnings: PackedStringArray = []

	var eng: float = float(agg.get("avg_engagement_rate", 0.0))
	if eng < 0.90:
		failures.append("交火率 %.1f%% < 90%%" % (eng * 100.0))

	var stall: float = float(agg.get("avg_stall_rate", 0.0))
	if stall > 0.02:
		failures.append("站桩率 %.1f%% > 2%%" % (stall * 100.0))

	var rounds: float = float(agg.get("median_rounds", agg.get("avg_rounds", 0.0)))
	if rounds < 8.0 or rounds > 16.0:
		failures.append("中位回合 %.1f 不在 [8, 16]" % rounds)

	var ally_wr: float = float(agg.get("ally_win_rate", 0.0))
	if ally_wr < 0.45 or ally_wr > 0.55:
		failures.append("友方胜率 %.1f%% 不在 45~55%%" % (ally_wr * 100.0))

	if float(agg.get("avg_attacks", 0.0)) < 4.0:
		failures.append("均攻击 %.1f < 4" % float(agg.get("avg_attacks", 0.0)))

	var ap_util: float = float(agg.get("avg_ap_utilization", 0.0))
	if ap_util < I3_AP_UTIL_MIN:
		failures.append("AP 利用率 " + str(ap_util * 100.0) + "% < " + str(int(I3_AP_UTIL_MIN * 100.0)) + "%")

	return {
		"pass": failures.is_empty(),
		"failures": failures,
		"warnings": warnings,
		"strict": strict,
	}


static func check_disposition_delta(agg_aggressive: Dictionary, agg_cautious: Dictionary, min_delta: float = 3.0) -> Dictionary:
	var r_agg: float = float(agg_aggressive.get("median_rounds", agg_aggressive.get("avg_rounds", 0.0)))
	var r_cau: float = float(agg_cautious.get("median_rounds", agg_cautious.get("avg_rounds", 0.0)))
	var delta: float = r_cau - r_agg
	var passed: bool = delta >= min_delta
	var msg: String = "berserk 中位回合 %.1f vs guard %.1f (差 %.1f，目标 ≥%.0f)" % [
		r_agg, r_cau, delta, min_delta
	]
	return {"pass": passed, "delta": delta, "message": msg}


static func _item_db():
	if Engine.get_main_loop() == null:
		return null
	return Engine.get_main_loop().root.get_node_or_null("WeaponArmorDB")


func _should_stalemate(telemetry: Telemetry, units: Array) -> bool:
	var surv: Dictionary = _count_survivors(units)
	if surv.ally <= 0 or surv.enemy <= 0:
		return false
	var drought: int = 0
	if telemetry.kills > 0 and telemetry.last_kill_round > 0:
		drought = telemetry.rounds - telemetry.last_kill_round
	elif telemetry.contact_round > 0:
		drought = telemetry.rounds - telemetry.contact_round
	else:
		return false
	var threshold: int = STALEMATE_ROUNDS
	if surv.ally == 1 and surv.enemy == 1:
		threshold = STALEMATE_1V1_ROUNDS
	return drought >= threshold


func _count_survivors(units: Array) -> Dictionary:
	var ally: int = 0
	var enemy: int = 0
	for u in units:
		if u == null or not u.is_alive():
			continue
		if u.get_faction() == 0:
			ally += 1
		else:
			enemy += 1
	return {"ally": ally, "enemy": enemy}
