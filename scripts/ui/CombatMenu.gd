extends PanelContainer
class_name CombatMenu
##
## CombatMenu.gd — 战斗 UI（屏幕底部居中，平铺式 / DOS2 风）
##
## 布局：
##   ┌────────────────────────────────────────────────────────┐
##   │ [头像] | [1斩][2刺][3瞄][4暴][5穿] | [P]详 [I]物 [Q]待 │
##   └────────────────────────────────────────────────────────┘
##                                                          ↑
##   按 P 切换：在操作栏上方弹出详情面板（HP/AP/头甲/身甲/气力/速度/装备）
##
## 设计要点：
## - 头像：当前操控单位的胸像（Unit.get_portrait_texture），切单位即换
## - 数字键 1~9, 0 仅绑定攻击/技能（动态构建于 weapon + abilities）
## - 固定字母键（不变位）：P=详情、I=道具、Q=等待
## - 详情默认隐藏；按 P 切换；不与 wsad/相机平移冲突
## - Esc：先关详情；详情已关时不消费让 BattleScene 接管
## - 信号 action_selected(action_id)：BattleScene 路由到具体行为
##

signal action_selected(action_id: String)

# ──── G5 新增信号（Hover 预览） ────
signal ability_preview_requested(ability_id: String, unit: Unit)
signal ability_preview_cancelled()

# ──────────── 视觉常量 ────────────
const BUTTON_W: int = 60
const BUTTON_H: int = 50
const BUTTON_GAP: int = 4
const SCREEN_MARGIN: int = 12
const PORTRAIT_SIZE: int = 50               ## 头像方块尺寸（与按钮高度对齐）
const FIXED_BUTTON_W: int = 56              ## 固定字母键 chip 宽度

const BAR_HEIGHT: int = 8
const BAR_HP_COLOR: Color = Color(0.78, 0.22, 0.22)
const BAR_AP_COLOR: Color = Color(0.92, 0.78, 0.20)
const BAR_HEAD_COLOR: Color = Color(0.55, 0.55, 0.55)
const BAR_BODY_COLOR: Color = Color(0.45, 0.55, 0.85)
const BAR_FATIGUE_COLOR: Color = Color(0.65, 0.40, 0.20)

# 数字键映射（1~9 + 0）
const NUMBER_KEYS: Array = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5,
	KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
]

# 动作类型
const KIND_ATTACK := "attack"
const KIND_SKILL := "skill"
const KIND_WAIT := "wait"
const KIND_ITEM := "item"

# 武器伤害类型 → 短标签（一字）
const MODE_LABEL: Dictionary = {
	"slash": "斩",
	"pierce": "刺",
	"crush": "砸",
	"ranged": "射",
}
const MODE_FULL: Dictionary = {
	"slash": "斩击",
	"pierce": "穿刺",
	"crush": "重击",
	"ranged": "远射",
}

# ──────────── 私有状态 ────────────
var _turn_manager: Node = null
var _current_unit: Unit = null
var _action_list: Array = []          ## 当前可用动作列表（仅攻击 + 技能；动态重建于 show_for_unit）
var _action_buttons: Array = []       ## Button 引用，下标对应 _action_list

var _action_panel: PanelContainer = null   ## 操作栏面板（chip 行；宽度随技能数变化）
var _hud_panel: PanelContainer = null      ## HUD 面板（独立居中，宽度恒定）
var _hud_row: Control = null               ## HUD 三层垂直容器（常驻）
var _action_row: HBoxContainer = null      ## 平铺按钮容器（外层）
var _portrait_rect: TextureRect = null     ## 当前单位头像
var _portrait_name_label: Label = null     ## 头像下方姓名（备用，可省略）
var _dynamic_row: HBoxContainer = null     ## 攻击/技能 chip 容器（中段，动态重建）
var _preempt_btn: Button = null            ## 固定：先发制人 [E]（G5）
var _wait_btn: Button = null               ## 固定：等待 [Q]
var _item_btn: Button = null               ## 固定：道具 [I]
var _detail_btn: Button = null             ## 固定：详情 [P]
var _detail_panel: PanelContainer = null   ## 详情面板（默认隐藏）
var _detail_visible: bool = false

