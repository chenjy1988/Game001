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


var _battle_log_panel: Panel = null             ## 独立左上角日志容器（Panel 不自动包裹子内容，尺寸由 offset 控制）
var _log_richtext: RichTextLabel = null         ## 日志 RichTextLabel 引用（从 SidePanel 中 reparent 出来）
var _log_hint_label: Label = null               ## 日志面板内独立 hint label（与 SidePanel 完全解耦）
var _bottom_bar_panel: PanelContainer = null   ## 底部独立头像行动条容器
var _combat_menu: Node = null                  ## 战斗 5 大类菜单（F1，CombatMenu 实例）
var _pending_attack_mode: String = ""          ## 当前待选择的攻击模式（F3）
var _log_expanded: bool = false                ## 记录战斗日志展开状态（展开/折叠）

const _CombatMenuScript = preload("res://scripts/ui/CombatMenu.gd")

func _ready() -> void:
	hex_grid.hex_clicked.connect(_on_hex_clicked)
	hex_grid.hex_hovered.connect(_on_hex_hovered)
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.battle_ended.connect(_on_battle_ended)

	_fit_camera_to_map()
	get_viewport().size_changed.connect(_fit_camera_to_map)

	_setup_battle_log_panel()
	_setup_combat_menu()
	_make_ui_passthrough()
	if top_bar and top_bar.has_method("bind_turn_manager"):
		top_bar.bind_turn_manager(turn_manager)

	_spawn_units()
	turn_manager.register_units(_all_units)
	for u in _all_units:
		u.attacked.connect(_on_any_unit_attacked)
		u.unit_died.connect(_on_any_unit_died)
	turn_manager.start_battle()


