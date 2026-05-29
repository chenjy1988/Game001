extends Node2D
##
## BattleScene.gd — 战斗场景主控制器
##
## 职责：
##   - 实例化 HexGrid、TurnManager
##   - 创建测试单位（2 友方 vs 3 敌方）
##   - 玩家输入状态机：选中 → 移动 / 攻击
##   - 敌方简单 AI（Phase 1 用最简：找最近敌人，能打就打，否则向其移动）
##   - 与 UnitPanel UI 交互（显示当前单位、战斗日志）
##

@onready var hex_grid: HexGrid = $HexGrid
@onready var turn_manager: TurnManager = $TurnManager
@onready var camera: Camera2D = $Camera2D
@onready var unit_layer: Node2D = $UnitLayer
@onready var unit_panel = $UI/SidePanel
@onready var top_bar = $UI/TopBar
@onready var battle_result_label: Label = $UI/BattleResultLabel

# 玩家输入状态
enum InputState { IDLE, UNIT_SELECTED }
var _input_state: int = InputState.IDLE
var _selected_unit: Unit = null
var _all_units: Array[Unit] = []
var _ai_acting: bool = false


func _ready() -> void:
	hex_grid.hex_clicked.connect(_on_hex_clicked)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.battle_ended.connect(_on_battle_ended)

	_spawn_units()
	turn_manager.register_units(_all_units)
	turn_manager.start_battle()


# ──────────── 单位生成 ────────────
func _spawn_units() -> void:
	# 友方 2 人
	_create_unit("阿尔伯特", 0, Vector2i(-3, 1), "short_sword", "leather_armor", {"hp": 65, "melee": 60, "def": 18, "init": 105})
	_create_unit("贡多巴德", 0, Vector2i(-2, 2), "war_hammer", "mail_armor", {"hp": 75, "melee": 55, "def": 12, "init": 90})

	# 敌方 3 人
	_create_unit("强盗头目", 1, Vector2i(2, -1), "battle_axe", "mail_armor", {"hp": 80, "melee": 55, "def": 15, "init": 95})
	_create_unit("强盗匕首手", 1, Vector2i(3, -2), "dagger", "leather_armor", {"hp": 50, "melee": 50, "def": 25, "init": 115})
	_create_unit("强盗矛兵", 1, Vector2i(2, 0), "spear", "leather_armor", {"hp": 60, "melee": 50, "def": 15, "init": 100})


func _create_unit(unit_name: String, faction: int, axial: Vector2i, weapon_id: String, armor_id: String, params: Dictionary) -> Unit:
	var unit := Unit.new()
	# Stats
	var stats := Stats.new()
	stats.unit_name = unit_name
	stats.faction = faction
	stats.max_hp = params.get("hp", 60)
	stats.melee_skill = params.get("melee", 55)
	stats.melee_defense = params.get("def", 10)
	stats.base_initiative = params.get("init", 100)
	# 武器/护甲
	var weapon: WeaponData = WeaponArmorDB.get_weapon(weapon_id)
	var armor: ArmorData = WeaponArmorDB.get_armor(armor_id)
	stats.max_head_armor = armor.head_armor
	stats.max_body_armor = armor.body_armor
	unit.stats = stats
	unit.weapon = weapon
	unit.armor = armor
	# 加到场景
	unit_layer.add_child(unit)
	unit.place_at(axial, hex_grid)
	_all_units.append(unit)
	return unit


# ──────────── 回合控制 ────────────
func _on_turn_started(unit: Unit) -> void:
	_clear_selection()
	top_bar.set_current_unit(unit, turn_manager.round_num, turn_manager.get_turn_order_preview())
	unit_panel.bind_unit(unit)
	if unit.get_faction() == 0:
		# 玩家回合：自动选中当前单位，显示移动范围
		_select_unit(unit)
	else:
		# AI 回合
		_ai_acting = true
		_run_ai_turn(unit)


# ──────────── 玩家输入 ────────────
func _on_hex_clicked(axial: Vector2i) -> void:
	if _ai_acting:
		return
	var current: Unit = turn_manager.get_current_unit()
	if current == null or current.get_faction() != 0:
		return

	var clicked_unit: Unit = hex_grid.get_occupant(axial)

	# 点到敌方 → 尝试攻击
	if clicked_unit and clicked_unit.get_faction() != current.get_faction():
		if HexCoord.distance(current.axial_pos, axial) <= current.weapon.attack_range and current.stats.ap >= current.weapon.ap_cost:
			_player_attack(current, clicked_unit)
			return

	# 点到自己 → 重新选中（已选中）
	if clicked_unit == current:
		_select_unit(current)
		return

	# 点到空格 → 尝试移动
	if clicked_unit == null and _selected_unit == current:
		var path: Array[Vector2i] = hex_grid.find_path(current.axial_pos, axial, current.axial_pos)
		@warning_ignore("integer_division")
		var max_steps: int = current.stats.ap / Unit.AP_PER_HEX
		if not path.is_empty() and path.size() <= max_steps:
			_player_move(current, path)


func _player_move(unit: Unit, path: Array[Vector2i]) -> void:
	hex_grid.clear_highlights()
	var ok: bool = unit.move_along_path(path)
	if not ok:
		_select_unit(unit)
		return
	# 等动画结束（用 moved 信号最后一次）—— 简单做法：等帧后刷新
	await get_tree().create_timer(path.size() * 0.18).timeout
	if unit.is_alive():
		# 仍可继续行动（攻击/再走）— 只要 AP 够
		_select_unit(unit)
		# 没 AP 了就结束回合
		if unit.stats.ap < 1:
			unit.end_turn()