# HUD 控件引用（操作栏顶部常驻显示）
var _hud_hp_bar: ProgressBar = null
var _hud_hp_value: Label = null
var _hud_head_bar: ProgressBar = null
var _hud_head_value: Label = null
var _hud_body_bar: ProgressBar = null
var _hud_body_value: Label = null
var _hud_fatigue_bar: ProgressBar = null
var _hud_fatigue_value: Label = null
var _hud_ap_dots: Label = null             ## AP 钻石点：◆◆◆◆◆◆◇◇◇

# 详情控件引用
var _name_label: Label = null
var _faction_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_value: Label = null
var _ap_bar: ProgressBar = null
var _ap_value: Label = null
var _head_bar: ProgressBar = null
var _head_value: Label = null
var _body_bar: ProgressBar = null
var _body_value: Label = null
var _fatigue_bar: ProgressBar = null
var _fatigue_value: Label = null
var _speed_label: Label = null
var _weapon_label: Label = null
var _armor_label: Label = null


func _ready() -> void:
	# 修复：主容器不拦截鼠标，只由内部的 HUD 面板、详情面板和操作栏拦截。防止展开详情后遮挡3D网格点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 让外层 PanelContainer 不绘制背景（透明）；详情/操作栏各自绘
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	add_theme_stylebox_override("panel", sb)

	# 垂直布局：上 详情（可隐）/ 下 操作栏
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_END
	add_child(vb)

	# 详情面板（默认隐藏）
	_detail_panel = PanelContainer.new()
	_apply_panel_style(_detail_panel, Color(0.62, 0.50, 0.32, 0.95))
	_detail_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_panel.add_child(_build_detail_section())
	_detail_panel.visible = false
	vb.add_child(_detail_panel)

	# 操作栏（默认显示）— HUD 与 chip 拆成两个独立 panel，各自居中
	# HUD 面板（永远屏幕底部居中，与 chip 长度解耦；无外框背景）
	_hud_panel = PanelContainer.new()
	var hud_sb := StyleBoxFlat.new()
	hud_sb.bg_color = Color(0, 0, 0, 0)
	_hud_panel.add_theme_stylebox_override("panel", hud_sb)
	_hud_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hud_row = _build_hud_section()
	_hud_panel.add_child(_hud_row)
	vb.add_child(_hud_panel)

	# Chip 操作栏（宽度随技能数动态变化，独立居中）
	_action_panel = PanelContainer.new()
	_apply_panel_style(_action_panel, Color(0.62, 0.50, 0.32, 0.95))
	_action_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", BUTTON_GAP)
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_panel.add_child(_action_row)
	_build_action_bar_layout()
	vb.add_child(_action_panel)

	visible = false
	set_process(true)