# ──────────── UI：日志独立 + 鼠标穿透 ────────────
func _setup_battle_log_panel() -> void:
	if _battle_log_panel != null:
		return
	var ui_layer: CanvasLayer = $UI as CanvasLayer

	# ──── 根因修复 ────
	# 之前 reparent 整个 old_log_panel（PanelContainer），PanelContainer 会自动
	# 扩展到子节点的 minimum_size，无论外层用什么容器都挡不住它撑大。
	# 修复：只 reparent log_text（RichTextLabel），不 reparent PanelContainer。
	# RichTextLabel 的尺寸由 custom_minimum_size + fit_content 控制，不会撑破外层。

	var box := Panel.new()
	box.name = "BattleLog"
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.anchor_right = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = 8.0
	box.offset_top = 50.0
	box.offset_right = 296.0
	box.offset_bottom = 116.0    # 初始折叠：标题栏 + 2行文字
	box.custom_minimum_size = Vector2(0, 0)
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Panel 本身不拦截鼠标；内部 Button 由 _recursively_set_mouse_passthrough 保留 STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, 0.78)
	sb.border_color = Color(0.40, 0.34, 0.25, 0.85)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(box)

	# 内部 VBox：用绝对定位填充 Panel 内容区
	var inner := VBoxContainer.new()
	inner.anchor_left = 0.0
	inner.anchor_top = 0.0
	inner.anchor_right = 1.0
	inner.anchor_bottom = 1.0
	inner.offset_left = 8.0
	inner.offset_top = 6.0
	inner.offset_right = -8.0
	inner.offset_bottom = -6.0
	inner.add_theme_constant_override("separation", 4)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)

	# 战斗日志标题 + 展开收起按钮行
	var header_hbox := HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "战斗日志"
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	header_hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var log_toggle_btn := Button.new()
	log_toggle_btn.text = "展开 ▼"
	log_toggle_btn.add_theme_font_size_override("font_size", 9)
	log_toggle_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	log_toggle_btn.focus_mode = Control.FOCUS_NONE  # 禁止获得焦点，避免 Space/Enter 误触发
	header_hbox.add_child(log_toggle_btn)

	# ──── 日志 body（可折叠区域）────
	var log_body := VBoxContainer.new()
	log_body.name = "LogBody"
	log_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_body.add_theme_constant_override("separation", 2)
	log_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_body.visible = false   # 默认折叠
	inner.add_child(log_body)

	# ──── 只 reparent RichTextLabel，不 reparent PanelContainer ────
	var rt: RichTextLabel = unit_panel.log_text
	if rt and rt.get_parent():
		rt.get_parent().remove_child(rt)
		rt.add_theme_font_size_override("normal_font_size", 10)
		rt.add_theme_font_size_override("bold_font_size", 10)
		rt.add_theme_font_size_override("italics_font_size", 10)
		rt.add_theme_font_size_override("bold_italics_font_size", 10)
		rt.add_theme_font_size_override("mono_font_size", 10)
		rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.scroll_following = true
		rt.fit_content = false
		rt.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 日志文本 + 右侧滚动按钮列，放入 HBox
		var log_hbox := HBoxContainer.new()
		log_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_hbox.add_theme_constant_override("separation", 2)
		log_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_body.add_child(log_hbox)
		log_hbox.add_child(rt)
		_log_richtext = rt

		# 右侧滚动按钮列
		var scroll_col := VBoxContainer.new()
		scroll_col.add_theme_constant_override("separation", 2)
		scroll_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_hbox.add_child(scroll_col)

		var btn_up := Button.new()
		btn_up.text = "▲"
		btn_up.add_theme_font_size_override("font_size", 9)
		btn_up.custom_minimum_size = Vector2(22, 22)
		btn_up.focus_mode = Control.FOCUS_NONE
		btn_up.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_up.pressed.connect(func():
			rt.scroll_following = false
			var vscroll: VScrollBar = rt.get_v_scroll_bar()
			if vscroll:
				vscroll.value -= vscroll.page * 0.4
		)
		scroll_col.add_child(btn_up)

		var spacer_scroll := Control.new()
		spacer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll_col.add_child(spacer_scroll)

		var btn_down := Button.new()
		btn_down.text = "▼"
		btn_down.add_theme_font_size_override("font_size", 9)
		btn_down.custom_minimum_size = Vector2(22, 22)
		btn_down.focus_mode = Control.FOCUS_NONE
		btn_down.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn_down.pressed.connect(func():
			var vscroll: VScrollBar = rt.get_v_scroll_bar()
			if vscroll:
				var at_bottom: bool = is_equal_approx(vscroll.value, vscroll.max_value - vscroll.page)
				if at_bottom:
					rt.scroll_following = true  # 到底了恢复自动滚动
				else:
					rt.scroll_following = false
					vscroll.value += vscroll.page * 0.4
		)
		scroll_col.add_child(btn_down)

		# 命名按钮并绑定全局状态
		log_toggle_btn.name = "LogToggleBtn"
		log_toggle_btn.pressed.connect(toggle_battle_log)

	# 隐藏 SidePanel 中残留的空 LogPanel（避免空壳占位）
	var old_log_panel: PanelContainer = unit_panel.log_panel
	if old_log_panel:
		old_log_panel.visible = false

	# 独立 hint label，放入 body 一起折叠
	var hint := Label.new()
	hint.name = "LogHint"
	hint.text = "左键：选中/移动/攻击  空格：结束回合  R：重开  ESC：取消\n滚轮：缩放  Cmd+0：复位  WASD/方向键：平移  中键拖拽：平移"
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_body.add_child(hint)
	_log_hint_label = hint

	_battle_log_panel = box


## 切换战斗日志展开/折叠（仅响应用户点击，与单位/回合完全无关）
func toggle_battle_log() -> void:
	_log_expanded = not _log_expanded
	_apply_log_expanded_state()


