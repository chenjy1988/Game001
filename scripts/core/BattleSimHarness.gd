extends RefCounted
class_name BattleSimHarness
##
## 无头战斗仿真（evaluating-gameplay-balance + implementing-gameplay-invariants）
##
## - 不加载 BattleScene / UI / tween
## - 策略：ai（BattleAI）/ pass（立即结束回合）
## - 确定性：每局 `seed(n)` 后跑完整场

const MAX_ACTIONS: int = 960
const MAX_ACTIONS_PASS: int = 2400
const MAP_RADIUS: int = 9

class Telemetry:
	var attacks: int = 0
	var hits: int = 0
	var pincers: int = 0
	var oa_attacks: int = 0
	var kills: int = 0
	var rounds: int = 0

	func to_dict() -> Dictionary:
		return {
			"attacks": attacks,
			"hits": hits,
			"pincers": pincers,
			"oa_attacks": oa_attacks,
			"kills": kills,
			"rounds": rounds,
		}


func run(
		tree: SceneTree,
		battle_seed: int,
		ally_policy: String = "ai",
		enemy_policy: String = "ai",
) -> Dictionary:
	var cap: int = MAX_ACTIONS_PASS if ally_policy == "pass" else MAX_ACTIONS
	return _run(tree, battle_seed, ally_policy, enemy_policy, cap)


func _run(tree: SceneTree, battle_seed: int, ally_policy: String, enemy_policy: String, action_cap: int) -> Dictionary:
	seed(battle_seed)
	var telemetry := Telemetry.new()
	var world := _build_world(tree, telemetry)
	var tm: TurnManager = world.turn_manager
	var units: Array = world.units
	var grid: HexGrid = world.hex_grid

	var winner: int = -2
	tm.battle_ended.connect(func(w: int) -> void: winner = w)
	tm.round_started.connect(func(_r: int) -> void: telemetry.rounds += 1)

	tm.register_units(units)
	tm.start_battle()

	var actions: int = 0
	while tm.is_running() and actions < action_cap:
		var u: Unit = tm.get_current_unit()
		if u == null:
			# 同步驱动：最后一击后调度器可能已停但 is_running 尚未刷新
			if not tm.is_running():
				break
			# 一方全灭时不再等待 current_unit
			var mid: Dictionary = _count_survivors(units)
			if mid.ally == 0 or mid.enemy == 0:
				break
			break
		var policy: String = ally_policy if u.get_faction() == 0 else enemy_policy
		_execute_turn(u, units, grid, tm, policy)
		actions += 1

	var reason: String = "complete"
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
	var hex_grid := HexGrid.new()
	hex_grid.map_radius = MAP_RADIUS
	hex_grid.fog_enabled = false
	hex_grid.skip_obstacle_generation = true
	tree.root.add_child(hex_grid)

	var turn_manager := TurnManager.new()
	tree.root.add_child(turn_manager)

	var unit_layer := Node2D.new()
	tree.root.add_child(unit_layer)

	var units: Array = _spawn_units(tree, hex_grid, unit_layer)
	for u in units:
		u.attacked.connect(func(_attacker: Unit, _target: Unit, result: Dictionary) -> void:
			telemetry.attacks += 1
			if result.get("hit", false):
				telemetry.hits += 1
			if result.get("is_pincer_attack", false):
				telemetry.pincers += 1
			if result.get("is_opportunity_attack", false):
				telemetry.oa_attacks += 1
		)
		u.unit_died.connect(func(_dead: Unit) -> void: telemetry.kills += 1)

	return {"hex_grid": hex_grid, "turn_manager": turn_manager, "unit_layer": unit_layer, "units": units}


func _teardown_world(world: Dictionary) -> void:
	for u in world.get("units", []):
		if u is Node and is_instance_valid(u):
			u.queue_free()
	for key in ["turn_manager", "hex_grid", "unit_layer"]:
		var n: Node = world.get(key, null)
		if n is Node and is_instance_valid(n):
			n.queue_free()