## 操作栏一次性骨架：[头像] | [固定字母 chip 区] | [动态数字 chip 区]
## 后续 show_for_unit 时只重建动态区
func _build_action_bar_layout() -> void:
	# 1) 头像
	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action_row.add_child(_portrait_rect)

	# 2) 分隔
	_action_row.add_child(_make_vsep())

	# 3) 固定字母 chip 区（先发制人 / 详情 / 道具 / 等待）
	# G5：先发制人（技能 chip，蓝色边框）
	_preempt_btn = _make_fixed_chip("先", "E", "", Color(0.30, 0.55, 0.85))
	_preempt_btn.mouse_entered.connect(func():
		if _current_unit and not _preempt_btn.disabled:
			# 动态计算下大回合行动顺位
			var order_text: String = ""
			var battle_scene = get_node_or_null("/root/BattleScene")
			if battle_scene and battle_scene.turn_manager:
				var next_round_queue = battle_scene.turn_manager.get_next_round_queue()
				var preview_entries = TurnScheduler.preview_with_preempt_bonus(next_round_queue, _current_unit, 40, 1)
				var preview_round_1: Array[Unit] = []
				for entry in preview_entries:
					var entry_unit: Unit = null
					if entry is Dictionary:
						entry_unit = entry.get("unit")
					elif "unit" in entry:
						entry_unit = entry.unit
					if entry_unit != null:
						preview_round_1.append(entry_unit)
				
				var next_order_index = preview_round_1.find(_current_unit)
				if next_order_index != -1:
					order_text = "\n【先发制人预演】下回合将在第 %d 顺位行动" % (next_order_index + 1)
			
			# 还原原生 Hover 提示框并动态追加预测结果
			_preempt_btn.tooltip_text = "先发制人：+40 Init（下回合），消耗 1 AP + 20 气力" + order_text
			if battle_scene and battle_scene.has_method("set_log_hint"):
				battle_scene.set_log_hint("先发制人：+40 Init（下回合），消耗 1 AP + 20 气力" + order_text)
			
			# 预演不要改动行动条（TopBar）的外显样式，故不发出预览信号给 TopBar
			# ability_preview_requested.emit("preempt", _current_unit)
	)
	_preempt_btn.mouse_exited.connect(func():
		var battle_scene = get_node_or_null("/root/BattleScene")
		if battle_scene and battle_scene.has_method("set_log_hint"):
			battle_scene.set_log_hint("左键：选中/移动/攻击  空格：结束回合  R：重开  ESC：取消\n滚轮：缩放  Cmd+0：复位  WASD/方向键：平移  中键拖拽：平移")
		# ability_preview_cancelled.emit()
	)
	_preempt_btn.pressed.connect(func():
		action_selected.emit("preempt")
	)
	_action_row.add_child(_preempt_btn)

	_detail_btn = _make_fixed_chip("详", "P", "详情面板（切换显示）", Color(0.55, 0.55, 0.85))
	_detail_btn.pressed.connect(_toggle_detail)
	_action_row.add_child(_detail_btn)

	_item_btn = _make_fixed_chip("物", "I", "道具（Phase 3+）", Color(0.45, 0.65, 0.40))
	_item_btn.disabled = true
	_item_btn.pressed.connect(func(): action_selected.emit("item_placeholder"))
	_action_row.add_child(_item_btn)

	_wait_btn = _make_fixed_chip("待", "Q", "等待 — 排到本回合队尾（不消耗 AP）", Color(0.85, 0.78, 0.30))
	_wait_btn.pressed.connect(_invoke_wait)
	_action_row.add_child(_wait_btn)

	# 4) 分隔
	_action_row.add_child(_make_vsep())

	# 5) 动态 chip 区（攻击 / 技能；数字键 1~9 直绑）
	_dynamic_row = HBoxContainer.new()
	_dynamic_row.add_theme_constant_override("separation", BUTTON_GAP)
	_action_row.add_child(_dynamic_row)


func _make_vsep() -> Control:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(2, BUTTON_H)
	return sep


# ──────────── HUD（DOS2 风常驻数值条，三层中心对称结构）────────────
##  Layer 1（最上）：头甲 | 身甲（同宽细条）
##  Layer 2（中）  ：HP   | 气力（同宽粗条）
##  Layer 3（最下）：AP 钻石点（居中）
##  无文字标签，鼠标 hover 显示 tooltip

const HUD_ARMOR_BAR_HEIGHT: int = 4
const HUD_MAIN_BAR_HEIGHT: int = 10
const HUD_BAR_W: int = 200             ## 所有条同宽，确保中心对称
const HUD_VALUE_W: int = 52            ## 数值文本宽度

## HUD 三层 VBox（中心对称：数值 → 条 || 条 → 数值）
func _build_hud_section() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)

	# Layer 1: [数值] 头甲 ════ ║ ════ 身甲 [数值]
	var armor_row := HBoxContainer.new()
	armor_row.add_theme_constant_override("separation", 24)
	armor_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_head_bar = ProgressBar.new()
	_hud_head_value = Label.new()
	armor_row.add_child(_make_hud_unit("头甲", _hud_head_bar, _hud_head_value, BAR_HEAD_COLOR, HUD_BAR_W, HUD_ARMOR_BAR_HEIGHT, true))
	_hud_body_bar = ProgressBar.new()
	_hud_body_value = Label.new()
	armor_row.add_child(_make_hud_unit("身甲", _hud_body_bar, _hud_body_value, BAR_BODY_COLOR, HUD_BAR_W, HUD_ARMOR_BAR_HEIGHT, false))
	vb.add_child(armor_row)

	# Layer 2: [数值] HP ════ ║ ════ 气力 [数值]
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 24)
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_hp_bar = ProgressBar.new()
	_hud_hp_value = Label.new()
	main_row.add_child(_make_hud_unit("HP", _hud_hp_bar, _hud_hp_value, BAR_HP_COLOR, HUD_BAR_W, HUD_MAIN_BAR_HEIGHT, true))
	_hud_fatigue_bar = ProgressBar.new()
	_hud_fatigue_value = Label.new()
	main_row.add_child(_make_hud_unit("气力", _hud_fatigue_bar, _hud_fatigue_value, BAR_FATIGUE_COLOR, HUD_BAR_W, HUD_MAIN_BAR_HEIGHT, false))
	vb.add_child(main_row)

	# Layer 3: AP 钻石点（居中，无数字）
	var ap_row := HBoxContainer.new()
	ap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ap_row.add_child(_make_ap_unit())
	vb.add_child(ap_row)

	return vb