## 根据 _log_expanded 切换 Panel 高度 + 内容可见性
## 只从 toggle_battle_log 调用，不与任何单位/回合逻辑绑定
func _apply_log_expanded_state() -> void:
	if _battle_log_panel == null:
		return
	var body: Node = _battle_log_panel.find_child("LogBody", true, false)
	var btn: Button = _battle_log_panel.find_child("LogToggleBtn", true, false) as Button
	if _log_expanded:
		if body:
			body.visible = true
		_battle_log_panel.offset_bottom = 260.0   # 展开高度：210px 内容区
		if btn:
			btn.text = "收起 ▲"
	else:
		if body:
			body.visible = false
		_battle_log_panel.offset_bottom = 116.0   # 折叠高度：标题栏 + 2行文字
		if btn:
			btn.text = "展开 ▼"


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
	if action_id == "wait":
		var unit: Unit = turn_manager.get_current_unit()
		if unit and unit.stats:
			var is_second_wait: bool = turn_manager.has_method("has_waited") and turn_manager.call("has_waited", unit)
			if is_second_wait:
				_log_hint("[color=#CC4444]【结束回合】%s 选择结束回合，剩余 AP 作废[/color]" % unit.stats.unit_name)
			else:
				_log_hint("[color=#CCAA44]【等待】%s 选择等待，将在本回合最后行动[/color]" % unit.stats.unit_name)
			print("[BattleScene] 等待触发：单位=%s, AP=%d, can_wait=%s, 第二次=%s" % [
				unit.stats.unit_name, unit.stats.ap,
				turn_manager.can_wait() if turn_manager.has_method("can_wait") else "N/A",
				str(is_second_wait)])
		# 先输出日志，再执行等待（wait_current 会立即切换到下一个单位）
		var wait_ok: bool = turn_manager.wait_current()
		print("[BattleScene] wait_current 返回：%s" % str(wait_ok))
		return
	# G5：先发制人激活
	if action_id == "preempt":
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
	if action_id.begins_with("attack_"):
		var mode: String = action_id.substr("attack_".length())
		_pending_attack_mode = mode
		_log_hint("[color=#FFD86B]【%s】[/color]鼠标点击红色高亮的敌人触发攻击。" % _mode_chinese(mode))
		return
	if action_id.begins_with("skill_"):
		_log_hint("[color=#888888]【技能】尚未开放（Phase 2.5 接入职业能力）[/color]")
		return
	if action_id.begins_with("item_"):
		_log_hint("[color=#888888]【道具】尚未开放（Phase 3 接入背包）[/color]")
		return


func _mode_chinese(mode: String) -> String:
	match mode:
		"slash":  return "斩击"
		"pierce": return "穿刺"
		"crush":  return "重击"
		"ranged": return "远射"
		_:        return mode


## 简短提示：直接写到独立战斗日志（不经过 SidePanel）
func _log_hint(bbcode: String) -> void:
	if _log_richtext:
		_log_richtext.append_text(bbcode + "\n")


## 更新日志面板 hint 文本（CombatMenu 等外部调用，不走 SidePanel）
func set_log_hint(text: String) -> void:
	if _log_hint_label:
		_log_hint_label.text = text


## 让所有 UI 容器不拦截鼠标，确保滚轮缩放、中键拖拽能传到 _unhandled_input
func _make_ui_passthrough() -> void:
	# TopBar 整条不拦事件（头像本身也是装饰，没有交互）
	if top_bar:
		top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_recursively_set_mouse_passthrough(top_bar)
	# 底部行动条同理
	if _bottom_bar_panel:
		_recursively_set_mouse_passthrough(_bottom_bar_panel)
	# 左上角日志容器同理
	if _battle_log_panel:
		_recursively_set_mouse_passthrough(_battle_log_panel)
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
	# 友方 2 人
	_create_unit("阿尔伯特", 0, Vector2i(-3, 1), "saber", "leather_armor", {"hp": 65, "melee": 60, "def": 18, "init": 200})
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
	if _ai_acting:
		return
	var current: Unit = turn_manager.get_current_unit()
	if current == null or current.get_faction() != 0:
		return

	var clicked_unit: Unit = hex_grid.get_occupant(axial)

	# 点到敌方 → 尝试攻击
	if clicked_unit and clicked_unit.get_faction() != current.get_faction():
		if current.weapon == null:
			return  # 没武器无法攻击
		if HexCoord.distance(current.axial_pos, axial) <= current.weapon.attack_range and current.stats.ap >= current.weapon.ap_cost:
			_player_attack(current, clicked_unit)
			return

	# 点到自己 → 重新选中（已选中）
	if clicked_unit == current:
		_select_unit(current)
		return

	# 点到空格 → 尝试移动
	if clicked_unit == null and _selected_unit == current:
		var path: Array[Vector2i] = hex_grid.find_path(current.axial_pos, axial, current.axial_pos, current.get_faction())
		@warning_ignore("integer_division")
		var max_steps: int = current.stats.ap / Unit.AP_PER_HEX
		if not path.is_empty() and path.size() <= max_steps:
			_player_move(current, path)


