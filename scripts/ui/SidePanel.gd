extends PanelContainer
##
## SidePanel.gd — 战斗右侧 UI（单位属性 + 战斗日志）
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
@onready var log_text: RichTextLabel = $VBox/LogPanel/Log
@onready var hint_label: Label = $VBox/Hint

var _bound_unit: Unit = null


func bind_unit(unit: Unit) -> void:
	if _bound_unit and _bound_unit.stats_changed.is_connected(_refresh):
		_bound_unit.stats_changed.disconnect(_refresh)
	_bound_unit = unit
	if unit:
		unit.stats_changed.connect(_refresh)
	_refresh(unit)


func _refresh(_u = null) -> void:
	if _bound_unit == null or _bound_unit.stats == null:
		return
	var s: Stats = _bound_unit.stats
	unit_name_label.text = s.unit_name
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

	fatigue_bar.max_value = max(1, s.max_fatigue)
	fatigue_bar.value = s.fatigue
	fatigue_label.text = "%d / %d" % [s.fatigue, s.max_fatigue]

	skill_label.text = "近战 %d  防御 %d (有效 %.0f)\n远程 %d  防御 %d" % [
		s.melee_skill, s.melee_defense, s.effective_melee_defense(),
		s.ranged_skill, s.ranged_defense
	]

	if _bound_unit.weapon:
		weapon_label.text = "武器：" + _bound_unit.weapon.to_string_brief()
	if _bound_unit.armor:
		armor_label.text = "护甲：" + _bound_unit.armor.to_string_brief()

	initiative_label.text = "Initiative：%d  (基础 %d - 疲劳 %d)" % [
		s.current_initiative(), s.base_initiative, s.fatigue
	]


func append_log(bbcode_line: String) -> void:
	if bbcode_line == "":
		return
	log_text.append_text(bbcode_line + "\n")


func set_hint(text: String) -> void:
	hint_label.text = text
