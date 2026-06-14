extends PanelContainer
##
## SidePanel.gd — 战斗右侧"详细信息卡"
##
## 行为：
##   - 默认隐藏；鼠标悬停在某个角色上时由 BattleScene 调用 show_for_unit() 弹出
##   - 当前回合开始时（_on_turn_started）会 bind_unit() 更新数据但不强制显示
##   - 战斗日志已移到独立的 BattleLog 容器（左上角）
##

@onready var unit_name_label: Label = $VBox/UnitName
@onready var faction_label: Label = $VBox/Faction
@onready var hp_bar: ProgressBar = $VBox/Stats/HPRow/Bar
@onready var hp_label: Label = $VBox/Stats/HPRow/Value
@onready var head_armor_bar: ProgressBar = $VBox/Stats/HeadArmorRow/Bar
@onready var head_armor_label: Label = $VBox/Stats/HeadArmorRow/Value
@onready var body_armor_bar: ProgressBar = $VBox/Stats/BodyArmorRow/Bar
@onready var body_armor_label: Label = $VBox/Stats/BodyArmorRow/Value
@onready var ap_bar: ProgressBar = $VBox/Stats/APRow/Bar
@onready var ap_label: Label = $VBox/Stats/APRow/Value
@onready var fatigue_bar: ProgressBar = $VBox/Stats/FatigueRow/Bar
@onready var fatigue_label: Label = $VBox/Stats/FatigueRow/Value
@onready var skill_label: Label = $VBox/Skills
@onready var weapon_label: Label = $VBox/WeaponInfo
@onready var armor_label: Label = $VBox/ArmorInfo
@onready var initiative_label: Label = $VBox/InitiativeLabel
@onready var log_panel: PanelContainer = $VBox/LogPanel    ## 旧位置：将由 BattleScene reparent 到独立 BattleLog
@onready var log_text: RichTextLabel = $VBox/LogPanel/Log
@onready var hint_label: Label = $VBox/Hint

var _bound_unit: Unit = null
var turn_manager = null   ## 由 BattleScene 在 _ready() 注入


func _ready() -> void:
	# 默认隐藏，仅悬停时弹出
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind_unit(unit: Unit) -> void:
	if _bound_unit and _bound_unit.stats_changed.is_connected(_refresh):
		_bound_unit.stats_changed.disconnect(_refresh)
	_bound_unit = unit
	if unit:
		unit.stats_changed.connect(_refresh)
	_refresh(unit)


## 悬停某个单位时显示
func show_for_unit(unit: Unit) -> void:
	if unit == null or not unit.is_alive():
		visible = false
		return
	bind_unit(unit)
	visible = true


## 鼠标离开时调用
func hide_card() -> void:
	visible = false


func _refresh(_u = null) -> void:
	if _bound_unit == null or _bound_unit.stats == null:
		return
	var s: Stats = _bound_unit.stats

	# 名称旁附加"第N回合即将行动"提示
	var turn_hint: String = _get_turn_hint(_bound_unit)
	unit_name_label.text = s.unit_name + ("　（%s）" % turn_hint if turn_hint != "" else "")

	faction_label.text = "[ 当前行动 ]  " + ("友方" if s.faction == 0 else "敌方")
	faction_label.modulate = Color(0.29, 0.56, 0.85) if s.faction == 0 else Color(0.78, 0.22, 0.22)

	hp_bar.max_value = s.max_hp
	hp_bar.value = s.hp
	hp_label.text = "%d / %d" % [s.hp, s.max_hp]

	head_armor_bar.max_value = max(1, s.max_head_armor)
	head_armor_bar.value = s.head_armor
	head_armor_label.text = "%d / %d" % [s.head_armor, s.max_head_armor]

	body_armor_bar.max_value = max(1, s.max_body_armor)
	body_armor_bar.value = s.body_armor
	body_armor_label.text = "%d / %d" % [s.body_armor, s.max_body_armor]

	ap_bar.max_value = s.max_ap
	ap_bar.value = s.ap
	ap_label.text = "%d / %d" % [s.ap, s.max_ap]

	fatigue_bar.max_value = max(1, s.max_stamina)
	var remain: int = s.remaining_stamina()
	fatigue_bar.value = remain
	fatigue_label.text = "%d / %d" % [remain, s.max_stamina]

	var job_name: String = _bound_unit.job.display_name if _bound_unit.job != null else "—"
	var crit_pct: int = int(round(DamageSystem.calculate_crit_chance(_bound_unit) * 100.0))
	skill_label.text = "职业 %s   Wisdom %d   暴击 %d%%\n近战 %d  防御 %d (有效 %.0f)\n远程 %d  防御 %d" % [
		job_name, s.wisdom, crit_pct,
		s.melee_skill, s.melee_defense, s.effective_melee_defense(),
		s.ranged_skill, s.ranged_defense
	]

	if _bound_unit.weapon:
		var w = _bound_unit.weapon
		var mode: String = w.attack_modes[0] if not w.attack_modes.is_empty() else "slash"
		var pen: float = DamageSystem.penetration_rate_for(w, mode)
		weapon_label.text = "武器：%s  基伤 %d  重 %d  渗透 %.0f%%（%s）" % [
			w.display_name, w.damage_base, w.weight, pen * 100.0, mode
		]
	if _bound_unit.armor:
		armor_label.text = "护甲：" + _bound_unit.armor.to_string_brief()

	# Initiative：显示有效值（含护甲重量惩罚），让玩家看清"重甲拖慢"的程度
	var armor_w: int = _bound_unit.armor.weight if _bound_unit.armor else 0
	var armor_init_penalty: int = int(floor(float(armor_w) / 4.0))
	initiative_label.text = "Initiative：%d  (基础 %d − 已耗 %d − 甲重 %d)" % [
		s.effective_initiative(armor_w, 0), s.base_initiative, s.stamina_spent(), armor_init_penalty
	]


func append_log(bbcode_line: String) -> void:
	if bbcode_line == "":
		return
	log_text.append_text(bbcode_line + "\n")


func set_hint(text: String) -> void:
	hint_label.text = text


## 返回该单位"第N回合即将行动"的提示文本
func _get_turn_hint(unit: Unit) -> String:
	if turn_manager == null:
		return ""
	var current: Unit = turn_manager.get_current_unit()
	if unit == current:
		return "▶ 正在行动"
	var pending: Array = turn_manager.get_pending_units()
	for u in pending:
		if u == unit:
			return "第 %d 回合 · 待行动" % turn_manager.round_num
	return "第 %d 回合行动" % (turn_manager.round_num + 1)