func _player_move(unit: Unit, path: Array[Vector2i]) -> void:
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
	_pending_attack_mode = ""  # 重置模式选择
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
	# 移动范围
	@warning_ignore("integer_division")
	var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
	var move_hexes: Array[Vector2i] = hex_grid.get_reachable(unit.axial_pos, max_steps, unit.get_faction())
	hex_grid.set_highlight_move(move_hexes)
	# 攻击范围
	var atk_range: int = unit.weapon.attack_range if unit.weapon else 1
	var atk_hexes: Array[Vector2i] = hex_grid.get_attack_targets(unit.axial_pos, atk_range, unit.get_faction())
	hex_grid.set_highlight_attack(atk_hexes)
	# 敌方 ZoC 威胁地图（仅友方选中时显示）
	if unit.get_faction() == 0:
		var enemy_faction: int = 1
		var zoc_cells: Array[Vector2i] = hex_grid.get_zoc_cells_of(enemy_faction)
		hex_grid.set_highlight_zoc(zoc_cells)


# 鼠标移到某格 → 实时预览路径与借机攻击触发点 + 单位浮层显隐
const TOOLTIP_HOVER_DELAY: float = 1.0    ## 悬停多久才弹出浮层（秒）
var _hover_unit: Unit = null
var _hover_started_at: float = 0.0


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
	if current.stats.ap < current.weapon.ap_cost:
		return null
	var d: int = HexCoord.distance(current.axial_pos, target.axial_pos)
	if d > current.weapon.attack_range:
		return null
	return current