## HUD 单元：mirror=true → [数值][条]（左侧用，数值靠右对齐）
##           mirror=false → [条][数值]（右侧用，数值靠左对齐）
func _make_hud_unit(tooltip: String, bar: ProgressBar, value_label: Label, color: Color, bar_w: int, bar_h: int, mirror: bool) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.tooltip_text = tooltip

	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(bar_w, bar_h)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = tooltip
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.05, 1.0)
	bg.border_color = Color(0.30, 0.26, 0.20)
	bg.border_width_left = 1
	bg.border_width_right = 1
	bg.border_width_top = 1
	bg.border_width_bottom = 1
	bg.corner_radius_top_left = 1
	bg.corner_radius_top_right = 1
	bg.corner_radius_bottom_left = 1
	bg.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.corner_radius_top_left = 1
	fg.corner_radius_top_right = 1
	fg.corner_radius_bottom_left = 1
	fg.corner_radius_bottom_right = 1
	bar.add_theme_stylebox_override("fill", fg)

	value_label.custom_minimum_size = Vector2(HUD_VALUE_W, 0)
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	value_label.tooltip_text = tooltip

	if mirror:
		# 左侧：[数值靠右][条]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(value_label)
		hb.add_child(bar)
	else:
		# 右侧：[条][数值靠左]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hb.add_child(bar)
		hb.add_child(value_label)
	return hb


## AP 钻石点（居中、无数字）
func _make_ap_unit() -> Control:
	_hud_ap_dots = Label.new()
	_hud_ap_dots.add_theme_font_size_override("font_size", 12)
	_hud_ap_dots.add_theme_color_override("font_color", Color(0.95, 0.85, 0.30))
	_hud_ap_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hud_ap_dots.tooltip_text = "AP（行动点）"
	_hud_ap_dots.mouse_filter = Control.MOUSE_FILTER_PASS
	return _hud_ap_dots


## 每帧刷新 HUD（HP/头甲/身甲/气力/AP）
func _refresh_hud() -> void:
	if _current_unit == null or _current_unit.stats == null:
		return
	var s: Stats = _current_unit.stats
	_hud_hp_bar.max_value = max(1, s.max_hp);            _hud_hp_bar.value = s.hp
	_hud_hp_value.text = "%d/%d" % [s.hp, s.max_hp]
	_hud_head_bar.max_value = max(1, s.max_head_armor);  _hud_head_bar.value = s.head_armor
	_hud_head_value.text = "%d/%d" % [s.head_armor, s.max_head_armor]
	_hud_body_bar.max_value = max(1, s.max_body_armor);  _hud_body_bar.value = s.body_armor
	_hud_body_value.text = "%d/%d" % [s.body_armor, s.max_body_armor]
	_hud_fatigue_bar.max_value = max(1, s.max_stamina)
	_hud_fatigue_bar.value = max(0, s.max_stamina - s.fatigue)
	_hud_fatigue_value.text = "%d/%d" % [max(0, s.max_stamina - s.fatigue), s.max_stamina]
	# AP：每点画一个钻石（满 ◆ / 空 ◇），无数字
	var ap: int = s.ap
	var max_ap: int = s.max_ap
	var dots := ""
	for i in range(max_ap):
		dots += "◆" if i < ap else "◇"
	_hud_ap_dots.text = dots


# ──────────── 对外接口 ────────────

func bind_turn_manager(tm: Node) -> void:
	_turn_manager = tm


func show_for_unit(unit: Unit) -> void:
	_current_unit = unit
	visible = true
	_rebuild_action_list()
	_refresh_hud()
	_refresh_unit_info()
	_refresh_action_states()


func hide_menu() -> void:
	_current_unit = null
	visible = false
	_set_detail_visible(false)


# ──────────── 动作列表（数据驱动）────────────

