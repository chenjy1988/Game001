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
@onready var tooltip = $UI/UnitTooltip
@onready var battle_result_label: Label = $UI/BattleResultLabel

# 玩家输入状态
enum InputState { IDLE, UNIT_SELECTED }
var _input_state: int = InputState.IDLE
var _selected_unit: Unit = null
var _all_units: Array[Unit] = []
var _ai_acting: bool = false


func _ready() -> void:
	hex_grid.hex_clicked.connect(_on_hex_clicked)
	hex_grid.hex_hovered.connect(_on_hex_hovered)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.battle_ended.connect(_on_battle_ended)

	_spawn_units()
	turn_manager.register_units(_all_units)
	# 统一监听攻击/死亡信号，正规攻击与借机攻击共用日志
	for u in _all_units:
		u.attacked.connect(_on_any_unit_attacked)
		u.unit_died.connect(_on_any_unit_died)
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
	# 等动画结束（每步约 0.22s，含借机攻击缓冲）
	await get_tree().create_timer(path.size() * 0.22 + 0.1).timeout
	if unit.is_alive():
		_select_unit(unit)
		# 既走不动也打不出，自动结束回合
		if unit.stats.ap < Unit.AP_PER_HEX and unit.stats.ap < unit.weapon.ap_cost:
			unit.end_turn()
	# 若被借机攻击打死，主动结束回合让 TurnManager 推进
	elif turn_manager.get_current_unit() == unit:
		unit.end_turn()


func _player_attack(unit: Unit, target: Unit) -> void:
	hex_grid.clear_highlights()
	# 攻击日志统一由 _on_any_unit_attacked 处理
	unit.attack_target(target)
	await get_tree().create_timer(0.45).timeout
	if not turn_manager.get_current_unit() == unit:
		return  # 战斗结束等
	if unit.is_alive():
		_select_unit(unit)
		# 既走不动也打不出，自动结束回合
		if unit.stats.ap < Unit.AP_PER_HEX and unit.stats.ap < unit.weapon.ap_cost:
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
	# 敌方 ZoC 威胁地图（仅友方选中时显示）
	if unit.get_faction() == 0:
		var enemy_faction: int = 1
		var zoc_cells: Array[Vector2i] = hex_grid.get_zoc_cells_of(enemy_faction)
		hex_grid.set_highlight_zoc(zoc_cells)


# 鼠标移到某格 → 实时预览路径与借机攻击触发点 + 单位 tooltip 显隐
func _on_hex_hovered(axial: Vector2i) -> void:
	# tooltip：任何单位（不论阵营）都显示
	var occ = hex_grid.get_occupant(axial)
	if occ != null and occ.is_alive():
		tooltip.show_for(occ, get_viewport().get_mouse_position())
	else:
		tooltip.hide()

	# 路径预览：仅当玩家正在控制时
	if _ai_acting or _selected_unit == null or not _selected_unit.is_alive():
		hex_grid.set_highlight_path([] as Array[Vector2i])
		hex_grid.set_highlight_oa_steps([] as Array[Vector2i])
		return
	if _selected_unit.get_faction() != 0:
		return
	var current: Unit = _selected_unit
	# 鼠标停在单位身上 → 清空路径预览
	if occ != null:
		hex_grid.set_highlight_path([] as Array[Vector2i])
		hex_grid.set_highlight_oa_steps([] as Array[Vector2i])
		return
	var path: Array[Vector2i] = hex_grid.find_path(current.axial_pos, axial, current.axial_pos)
	@warning_ignore("integer_division")
	var max_steps: int = current.stats.ap / Unit.AP_PER_HEX
	if path.is_empty() or path.size() > max_steps:
		hex_grid.set_highlight_path([] as Array[Vector2i])
		hex_grid.set_highlight_oa_steps([] as Array[Vector2i])
		return
	hex_grid.set_highlight_path(path)
	# 标记会触发借机攻击的步格
	var oa_steps: Array[Vector2i] = []
	var step_info: Array = hex_grid.analyze_path_oa(current.axial_pos, path, current.get_faction())
	for s in step_info:
		if not s["oa_attackers"].is_empty():
			oa_steps.append(s["to"])
	hex_grid.set_highlight_oa_steps(oa_steps)


# ──────────── 屏幕震动（暴击/重大命中反馈） ────────────
var _shake_remaining: float = 0.0
var _shake_total: float = 0.0
var _shake_magnitude: float = 0.0
var _camera_base_offset: Vector2 = Vector2.ZERO


