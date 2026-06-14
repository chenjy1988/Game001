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

signal unit_hovered(unit: Unit)  ## 鼠标悬停到单位模型
signal unit_unhovered(unit: Unit)  ## 鼠标离开单位模型

const HitEffectScript = preload("res://scripts/effects/HitEffect.gd")
const DamageNumberScript = preload("res://scripts/effects/DamageNumber.gd")
const _FactionBrain = preload("res://scripts/ai/faction_brain.gd")

@onready var hex_grid: HexGrid = $HexGrid
@onready var turn_manager: TurnManager = $TurnManager
@onready var camera: Camera2D = $Camera2D
@onready var unit_layer: Node2D = $UnitLayer
@onready var effect_layer: Node2D = $EffectLayer   ## 粒子 / 伤害飘字宿主层（与 UnitLayer 同坐标系）
@onready var unit_panel = $UI/SidePanel
@onready var top_bar = $UI/TopBar
@onready var tooltip = $UI/UnitTooltip
@onready var battle_result_label: Label = $UI/BattleResultLabel
@onready var flash_overlay: ColorRect = $UI/FlashOverlay

# 玩家输入状态
enum InputState { IDLE, UNIT_SELECTED }
var _input_state: int = InputState.IDLE
var _selected_unit: Unit = null
var _all_units: Array[Unit] = []
var _ai_acting: bool = false
var _battle_seed: int = 0  ## 每局种子（_ready 时初始化，AI RNG 派生于它）


var _battle_log_panel: Panel = null
var _log_scroll: ScrollContainer = null
var _log_richtext: RichTextLabel = null
var _log_last_entry_lbl: Label = null    ## 收起时显示最新一条日志
var _bottom_bar_panel: PanelContainer = null   ## 底部独立头像行动条容器
var _combat_menu: Node = null                  ## 战斗 5 大类菜单（F1，CombatMenu 实例）
var _pending_attack_mode: String = ""          ## 当前待选择的攻击模式（F3）
var _pending_item_id: String = ""              ## 当前待选目标的道具 id（F4 占位）
var _log_expanded: bool = false                ## 记录战斗日志展开状态（展开/折叠）
const LOG_COLLAPSED_MAX_ENTRIES: int = 2       ## 折叠区保留最近 N 条（攻击+倒下等连续事件）
const LOG_PANEL_W: float = 288.0
const LOG_PANEL_MARGIN: float = 8.0
const LOG_PANEL_GAP_BELOW_TOPBAR: float = 8.0   ## 与 TopBar 底边的间距
const LOG_PANEL_COLLAPSED_H: float = 102.0
const LOG_PANEL_EXPANDED_H: float = 234.0
var _log_panel_top: float = 82.0                ## TopBar 底 + gap；_setup 时重算
var _log_collapsed_entries: Array[String] = []
var _log_scroll_following: bool = true         ## 用户手动上滑后为 false，回到底部后恢复

var _pause_menu_visible: bool = false
var _pause_overlay: ColorRect = null
var _faction_brains: Dictionary = {}

const _CombatMenuScript = preload("res://scripts/ui/CombatMenu.gd")

func _ready() -> void:
	# 每局固定种子，AI 决策可复现
	_battle_seed = randi() % 2147483647
	hex_grid.hex_clicked.connect(_on_hex_clicked)
	hex_grid.hex_hovered.connect(_on_hex_hovered)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.round_started.connect(_on_ai_round_started)
	turn_manager.battle_ended.connect(_on_battle_ended)

	_fit_camera_to_map()
	get_viewport().size_changed.connect(_fit_camera_to_map)

	_setup_battle_log_panel()
	_setup_combat_menu()
	_setup_pause_menu()
	_make_ui_passthrough()
	if top_bar and top_bar.has_method("bind_turn_manager"):
		top_bar.bind_turn_manager(turn_manager)
	if unit_panel and unit_panel.has_method("set_hint"):
		unit_panel.turn_manager = turn_manager

	_spawn_units()
	_init_unit_facing()
	turn_manager.register_units(_all_units)
	for u in _all_units:
		u.attacked.connect(_on_any_unit_attacked)
		u.unit_died.connect(_on_any_unit_died)
		u.moved.connect(_on_any_unit_moved)
	turn_manager.start_battle()
	_refresh_faction_brains()
	# 初始化战争迷雾（基于友方单位初始位置）
	_update_fog_of_war()


# ──────────── UI：日志独立 + 鼠标穿透 ────────────
func _setup_battle_log_panel() -> void:
	if _battle_log_panel != null:
		return
	var ui_layer: CanvasLayer = $UI as CanvasLayer

	# ── Panel 容器 ──
	var box := Panel.new()
	box.name = "BattleLog"
	box.anchor_left = 1.0; box.anchor_top = 0.0
	box.anchor_right = 1.0; box.anchor_bottom = 0.0
	_log_panel_top = _compute_log_panel_top()
	box.offset_left = -(LOG_PANEL_W + LOG_PANEL_MARGIN)
	box.offset_top = _log_panel_top
	box.offset_right = -LOG_PANEL_MARGIN
	box.offset_bottom = _log_panel_top + LOG_PANEL_COLLAPSED_H
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.78)
	sb.border_color = Color(0.40, 0.34, 0.25, 0.85)
	sb.border_width_left = 1; sb.border_width_right = 1
	sb.border_width_top = 1; sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(box)

	# ── 内部 VBox ──
	var inner := VBoxContainer.new()
	inner.anchor_left = 0.0; inner.anchor_top = 0.0
	inner.anchor_right = 1.0; inner.anchor_bottom = 1.0
	inner.offset_left = 8.0; inner.offset_top = 6.0
	inner.offset_right = -8.0; inner.offset_bottom = -6.0
	inner.add_theme_constant_override("separation", 4)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)

	# ── 标题行 ──
	var header_hbox := HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "战斗日志"
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header_hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var log_toggle_btn := Button.new()
	log_toggle_btn.name = "LogToggleBtn"
	log_toggle_btn.text = "展开 ▼"
	log_toggle_btn.add_theme_font_size_override("font_size", 12)
	log_toggle_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	log_toggle_btn.focus_mode = Control.FOCUS_NONE
	log_toggle_btn.pressed.connect(toggle_battle_log)
	header_hbox.add_child(log_toggle_btn)

	# ── 收起时显示最新一条日志 ──
	var last_lbl := Label.new()
	last_lbl.name = "LogLastEntry"
	last_lbl.add_theme_font_size_override("font_size", 11)
	last_lbl.add_theme_color_override("font_color", Color(0.75, 0.73, 0.60))
	last_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	last_lbl.clip_text = false
	last_lbl.custom_minimum_size = Vector2(0, 54)   # 约 3 行（攻击两行 + 倒下）
	last_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	last_lbl.visible = true   # 折叠时可见
	inner.add_child(last_lbl)
	_log_last_entry_lbl = last_lbl

	# ── 日志区（单一区域，展开时显示）──
	var rt: RichTextLabel = unit_panel.log_text
	if rt and rt.get_parent():
		rt.get_parent().remove_child(rt)
		rt.add_theme_font_size_override("normal_font_size", 12)
		rt.add_theme_font_size_override("bold_font_size", 12)
		rt.add_theme_font_size_override("italics_font_size", 12)
		rt.add_theme_font_size_override("bold_italics_font_size", 12)
		rt.add_theme_font_size_override("mono_font_size", 12)
		rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.scroll_active = false
		rt.fit_content = true
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rt.custom_minimum_size = Vector2(248, 0)
		rt.scroll_following = false
		rt.focus_mode = Control.FOCUS_NONE
		rt.context_menu_enabled = false
		rt.mouse_filter = Control.MOUSE_FILTER_PASS

		var log_area := Control.new()
		log_area.name = "LogArea"
		log_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_area.visible = false
		inner.add_child(log_area)

		var scroll := ScrollContainer.new()
		scroll.name = "LogScroll"
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		log_area.add_child(scroll)
		_log_scroll = scroll
		scroll.add_child(rt)
		_log_richtext = rt

		var vscroll: VScrollBar = _log_scroll.get_v_scroll_bar()
		_style_battle_log_scrollbar(vscroll)
		vscroll.value_changed.connect(_on_log_scroll_value_changed)



	# 隐藏原 SidePanel 中的残留 LogPanel
	var old_log_panel: PanelContainer = unit_panel.log_panel
	if old_log_panel:
		old_log_panel.visible = false

	_battle_log_panel = box
	_configure_battle_log_mouse_filters()