## 根据当前单位 + 武器 + 已实装能力构建动作 chip 列表（仅 attack + skill）
## 等待/道具/详情 是固定按键，不进 list
func _rebuild_action_list() -> void:
	_action_list.clear()
	# 清空旧动态按钮
	for c in _dynamic_row.get_children():
		c.queue_free()
	_action_buttons.clear()

	# 头像同步
	if _current_unit != null and _portrait_rect != null:
		_portrait_rect.texture = _current_unit.get_portrait_texture()
		_portrait_rect.tooltip_text = _current_unit.stats.unit_name if _current_unit.stats else ""

	if _current_unit == null:
		return

	var u: Unit = _current_unit
	var ap: int = u.stats.ap if u.stats else 0
	var weapon_ap: int = u.weapon.ap_cost if u.weapon else 999

	# 1) 武器攻击模式（每个 mode 一个 chip）
	if u.weapon != null:
		var modes: Array = u.weapon.attack_modes if not u.weapon.attack_modes.is_empty() else [u.weapon.damage_type]
		for mode in modes:
			var short: String = MODE_LABEL.get(mode, mode.substr(0, 1))
			var full: String = MODE_FULL.get(mode, mode)
			_action_list.append({
				"id": "attack_" + str(mode),
				"label": short,
				"tooltip": "%s (%s) — AP %d" % [full, u.weapon.display_name, weapon_ap],
				"kind": KIND_ATTACK,
				"locked": ap < weapon_ap,
				"data": {"mode": mode},
			})

	# 2) 占位技能（Phase 2.5+ 接入 JobClass.abilities 后改）
	_action_list.append({"id": "skill_aim_head",  "label": "瞄", "tooltip": "瞄头（Phase 2.5）",     "kind": KIND_SKILL, "locked": true, "data": {}})
	_action_list.append({"id": "skill_all_out",   "label": "暴", "tooltip": "全力一击（Phase 2.5）", "kind": KIND_SKILL, "locked": true, "data": {}})
	_action_list.append({"id": "skill_puncture",  "label": "穿", "tooltip": "穿心刺（Phase 2.5）",   "kind": KIND_SKILL, "locked": true, "data": {}})

	# 数字键标号（1..9, 第10项 = 0）
	for i in range(_action_list.size()):
		var act: Dictionary = _action_list[i]
		if i < NUMBER_KEYS.size():
			act["key"] = "%d" % ((i + 1) % 10)
		else:
			act["key"] = ""
		var btn := _make_chip(act)
		_dynamic_row.add_child(btn)
		_action_buttons.append(btn)


func _refresh_action_states() -> void:
	if _current_unit == null:
		return
	var u: Unit = _current_unit
	var ap: int = u.stats.ap if u.stats else 0
	# 动态 chip：仅 attack 类需要根据 AP 重判
	for i in range(_action_list.size()):
		var act: Dictionary = _action_list[i]
		var btn: Button = _action_buttons[i]
		var locked: bool = act.get("locked", false)
		if act["kind"] == KIND_ATTACK:
			var weapon_ap: int = u.weapon.ap_cost if u.weapon else 999
			locked = (ap < weapon_ap)
			act["locked"] = locked
		btn.disabled = locked
	# 固定按钮：先发制人（G5）
	if _preempt_btn != null:
		var can_preempt: bool = false
		if u.stats and ap >= 1:
			var fatigue_cost: int = 20
			if u.is_wearing_heavy_armor():
				fatigue_cost = int(20 * 1.6)
			can_preempt = (u.stats.fatigue + fatigue_cost <= u.stats.max_stamina)
		_preempt_btn.disabled = not can_preempt
	# 固定按钮：等待（已等待过 → tooltip 改为"结束回合"）
	if _wait_btn != null:
		var can_wait: bool = _turn_manager != null and _turn_manager.has_method("can_wait") and _turn_manager.call("can_wait")
		_wait_btn.disabled = not can_wait
		if _turn_manager != null and _turn_manager.has_method("has_waited") and _current_unit and _turn_manager.call("has_waited", _current_unit):
			_wait_btn.tooltip_text = "等待 — 结束回合（放弃剩余 AP）"
		else:
			_wait_btn.tooltip_text = "等待 — 排到本回合队尾（不消耗 AP）"


# ──────────── 详情面板 ────────────

func _set_detail_visible(v: bool) -> void:
	_detail_visible = v
	_detail_panel.visible = v


