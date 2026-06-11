extends PanelContainer
##
## UnitTooltip.gd — 鼠标悬停某个单位时弹出的"羊皮纸卡"浮层
##
## 一卡显示：标题 + 状态行 + HP / 头甲 / 身甲 / AP / 疲劳 五条数值进度条 + 武器/护甲文字
## 跟随光标实时更新；离开单位区域立刻隐藏。
##

const STATE_HEALTHY: String = "完好无伤"
const STATE_LIGHT: String   = "轻伤"
const STATE_HEAVY: String   = "重伤"
const STATE_CRITICAL: String = "濒死"
const STATE_TIRED: String   = "疲惫"
const STATE_EXHAUSTED: String = "力竭"

@onready var name_label: Label = $VBox/Header/Name
@onready var faction_dot: ColorRect = $VBox/Header/FactionDot
@onready var state_label: Label = $VBox/StateLabel

# 浮层左上角的"头像"——用代码替换 FactionDot 的视觉
const _PORTRAIT_BOX_SIZE: int = 38
var _portrait_panel: PanelContainer = null
var _portrait_tex_rect: TextureRect = null

@onready var hp_bar: ProgressBar = $VBox/HPBar
@onready var head_bar: ProgressBar = $VBox/HeadBar
@onready var body_bar: ProgressBar = $VBox/BodyBar
@onready var fatigue_bar: ProgressBar = $VBox/FatigueBar

# 动态新增的扩展行
var _ap_bar: ProgressBar = null
var _initiative_label: Label = null
var _weapon_label: Label = null
var _armor_label: Label = null
var _bound_unit: Unit = null

# ── 攻击预览块（仅当 _attacker_context 非空时展示） ──
var _attacker_context: Unit = null
var _atk_preview_box: PanelContainer = null
var _atk_title_label: Label = null
var _atk_hit_label: Label = null
var _atk_overwhelm_label: Label = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	custom_minimum_size = Vector2(240, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	_apply_parchment_style()
	_decorate_existing_bars()
	_extend_panel()
	_install_portrait_in_header()
	var vbox: VBoxContainer = $VBox as VBoxContainer
	if vbox:
		vbox.add_theme_constant_override("separation", 3)
		vbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## 把 Header 里的 FactionDot 替换为带阵营色边框的小头像
func _install_portrait_in_header() -> void:
	if faction_dot == null:
		return
	var header: Node = faction_dot.get_parent()
	if header == null:
		return
	# 隐藏原 dot
	faction_dot.custom_minimum_size = Vector2(0, 0)
	faction_dot.visible = false

	# 在 dot 之前插一个 PanelContainer 放头像
	_portrait_panel = PanelContainer.new()
	_portrait_panel.custom_minimum_size = Vector2(_PORTRAIT_BOX_SIZE, _PORTRAIT_BOX_SIZE)
	_portrait_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 默认描边（之后 _refresh 时按阵营改）
	_portrait_panel.add_theme_stylebox_override("panel",
		_make_portrait_stylebox(Color(0.34, 0.22, 0.10)))

	_portrait_tex_rect = TextureRect.new()
	_portrait_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_tex_rect.custom_minimum_size = Vector2(_PORTRAIT_BOX_SIZE - 4, _PORTRAIT_BOX_SIZE - 4)
	_portrait_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 1)
	mc.add_theme_constant_override("margin_right", 1)
	mc.add_theme_constant_override("margin_top", 1)
	mc.add_theme_constant_override("margin_bottom", 1)
	mc.clip_contents = true
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(_portrait_tex_rect)
	_portrait_panel.add_child(mc)

	# 放在 header 的最左
	header.add_child(_portrait_panel)
	header.move_child(_portrait_panel, 0)


func _make_portrait_stylebox(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.08)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_color = c
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	return sb