func _style_battle_log_scrollbar(sb: ScrollBar) -> void:
	sb.custom_minimum_size.x = 14
	sb.mouse_filter = Control.MOUSE_FILTER_STOP

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.10, 0.08, 0.9)
	track.content_margin_left = 2
	track.content_margin_right = 2
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	sb.add_theme_stylebox_override("scroll", track)
	sb.add_theme_stylebox_override("scroll_focus", track)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.58, 0.50, 0.38, 0.95)
	grabber.corner_radius_top_left = 4
	grabber.corner_radius_top_right = 4
	grabber.corner_radius_bottom_left = 4
	grabber.corner_radius_bottom_right = 4
	sb.add_theme_stylebox_override("grabber", grabber)

	var grabber_hi := grabber.duplicate() as StyleBoxFlat
	grabber_hi.bg_color = Color(0.72, 0.63, 0.48, 1.0)
	sb.add_theme_stylebox_override("grabber_highlight", grabber_hi)


func _configure_battle_log_mouse_filters() -> void:
	if _battle_log_panel == null:
		return
	var toggle_btn := _battle_log_panel.find_child("LogToggleBtn", true, false)
	if toggle_btn is Control:
		(toggle_btn as Control).mouse_filter = Control.MOUSE_FILTER_STOP
	if _log_scroll:
		_log_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	if _log_richtext:
		_log_richtext.mouse_filter = Control.MOUSE_FILTER_STOP
	var log_area := _battle_log_panel.find_child("LogArea", true, false)
	if log_area is Control:
		(log_area as Control).mouse_filter = Control.MOUSE_FILTER_PASS


func _on_log_scroll_value_changed(value: float) -> void:
	if _log_scroll == null:
		return
	var sb: VScrollBar = _log_scroll.get_v_scroll_bar()
	_log_scroll_following = value >= sb.max_value - 2.0


func _scroll_log_to_bottom() -> void:
	if not _log_scroll_following:
		return
	call_deferred("_scroll_log_to_bottom_deferred")


## 切换战斗日志展开/折叠（仅响应用户点击）
func toggle_battle_log() -> void:
	_log_expanded = not _log_expanded
	_apply_log_expanded_state()


## 战斗日志顶边 = TopBar 底边 + 间距（避免与行动条重合）
func _compute_log_panel_top() -> float:
	if top_bar == null:
		return 74.0 + LOG_PANEL_GAP_BELOW_TOPBAR
	var bar_h: float = top_bar.size.y
	if bar_h < 1.0:
		bar_h = top_bar.get_combined_minimum_size().y
	if bar_h < 1.0:
		bar_h = 74.0   # TopBar.tscn offset_bottom / PORTRAIT_ROW_H+6
	return bar_h + LOG_PANEL_GAP_BELOW_TOPBAR


## 根据 _log_expanded 切换高度 + 日志区可见性
func _apply_log_expanded_state() -> void:
	if _battle_log_panel == null:
		return
	var log_area: Node = _battle_log_panel.find_child("LogArea", true, false)
	var btn: Button = _battle_log_panel.find_child("LogToggleBtn", true, false) as Button
	if _log_expanded:
		if log_area: log_area.visible = true
		if _log_last_entry_lbl: _log_last_entry_lbl.visible = false
		_battle_log_panel.offset_bottom = _log_panel_top + LOG_PANEL_EXPANDED_H
		call_deferred("_scroll_log_to_bottom")
		if btn: btn.text = "收起 ▲"
	else:
		if log_area: log_area.visible = false
		if _log_last_entry_lbl: _log_last_entry_lbl.visible = true
		_battle_log_panel.offset_bottom = _log_panel_top + LOG_PANEL_COLLAPSED_H
		if btn: btn.text = "展开 ▼"
	_configure_battle_log_mouse_filters()