func _player_attack(unit: Unit, target: Unit) -> void:
	hex_grid.clear_highlights()
	var result: Dictionary = unit.attack_target(target)
	unit_panel.append_log(DamageSystem.format_attack_log(result))
	await get_tree().create_timer(0.45).timeout
	if not turn_manager.get_current_unit() == unit:
		return  # 战斗结束等
	if unit.is_alive():
		_select_unit(unit)
		if unit.stats.ap < unit.weapon.ap_cost and unit.stats.ap < 1:
			unit.end_turn()


func _select_unit(unit: Unit) -> void:
	_selected_unit = unit
	_input_state = InputState.UNIT_SELECTED
	hex_grid.clear_highlights()
	hex_grid.set_selected(unit.axial_pos)
	# 移动范围
	@warning_ignore("integer_division")
	var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
	var move_hexes: Array[Vector2i] = hex_grid.get_reachable(unit.axial_pos, max_steps)
	hex_grid.set_highlight_move(move_hexes)
	# 攻击范围
	var atk_hexes: Array[Vector2i] = hex_grid.get_attack_targets(unit.axial_pos, unit.weapon.attack_range, unit.get_faction())
	hex_grid.set_highlight_attack(atk_hexes)
	print("[DEBUG] _select_unit: ", unit.get_unit_name(),
		" pos=", unit.axial_pos,
		" max_steps=", max_steps,
		" move_hexes=", move_hexes.size(),
		" atk_hexes=", atk_hexes.size())


func _clear_selection() -> void:
	_selected_unit = null
	_input_state = InputState.IDLE
	hex_grid.clear_highlights()


# ──────────── 简单 AI ────────────
func _run_ai_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.35).timeout

	# 找最近的友方单位
	var target: Unit = _find_closest_enemy(unit)
	if target == null:
		unit.end_turn()
		_ai_acting = false
		return

	# 在攻击范围 → 直接打
	var dist: int = HexCoord.distance(unit.axial_pos, target.axial_pos)
	if dist <= unit.weapon.attack_range and unit.stats.ap >= unit.weapon.ap_cost:
		var result: Dictionary = unit.attack_target(target)
		unit_panel.append_log(DamageSystem.format_attack_log(result))
		await get_tree().create_timer(0.5).timeout
		# 还能再打就再打一次
		if unit.is_alive() and target.is_alive() and unit.stats.ap >= unit.weapon.ap_cost:
			result = unit.attack_target(target)
			unit_panel.append_log(DamageSystem.format_attack_log(result))
			await get_tree().create_timer(0.5).timeout
		unit.end_turn()
		_ai_acting = false
		return

	# 否则向目标走（找一条尽量靠近的路径）
	var path: Array[Vector2i] = hex_grid.find_path(unit.axial_pos, target.axial_pos, unit.axial_pos)
	if path.is_empty():
		unit.end_turn()
		_ai_acting = false
		return
	# 路径终点是 target 占用格 → 截断到攻击范围以内
	@warning_ignore("integer_division")
	var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
	var trimmed: Array[Vector2i] = []
	for step in path:
		if HexCoord.distance(step, target.axial_pos) < 1:
			break  # 不能走到敌人格上
		trimmed.append(step)
		if trimmed.size() >= max_steps:
			break
		if HexCoord.distance(step, target.axial_pos) <= unit.weapon.attack_range:
			# 走到攻击范围就停下
			break
	if trimmed.is_empty():
		unit.end_turn()
		_ai_acting = false
		return
	unit.move_along_path(trimmed)
	await get_tree().create_timer(trimmed.size() * 0.18 + 0.1).timeout

	# 走完看能不能打
	if unit.is_alive() and target.is_alive():
		var d: int = HexCoord.distance(unit.axial_pos, target.axial_pos)
		if d <= unit.weapon.attack_range and unit.stats.ap >= unit.weapon.ap_cost:
			var result: Dictionary = unit.attack_target(target)
			unit_panel.append_log(DamageSystem.format_attack_log(result))
			await get_tree().create_timer(0.5).timeout
	unit.end_turn()
	_ai_acting = false


func _find_closest_enemy(unit: Unit) -> Unit:
	var best: Unit = null
	var best_dist: int = 9999
	for u in _all_units:
		if not u.is_alive():
			continue
		if u.get_faction() == unit.get_faction():
			continue
		var d: int = HexCoord.distance(unit.axial_pos, u.axial_pos)
		if d < best_dist:
			best_dist = d
			best = u
	return best


# ──────────── 战斗结束 ────────────
func _on_battle_ended(winner: int) -> void:
	_ai_acting = true  # 锁定输入
	hex_grid.clear_highlights()
	battle_result_label.visible = true
	if winner == 0:
		battle_result_label.text = "胜利！"
		battle_result_label.modulate = Color(0.85, 0.69, 0.22)
	elif winner == 1:
		battle_result_label.text = "失败"
		battle_result_label.modulate = Color(0.78, 0.22, 0.22)
	else:
		battle_result_label.text = "平局"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_clear_selection()
		elif event.keycode == KEY_SPACE:
			# 空格：跳过当前回合
			var cur: Unit = turn_manager.get_current_unit()
			if cur and cur.get_faction() == 0 and not _ai_acting:
				cur.end_turn()
		elif event.keycode == KEY_R:
			# R 键重开
			get_tree().reload_current_scene()