# ──────────── 羊皮纸样式背板 ────────────
func _apply_parchment_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.86, 0.70)             # 羊皮纸底
	sb.border_color = Color(0.34, 0.22, 0.10)         # 深棕外框
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
	add_theme_stylebox_override("panel", sb)


## 把已有的 4 条进度条样式调整为"羊皮纸卡"风格
func _decorate_existing_bars() -> void:
	if name_label:
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color(0.18, 0.10, 0.05))
	if state_label:
		state_label.add_theme_font_size_override("font_size", 11)
		state_label.add_theme_color_override("font_color", Color(0.30, 0.18, 0.08))
	for bar in [hp_bar, head_bar, body_bar, fatigue_bar]:
		if bar == null:
			continue
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.add_theme_stylebox_override("background", _make_bar_bg())
	hp_bar.add_theme_stylebox_override("fill", _make_bar_fill(Color(0.74, 0.18, 0.18)))
	head_bar.add_theme_stylebox_override("fill", _make_bar_fill(Color(0.55, 0.55, 0.55)))
	body_bar.add_theme_stylebox_override("fill", _make_bar_fill(Color(0.52, 0.62, 0.78)))
	fatigue_bar.add_theme_stylebox_override("fill", _make_bar_fill(Color(0.78, 0.50, 0.25)))


func _make_bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.13, 0.07, 0.92)
	sb.border_color = Color(0.34, 0.22, 0.10)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _make_bar_fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


## 给 4 条进度条加上前缀图标 + 数值后缀
## 简化做法：用 Label 叠加在 ProgressBar 上方显示文字（行高一致）
##   每条 bar 包一层 HBoxContainer：[ICON 16x16][BAR][TEXT 60x16]
##   原来的 Bar 直接挂在 VBox 下，现在 reparent 到 HBoxContainer 里
func _extend_panel() -> void:
	# 给 4 条 bar 各加一个 HBox 包装：图标 + bar + 数值文本
	_wrap_bar(hp_bar, "♥", "%d/%d", "hp")
	_wrap_bar(head_bar, "🜨", "%d/%d", "head")
	_wrap_bar(body_bar, "✤", "%d/%d", "body")
	_wrap_bar(fatigue_bar, "≋", "%d/%d", "fatigue")

	# 追加：AP 条（动态新增）
	var vbox: VBoxContainer = $VBox as VBoxContainer
	if vbox:
		var ap_bar := ProgressBar.new()
		ap_bar.name = "APBar"
		ap_bar.show_percentage = false
		ap_bar.custom_minimum_size = Vector2(0, 11)
		ap_bar.add_theme_stylebox_override("background", _make_bar_bg())
		ap_bar.add_theme_stylebox_override("fill", _make_bar_fill(Color(0.85, 0.69, 0.22)))
		_ap_bar = ap_bar
		vbox.add_child(ap_bar)
		# reparent 后再包装
		_wrap_bar(ap_bar, "⚡", "%d/%d", "ap")
		# 把 AP 条挪到 HP 条之后（视觉一致）
		# 注意：_wrap_bar 后层级为 VBox > Row_HBox > Overlay > Bar，
		#   要操作的是 vbox 的直接子节点 Row_HBox（需向上取两层），
		#   之前误取 Bar 的直接父节点 Overlay 导致 move_child 报 "Child is not a child"。
		var hp_row: Node = hp_bar.get_parent().get_parent() if hp_bar.get_parent() else null
		var ap_row: Node = ap_bar.get_parent().get_parent() if ap_bar.get_parent() else null
		if hp_row and ap_row and ap_row.get_parent() == vbox:
			vbox.move_child(ap_row, hp_row.get_index() + 1)

	# Initiative 行
	if vbox:
		_initiative_label = Label.new()
		_initiative_label.add_theme_font_size_override("font_size", 10)
		_initiative_label.add_theme_color_override("font_color", Color(0.30, 0.18, 0.08))
		vbox.add_child(_initiative_label)

	# 武器 / 护甲文字
	if vbox:
		_weapon_label = Label.new()
		_weapon_label.add_theme_font_size_override("font_size", 10)
		_weapon_label.add_theme_color_override("font_color", Color(0.50, 0.30, 0.10))
		_weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_weapon_label)

		_armor_label = Label.new()
		_armor_label.add_theme_font_size_override("font_size", 10)
		_armor_label.add_theme_color_override("font_color", Color(0.30, 0.34, 0.55))
		_armor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(_armor_label)

	# 攻击预览块（默认隐藏，置顶）
	_build_attack_preview()