## 把 TopBar 里的头像条 (PortraitBox) 搬到屏幕底部，单独成 BottomBar
func _setup_bottom_action_bar() -> void:
	if _bottom_bar_panel != null:
		return
	if top_bar == null:
		return
	var ui_layer: CanvasLayer = $UI as CanvasLayer

	# 找到 PortraitBox（TopBar.gd 在 _ready 时创建挂在 $HBox 下）
	var portrait_box: Node = null
	var hbox: Node = top_bar.get_node_or_null("HBox")
	if hbox:
		portrait_box = hbox.get_node_or_null("PortraitBox")
	if portrait_box == null:
		push_warning("[BottomBar] 未找到 PortraitBox，跳过底部行动条")
		return

	# 创建底部容器（用 SHRINK_BEGIN，让宽度按内容自适应）
	var box := PanelContainer.new()
	box.name = "BottomBar"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	# 中心锚点：左右各偏移到 -宽/2，定一个最小宽，让内容撑开
	box.offset_left = -260.0
	box.offset_right = 260.0
	box.offset_top = -50.0
	box.offset_bottom = -8.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.06, 0.92)        # 更不透明，肯定能看见
	sb.border_color = Color(0.55, 0.45, 0.30, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(box)
	# 让 BottomBar 浮在最顶层，避免被其他 UI 遮挡
	box.z_index = 5

	# 把 PortraitBox 从 TopBar 里 reparent 到 BottomBar
	portrait_box.get_parent().remove_child(portrait_box)
	box.add_child(portrait_box)
	# 头像条本身也居中
	if portrait_box is HBoxContainer:
		(portrait_box as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
		(portrait_box as HBoxContainer).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_bottom_bar_panel = box


## 创建固定屏幕左下角的战斗菜单（CombatMenu，F1）
## 参考 FFT 风：菜单常驻屏幕左下角，单位身份切换时只更新内容不动位置
## 仅玩家回合显示；AI 回合 / 战斗结束自动隐藏
func _setup_combat_menu() -> void:
	if _combat_menu != null:
		return
	var ui_layer: CanvasLayer = $UI as CanvasLayer
	var menu = _CombatMenuScript.new()
	menu.name = "CombatMenu"
	# 不设 anchor，由 CombatMenu 自己每帧根据 viewport size 算 position（左下角）
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui_layer.add_child(menu)
	menu.bind_turn_manager(turn_manager)
	menu.action_selected.connect(_on_combat_menu_action)
	# G3/G5：连接预览信号到 TopBar
	if top_bar:
		menu.ability_preview_requested.connect(top_bar._on_ability_preview_requested)
		menu.ability_preview_cancelled.connect(top_bar._on_ability_preview_cancelled)
	_combat_menu = menu


## CombatMenu 触发某个动作（数字键 / 按钮点击）
## F5：扁平化动作 id —— wait 已自处理；attack_<mode> 提示选目标；skill_*/item_* 占位
func _on_combat_menu_action(action_id: String) -> void:
	if _pause_menu_visible:
		return
	if action_id == "end_turn":
		_clear_attack_targeting()
		var end_unit: Unit = turn_manager.get_current_unit()
		if end_unit and end_unit.stats:
			_log_hint("[color=#CC4444]【结束回合】%s 放弃剩余 AP[/color]" % end_unit.stats.unit_name)
			end_unit.end_turn()
		return
	if action_id == "wait":
		_clear_attack_targeting()
		var unit: Unit = turn_manager.get_current_unit()
		if unit and unit.stats:
			var is_second_wait: bool = turn_manager.has_method("has_waited") and turn_manager.call("has_waited", unit)
			if is_second_wait:
				_log_hint("[color=#CC4444]【结束回合】%s 选择结束回合，剩余 AP 作废[/color]" % unit.stats.unit_name)
			else:
				_log_hint("[color=#CCAA44]【等待】%s 选择等待，将在本回合最后行动（气力 -%d）[/color]" % [
					unit.stats.unit_name, TurnManager.WAIT_STAMINA_COST])
			print("[BattleScene] 等待触发：单位=%s, AP=%d, can_wait=%s, 第二次=%s" % [
				unit.stats.unit_name, unit.stats.ap,
				turn_manager.can_wait() if turn_manager.has_method("can_wait") else "N/A",
				str(is_second_wait)])
		var wait_ok: bool = turn_manager.wait_current()
		print("[BattleScene] wait_current 返回：%s" % str(wait_ok))
		return
	# G5：先发制人激活
	if action_id == "preempt":
		_clear_attack_targeting()
		var unit: Unit = turn_manager.get_current_unit()
		if unit and unit.use_ability_preempt():
			_log_hint("[color=#00FF88]【先发制人】激活！下回合行动顺序提前[/color]")
			# 刷新 TopBar 显示当前单位新的预览
			if top_bar:
				top_bar.set_current_unit(unit, turn_manager.round_num, turn_manager.get_pending_units(), turn_manager.get_next_round_queue())
			# 立即结束本单位回合
			unit.end_turn()
		else:
			_log_hint("[color=#FF6666]【先发制人】激活失败（AP 不足或气力满）[/color]")
		return
	if action_id == "breath_regulation":
		_clear_attack_targeting()
		var breath_unit: Unit = turn_manager.get_current_unit()
		if breath_unit and breath_unit.use_ability_breath_regulation():
			var remain_b: int = max(0, breath_unit.stats.max_stamina - breath_unit.stats.stamina_spent())
			_log_hint("[color=#88CCAA]【吐纳调息】%s 深调一口气，气力恢复至 %d/%d[/color]" % [
				breath_unit.get_unit_name(), remain_b, breath_unit.stats.max_stamina])
			breath_unit.end_turn()
		else:
			_log_hint("[color=#FF6666]【吐纳调息】AP 不足（需要 9）[/color]")
		return
	if action_id.begins_with("attack_"):
		var mode: String = action_id.substr("attack_".length())
		_pending_attack_mode = mode
		var current: Unit = turn_manager.get_current_unit()
		if current and current.get_faction() == 0:
			_select_unit(current)
		return
	if action_id.begins_with("skill_"):
		_log_hint("[color=#888888]【技能】尚未开放（Phase 2.5 接入职业能力）[/color]")
		return
	if action_id.begins_with("item_"):
		var item_id: String = action_id.substr("item_".length())
		if item_id == "":
			return
		_pending_attack_mode = ""
		_pending_item_id = item_id
		var item_unit: Unit = turn_manager.get_current_unit()
		var item_label: String = item_id
		if item_unit:
			for entry in item_unit.inventory:
				if entry is Dictionary and str(entry.get("id", "")) == item_id:
					item_label = str(entry.get("name", item_id))
					break
		_log_hint("[color=#88AA88]【道具】已选 %s — 点击目标单位（Phase 3 占位）[/color]" % item_label)
		if item_unit and item_unit.get_faction() == 0:
			_select_unit(item_unit)
		return


func _primary_attack_mode(unit: Unit) -> String:
	if unit == null or unit.weapon == null:
		return ""
	var modes: Array = unit.weapon.attack_modes if not unit.weapon.attack_modes.is_empty() else [unit.weapon.damage_type]
	return str(modes[0]) if modes.size() > 0 else ""


func _clear_attack_targeting() -> void:
	_pending_attack_mode = ""
	_pending_item_id = ""
	if _combat_menu and _combat_menu.has_method("clear_action_highlight"):
		_combat_menu.clear_action_highlight()
	if _combat_menu and _combat_menu.has_method("close_item_popup"):
		_combat_menu.close_item_popup()


func _mode_chinese(mode: String) -> String:
	match mode:
		"slash":  return "斩击"
		"pierce": return "穿刺"
		"crush":  return "重击"
		"ranged": return "远射"
		_:        return mode


## 所有战斗日志都走这里：写 RichTextLabel + 同步更新折叠行
func _log_hint(bbcode: String) -> void:
	if _log_richtext:
		_log_richtext.append_text(bbcode + "\n")
		call_deferred("_scroll_log_to_bottom")
	_update_log_last_entry(bbcode)


func _scroll_log_to_bottom_deferred() -> void:
	if _log_richtext == null:
		return
	await get_tree().process_frame
	if _log_scroll:
		var bar: VScrollBar = _log_scroll.get_v_scroll_bar()
		if bar:
			bar.value = bar.max_value
	elif _log_richtext.scroll_active:
		var bar: VScrollBar = _log_richtext.get_v_scroll_bar()
		if bar:
			bar.value = bar.max_value
		var lines: int = _log_richtext.get_line_count()
		if lines > 0:
			_log_richtext.scroll_to_line(lines - 1)


func _strip_log_bbcode(bbcode: String) -> String:
	var plain: String = bbcode
	plain = plain.replace("[/color]", "").replace("[b]", "").replace("[/b]", "")
	plain = plain.replace("[i]", "").replace("[/i]", "")
	while plain.find("[color=") >= 0:
		var s: int = plain.find("[color=")
		var e: int = plain.find("]", s)
		if e >= 0:
			plain = plain.left(s) + plain.substr(e + 1)
		else:
			break
	return plain


func _update_log_last_entry(bbcode: String) -> void:
	if _log_last_entry_lbl == null:
		return
	var plain: String = _strip_log_bbcode(bbcode)
	_log_collapsed_entries.append(plain)
	while _log_collapsed_entries.size() > LOG_COLLAPSED_MAX_ENTRIES:
		_log_collapsed_entries.pop_front()
	_log_last_entry_lbl.text = "\n".join(_log_collapsed_entries)


## 更新日志面板 hint 文本（CombatMenu 等外部调用）
func set_log_hint(text: String) -> void:
	_log_hint(text)  # 直接写入日志


## 让所有 UI 容器不拦截鼠标，确保滚轮缩放、中键拖拽能传到 _unhandled_input
func _make_ui_passthrough() -> void:
	# TopBar 整条不拦事件（头像本身也是装饰，没有交互）
	if top_bar:
		top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_recursively_set_mouse_passthrough(top_bar)
	# 底部行动条同理
	if _bottom_bar_panel:
		_recursively_set_mouse_passthrough(_bottom_bar_panel)
	# 左上角日志面板保留滚轮/滚动按钮交互，不做穿透
	if _battle_log_panel:
		_configure_battle_log_mouse_filters()
	# SidePanel 默认就是 IGNORE（在 SidePanel.gd _ready 里设过）
	# UnitTooltip 已是 IGNORE（在 UnitTooltip.gd _ready）
	# Background 已是 mouse_filter=2 (IGNORE) 在 .tscn 里设了


func _recursively_set_mouse_passthrough(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			# 修复：如果是按钮（Button），则必须保留其事件拦截，否则无法接收点击！
			if child is Button:
				child.mouse_filter = Control.MOUSE_FILTER_STOP
			else:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_recursively_set_mouse_passthrough(child)


# ──────────── 单位生成 ────────────
func _spawn_units() -> void:
	# 友方 4v4（jobs.json：跳荡 / 枪手 / 奇兵 / 斥候，固定中值）
	_create_unit_from_job("王五", 0, Vector2i(-4,  1), "tiaodang",  "saber",  "mail_armor")
	_create_unit_from_job("张三", 0, Vector2i(-3,  2), "qiangbing", "spear",  "mail_armor")
	_create_unit_from_job("赵六", 0, Vector2i(-2,  1), "qibing",    "saber",  "leather_armor")
	_create_unit_from_job("李四", 0, Vector2i(-3,  0), "chihou",    "dagger", "leather_armor")

	# 敌方 4 人：杂兵 ×3 + 重甲精英（plate_armor Body 280）
	_create_unit("强盗头目", 1, Vector2i(2, -1), "battle_axe", "mail_armor",
		{"hp": 80, "melee": 55, "def": 15, "init": 95, "archetype": "bandit", "disposition": "berserk"})
	_create_unit("强盗匕首手", 1, Vector2i(3, -2), "dagger", "leather_armor",
		{"hp": 50, "melee": 50, "def": 25, "init": 115, "archetype": "skirmisher", "disposition": "default"})
	_create_unit("强盗矛兵", 1, Vector2i(2, 0), "spear", "leather_armor",
		{"hp": 60, "melee": 50, "def": 15, "init": 100, "archetype": "infantry", "disposition": "default"})
	_create_unit("强盗重甲头目", 1, Vector2i(3, -1), "battle_axe", "plate_armor",
		{"hp": 95, "melee": 52, "def": 18, "init": 72, "wisdom": 22, "stamina": 120,
		"archetype": "heavy_infantry", "disposition": "guard"})


func _init_unit_facing() -> void:
	for u in _all_units:
		if u:
			u.face_nearest_enemy(_all_units)


## 按职业 id 生成单位（使用 fixed_stats 中值，不随机）
func _create_unit_from_job(unit_name: String, faction: int, axial: Vector2i,
		job_id: String, weapon_id: String, armor_id: String) -> Unit:
	var job = JobDB.get_job(job_id)
	if job == null:
		push_error("[BattleScene] unknown job_id: %s, fallback to default stats" % job_id)
		return _create_unit(unit_name, faction, axial, weapon_id, armor_id, {})
	var p: Dictionary = job.fixed_stats()
	var unit := _create_unit(unit_name, faction, axial, weapon_id, armor_id, {
		"hp":      p["max_hp"],
		"melee":   p["melee_skill"],
		"def":     p["defense"],
		"init":    p["base_initiative"],
		"resolve": p["resolve"],
		"wisdom":  p["wisdom"],
		"move":    p["move_range"],
	})
	unit.job = job
	unit.ai_archetype_id = get_node("/root/ArchetypeDB").archetype_for_job(job_id)
	unit.ai_disposition_id = "disciplined" if faction == 0 else "default"
	return unit


func _create_unit(unit_name: String, faction: int, axial: Vector2i, weapon_id: String, armor_id: String, params: Dictionary) -> Unit:
	var unit := Unit.new()
	# Stats
	var stats := Stats.new()
	stats.unit_name = unit_name
	stats.faction = faction
	stats.max_hp = params.get("hp", 60)
	stats.melee_skill = params.get("melee", 55)
	# Ranged 已移除：由 melee × 0.6 + bow_mastery 派生
	stats.wisdom = params.get("wisdom", 30)
	stats.defense = params.get("def", 10)
	stats.melee_defense = stats.defense
	stats.base_initiative = params.get("init", 100)
	stats.resolve = params.get("resolve", 40)
	stats.max_stamina = params.get("stamina", 100)  # 气力上限（design.md § 一：60-150，独立可升级属性）
	stats.move_range = params.get("move", 4)         # 移动力（design.md § 一：3-6，职业基础值）
	# 武器/护甲
	var weapon: WeaponData = WeaponArmorDB.get_weapon(weapon_id)
	var armor: ArmorData = WeaponArmorDB.get_armor(armor_id)
	stats.max_head_armor = armor.head_armor
	stats.max_body_armor = armor.body_armor
	unit.stats = stats
	unit.weapon = weapon
	unit.armor = armor
	if params.has("archetype"):
		unit.ai_archetype_id = str(params["archetype"])
	if params.has("disposition"):
		unit.ai_disposition_id = str(params["disposition"])
	# 加到场景
	unit_layer.add_child(unit)
	unit.place_at(axial, hex_grid)
	_all_units.append(unit)
	return unit


# ──────────── 回合控制 ────────────
func _on_turn_started(unit: Unit) -> void:
	_clear_selection()
	# 切换"当前回合"标记：只给当前单位 true，其他都 false
	#   这控制了 Unit._draw_sprite_mode 里的脚下光环、HP 条右端金标、
	#   以及"当前回合 + 己方"才触发的心跳跳跃
	for u in _all_units:
		if u and u.has_method("set_active_turn"):
			u.set_active_turn(u == unit)
	top_bar.set_current_unit(unit, turn_manager.round_num, turn_manager.get_pending_units(), turn_manager.get_next_round_queue())
	unit_panel.bind_unit(unit)
	# 等待恢复行动时给出提示
	if turn_manager.has_waited(unit) and unit.get_faction() == 0 and unit.stats:
		_log_hint("[color=#CCAA44]【等待结束】%s 恢复行动[/color]" % unit.stats.unit_name)
		print("[BattleScene] 等待恢复：%s 恢复行动，AP=%d" % [unit.stats.unit_name, unit.stats.ap])
	if unit.get_faction() == 0:
		# 玩家回合：解锁输入，自动选中当前单位，显示移动范围；显示战斗菜单
		_ai_acting = false
		_select_unit(unit)
		if _combat_menu:
			_combat_menu.show_for_unit(unit)
		print("[BattleScene] 玩家回合：%s, AP=%d, _ai_acting=%s, _input_state=%d" % [
			unit.get_unit_name(), unit.stats.ap if unit.stats else -1, str(_ai_acting), _input_state])
	else:
		# AI 回合：锁定输入
		if _combat_menu:
			_combat_menu.hide_menu()
		_ai_acting = true
		_run_ai_turn(unit)


# ──────────── 玩家输入 ────────────
func _on_hex_clicked(axial: Vector2i) -> void:
	if _pause_menu_visible or _ai_acting:
		return
	var current: Unit = turn_manager.get_current_unit()
	if current == null or current.get_faction() != 0:
		return

	var clicked_unit: Unit = hex_grid.get_occupant(axial)

	# 道具选目标（Phase 3 占位：仅日志）
	if _pending_item_id != "":
		if clicked_unit and clicked_unit.is_alive():
			_log_hint("[color=#888888]【道具】%s 尚未开放（Phase 3 接入背包）[/color]" % _pending_item_id)
		_clear_attack_targeting()
		return

	# 点到敌方 → 仅在选择攻击/技能后允许发动
	if clicked_unit and clicked_unit.get_faction() != current.get_faction():
		if _pending_attack_mode == "":
			return
		if current.weapon == null:
			return
		if HexCoord.distance(current.axial_pos, axial) <= current.weapon.attack_range \
				and current.stats.ap >= current.get_weapon_ap_cost():
			_player_attack(current, clicked_unit)
			return
		return

	# 点到自己 → 重新选中（已选中）
	if clicked_unit == current:
		_select_unit(current)
		return

	# 点到空格 → 尝试移动（攻击选目标中不移动）
	if clicked_unit == null and _selected_unit == current:
		if _pending_attack_mode != "" or _pending_item_id != "":
			return
		var path: Array[Vector2i] = hex_grid.find_path(current.axial_pos, axial, current.axial_pos, current.get_faction())
		@warning_ignore("integer_division")
		var max_steps: int = current.stats.ap / Unit.AP_PER_HEX
		print("[DEBUG] click empty axial=", axial, " path=", path, " path.size=", path.size(), " max_steps=", max_steps, " ap=", current.stats.ap)
		if not path.is_empty() and path.size() <= max_steps:
			_player_move(current, path)


func _player_move(unit: Unit, path: Array[Vector2i]) -> void:
	_clear_attack_targeting()
	hex_grid.clear_highlights()
	# 菜单固定屏幕左下角，移动期间不需要 hide（按钮会按 AP 灰化）
	var ok: bool = unit.move_along_path(path)
	if not ok:
		_select_unit(unit)
		return
	# 等动画结束（每步约 0.22s，含借机攻击缓冲）
	await get_tree().create_timer(path.size() * 0.22 + 0.1).timeout
	if unit.is_alive():
		_select_unit(unit)
		# 移动后刷一次菜单（AP 变化要反映到按钮置灰状态）
		if _combat_menu and unit.get_faction() == 0 and turn_manager.get_current_unit() == unit:
			_combat_menu.show_for_unit(unit)
		# 只有 AP 完全用完（= 0）时才自动结束回合；否则保留操作权让玩家决定
		if unit.stats.ap <= 0:
			unit.end_turn()
	# 若被借机攻击打死，主动结束回合让 TurnManager 推进
	elif turn_manager.get_current_unit() == unit:
		unit.end_turn()


func _player_attack(unit: Unit, target: Unit) -> void:
	hex_grid.clear_highlights()
	# 攻击日志统一由 _on_any_unit_attacked 处理
	# F3：若玩家已选择攻击模式，传递给 attack_target；否则用默认
	unit.attack_target(target, _pending_attack_mode)
	_clear_attack_targeting()
	await get_tree().create_timer(0.45).timeout
	if not turn_manager.get_current_unit() == unit:
		return  # 战斗结束等
	if unit.is_alive():
		_select_unit(unit)
		# 攻击后刷一次菜单（AP / HP 变化要反映）
		if _combat_menu and unit.get_faction() == 0:
			_combat_menu.show_for_unit(unit)
		# 只有 AP 完全用完（= 0）时才自动结束回合；否则保留操作权让玩家决定
		if unit.stats.ap <= 0:
			unit.end_turn()


func _select_unit(unit: Unit) -> void:
	_selected_unit = unit
	_input_state = InputState.UNIT_SELECTED
	hex_grid.clear_highlights()
	hex_grid.set_selected(unit.axial_pos)
	# 移动范围（攻击/道具选目标时不显示蓝格，避免与射程标混淆）
	if _pending_attack_mode == "" and _pending_item_id == "":
		@warning_ignore("integer_division")
		var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
		var move_hexes: Array[Vector2i] = hex_grid.get_reachable(unit.axial_pos, max_steps, unit.get_faction())
		hex_grid.set_highlight_move(move_hexes)
	# 攻击射程：仅在按下攻击/技能后显示（BB 风）
	if unit.weapon and _pending_attack_mode != "":
		var rmin: int = unit.weapon.range_min if unit.weapon.range_min > 0 else 1
		var rmax: int = unit.weapon.range_max if unit.weapon.range_max > 0 else unit.weapon.attack_range
		var all_range: Array[Vector2i] = hex_grid.get_attack_range_hexes(unit.axial_pos, rmin, rmax)
		var enemy_hexes: Array[Vector2i] = hex_grid.get_attack_targets(
			unit.axial_pos, rmax, unit.get_faction())
		var enemy_set: Dictionary = {}
		for h in enemy_hexes:
			enemy_set[h] = true
		var marker_hexes: Array[Vector2i] = []
		for h in all_range:
			if not enemy_set.has(h):
				marker_hexes.append(h)
		hex_grid.set_highlight_attack_range(marker_hexes, enemy_hexes)
	# 敌方 ZoC 威胁地图（仅友方选中时显示）
	if unit.get_faction() == 0:
		var enemy_faction: int = 1
		var zoc_cells: Array[Vector2i] = hex_grid.get_zoc_cells_of(enemy_faction)
		hex_grid.set_highlight_zoc(zoc_cells)


# 鼠标移到某格 → 实时预览路径与借机攻击触发点 + 单位浮层显隐
var _hover_unit: Unit = null


## 计算"目标 target 是否是当前出战玩家单位的可立即攻击敌人"。
## 是 → 返回攻击者（用于浮层攻击预览）；否 → null。
##   条件：当前出战、玩家阵营、活着、武器存在、AP 够、距离在攻击范围内、target 是敌方
func _attack_preview_attacker_for(target: Unit) -> Unit:
	if _ai_acting:
		return null
	if target == null or target.stats == null or not target.is_alive():
		return null
	var current: Unit = turn_manager.get_current_unit()
	if current == null or current.get_faction() != 0:
		return null
	if not current.is_alive() or current.weapon == null:
		return null
	if target.get_faction() == current.get_faction():
		return null
	if current.stats.ap < current.get_weapon_ap_cost():
		return null
	var d: int = HexCoord.distance(current.axial_pos, target.axial_pos)
	if _pending_attack_mode == "" or _pending_item_id != "":
		return null
	if d > current.weapon.attack_range:
		return null
	return current


func _on_hex_hovered(axial: Vector2i) -> void:
	# 悬停非当前行动单位 → 立即弹出信息卡（已选攻击且可打时附带命中预览）
	var occ = hex_grid.get_occupant(axial)
	var current_unit: Unit = turn_manager.get_current_unit()
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	if occ != null and occ.is_alive() and occ != current_unit:
		if occ != _hover_unit:
			if _hover_unit != null:
				unit_unhovered.emit(_hover_unit)
			_hover_unit = occ
			unit_hovered.emit(_hover_unit)
		var atk_ctx: Unit = _attack_preview_attacker_for(occ)
		if atk_ctx != null:
			tooltip.show_for_attack(occ, atk_ctx, mouse_pos)
		else:
			tooltip.show_for(occ, mouse_pos)
	else:
		if _hover_unit != null:
			unit_unhovered.emit(_hover_unit)
		_hover_unit = null
		tooltip.hide_card()

	# 路径预览：仅当玩家正在控制时
	if _ai_acting or _selected_unit == null or not _selected_unit.is_alive():
		hex_grid.set_highlight_path([] as Array[Vector2i])
		hex_grid.set_highlight_oa_steps([] as Array[Vector2i])
		return
	if _pending_attack_mode != "" or _pending_item_id != "":
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
	var path: Array[Vector2i] = hex_grid.find_path(current.axial_pos, axial, current.axial_pos, current.get_faction())
	@warning_ignore("integer_division")
	var max_steps: int = current.stats.ap / Unit.AP_PER_HEX
	if path.is_empty() or path.size() > max_steps:
		hex_grid.set_highlight_path([] as Array[Vector2i])
		hex_grid.set_highlight_oa_steps([] as Array[Vector2i])
		return
	hex_grid.set_highlight_path(path)
	# 标记会触发借机攻击的步格
	var oa_steps: Array[Vector2i] = []
	var step_info: Array = hex_grid.analyze_path_oa(current.axial_pos, path, current.get_faction(), current)
	for s in step_info:
		if not s["oa_attackers"].is_empty():
			oa_steps.append(s["to"])
	hex_grid.set_highlight_oa_steps(oa_steps)


# ──────────── 屏幕震动（暴击/重大命中反馈） ────────────
var _shake_remaining: float = 0.0
var _shake_total: float = 0.0
var _shake_magnitude: float = 0.0
var _camera_base_offset: Vector2 = Vector2.ZERO





# ──────────── 整屏闪色反馈（暴击/重击） ────────────
func _flash_screen(flash_color: Color, duration: float) -> void:
	if flash_overlay == null:
		return
	flash_overlay.color = flash_color
	flash_overlay.visible = true
	var tw := create_tween()
	tw.tween_property(flash_overlay, "color", Color(flash_color.r, flash_color.g, flash_color.b, 0.0), duration)
	tw.tween_callback(func(): flash_overlay.visible = false)

func _shake_camera(duration: float, magnitude: float) -> void:
	if camera == null:
		return
	# 叠加规则：取最大剩余时长 + 最大震动幅度
	if duration > _shake_remaining:
		_shake_remaining = duration
		_shake_total = duration
	_shake_magnitude = max(_shake_magnitude, magnitude)


func _process(delta: float) -> void:
	# DEBUG: 监控日志面板尺寸变化
	if tooltip and tooltip.visible:
		tooltip.update_position(get_viewport().get_mouse_position())
	# WASD / 方向键平移相机（速度按 zoom 反比缩放，远离时移动更快）
	_handle_camera_keyboard_pan(delta)
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
	var bbcode: String = DamageSystem.format_attack_log(result)
	_log_hint(bbcode)
	var did_hit: bool = result.get("hit", false)
	var is_crit: bool = result.get("critical", false)
	var hp_dmg: int = result.get("hp_damage", 0)
	var armor_dmg: int = result.get("armor_damage", 0)
	print("[FX] %s -> %s  hit=%s crit=%s dmg=%d" % [
		attacker.get_unit_name() if attacker else "?",
		target.get_unit_name() if target else "?",
		did_hit, is_crit, hp_dmg,
	])
	# 攻击者前冲
	if attacker and attacker.is_alive():
		attacker.play_attack_lunge(target.axial_pos)
	# 目标受击
	if target and target.is_alive():
		var strength: float = 0.0
		if did_hit:
			strength = clamp(0.4 + float(hp_dmg) / 50.0, 0.4, 1.0)
			if is_crit:
				strength = 1.0
		var from_axial: Vector2i = attacker.axial_pos if attacker else Vector2i(99999, 99999)
		target.play_hit_reaction(strength, did_hit, from_axial, is_crit)
	# 屏幕震动 + 整屏闪红（暴击 / 重击）
	if is_crit and did_hit:
		_shake_camera(0.30, 6.0)
		_flash_screen(CombatPalette.screen_flash_crit, 0.18)
	elif did_hit and hp_dmg >= 30:
		_shake_camera(0.15, 3.0)
		_flash_screen(CombatPalette.screen_flash_heavy, 0.10)

	# ──────────── 命中粒子 + 伤害飘字（与攻击结果联动） ────────────
	if target == null or effect_layer == null:
		return
	var pos: Vector2 = target.position
	var crit_intensity: float = 1.5 if is_crit else 1.0

	_play_attack_audio(result, did_hit, is_crit, hp_dmg, armor_dmg)

	var hit_dir: Vector2 = Vector2.UP
	if attacker and target:
		hit_dir = (target.position - attacker.position).normalized()
	if not did_hit:
		var miss_label: String = "MISS"
		var miss_color: Color = CombatPalette.miss_neutral
		if result.get("blocked", false):
			miss_label = "格挡"
			miss_color = CombatPalette.armor_hit
			HitEffectScript.spawn(effect_layer, pos, "spark", 0.8, hit_dir)
		elif result.get("dodged", false):
			miss_label = "闪避"
		DamageNumberScript.spawn(effect_layer, pos, miss_label, miss_color)
	elif hp_dmg > 0:
		# 见血：红色血溅 + 红字伤害
		HitEffectScript.spawn(effect_layer, pos, "blood", crit_intensity, hit_dir)
		var dmg_color: Color = CombatPalette.damage_crit if is_crit else CombatPalette.damage_hp
		var dmg_text: String = ("%d!" % hp_dmg) if is_crit else str(hp_dmg)
		DamageNumberScript.spawn(effect_layer, pos, dmg_text, dmg_color, is_crit)
	else:
		# 命中但未破防（纯破甲 / 0 伤）：火花 + 甲值字
		HitEffectScript.spawn(effect_layer, pos, "spark", 1.0, hit_dir)
		if armor_dmg > 0:
			DamageNumberScript.spawn(effect_layer, pos, "甲-%d" % armor_dmg, CombatPalette.armor_hit)


func _play_attack_audio(result: Dictionary, did_hit: bool, is_crit: bool, hp_dmg: int, armor_dmg: int) -> void:
	if not is_instance_valid(CombatAudio):
		return
	if not did_hit:
		if result.get("blocked", false):
			CombatAudio.play_blocked()
		else:
			CombatAudio.play_miss()
	elif is_crit:
		CombatAudio.play_crit()
	elif hp_dmg > 0:
		var intensity: float = clampf(0.5 + float(hp_dmg) / 40.0, 0.5, 1.5)
		CombatAudio.play_damage(intensity)
	elif armor_dmg > 0:
		CombatAudio.play_armor_hit()


func _on_any_unit_died(unit: Unit) -> void:
	if is_instance_valid(CombatAudio):
		CombatAudio.play_death()
	hex_grid.set_occupant(unit.axial_pos, null)
	unit.queue_redraw()
	var bbcode: String = "[color=#A03030]✦ %s 倒下[/color]" % unit.get_unit_name()
	_log_hint(bbcode)
	# 死亡特效：血溅 + 烟雾飘起
	if effect_layer and unit:
		HitEffectScript.spawn(effect_layer, unit.position, "blood", 1.3)
		HitEffectScript.spawn(effect_layer, unit.position, "smoke", 1.0)
	if _selected_unit == unit:
		_clear_selection()
	# 立刻刷新行动条，让死亡单位立刻从条上消失
	if top_bar and turn_manager:
		top_bar.set_current_unit(turn_manager.get_current_unit(),
			turn_manager.round_num,
			turn_manager.get_pending_units(),
			turn_manager.get_next_round_queue())


func _clear_selection() -> void:
	_clear_attack_targeting()
	_selected_unit = null
	_input_state = InputState.IDLE
	hex_grid.clear_highlights()


func _setup_pause_menu() -> void:
	if _pause_overlay != null:
		return
	var ui_layer: CanvasLayer = $UI as CanvasLayer

	var overlay := ColorRect.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.02, 0.03, 0.72)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 50
	ui_layer.add_child(overlay)
	_pause_overlay = overlay

	var panel := Panel.new()
	panel.name = "PausePanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -140.0
	panel.offset_right = 140.0
	panel.offset_top = -140.0
	panel.offset_bottom = 140.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.07, 0.96)
	sb.border_color = Color(0.55, 0.45, 0.30, 0.95)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20.0
	vbox.offset_top = 16.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -16.0
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "战斗菜单"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Esc 继续战斗"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.75, 0.72, 0.65)
	vbox.add_child(hint)

	var resume_btn := Button.new()
	resume_btn.text = "继续战斗"
	resume_btn.pressed.connect(_close_pause_menu)
	vbox.add_child(resume_btn)

	var restart_btn := Button.new()
	restart_btn.text = "重新开始"
	restart_btn.pressed.connect(_restart_battle)
	vbox.add_child(restart_btn)

	var main_btn := Button.new()
	main_btn.text = "返回主菜单"
	main_btn.pressed.connect(_return_to_main_menu)
	vbox.add_child(main_btn)


func _toggle_pause_menu() -> void:
	if _pause_menu_visible:
		_close_pause_menu()
	else:
		_open_pause_menu()


func _restart_battle() -> void:
	get_tree().reload_current_scene()


func _open_pause_menu() -> void:
	if _pause_overlay == null:
		return
	_clear_attack_targeting()
	_pause_menu_visible = true
	_pause_overlay.visible = true
	if _combat_menu:
		_combat_menu.set_process_unhandled_input(false)
	var cur: Unit = turn_manager.get_current_unit()
	if cur and cur.get_faction() == 0 and cur.is_alive() and not _ai_acting:
		_select_unit(cur)


func _close_pause_menu() -> void:
	if _pause_overlay == null:
		return
	_pause_menu_visible = false
	_pause_overlay.visible = false
	if _combat_menu:
		_combat_menu.set_process_unhandled_input(true)
	var cur: Unit = turn_manager.get_current_unit()
	if cur and cur.get_faction() == 0 and cur.is_alive() and not _ai_acting:
		_select_unit(cur)
		if _combat_menu:
			_combat_menu.show_for_unit(cur)


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ──────────── 战争迷雾 ────────────
func _update_fog_of_war() -> void:
	var friendly: Array = []
	for u in _all_units:
		if u != null and u.is_alive() and u.get_faction() == 0:
			friendly.append(u)
	hex_grid.update_fog_of_war(friendly)
	_update_unit_visibility()


func _update_unit_visibility() -> void:
	for u in _all_units:
		if u == null or not u.is_alive():
			continue
		if u.get_faction() == 0:
			u.visible = true
		else:
			u.visible = hex_grid.is_hex_visible(u.axial_pos)


func _on_any_unit_moved(unit: Unit, _from: Vector2i, _to: Vector2i) -> void:
	_update_fog_of_war()
	if is_instance_valid(CombatAudio) and unit:
		CombatAudio.play_footstep(unit.get_total_weight() if unit.has_method("get_total_weight") else 0)


func _on_ai_round_started(_round_num: int) -> void:
	_refresh_faction_brains()


func _refresh_faction_brains() -> void:
	_faction_brains = _FactionBrain.compute_all(_all_units, hex_grid)


# ──────────── focus_marks 集火标记（已由 FactionBrain 产出，保留兼容）────────────

## @deprecated 使用 FactionBrain.compute → focus_marks
func _build_focus_marks(ai_unit: Unit) -> Dictionary:
	var marks: Array = []
	var my_faction: int = ai_unit.get_faction()
	for ally in _all_units:
		if ally == ai_unit or not ally.is_alive() or ally.get_faction() != my_faction:
			continue
		for d in range(6):
			var nb: Vector2i = HexCoord.neighbor(ally.axial_pos, d)
			var occ = hex_grid.get_occupant(nb) if hex_grid else null
			# occ is Unit
			if occ != null and occ.is_alive() and occ.get_faction() != my_faction:
				if not occ in marks:
					marks.append(occ)
	return { "focus_marks": marks }


# ──────────── AI（评分式决策） ────────────
## 新 AI（决策/执行分离）：AIAgent + SceneExecutor
## 旧 AI（BattleAI.decide）：保留作为 fallback，切换 flag use_new_ai
## 注意：_ai_acting 由 _on_turn_started 统一管理，此处不再设置
func _run_ai_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.35).timeout
	if not unit.is_alive():
		if turn_manager.get_current_unit() == unit:
			unit.end_turn()
		return

	# 独立 RNG（从 battle_seed + unit 位置派生，同局可复现）
	var ai_rng := RandomNumberGenerator.new()
	ai_rng.seed = _battle_seed + unit.axial_pos.x * 1000 + unit.axial_pos.y

	var agent := AIAgent.new(unit, ai_rng)
	var executor := AISceneExecutor.new()
	var guard: int = 0

	while guard < agent._max_actions and unit.is_alive():
		guard += 1
		var brain: Dictionary = _faction_brains.get(unit.get_faction(), {})
		var view: AIWorldView = AIWorldView.capture(unit, _all_units, hex_grid, turn_manager, brain)
		var action = agent.decide_next_action(view)
		var _AT = AISceneExecutor._AT

		if action.type == _AT.END_TURN:
			break

		if action.type == _AT.WAIT:
			await executor.run(action, unit, self, turn_manager)
			return  # wait 后本回合不继续

		var cont: bool = await executor.run(action, unit, self, turn_manager)
		if not cont:
			break
		if not unit.is_alive():
			return

	if unit.is_alive():
		unit.end_turn()


