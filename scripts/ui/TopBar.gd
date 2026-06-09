extends PanelContainer
##
## TopBar.gd — 战斗顶部长线滚动式时间轴条（回合数 + 极简单行滚动 + 敌友边框高亮 + 无缝下回合衔接 + 金色回合分割线）
##

# ─────────────────────────────────────────────────────────────
# 内部 PortraitItem 类：具有敌友战术边框的单位头像 + 向上箭头指示
# ─────────────────────────────────────────────────────────────
class PortraitItem extends Control:
	var unit: Unit = null
	var border_rect: ColorRect = null
	var portrait_rect: TextureRect = null
	var arrow_label: Label = null

	func _init(u: Unit) -> void:
		unit = u
		custom_minimum_size = Vector2(48, 48)
		mouse_filter = MOUSE_FILTER_STOP

		# 1. 敌友区分边框（取代直接对头像染色，保持头像色彩纯正）
		# 友方采用清澈的战术蓝，敌方采用醒目的战术红
		border_rect = ColorRect.new()
		border_rect.color = Color(0.15, 0.55, 0.85) if u.get_faction() == 0 else Color(0.8, 0.15, 0.15)
		border_rect.anchor_right = 1.0
		border_rect.anchor_bottom = 1.0
		border_rect.offset_left = 0
		border_rect.offset_top = 0
		border_rect.offset_right = 0
		border_rect.offset_bottom = 0
		add_child(border_rect)

		# 2. 内嵌头像
		portrait_rect = TextureRect.new()
		portrait_rect.texture = u.get_action_bar_portrait()
		portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# 内缩 2 像素展示边框
		portrait_rect.anchor_right = 1.0
		portrait_rect.anchor_bottom = 1.0
		portrait_rect.offset_left = 2
		portrait_rect.offset_top = 2
		portrait_rect.offset_right = -2
		portrait_rect.offset_bottom = -2
		
		# 头像保持纯净白光，绝不偏色，消除 boss 头像偏粉怪异感
		portrait_rect.modulate = Color.WHITE
		add_child(portrait_rect)

		# 3. 向上箭头标签（初始隐藏）
		arrow_label = Label.new()
		arrow_label.text = "↑"
		arrow_label.add_theme_font_size_override("font_size", 12)
		arrow_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))  # 绿色
		arrow_label.anchor_left = 0.5
		arrow_label.anchor_top = 1.0
		arrow_label.offset_left = -16
		arrow_label.offset_top = -14
		arrow_label.visible = false
		add_child(arrow_label)

	func show_arrow() -> void:
		if arrow_label:
			arrow_label.text = "↑"
			arrow_label.visible = true
		if border_rect:
			# 悬停时边框高亮发光
			border_rect.color = Color(0.4, 0.8, 1.0) if unit.get_faction() == 0 else Color(1.0, 0.4, 0.4)

	func hide_arrow() -> void:
		if arrow_label:
			arrow_label.visible = false
		if border_rect:
			border_rect.color = Color(0.15, 0.55, 0.85) if unit.get_faction() == 0 else Color(0.8, 0.15, 0.15)

	func show_boost() -> void:
		if arrow_label:
			# 移除多余的 "+40" 文本，使绿色闪烁指示器保持极简、干练
			arrow_label.text = "↑"
			arrow_label.visible = true
		if border_rect:
			border_rect.color = Color(0.2, 0.9, 0.2)  # 超车绿色边框


@onready var round_label: Label = $HBox/RoundLabel
@onready var page_button: Button = $HBox/PageButton
@onready var header_portrait_container: HBoxContainer = $HBox/HeaderPortraitContainer

var _current_unit: Unit = null
var _current_round_0: Array[Unit] = []
var _current_round_1: Array[Unit] = []
var _is_preview_mode: bool = false
var _portrait_items: Array = []  ## 保留当前渲染的所有 PortraitItem 引用

var _display_offset: int = 0
const MAX_VISIBLE_PORTRAITS: int = 12  ## 调高上限（一屏可容纳 12 人），保证下大回合的队列能完整展现，同时维持单行极简


func set_current_unit(unit: Unit, round_num: int, round_0_order: Array[Unit], round_1_order: Array[Unit]) -> void:
	_current_unit = unit
	_current_round_0 = round_0_order
	_current_round_1 = round_1_order
	_is_preview_mode = false
	_display_offset = 0  ## 轮到新单位时，自动重置偏移到最前
	
	round_label.text = "回合 %d" % round_num
	_build_portrait_containers()