func _shake_camera(duration: float, magnitude: float) -> void:
	if camera == null:
		return
	# 叠加规则：取最大剩余时长 + 最大震动幅度
	if duration > _shake_remaining:
		_shake_remaining = duration
		_shake_total = duration
	_shake_magnitude = max(_shake_magnitude, magnitude)


func _process(delta: float) -> void:
	# tooltip 跟随光标
	if tooltip and tooltip.visible:
		tooltip.update_position(get_viewport().get_mouse_position())
	# 屏幕震动（随时间线性衰减）
	if _shake_remaining > 0.0 and camera:
		_shake_remaining = max(0.0, _shake_remaining - delta)
		if _shake_remaining <= 0.0:
			camera.offset = _camera_base_offset
			_shake_magnitude = 0.0
		else:
			var fade: float = _shake_remaining / max(0.001, _shake_total)
			var mag: float = _shake_magnitude * fade
			camera.offset = _camera_base_offset + Vector2(
				randf_range(-mag, mag),
				randf_range(-mag, mag)
			)


# ──────────── 攻击日志 / 死亡通知（正规与借机攻击统一处理） ────────────
func _on_any_unit_attacked(attacker: Unit, target: Unit, result: Dictionary) -> void:
	unit_panel.append_log(DamageSystem.format_attack_log(result))
	# 视觉反馈
	if attacker and attacker.is_alive():
		attacker.play_attack_lunge(target.axial_pos)
	if target and target.is_alive():
		var did_hit: bool = result.get("hit", false)
		var is_crit: bool = result.get("critical", false)
		var hp_dmg: int = result.get("hp_damage", 0)
		# 震动强度：暴击 > 普通命中 > miss
		var strength: float = 0.0
		if did_hit:
			strength = clamp(0.4 + float(hp_dmg) / 50.0, 0.4, 1.0)
			if is_crit:
				strength = 1.0
		target.play_hit_reaction(strength, did_hit)
		# 暴击 → 屏幕震动
		if is_crit and did_hit:
			_shake_camera(0.25, 4.0)
		elif did_hit and hp_dmg >= 30:
			# 重击（>=30 HP 伤害）也轻微震
			_shake_camera(0.12, 2.0)


func _on_any_unit_died(unit: Unit) -> void:
	hex_grid.set_occupant(unit.axial_pos, null)
	unit.queue_redraw()
	unit_panel.append_log("[color=#A03030]✦ %s 倒下[/color]" % unit.get_unit_name())
	if _selected_unit == unit:
		_clear_selection()


func _clear_selection() -> void:
	_selected_unit = null
	_input_state = InputState.IDLE
	hex_grid.clear_highlights()


# ──────────── AI（评分式决策） ────────────
## 评分式：BattleAI 静态决策器返回 Plan，这里负责按 Plan 执行（移动 + 攻击 + 兜底结束回合）
func _run_ai_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.35).timeout
	if not unit.is_alive():
		unit.end_turn()
		_ai_acting = false
		return

	# 主循环：可能"移动+攻击"后 AP 还够再打 1 次，所以决策最多重试 3 次
	var safety: int = 3
	while safety > 0 and unit.is_alive():
		safety -= 1
		var plan: Dictionary = BattleAI.decide(unit, _all_units, hex_grid)
		var path: Array[Vector2i] = plan.get("path", [] as Array[Vector2i])
		var target: Unit = plan.get("target", null)

		# 1) 先执行移动（若有）
		if not path.is_empty():
			unit.move_along_path(path)
			await get_tree().create_timer(path.size() * 0.22 + 0.1).timeout
			if not unit.is_alive():
				break  # 被借机攻击打死

		# 2) 再执行攻击（若 plan 给出且仍可执行）
		if target != null and unit.is_alive() and target.is_alive():
			var d: int = HexCoord.distance(unit.axial_pos, target.axial_pos)
			if d <= unit.weapon.attack_range and unit.stats.ap >= unit.weapon.ap_cost:
				unit.attack_target(target)
				await get_tree().create_timer(0.5).timeout
				# AP 还多 → 再继续循环看是否能补刀
				if unit.is_alive() and unit.stats.ap >= unit.weapon.ap_cost:
					continue
		# 没有目标或已动用，回合结束
		break

	if unit.is_alive():
		unit.end_turn()
	_ai_acting = false


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