## 旧 AI（已下线：BattleAI.decide 被 AIAgent 替代）
## BattleAI.gd 保留作参考但不调用


# ──────────── 战斗结束 ────────────
func _on_battle_ended(winner: int) -> void:
	_ai_acting = true  # 锁定输入
	if _combat_menu:
		_combat_menu.hide_menu()
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
	# ──────── 相机缩放（滚轮） ────────
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.0 + CAMERA_ZOOM_STEP, event.position)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / (1.0 + CAMERA_ZOOM_STEP), event.position)
			return

	# ──────── 中键拖拽平移 ────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_pan_last_pos = event.position
			return
	elif event is InputEventMouseMotion and _panning:
		if camera:
			var delta_screen: Vector2 = event.position - _pan_last_pos
			camera.position -= delta_screen / max(camera.zoom.x, 0.0001)
			_pan_last_pos = event.position
		return

	# ──────── 键盘 ────────
	if event is InputEventKey and event.pressed:
		var ctrl: bool = event.ctrl_pressed or event.meta_pressed
		if ctrl and (event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS):
			_zoom_camera(1.0 + CAMERA_ZOOM_STEP, get_viewport().get_mouse_position())
			return
		elif ctrl and event.keycode == KEY_MINUS:
			_zoom_camera(1.0 / (1.0 + CAMERA_ZOOM_STEP), get_viewport().get_mouse_position())
			return
		elif ctrl and event.keycode == KEY_0:
			_reset_camera()
			return

		if event.keycode == KEY_ESCAPE:
			if _pause_menu_visible:
				_close_pause_menu()
			else:
				_open_pause_menu()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_R:
			# R 键重开
			get_tree().reload_current_scene()


