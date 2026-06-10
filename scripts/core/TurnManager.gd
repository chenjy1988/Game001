extends Node
class_name TurnManager
##
## TurnManager.gd — AP + 回合制调度器（DOS2 风，简化版）
##
## 设计要点（参考 design.md § 十二）：
##   • 每回合开始时，按 effective_initiative 降序一次性排出本回合的 _turn_queue，
##     按队首推进。Init 仅决定回合内顺序，不决定频率——每个活着的单位每回合 1 次。
##
##   • 等待（Wait）机制：单位轮到自己时可以调用 wait_current()，把自己挪到本回合
##     未行动队列的末尾。每回合每单位限 1 次。等待不消耗 AP，再次轮到时不重置 AP/Fatigue
##     （只在第一次轮到时 start_turn）。
##
##   • AP 不跨回合保留：Unit.start_turn() 调用 stats.reset_ap()，轮到时 AP 重置为 max_ap。
##     end_turn 时本回合剩余 AP 自然丢弃（不持久化）。
##
##   • Round（回合）的定义：每个活着的单位按 Init 顺序行动 1 次，全部完成后进入下一轮。
##
##   • 单位行动完毕通过 action_completed 信号通知，调度器进入下一个队首。
##
## 兼容 UI 接口（不破坏 SidePanel/TopBar）：
##   - get_turn_order_preview()：返回 [本回合剩余] + [下回合预览]（按 Init 排序）。
##   - get_acted_units()：本回合内已行动的活着单位。
##   - get_pending_units()：本回合内尚未行动的活着单位（含当前）。
##

signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal round_started(round_num: int)
signal round_ended(round_num: int)
signal battle_ended(winner_faction: int)  ## 0=友方胜 1=敌方胜 -1=平局

const PREVIEW_NEXT_ROUND_TAIL: int = 4   ## 行动条 UI 在本回合剩余之后再补几个下回合预览

var _units: Array[Unit] = []
var _turn_queue: Array[Unit] = []        ## 本回合尚未行动的单位（队首即下一个轮到的）
var _current_unit: Unit = null           ## 当前正在行动的单位
var _acted_this_round: Dictionary = {}   ## Unit -> true（本回合已行动完毕）
var _waited_this_round: Dictionary = {}  ## Unit -> true（本回合已使用过等待，限 1 次）
var round_num: int = 0
var _battle_running: bool = false


func register_units(units: Array) -> void:
	_units.clear()
	_turn_queue.clear()
	_acted_this_round.clear()
	_waited_this_round.clear()
	for u in units:
		if u is Unit:
			_units.append(u)
			u.action_completed.connect(_on_unit_action_completed)
			u.unit_died.connect(_on_unit_died)


func start_battle() -> void:
	_battle_running = true
	round_num = 0
	_start_new_round()
	_advance_to_next()


func _start_new_round() -> void:
	round_num += 1
	_acted_this_round.clear()
	_waited_this_round.clear()
	_turn_queue = _build_round_queue()
	round_started.emit(round_num)


## 按 effective_initiative 降序生成本回合行动队列（活着的单位）
func _build_round_queue() -> Array[Unit]:
	var alive: Array[Unit] = []
	for u in _units:
		if u.is_alive():
			alive.append(u)
	alive.sort_custom(func(a: Unit, b: Unit) -> bool:
		var ia: int = _eff_init(a)
		var ib: int = _eff_init(b)
		if ia != ib:
			return ia > ib
		# 同 init 时按注册顺序稳定（避免每帧重排）
		return _units.find(a) < _units.find(b)
	)
	return alive


## 当所有活着的单位本轮都行动过 → 进入下一轮
func _maybe_close_round() -> void:
	# 队列空 + 没有等待中的单位 = 本轮结束
	if _turn_queue.is_empty():
		round_ended.emit(round_num)
		_start_new_round()


# ──────────── 调度核心 ────────────
## 推进到下一个轮到的单位（队首）
func _advance_to_next() -> void:
	if not _battle_running:
		return
	if _check_battle_end():
		return

	# 跳过队首已死亡的单位
	while not _turn_queue.is_empty() and not _turn_queue[0].is_alive():
		_turn_queue.pop_front()

	if _turn_queue.is_empty():
		_maybe_close_round()
		# 新回合开始后队列已重建，递归推进
		if _battle_running and not _turn_queue.is_empty():
			_advance_to_next()
		return

	var u: Unit = _turn_queue.pop_front()
	_current_unit = u

	# 等待回来 vs 第一次轮到：等待回来不重置 AP/Fatigue
	var is_resumed_from_wait: bool = _waited_this_round.has(u)
	if is_resumed_from_wait:
		print("[TurnMgr] %s 等待恢复行动，AP=%d（不重置）" % [u.get_unit_name(), u.stats.ap if u.stats else -1])
	else:
		u.start_turn()  # 内部 reset_ap + recover_fatigue(15) + emit stats_changed
		print("[TurnMgr] %s 正常轮到，AP=%d" % [u.get_unit_name(), u.stats.ap if u.stats else -1])
	turn_started.emit(u)


