extends PanelContainer
##
## UnitTooltip.gd — 鼠标悬停在某个单位上时显示的浮动概览面板
##
## 不显示具体数值，只用进度条 + 状态文字给出"还撑得住吗 / 甲还有没有 / 累不累"的速览
## 跟随光标位置实时更新；离开单位区域立刻隐藏
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

@onready var hp_bar: ProgressBar = $VBox/HPBar
@onready var head_bar: ProgressBar = $VBox/HeadBar
@onready var body_bar: ProgressBar = $VBox/BodyBar
@onready var fatigue_bar: ProgressBar = $VBox/FatigueBar


func _ready() -> void:
	visible = false
	# tooltip 不应拦截鼠标事件
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true  ## 跟 viewport 走，不被父节点 transform 影响


func show_for(unit: Unit, screen_pos: Vector2) -> void:
	if unit == null or unit.stats == null or not unit.is_alive():
		hide()
		return
	var s: Stats = unit.stats
	name_label.text = s.unit_name
	faction_dot.color = Color(0.29, 0.56, 0.85) if s.faction == 0 else Color(0.78, 0.22, 0.22)

	# HP 条
	hp_bar.max_value = s.max_hp
	hp_bar.value = s.hp
	# 头部甲（无甲时仍画框，但显示满灰）
	head_bar.max_value = max(1, s.max_head_armor)
	head_bar.value = s.head_armor
	head_bar.modulate = Color(0.6, 0.6, 0.6, 1) if s.max_head_armor > 0 else Color(0.3, 0.3, 0.3, 0.4)
	# 身体甲
	body_bar.max_value = max(1, s.max_body_armor)
	body_bar.value = s.body_armor
	body_bar.modulate = Color(0.55, 0.65, 0.78, 1) if s.max_body_armor > 0 else Color(0.3, 0.3, 0.3, 0.4)
	# 疲劳：用百分比比例
	fatigue_bar.max_value = max(1, s.max_fatigue)
	fatigue_bar.value = s.fatigue

	# 综合状态描述
	var hp_ratio: float = float(s.hp) / float(max(1, s.max_hp))
	var fatigue_ratio: float = float(s.fatigue) / float(max(1, s.max_fatigue))
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
	state_label.text = hp_state + fatigue_state

	visible = true
	_place_at(screen_pos)


func update_position(screen_pos: Vector2) -> void:
	if visible:
		_place_at(screen_pos)


func _place_at(screen_pos: Vector2) -> void:
	# 把 tooltip 放在光标右下，超出屏幕则翻转
	var sz: Vector2 = size
	var vp: Vector2 = get_viewport_rect().size
	var offset: Vector2 = Vector2(18, 18)
	var pos: Vector2 = screen_pos + offset
	if pos.x + sz.x > vp.x:
		pos.x = screen_pos.x - sz.x - offset.x
	if pos.y + sz.y > vp.y:
		pos.y = screen_pos.y - sz.y - offset.y
	global_position = pos
