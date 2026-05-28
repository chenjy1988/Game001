extends Node
class_name TurnManager
##
## TurnManager.gd — Initiative 动态回合调度器
##
## 不区分玩家/敌方回合。每轮开始时按 current_initiative() 排序所有存活单位，
## 逐个发放回合。单位行动完毕通过 action_completed 信号通知，调度器推进下一个。
##

signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal round_started(round_num: int)
signal round_ended(round_num: int)
signal battle_ended(winner_faction: int)  ## 0=友方胜 1=敌方胜 -1=平局

var _units: Array[Unit] = []
var _turn_order: Array[Unit] = []   ## 本轮按 Initiative 排好的顺序
var _current_index: int = -1
var round_num: int = 0
var _battle_running: bool = false


func register_units(units: Array) -> void:
	_units.clear()
	for u in units:
		if u is Unit:
			_units.append(u)
			u.action_completed.connect(_on_unit_action_completed)
			u.unit_died.connect(_on_unit_died)


func start_battle() -> void:
	_battle_running = true
	round_num = 0
	_start_next_round()


func _start_next_round() -> void:
	if not _battle_running:
		return
	if _check_battle_end():
		return
	round_num += 1
	# 按 Initiative 降序
	_turn_order = _units.filter(func(u): return u.is_alive())
	_turn_order.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.stats.current_initiative() > b.stats.current_initiative()
	)
	_current_index = -1
	round_started.emit(round_num)
	_advance_to_next()


func _advance_to_next() -> void:
	if not _battle_running:
		return
	_current_index += 1
	# 跳过已死单位
	while _current_index < _turn_order.size() and not _turn_order[_current_index].is_alive():
		_current_index += 1
	if _current_index >= _turn_order.size():
		round_ended.emit(round_num)
		_start_next_round()
		return
	if _check_battle_end():
		return
	var u: Unit = _turn_order[_current_index]
	u.start_turn()
	turn_started.emit(u)


func get_current_unit() -> Unit:
	if _current_index < 0 or _current_index >= _turn_order.size():
		return null
	return _turn_order[_current_index]


## 取本轮 Initiative 排序快照（用于 UI 显示）
func get_turn_order_preview() -> Array[Unit]:
	return _turn_order.duplicate()


func _on_unit_action_completed(unit: Unit) -> void:
	turn_ended.emit(unit)
	_advance_to_next()


func _on_unit_died(_unit: Unit) -> void:
	# 死亡后立刻检查胜负
	_check_battle_end()


func _check_battle_end() -> bool:
	var alive_friendly: int = 0
	var alive_enemy: int = 0
	for u in _units:
		if u.is_alive():
			if u.get_faction() == 0:
				alive_friendly += 1
			else:
				alive_enemy += 1
	if alive_friendly == 0 and alive_enemy == 0:
		_battle_running = false
		battle_ended.emit(-1)
		return true
	if alive_friendly == 0:
		_battle_running = false
		battle_ended.emit(1)
		return true
	if alive_enemy == 0:
		_battle_running = false
		battle_ended.emit(0)
		return true
	return false