func _refresh_unit_info() -> void:
	if not _detail_visible:
		return  # 详情隐藏时不更新（节省每帧成本）
	if _current_unit == null or _current_unit.stats == null:
		return
	var s: Stats = _current_unit.stats
	_name_label.text = s.unit_name
	_faction_label.text = "[友方]" if _current_unit.get_faction() == 0 else "[敌方]"
	_hp_bar.max_value = max(1, s.max_hp);            _hp_bar.value = s.hp
	_hp_value.text = "%d/%d" % [s.hp, s.max_hp]
	_ap_bar.max_value = max(1, s.max_ap);            _ap_bar.value = s.ap
	_ap_value.text = "%d/%d" % [s.ap, s.max_ap]
	_head_bar.max_value = max(1, s.max_head_armor);  _head_bar.value = s.head_armor
	_head_value.text = "%d/%d" % [s.head_armor, s.max_head_armor]
	_body_bar.max_value = max(1, s.max_body_armor);  _body_bar.value = s.body_armor
	_body_value.text = "%d/%d" % [s.body_armor, s.max_body_armor]
	_fatigue_bar.max_value = max(1, s.max_stamina)
	_fatigue_bar.value = max(0, s.max_stamina - s.fatigue)
	_fatigue_value.text = "%d/%d" % [max(0, s.max_stamina - s.fatigue), s.max_stamina]
	var aw: int = _current_unit.armor.weight if _current_unit.armor else 0
	var ww: int = _current_unit.weapon.weight if _current_unit.weapon else 0
	var eff_init: int = s.effective_initiative(aw, ww)
	_speed_label.text = "速度 %d (基础 %d − 疲劳 %d)" % [eff_init, s.base_initiative, s.fatigue]
	if _current_unit.weapon != null:
		var w: WeaponData = _current_unit.weapon
		var modes: String = ",".join(w.attack_modes) if not w.attack_modes.is_empty() else w.damage_type
		_weapon_label.text = "武器：%s (base %d / wt %d / %s / AP %d)" % [w.display_name, w.damage_base, w.weight, modes, w.ap_cost]
	else:
		_weapon_label.text = "武器：（无）"
	if _current_unit.armor != null:
		var a: ArmorData = _current_unit.armor
		_armor_label.text = "护甲：%s (头%d 身%d 重%d)" % [a.display_name, a.head_armor, a.body_armor, a.weight]
	else:
		_armor_label.text = "护甲：（无）"


# ──────────── 屏幕定位 ────────────

func _process(_delta: float) -> void:
	if visible:
		_update_screen_position()
		if _current_unit != null and _current_unit.is_alive():
			_refresh_hud()
			_refresh_unit_info()
			_refresh_action_states()
			_refresh_action_states()


## 固定到屏幕底部居中
func _update_screen_position() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var sz: Vector2 = size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = get_combined_minimum_size()
	position = Vector2((vp_size.x - sz.x) * 0.5, vp_size.y - sz.y - SCREEN_MARGIN)


# ──────────── 输入处理 ────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or _current_unit == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ke: InputEventKey = event as InputEventKey

	# 固定字母键
	# G5：E 键触发先发制人预览
	if ke.keycode == KEY_E:
		if _current_unit:
			ability_preview_requested.emit("preempt", _current_unit)
		get_viewport().set_input_as_handled()
		return

	if ke.keycode == KEY_P:
		_toggle_detail()
		get_viewport().set_input_as_handled()
		return
	if ke.keycode == KEY_I:
		# 道具占位
		if not _item_btn.disabled:
			action_selected.emit("item_placeholder")
		get_viewport().set_input_as_handled()
		return
	if ke.keycode == KEY_Q:
		_invoke_wait()
		get_viewport().set_input_as_handled()
		return

	# Esc：先关详情；详情已关时让 BattleScene 接管（不消费）
	if ke.keycode == KEY_ESCAPE:
		if _detail_visible:
			_set_detail_visible(false)
			get_viewport().set_input_as_handled()
		return

	# 数字键 1~9 / 0 → 触发对应 chip（仅 attack/skill）
	var idx: int = NUMBER_KEYS.find(ke.keycode)
	if idx == -1:
		return
	if idx >= _action_list.size():
		return
	get_viewport().set_input_as_handled()
	_invoke_action(idx)


## 由数字键或鼠标点击触发（仅 attack / skill）
func _invoke_action(idx: int) -> void:
	if idx < 0 or idx >= _action_list.size():
		return
	var act: Dictionary = _action_list[idx]
	if act.get("locked", false):
		return
	# 攻击/技能 → 把 action_id 抛给 BattleScene 路由
	action_selected.emit(act["id"])


