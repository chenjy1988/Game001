extends RefCounted
class_name TimelineEntry
##
## TimelineEntry.gd — 行动条时间轴条目
##
## 表示单位在某个回合的行动顺位
##

var round: int              ## 所属回合（0=当前回合，1=下一回合）
var order: int              ## 该回合内的顺序（0-based）
var unit: Unit              ## 引用的单位对象
var y_position: float       ## UI 渲染的纵轴位置（供 TopBar 使用）

func _init(p_round: int, p_order: int, p_unit: Unit, p_y: float = 0.0) -> void:
	round = p_round
	order = p_order
	unit = p_unit
	y_position = p_y