## 把一条 ProgressBar 包装成 [图标][overlay(bar+数值居中)]
func _wrap_bar(bar: ProgressBar, icon_text: String, _format: String, tag: String) -> void:
	var parent_vbox: Node = bar.get_parent()
	if parent_vbox == null:
		return
	var idx: int = bar.get_index()
	var hb := HBoxContainer.new()
	hb.name = "Row_" + tag
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_label := Label.new()
	icon_label.text = icon_text
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.add_theme_color_override("font_color", Color(0.30, 0.18, 0.08))
	icon_label.custom_minimum_size = Vector2(14, 0)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Overlay 容器：bar 和 value_label 叠在一起
	var overlay := Control.new()
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.custom_minimum_size = Vector2(0, 14)

	parent_vbox.remove_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.add_child(bar)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	value_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	value_label.add_theme_constant_override("shadow_offset_x", 1)
	value_label.add_theme_constant_override("shadow_offset_y", 1)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(value_label)

	hb.add_child(icon_label)
	hb.add_child(overlay)
	parent_vbox.add_child(hb)
	parent_vbox.move_child(hb, idx)


# ──────────── 攻击预览块（命中率 + 围攻加成） ────────────
## 在 VBox 顶端塞一个紧凑的"攻击预览"区。仅当外部调用 show_for_attack() 设置
## 攻击者上下文时才会显示；普通悬停时自动隐藏。
func _build_attack_preview() -> void:
	var vbox: VBoxContainer = $VBox as VBoxContainer
	if vbox == null:
		return
	_atk_preview_box = PanelContainer.new()
	_atk_preview_box.name = "AttackPreview"
	_atk_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atk_preview_box.visible = false
	# 深色金边背板（与羊皮纸主体形成对比）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.13, 0.07, 0.94)
	sb.border_color = Color(0.85, 0.69, 0.22)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_atk_preview_box.add_theme_stylebox_override("panel", sb)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atk_preview_box.add_child(inner)

	# 第一行：标题（小字）
	_atk_title_label = Label.new()
	_atk_title_label.text = "⚔ 攻击预览"
	_atk_title_label.add_theme_font_size_override("font_size", 9)
	_atk_title_label.add_theme_color_override("font_color", Color(0.75, 0.62, 0.30))
	inner.add_child(_atk_title_label)

	# 第二行：命中率（大字 + 金）
	_atk_hit_label = Label.new()
	_atk_hit_label.add_theme_font_size_override("font_size", 16)
	_atk_hit_label.add_theme_color_override("font_color", Color(1.00, 0.86, 0.30))
	inner.add_child(_atk_hit_label)

	# 第三行：围攻加成（仅有时显示，浅蓝）
	_atk_overwhelm_label = Label.new()
	_atk_overwhelm_label.add_theme_font_size_override("font_size", 10)
	_atk_overwhelm_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1.00))
	inner.add_child(_atk_overwhelm_label)

	vbox.add_child(_atk_preview_box)
	vbox.move_child(_atk_preview_box, 0)  # 置顶