## 让当前单位"等待"——第一次等待挪到队尾，第二次等待直接结束回合
##   - 不消耗 AP / Fatigue
##   - 第一次等待：挪到本回合队尾，再次轮到时不重置 AP/Fatigue
##   - 第二次等待（已等过）：直接结束回合，丢弃剩余 AP
##   - 返回 true = 等待/结束成功；false = 当前没人在行动 / 队列空
func wait_current() -> bool:
	if _current_unit == null or not _current_unit.is_alive():
		print("[Wait] 失败：无当前单位或已死亡")
		return false
	var u: Unit = _current_unit
	# 第二次等待：直接结束回合
	if _waited_this_round.has(u):
		print("[Wait] %s 已等待过，直接结束回合" % u.get_unit_name())
		u.end_turn()  # 触发 action_completed → _on_unit_action_completed → _advance_to_next
		return true
	# 第一次等待：队列空则无意义
	if _turn_queue.is_empty():
		print("[Wait] 失败：%s 是最后一个行动的，等待无意义" % u.get_unit_name())
		return false
	_waited_this_round[u] = true
	_turn_queue.push_back(u)
	_current_unit = null
	print("[Wait] 成功：%s 等待，排到队尾。剩余队列：%d 人" % [u.get_unit_name(), _turn_queue.size()])
	_advance_to_next()
	return true


## 查询当前单位是否可以等待（用于 UI 按钮状态）
##   - 已等待过 → 可以（实际是结束回合）
##   - 未等待过 + 队列空 → 不行（等了也没意义）
##   - 未等待过 + 队列非空 → 可以
func can_wait() -> bool:
	if _current_unit == null or not _current_unit.is_alive():
		return false
	if _waited_this_round.has(_current_unit):
		return true  # 第二次等待 = 结束回合，始终可用
	if _turn_queue.is_empty():
		return false  # 最后一个，第一次等待无意义
	return true


## 取单位的有效 Initiative（含护甲重量惩罚 + 先发制人加值）
func _eff_init(u: Unit) -> int:
	if u == null or u.stats == null:
		return 1
	var aw: int = u.armor.weight if u.armor else 0
	var ww: int = 0
	if u.weapon and u.weapon.has_method("get") and "weight" in u.weapon:
		ww = int(u.weapon.weight)
	var base_init: int = u.stats.effective_initiative(aw, ww)
	# 先发制人加值：上回合激活后影响本回合排序
	if u.preempt_active:
		base_init += u.preempt_initiative_bonus
	return base_init


# ──────────── 信号回调 ────────────
func _on_unit_action_completed(unit: Unit) -> void:
	turn_ended.emit(unit)
	if _current_unit == unit:
		_current_unit = null
	_acted_this_round[unit] = true
	# 行动完毕后从 waited 集合移除（避免影响下一回合的判定——其实下回合 _start_new_round 会清空）
	_advance_to_next()


func _on_unit_died(unit: Unit) -> void:
	# 死亡单位从队列移除
	_turn_queue.erase(unit)
	# 关键：如果死亡的是当前行动单位，必须推进调度，
	# 否则 TurnManager 卡死（_current_unit 指向死人，无人触发 _advance_to_next）
	if _current_unit == unit:
		_current_unit = null
		_acted_this_round[unit] = true
		_advance_to_next()
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


# ──────────── 对外查询接口 ────────────
func get_current_unit() -> Unit:
	return _current_unit


## 取行动顺序预览：本回合剩余（含当前）+ 下回合前 N 个预览（按 Init 排序）
## TopBar / 行动条 UI 使用
func get_turn_order_preview() -> Array[Unit]:
	var preview: Array[Unit] = []

	# 1) 当前单位放第 0 位
	if _current_unit != null and _current_unit.is_alive():
		preview.append(_current_unit)

	# 2) 本回合剩余队列（按当前队列顺序，已经反映了等待重排）
	for u in _turn_queue:
		if u.is_alive() and u != _current_unit:
			preview.append(u)

	# 3) 下回合预览（按 Init 排序，最多 PREVIEW_NEXT_ROUND_TAIL 个）
	var next_round: Array[Unit] = _build_round_queue()
	var added: int = 0
	for u in next_round:
		if added >= PREVIEW_NEXT_ROUND_TAIL:
			break
		preview.append(u)
		added += 1

	return preview


## 取"本回合已行动"的活着单位（不含当前正在行动的）
func get_acted_units() -> Array[Unit]:
	var arr: Array[Unit] = []
	for u in _units:
		if u.is_alive() and _acted_this_round.has(u) and u != _current_unit:
			arr.append(u)
	return arr


## 取"本回合等候行动"的活着单位（含当前）
func get_pending_units() -> Array[Unit]:
	var arr: Array[Unit] = []
	if _current_unit != null and _current_unit.is_alive():
		arr.append(_current_unit)
	for u in _turn_queue:
		if u.is_alive() and u != _current_unit:
			arr.append(u)
	return arr


## 取"下回合预备行动"的所有活着单位（按 Initiative 排序）
func get_next_round_queue() -> Array[Unit]:
	return _build_round_queue()


## 兼容旧 UI：原 get_ct(unit) 返回 0..100。新调度无 CT 概念，
## 返回 100（即"满"）作为默认；若有调用方需要进度条，应改用 has_acted/is_current 接口
func get_ct(unit: Unit) -> int:
	if _acted_this_round.has(unit):
		return 0
	if _current_unit == unit:
		return 100
	return 100


## 当前单位是否已使用本回合的等待
func has_waited(unit: Unit) -> bool:
	return _waited_this_round.has(unit)