## 构建无缝滚动的时间轴列表
func _build_portrait_containers() -> void:
	# 1) 清理旧头像
	for child in header_portrait_container.get_children():
		child.queue_free()
	_portrait_items.clear()

	# 2) 拼装无缝长行动链（本回合剩余 + 下回合全部）
	var full_timeline: Array[Unit] = []
	for u in _current_round_0:
		if u.is_alive():
			full_timeline.append(u)
	
	var next_round_queue: Array[Unit] = []
	for u in _current_round_1:
		if u.is_alive():
			next_round_queue.append(u)

	var combined_list = full_timeline + next_round_queue

	# 如果列表为空，直接返回
	if combined_list.size() == 0:
		page_button.visible = false
		return

	# 3) 控制右侧翻页按钮可见性
	page_button.visible = combined_list.size() > MAX_VISIBLE_PORTRAITS
	if _display_offset >= combined_list.size():
		_display_offset = 0

	# 4) 切片截取当前批次显示的单位
	var end_idx = min(_display_offset + MAX_VISIBLE_PORTRAITS, combined_list.size())
	var visible_batch = combined_list.slice(_display_offset, end_idx)

	# 5) 实例化头像
	for i in range(visible_batch.size()):
		var absolute_index = _display_offset + i
		
		# 检查是否到了下大回合的边界，插入金黄色竖线分割（|）
		if absolute_index == full_timeline.size() and i > 0:
			var separator := ColorRect.new()
			separator.custom_minimum_size = Vector2(4, 48)
			separator.color = Color(0.85, 0.69, 0.22)  # 金黄色
			header_portrait_container.add_child(separator)
			
		var u: Unit = visible_batch[i]
		var item = PortraitItem.new(u)
		header_portrait_container.add_child(item)
		_portrait_items.append(item)
		
		# 先发制人超车预览标记
		if _is_preview_mode and u == _current_unit:
			# 只有当下大回合的预览位置被渲染时才标记
			if absolute_index >= full_timeline.size():
				item.show_boost()


func _ready() -> void:
	# 绑定右键翻页按钮
	if page_button:
		page_button.pressed.connect(_on_page_pressed)

	# 连接 CombatMenu 的预览信号
	var combat_menu: Node = get_node_or_null("/root/BattleScene/CombatMenu")
	if combat_menu:
		if combat_menu.has_signal("ability_preview_requested"):
			combat_menu.ability_preview_requested.connect(_on_ability_preview_requested)
		if combat_menu.has_signal("ability_preview_cancelled"):
			combat_menu.ability_preview_cancelled.connect(_on_ability_preview_cancelled)

	# 连接 BattleScene 的单位悬停信号
	var battle_scene: Node = get_node_or_null("/root/BattleScene")
	if battle_scene:
		if battle_scene.has_signal("unit_hovered"):
			battle_scene.unit_hovered.connect(_on_unit_hovered)
		if battle_scene.has_signal("unit_unhovered"):
			battle_scene.unit_unhovered.connect(_on_unit_unhovered)


func _on_page_pressed() -> void:
	var full_timeline_size = _current_round_0.size() + _current_round_1.size()
	if full_timeline_size <= MAX_VISIBLE_PORTRAITS:
		return
		
	# 点击切换下一批（每次向后滑动 3 格，形成平滑翻页）
	_display_offset = (_display_offset + 3) % full_timeline_size
	_build_portrait_containers()


func _on_unit_hovered(unit: Unit) -> void:
	for item in _portrait_items:
		if item.unit == unit:
			item.show_arrow()


func _on_unit_unhovered(unit: Unit) -> void:
	for item in _portrait_items:
		if item.unit == unit:
			item.hide_arrow()


## 处理先发制人 Hover 预览请求
func _on_ability_preview_requested(ability_id: String, unit: Unit) -> void:
	if ability_id != "preempt" or unit == null or _current_round_0.size() == 0:
		return

	_is_preview_mode = true
	
	var preview_round_0 = _current_round_0.duplicate()
	var preview_entries = TurnScheduler.preview_with_preempt_bonus(_current_round_1, unit, 40, 1)
	var preview_round_1: Array[Unit] = []
	for entry in preview_entries:
		var entry_unit: Unit = null
		if entry is Dictionary:
			entry_unit = entry.get("unit")
		elif "unit" in entry:
			entry_unit = entry.unit
			
		if entry_unit != null:
			preview_round_1.append(entry_unit)

	if preview_round_1.size() == 0:
		preview_round_1 = _current_round_1.duplicate()

	_is_preview_mode = true
	_current_round_0 = preview_round_0
	_current_round_1 = preview_round_1
	_build_portrait_containers()


## 处理预览取消
func _on_ability_preview_cancelled() -> void:
	if not _is_preview_mode:
		return
	_is_preview_mode = false
	_build_portrait_containers()