## 把一次"鼠标悬停在可攻击敌人上"翻译成攻击预览数据。
## 调用前 _bound_unit 必须已是被攻击的目标（show_for 已绑好）。
func _refresh_attack_preview() -> void:
	if _atk_preview_box == null:
		return
	if _attacker_context == null or _bound_unit == null \
			or not _attacker_context.is_alive() or not _bound_unit.is_alive() \
			or _attacker_context.weapon == null:
		_atk_preview_box.visible = false
		return
	_atk_preview_box.visible = true
	# 命中率（已含围攻加成 / 已 clamp）
	var chance: float = DamageSystem.calculate_hit_chance(_attacker_context, _bound_unit)
	var allies: int = DamageSystem.count_overwhelm_allies(_attacker_context, _bound_unit)
	var bonus: float = min(float(allies) * DamageSystem.OVERWHELM_PER_ALLY,
		DamageSystem.OVERWHELM_MAX)
	# 行 1 标题：注明攻击者武器
	var weapon_brief: String = _attacker_context.weapon.display_name \
		if _attacker_context.weapon else "武器"
	_atk_title_label.text = "⚔ %s 的%s" % [_attacker_context.get_unit_name(), weapon_brief]
	# 行 2 命中率：百分比，并附"未围攻时的基础命中率"对照
	var pct: int = int(round(chance * 100.0))
	_atk_hit_label.text = "命中 %d%%" % pct
	# 行 3 围攻命中加成（仅显示 +X%）
	if allies > 0 and bonus > 0.0:
		var bpct: int = int(round(bonus * 100.0))
		_atk_overwhelm_label.text = "+%d%%" % bpct
		_atk_overwhelm_label.visible = true
	else:
		_atk_overwhelm_label.visible = false


# ──────────── 对外接口 ────────────
func show_for(unit: Unit, screen_pos: Vector2) -> void:
	if unit == null or unit.stats == null or not unit.is_alive():
		_disconnect_unit()
		hide()
		return
	# 若与上一次绑定不同，重连 stats_changed 信号
	if unit != _bound_unit:
		_disconnect_unit()
		_bound_unit = unit
		if unit and unit.stats_changed.is_connected(_on_stats_changed) == false:
			unit.stats_changed.connect(_on_stats_changed)
	# 普通悬停 → 清掉攻击者上下文（隐藏攻击预览）
	_attacker_context = null
	_refresh()
	visible = true
	_place_at(screen_pos)


## 攻击者悬停在可攻击敌人 target 上时调用：浮层立即出现，
## 顶部展示"命中 NN%"与围攻命中加成"+X%"。
func show_for_attack(target: Unit, attacker: Unit, screen_pos: Vector2) -> void:
	if target == null or target.stats == null or not target.is_alive():
		_disconnect_unit()
		hide()
		return
	if target != _bound_unit:
		_disconnect_unit()
		_bound_unit = target
		if target.stats_changed.is_connected(_on_stats_changed) == false:
			target.stats_changed.connect(_on_stats_changed)
	_attacker_context = attacker
	_refresh()
	visible = true
	_place_at(screen_pos)


func update_position(screen_pos: Vector2) -> void:
	if visible:
		_place_at(screen_pos)


func hide_card() -> void:
	_disconnect_unit()
	_attacker_context = null
	if _atk_preview_box:
		_atk_preview_box.visible = false
	hide()


func _disconnect_unit() -> void:
	if _bound_unit and _bound_unit.stats_changed.is_connected(_on_stats_changed):
		_bound_unit.stats_changed.disconnect(_on_stats_changed)
	_bound_unit = null


func _on_stats_changed(_u = null) -> void:
	_refresh()