## 等待：通过 action_selected 信号通知 BattleScene 处理（统一路由 + 日志输出）
func _invoke_wait() -> void:
	if _turn_manager == null:
		print("[CombatMenu] _invoke_wait: _turn_manager 为空")
		return
	var cw: bool = _turn_manager.has_method("can_wait") and _turn_manager.call("can_wait")
	print("[CombatMenu] _invoke_wait: can_wait=%s, visible=%s, _current_unit=%s" % [
		str(cw), str(visible), _current_unit.get_unit_name() if _current_unit else "null"])
	if not cw:
		return
	action_selected.emit("wait")
	_refresh_action_states()


## 详情切换
func _toggle_detail() -> void:
	_set_detail_visible(not _detail_visible)
	if _detail_visible:
		_refresh_unit_info()


# ──────────── UI 构建 ────────────

func _apply_panel_style(panel: PanelContainer, border: Color) -> void:
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # 修复：子面板显式拦截点击，配合父级 IGNORE 达到局部高精点击拦截
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.06, 0.94)
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	panel.z_index = 8


## 平铺 chip：60×50 紧凑方块，上行大字 + 下行 [N] 数字
func _make_chip(act: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	var key_str: String = act.get("key", "")
	if key_str != "":
		btn.text = "%s\n[%s]" % [act["label"], key_str]
	else:
		btn.text = act["label"]
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.55))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.30))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.38))
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = act.get("locked", false)
	btn.tooltip_text = act.get("tooltip", "")
	# kind 染色边框（视觉分组）
	var border_color: Color = Color(0.55, 0.45, 0.30)
	match act["kind"]:
		KIND_ATTACK: border_color = Color(0.85, 0.30, 0.25)   # 红：攻击
		KIND_SKILL:  border_color = Color(0.30, 0.55, 0.85)   # 蓝：技能
		KIND_WAIT:   border_color = Color(0.85, 0.78, 0.30)   # 黄：等待
		KIND_ITEM:   border_color = Color(0.45, 0.65, 0.40)   # 绿：道具

	for state in ["normal", "hover", "pressed", "disabled"]:
		var ssb := StyleBoxFlat.new()
		match state:
			"normal":
				ssb.bg_color = Color(0.14, 0.12, 0.10, 0.95)
				ssb.border_color = border_color
			"hover":
				ssb.bg_color = Color(0.22, 0.18, 0.13, 0.98)
				ssb.border_color = border_color.lightened(0.25)
			"pressed":
				ssb.bg_color = Color(0.30, 0.22, 0.12, 1.0)
				ssb.border_color = border_color.lightened(0.45)
			"disabled":
				ssb.bg_color = Color(0.10, 0.09, 0.08, 0.85)
				ssb.border_color = Color(0.30, 0.27, 0.22)
		ssb.border_width_left = 1
		ssb.border_width_right = 1
		ssb.border_width_top = 1
		ssb.border_width_bottom = 1
		ssb.corner_radius_top_left = 4
		ssb.corner_radius_top_right = 4
		ssb.corner_radius_bottom_left = 4
		ssb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override(state, ssb)

	# 闭包捕获索引
	var captured_id: String = act["id"]
	btn.pressed.connect(func():
		# 通过 id 反查索引（rebuild 时 idx 稳定，但 list 重建后引用失效，改用 id 反查）
		for i in range(_action_list.size()):
			if _action_list[i]["id"] == captured_id:
				_invoke_action(i)
				return
	)

	# ──── G5 新增：Hover 信号（仅技能 chip 用于 TopBar 预演） ────
	if act["kind"] == KIND_SKILL:
		btn.mouse_entered.connect(func():
			if _current_unit and not btn.disabled:
				ability_preview_requested.emit(captured_id, _current_unit)
		)
		btn.mouse_exited.connect(func():
			ability_preview_cancelled.emit()
		)

	return btn


