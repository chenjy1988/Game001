extends PanelContainer
##
## TopBar.gd — 战斗顶部信息条（回合数 + 当前单位 + Initiative 排序预览）
##

@onready var round_label: Label = $HBox/RoundLabel
@onready var current_label: Label = $HBox/CurrentLabel
@onready var order_label: Label = $HBox/OrderLabel


func set_current_unit(unit: Unit, round_num: int, order: Array[Unit]) -> void:
	round_label.text = "回合 %d" % round_num
	if unit:
		var faction_tag: String = "[友]" if unit.get_faction() == 0 else "[敌]"
		current_label.text = "%s %s 行动中" % [faction_tag, unit.get_unit_name()]
		current_label.modulate = Color(0.85, 0.69, 0.22)
	# Initiative 序列预览
	var parts: PackedStringArray = []
	for u in order:
		if not u.is_alive():
			continue
		var marker: String = "▶ " if u == unit else ""
		parts.append("%s%s(%d)" % [marker, u.get_unit_name(), u.stats.current_initiative()])
	order_label.text = "Initiative: " + " → ".join(parts)