func _refresh() -> void:
	if _bound_unit == null or _bound_unit.stats == null:
		return
	var s: Stats = _bound_unit.stats

	name_label.text = s.unit_name
	# 头像 + 阵营色描边
	if _portrait_panel:
		var border_color: Color = (Color(0.45, 0.65, 0.95)
			if s.faction == 0 else Color(0.90, 0.40, 0.35))
		_portrait_panel.add_theme_stylebox_override("panel",
			_make_portrait_stylebox(border_color))
	if _portrait_tex_rect and _bound_unit and _bound_unit.has_method("get_action_bar_portrait"):
		var t: Texture2D = _bound_unit.get_action_bar_portrait()
		if t:
			# 裁出胸像顶部 80% 让脸更聚焦（比行动条 65% 留多一点身体）
			var ts: Vector2 = t.get_size()
			var atlas := AtlasTexture.new()
			atlas.atlas = t
			atlas.region = Rect2(0, ts.y * 0.02, ts.x, ts.y * 0.80)
			_portrait_tex_rect.texture = atlas
		else:
			_portrait_tex_rect.texture = null

	# 状态行
	var hp_ratio: float = float(s.hp) / float(max(1, s.max_hp))
	var fatigue_ratio: float = float(s.fatigue) / float(max(1, s.max_stamina))
	var hp_state: String = STATE_HEALTHY
	if hp_ratio < 0.25:
		hp_state = STATE_CRITICAL
	elif hp_ratio < 0.5:
		hp_state = STATE_HEAVY
	elif hp_ratio < 1.0:
		hp_state = STATE_LIGHT
	var fatigue_state: String = ""
	if fatigue_ratio > 0.85:
		fatigue_state = " · " + STATE_EXHAUSTED
	elif fatigue_ratio > 0.5:
		fatigue_state = " · " + STATE_TIRED
	var faction_text: String = "[友方]" if s.faction == 0 else "[敌方]"
	state_label.text = "%s  %s%s" % [faction_text, hp_state, fatigue_state]

	# HP / 头甲 / 身甲 / 疲劳 / AP
	_set_bar_value(hp_bar, s.hp, s.max_hp)
	_set_bar_value(head_bar, s.head_armor, max(1, s.max_head_armor))
	_set_bar_value(body_bar, s.body_armor, max(1, s.max_body_armor))
	_set_bar_value(fatigue_bar, s.fatigue, max(1, s.max_stamina))
	if _ap_bar:
		_set_bar_value(_ap_bar, s.ap, s.max_ap)

	# Initiative
	if _initiative_label:
		_initiative_label.text = "速度 %d (基础 %d − 疲劳 %d)" % [
			s.current_initiative(), s.base_initiative, s.fatigue
		]

	# 武器 / 护甲
	if _weapon_label:
		_weapon_label.text = "武器：" + (_bound_unit.weapon.to_string_brief()
			if _bound_unit.weapon else "无")
	if _armor_label:
		_armor_label.text = "护甲：" + (_bound_unit.armor.to_string_brief()
			if _bound_unit.armor else "无")

	# 攻击预览（仅在 _attacker_context 非空时可见）
	_refresh_attack_preview()


## 同步 ProgressBar 数值 + 叠加在 bar 中间的白色文字
func _set_bar_value(bar: ProgressBar, value: int, max_v: int) -> void:
	if bar == null:
		return
	bar.max_value = max_v
	bar.value = value
	# 数值 label 在 bar 的父级 overlay 里
	var overlay: Node = bar.get_parent()
	if overlay and overlay.has_node("Value"):
		var lbl: Label = overlay.get_node("Value")
		lbl.text = "%d/%d" % [value, max_v]


func _place_at(screen_pos: Vector2) -> void:
	# 强制让 PanelContainer 收缩到内容大小（避免布局父级把它撑得很高）
	size = Vector2.ZERO
	# 等一帧让布局完成（reset_size 立即同步）
	reset_size()
	var sz: Vector2 = size
	var vp: Vector2 = get_viewport_rect().size
	var offset: Vector2 = Vector2(20, 20)
	var pos: Vector2 = screen_pos + offset
	if pos.x + sz.x > vp.x:
		pos.x = screen_pos.x - sz.x - offset.x
	if pos.y + sz.y > vp.y:
		pos.y = screen_pos.y - sz.y - offset.y
	pos.x = max(4.0, pos.x)
	pos.y = max(4.0, pos.y)
	global_position = pos