func _spawn_units(tree: SceneTree, grid: HexGrid, layer: Node) -> Array:
	var units: Array = []
	units.append(_create_from_job(tree, grid, layer, "王五", 0, Vector2i(-4, 1), "tiaodang", "saber", "mail_armor"))
	units.append(_create_from_job(tree, grid, layer, "张三", 0, Vector2i(-3, 2), "qiangbing", "spear", "mail_armor"))
	units.append(_create_from_job(tree, grid, layer, "赵六", 0, Vector2i(-2, 1), "qibing", "saber", "leather_armor"))
	units.append(_create_from_job(tree, grid, layer, "李四", 0, Vector2i(-3, 0), "chihou", "dagger", "leather_armor"))
	units.append(_create_manual(tree, grid, layer, "强盗头目", 1, Vector2i(2, -1), "battle_axe", "mail_armor",
		{"hp": 80, "melee": 55, "def": 15, "init": 95}))
	units.append(_create_manual(tree, grid, layer, "强盗匕首手", 1, Vector2i(3, -2), "dagger", "leather_armor",
		{"hp": 50, "melee": 50, "def": 25, "init": 115}))
	units.append(_create_manual(tree, grid, layer, "强盗矛兵", 1, Vector2i(2, 0), "spear", "leather_armor",
		{"hp": 60, "melee": 50, "def": 15, "init": 100}))
	units.append(_create_manual(tree, grid, layer, "强盗重甲头目", 1, Vector2i(3, -1), "battle_axe", "plate_armor",
		{"hp": 95, "melee": 52, "def": 18, "init": 72, "wisdom": 22}))
	for u in units:
		if u is Unit:
			u.face_nearest_enemy(units)
	return units


func _create_from_job(tree: SceneTree, grid: HexGrid, layer: Node, unit_name: String, faction: int, axial: Vector2i,
		job_id: String, weapon_id: String, armor_id: String) -> Unit:
	var job = JobDB.get_job(job_id)
	var p: Dictionary = job.fixed_stats() if job else {}
	return _create_manual(tree, grid, layer, unit_name, faction, axial, weapon_id, armor_id, {
		"hp": p.get("max_hp", 60),
		"melee": p.get("melee_skill", 55),
		"def": p.get("defense", 10),
		"init": p.get("base_initiative", 100),
		"resolve": p.get("resolve", 40),
		"wisdom": p.get("wisdom", 30),
		"move": p.get("move_range", 4),
		"job": job,
	})


func _create_manual(tree: SceneTree, grid: HexGrid, layer: Node, unit_name: String, faction: int, axial: Vector2i,
		weapon_id: String, armor_id: String, params: Dictionary) -> Unit:
	var unit := Unit.new()
	var stats := Stats.new()
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
	var armor: ArmorData = WeaponArmorDB.get_armor(armor_id)
	stats.max_head_armor = armor.head_armor
	stats.max_body_armor = armor.body_armor
	unit.stats = stats
	unit.weapon = WeaponArmorDB.get_weapon(weapon_id)
	unit.armor = armor
	if params.has("job"):
		unit.job = params["job"]
	layer.add_child(unit)
	unit.place_at(axial, grid)
	return unit


func _execute_turn(unit: Unit, all_units: Array, grid: HexGrid, tm: TurnManager, policy: String) -> void:
	if not unit.is_alive():
		if tm.get_current_unit() == unit:
			unit.end_turn()
		return
	if policy == "pass":
		unit.end_turn()
		return
	var safety: int = 3
	while safety > 0 and unit.is_alive():
		safety -= 1
		var plan: Dictionary = BattleAI.decide(unit, all_units, grid)
		var path: Array[Vector2i] = []
		var path_raw: Variant = plan.get("path", null)
		if path_raw is Array:
			for p in path_raw:
				if p is Vector2i:
					path.append(p)
		var target: Unit = plan.get("target", null)
		if not path.is_empty():
			unit.move_along_path_sync(path)
			if not unit.is_alive():
				break
		if target != null and unit.is_alive() and target.is_alive():
			var d: int = HexCoord.distance(unit.axial_pos, target.axial_pos)
			if d <= unit.weapon.attack_range and unit.stats.ap >= unit.get_weapon_ap_cost():
				unit.attack_target(target)
				if unit.is_alive() and unit.stats.ap >= unit.get_weapon_ap_cost():
					continue
		break
	if unit.is_alive() or tm.get_current_unit() == unit:
		unit.end_turn()


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