func _on_hex_hovered(axial: Vector2i) -> void:
	# tooltip：悬停在角色身上 1s 后弹出
	# 但若 hover 的是当前轮到的玩家单位（CombatMenu 已显示该单位详情）→ 不再弹 tooltip
	var occ = hex_grid.get_occupant(axial)
	var current_unit: Unit = turn_manager.get_current_unit()
	if occ != null and occ.is_alive() and occ != current_unit:
		# 切换到不同单位 → 重置计时
		if occ != _hover_unit:
			# 发射前一个单位的 unhovered 信号
			if _hover_unit != null:
				unit_unhovered.emit(_hover_unit)
			# 更新悬停单位并发射 hovered 信号
			_hover_unit = occ
			unit_hovered.emit(_hover_unit)
			_hover_started_at = float(Time.get_ticks_msec()) * 0.001
			tooltip.hide_card()       # 离开旧目标先收起
		# 若该敌人正好是当前玩家单位的可攻击目标 → 立即弹出"攻击预览"浮层
		# （不等 1 秒延迟，瞄准时第一时间看到命中率与围攻加成）
		var atk_ctx: Unit = _attack_preview_attacker_for(occ)
		if atk_ctx != null:
			tooltip.show_for_attack(occ, atk_ctx, get_viewport().get_mouse_position())
	else:
		# 离开单位 → 发射 unhovered 信号
		if _hover_unit != null:
			unit_unhovered.emit(_hover_unit)
		_hover_unit = null
		_hover_started_at = 0.0
		tooltip.hide_card()

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
	# tooltip 延迟弹出 + 已弹出后跟随光标
	if tooltip:
		if tooltip.visible:
			tooltip.update_position(get_viewport().get_mouse_position())
		elif _hover_unit and _hover_unit.is_alive():
			var elapsed: float = float(Time.get_ticks_msec()) * 0.001 - _hover_started_at
			if elapsed >= TOOLTIP_HOVER_DELAY:
				tooltip.show_for(_hover_unit, get_viewport().get_mouse_position())
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
	if _log_richtext:
		_log_richtext.append_text(DamageSystem.format_attack_log(result) + "\n")
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
		target.play_hit_reaction(strength, did_hit)
	# 屏幕震动 + 整屏闪红（暴击 / 重击）
	if is_crit and did_hit:
		_shake_camera(0.30, 6.0)
		_flash_screen(Color(1.0, 0.2, 0.2, 0.35), 0.18)  # 暴击：明显红
	elif did_hit and hp_dmg >= 30:
		_shake_camera(0.15, 3.0)
		_flash_screen(Color(1.0, 0.4, 0.4, 0.18), 0.10)  # 重击：浅红

	# ──────────── 命中粒子 + 伤害飘字（与攻击结果联动） ────────────
	if target == null or effect_layer == null:
		return
	var pos: Vector2 = target.position
	var crit_intensity: float = 1.5 if is_crit else 1.0

	if not did_hit:
		# 未命中：灰字 MISS，无粒子
		DamageNumberScript.spawn(effect_layer, pos, "MISS", Color(0.75, 0.75, 0.75))
	elif hp_dmg > 0:
		# 见血：红色血溅 + 红字伤害
		HitEffectScript.spawn(effect_layer, pos, "blood", crit_intensity)
		var dmg_color: Color = Color(1.0, 0.85, 0.30) if is_crit else Color(1.0, 0.30, 0.30)
		var dmg_text: String = ("%d!" % hp_dmg) if is_crit else str(hp_dmg)
		DamageNumberScript.spawn(effect_layer, pos, dmg_text, dmg_color, is_crit)
	else:
		# 命中但未破防（纯破甲 / 0 伤）：黄色火花 + 浅蓝甲值字
		HitEffectScript.spawn(effect_layer, pos, "spark", 1.0)
		if armor_dmg > 0:
			DamageNumberScript.spawn(effect_layer, pos, "甲-%d" % armor_dmg,
				Color(0.70, 0.85, 1.00))


func _on_any_unit_died(unit: Unit) -> void:
	hex_grid.set_occupant(unit.axial_pos, null)
	unit.queue_redraw()
	if _log_richtext:
		_log_richtext.append_text("[color=#A03030]✦ %s 倒下[/color]\n" % unit.get_unit_name())
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
	_selected_unit = null
	_input_state = InputState.IDLE
	hex_grid.clear_highlights()


# ──────────── AI（评分式决策） ────────────
## 评分式：BattleAI 静态决策器返回 Plan，这里负责按 Plan 执行（移动 + 攻击 + 兜底结束回合）
## 注意：_ai_acting 由 _on_turn_started 统一管理，此处不再设置
func _run_ai_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.35).timeout
	if not unit.is_alive():
		# 开局前已死（极端情况），确保 TurnManager 推进
		if turn_manager.get_current_unit() == unit:
			unit.end_turn()
		return

	# 主循环：可能"移动+攻击"后 AP 还够再打 1 次，所以决策最多重试 3 次
	var safety: int = 3
	while safety > 0 and unit.is_alive():
		safety -= 1
		var plan: Dictionary = BattleAI.decide(unit, _all_units, hex_grid)
		var path_raw: Variant = plan.get("path", null)
		var path: Array[Vector2i] = []
		if path_raw != null and path_raw is Array:
			for p in path_raw:
				if p is Vector2i:
					path.append(p)
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

	# 活着 → 正常结束回合；死了但仍是 current → 也调 end_turn 推进调度
	# （_on_unit_died 也会推进，但 end_turn 的 _on_unit_action_completed 会安全跳过）
	if unit.is_alive() or turn_manager.get_current_unit() == unit:
		unit.end_turn()


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
			_clear_selection()
		elif event.keycode == KEY_SPACE:
			# 空格：跳过当前回合
			var cur: Unit = turn_manager.get_current_unit()
			if cur and cur.get_faction() == 0 and not _ai_acting:
				cur.end_turn()
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