# ──────────── 相机控制（缩放/平移） ────────────
const CAMERA_ZOOM_MIN: float = 0.5
const CAMERA_ZOOM_MAX: float = 3.0
const CAMERA_ZOOM_STEP: float = 0.12
## 地图铺满窗口时的边距比例（0.0 = 完全贴边，0.08 = 留 8% 边距）
const CAMERA_FIT_PADDING: float = 0.0

var _panning: bool = false
var _pan_last_pos: Vector2 = Vector2.ZERO


## Battle Brothers 风格：相机自动适配窗口大小，让地图铺满整个屏幕。
## 用 max(zoom_x, zoom_y) 保证地图在至少一个方向上完全铺满窗口；
## 另一个方向可能溢出屏幕（可滚轮/平移查看），这与 BB 的体验一致。
func _fit_camera_to_map() -> void:
	if camera == null or hex_grid == null:
		return
	var map_bounds: Rect2 = hex_grid.get_map_bounds()
	# 地图包围盒是相对 HexGrid.position 的局部坐标，需转到场景全局坐标
	var grid_pos: Vector2 = hex_grid.position
	var world_min: Vector2 = grid_pos + map_bounds.position
	var world_max: Vector2 = grid_pos + map_bounds.position + map_bounds.size
	var world_center: Vector2 = (world_min + world_max) * 0.5
	var world_size: Vector2 = world_max - world_min

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	# 加 padding：让地图不完全贴屏幕边缘
	var effective_vp: Vector2 = vp_size * (1.0 - CAMERA_FIT_PADDING)
	# 用 max 而非 min：保证地图至少在一个方向完全铺满窗口（另一个方向可溢出）
	var zoom_x: float = effective_vp.x / max(world_size.x, 1.0)
	var zoom_y: float = effective_vp.y / max(world_size.y, 1.0)
	var fit_zoom: float = clamp(max(zoom_x, zoom_y), CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)

	camera.zoom = Vector2(fit_zoom, fit_zoom)
	camera.position = world_center


## 以鼠标位置为锚点缩放（鼠标下方的世界点保持不动）
func _zoom_camera(factor: float, screen_anchor: Vector2) -> void:
	if camera == null:
		return
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clamp(old_zoom * factor, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	# 保持鼠标下方的世界坐标不变
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var anchor_offset: Vector2 = screen_anchor - viewport_size * 0.5
	var world_anchor: Vector2 = camera.position + anchor_offset / old_zoom
	camera.zoom = Vector2(new_zoom, new_zoom)
	camera.position = world_anchor - anchor_offset / new_zoom


func _reset_camera() -> void:
	_fit_camera_to_map()


## WASD / 方向键平移（按住持续移动）
const CAMERA_KEYBOARD_PAN_SPEED: float = 600.0   # 像素/秒（zoom=1 时）

func _handle_camera_keyboard_pan(delta: float) -> void:
	if camera == null:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()
	# 速度按 zoom 反比：放大状态下移动慢一点，缩小时快一点（手感更自然）
	var speed: float = CAMERA_KEYBOARD_PAN_SPEED / max(camera.zoom.x, 0.0001)
	camera.position += dir * speed * delta