## 固定字母键 chip（不变位、与动态 chip 同款外观，专门用于详情/道具/等待）
func _make_fixed_chip(label: String, key: String, tooltip: String, border_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(FIXED_BUTTON_W, BUTTON_H)
	btn.text = "%s\n[%s]" % [label, key]
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.55))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.30))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.38))
	btn.focus_mode = Control.FOCUS_NONE
	btn.tooltip_text = tooltip

	for state in ["normal", "hover", "pressed", "disabled"]:
		var ssb := StyleBoxFlat.new()
		match state:
			"normal":
				ssb.bg_color = Color(0.14, 0.12, 0.10, 0.95)
				ssb.border_color = border_color
			"hover":
				ssb.bg_color = Color(0.22, 0.18, 0.13, 0.98)
				ssb.border_color = border_color.lightened(0.25)
			"pressed":
				ssb.bg_color = Color(0.30, 0.22, 0.12, 1.0)
				ssb.border_color = border_color.lightened(0.45)
			"disabled":
				ssb.bg_color = Color(0.10, 0.09, 0.08, 0.85)
				ssb.border_color = Color(0.30, 0.27, 0.22)
		ssb.border_width_left = 1
		ssb.border_width_right = 1
		ssb.border_width_top = 1
		ssb.border_width_bottom = 1
		ssb.corner_radius_top_left = 4
		ssb.corner_radius_top_right = 4
		ssb.corner_radius_bottom_left = 4
		ssb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override(state, ssb)

	return btn


## 详情区（紧凑 BB 风）：
##   行 1：名字 + 阵营
##   行 2：2 列 × 3 行 GridContainer（HP/AP/头甲/身甲/气力 + 速度）
##   行 3：武器 + 护甲
func _build_detail_section() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.custom_minimum_size = Vector2(380, 0)

	# 行 1: 名字 + 阵营（同行）
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.62))
	_name_label.clip_text = true
	name_row.add_child(_name_label)
	_faction_label = Label.new()
	_faction_label.add_theme_font_size_override("font_size", 10)
	_faction_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))
	_faction_label.clip_text = true
	_faction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_faction_label)
	vb.add_child(name_row)

	# 行 2: 2 列 × 3 行 grid 数据条
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)

	_hp_bar = ProgressBar.new(); _hp_value = Label.new()
	grid.add_child(_make_stat_row("HP", _hp_bar, _hp_value, BAR_HP_COLOR))
	_ap_bar = ProgressBar.new(); _ap_value = Label.new()
	grid.add_child(_make_stat_row("AP", _ap_bar, _ap_value, BAR_AP_COLOR))
	_head_bar = ProgressBar.new(); _head_value = Label.new()
	grid.add_child(_make_stat_row("头甲", _head_bar, _head_value, BAR_HEAD_COLOR))
	_body_bar = ProgressBar.new(); _body_value = Label.new()
	grid.add_child(_make_stat_row("身甲", _body_bar, _body_value, BAR_BODY_COLOR))
	_fatigue_bar = ProgressBar.new(); _fatigue_value = Label.new()
	grid.add_child(_make_stat_row("气力", _fatigue_bar, _fatigue_value, BAR_FATIGUE_COLOR))
	# 第 6 格：速度
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 6)
	var speed_lbl := Label.new()
	speed_lbl.text = "速度"
	speed_lbl.custom_minimum_size = Vector2(36, 0)
	speed_lbl.add_theme_font_size_override("font_size", 10)
	speed_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.70))
	speed_box.add_child(speed_lbl)
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 10)
	_speed_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	_speed_label.clip_text = true
	_speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_box.add_child(_speed_label)
	grid.add_child(speed_box)
	vb.add_child(grid)

	# 行 3: 武器 + 护甲
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 10)
	_weapon_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	_weapon_label.clip_text = true
	vb.add_child(_weapon_label)

	_armor_label = Label.new()
	_armor_label.add_theme_font_size_override("font_size", 10)
	_armor_label.add_theme_color_override("font_color", Color(0.78, 0.85, 1.00))
	_armor_label.clip_text = true
	vb.add_child(_armor_label)

	# 行 4: 提示
	var hint := Label.new()
	hint.text = "[P] 切换详情"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.55, 0.52, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)

	return vb


## 数值条单行：[标签 36px][进度条 expand][数值 64px]
func _make_stat_row(label_text: String, bar: ProgressBar, value_label: Label, color: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(36, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.70))
	hb.add_child(lbl)

	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.10, 0.08, 1.0)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.corner_radius_top_left = 2
	fg.corner_radius_top_right = 2
	fg.corner_radius_bottom_left = 2
	fg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fg)
	hb.add_child(bar)

	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(value_label)
	return hb
