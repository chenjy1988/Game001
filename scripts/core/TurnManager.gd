extends Node
class_name TurnManager

const _Unit = preload("res://scripts/core/Unit.gd")
const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")
##
## TurnManager.gd — AP + 回合制调度器（DOS2 风，简化版）
##
## 设计要点（参考 design.md § 十二）：
##   • 每回合开始时，按 effective_initiative 降序一次性排出本回合的 _turn_queue，
##     按队首推进。Init 仅决定回合内顺序，不决定频率——每个活着的单位每回合 1 次。
##
##   • 等待（Wait）机制：第一次 Q → 挪到本回合队尾（不消耗 AP，+WAIT_STAMINA_COST 气力；
##     再次轮到不重置 AP）；第二次 Q（本回合已等待过）→ 视为结束回合，剩余 AP 作废。
##     每回合每单位仅可「延后」1 次。
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

signal turn_started(unit:_Unit)
signal turn_ended(unit:_Unit)
signal round_started(round_num: int)
signal round_ended(round_num: int)
signal battle_ended(winner_faction: int)  ## 0=友方胜 1=敌方胜 -1=平局

const PREVIEW_NEXT_ROUND_TAIL: int = 4   ## 行动条 UI 在本回合剩余之后再补几个下回合预览
const WAIT_STAMINA_COST: int = 5         ## 等待 base（design.md §三）；实际 = ceil(base × weight_mult)

var _units: Array[_Unit] = []
var _turn_queue: Array[_Unit] = []        ## 本回合尚未行动的单位（队首即下一个轮到的）
var _current_unit:_Unit = null           ## 当前正在行动的单位
var _acted_this_round: Dictionary = {}   ## Unit -> true（本回合已行动完毕）
var _waited_this_round: Dictionary = {}  ## Unit -> true（本回合已使用过等待，限 1 次）
var round_num: int = 0
var _battle_running: bool = false
var _init_tie_seed: int = 0


func set_init_tie_seed(seed: int) -> void:
	_init_tie_seed = seed


func is_running() -> bool:
	return _battle_running


func register_units(units: Array) -> void:
	_units.clear()
	_turn_queue.clear()
	_acted_this_round.clear()
	_waited_this_round.clear()
	for u in units:
		if u is _Unit:
			_units.append(u)
			u.action_completed.connect(_on_unit_action_completed)
			u.unit_died.connect(_on_unit_died)


func start_battle() -> void:
	_battle_running = true
	round_num = 0
	for u in _units:
		if u != null and u.is_alive() and u.has_method("get_effect_container"):
			u.get_effect_container().notify_combat_started()
	_start_new_round()
	_advance_to_next()


func _start_new_round() -> void:
	round_num += 1
	_acted_this_round.clear()
	_waited_this_round.clear()
	_turn_queue = _build_round_queue()
	round_started.emit(round_num)


## 按 effective_initiative 降序生成本回合行动队列（活着的单位）
func _build_round_queue() -> Array[_Unit]:
	var alive: Array[_Unit] = []
	for u in _units:
		if u.is_alive():
			alive.append(u)
	alive.sort_custom(func(a:_Unit, b:_Unit) -> bool:
		var ia: int = _eff_init(a)
		var ib: int = _eff_init(b)
		if ia != ib:
			return ia > ib
		return _init_sort_before(a, b)
	)
	return alive


## 同 Init 排序：默认注册序；镜像 sim 设 tie_seed 后按单位 hash 公平打破
func _init_sort_before(a: _Unit, b: _Unit) -> bool:
	if _init_tie_seed != 0:
		return _unit_init_tie_key(a) < _unit_init_tie_key(b)
	return _units.find(a) < _units.find(b)


func _unit_init_tie_key(u: _Unit) -> int:
	var pos: Vector2i = u.axial_pos if u != null else Vector2i.ZERO
	var name_h: int = u.get_unit_name().hash() if u != null else 0
	return (name_h ^ (pos.x * 83492791) ^ (pos.y * 1939391) ^ _init_tie_seed) & 0x7FFFFFFF


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

	var u:_Unit = _turn_queue.pop_front()
	_current_unit = u

	# 等待回来 vs 第一次轮到：等待回来不重置 AP/Fatigue
	var is_resumed_from_wait: bool = _waited_this_round.has(u)
	if is_resumed_from_wait:
		print("[TurnMgr] %s 等待恢复行动，AP=%d（不重置）" % [u.get_unit_name(), u.stats.ap if u.stats else -1])
	else:
		u.start_turn()  # 内部 reset_ap + restore_stamina(15) + emit stats_changed
		print("[TurnMgr] %s 正常轮到，AP=%d" % [u.get_unit_name(), u.stats.ap if u.stats else -1])
	turn_started.emit(u)


## 让当前单位"等待"——第一次挪到队尾，第二次视为结束回合
##   - 不消耗 AP；首次等待 +WAIT_STAMINA_COST 气力
##   - 第一次等待：挪到本回合队尾，再次轮到时不重置 AP（气力已扣，不恢复）
##   - 第二次等待（已等过）：直接 end_turn，丢弃剩余 AP（无额外气力惩罚）
##   - 返回 true = 等待/结束成功；false = 无当前单位 / 队列空（首次等待时）
func wait_current() -> bool:
	if _current_unit == null or not _current_unit.is_alive():
		print("[Wait] 失败：无当前单位或已死亡")
		return false
	var u:_Unit = _current_unit
	if _waited_this_round.has(u):
		print("[Wait] %s 已等待过，直接结束回合" % u.get_unit_name())
		u.end_turn()
		return true
	if _turn_queue.is_empty():
		print("[Wait] 失败：%s 是最后一个行动的，等待无意义" % u.get_unit_name())
		return false
	_waited_this_round[u] = true
	var wait_cost: int = 0
	if u.stats:
		wait_cost = _DamageSystem.calculate_action_stamina_cost(
			u, _DamageSystem.WAIT_STAMINA_BASE)
		u.stats.spend_stamina(wait_cost)
		u.stats_changed.emit(u)
	_turn_queue.push_back(u)
	_current_unit = null
	print("[Wait] 成功：%s 等待，排到队尾，气力 -%d。剩余队列：%d 人" % [
		u.get_unit_name(), wait_cost, _turn_queue.size()])
	_advance_to_next()
	return true


## 查询当前单位是否可以等待（用于 UI 按钮状态）
##   - 已等待过 → 可以（第二次 Q = 结束回合）
##   - 未等待过 + 队列空 → 不行
##   - 未等待过 + 队列非空 → 可以（第一次 Q = 排到队尾）
func can_wait() -> bool:
	if _current_unit == null or not _current_unit.is_alive():
		return false
	if _waited_this_round.has(_current_unit):
		return true
	if _turn_queue.is_empty():
		return false
	return true


## 取单位的有效 Initiative（含护甲重量惩罚 + 先发制人加值）
func _eff_init(u:_Unit) -> int:
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
func _on_unit_action_completed(unit:_Unit) -> void:
	turn_ended.emit(unit)
	if _current_unit == unit:
		_current_unit = null
	_acted_this_round[unit] = true
	# 行动完毕后从 waited 集合移除（避免影响下一回合的判定——其实下回合 _start_new_round 会清空）
	_advance_to_next()


func _on_unit_died(unit:_Unit) -> void:
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
func get_current_unit() -> _Unit:
	return _current_unit


## 取行动顺序预览：本回合剩余（含当前）+ 下回合前 N 个预览（按 Init 排序）
## TopBar / 行动条 UI 使用
func get_turn_order_preview() -> Array[_Unit]:
	var preview: Array[_Unit] = []

	# 1) 当前单位放第 0 位
	if _current_unit != null and _current_unit.is_alive():
		preview.append(_current_unit)

	# 2) 本回合剩余队列（按当前队列顺序，已经反映了等待重排）
	for u in _turn_queue:
		if u.is_alive() and u != _current_unit:
			preview.append(u)

	# 3) 下回合预览（按 Init 排序，最多 PREVIEW_NEXT_ROUND_TAIL 个）
	var next_round: Array[_Unit] = _build_round_queue()
	var added: int = 0
	for u in next_round:
		if added >= PREVIEW_NEXT_ROUND_TAIL:
			break
		preview.append(u)
		added += 1

	return preview


## 取"本回合已行动"的活着单位（不含当前正在行动的）
func get_acted_units() -> Array[_Unit]:
	var arr: Array[_Unit] = []
	for u in _units:
		if u.is_alive() and _acted_this_round.has(u) and u != _current_unit:
			arr.append(u)
	return arr


## 取"本回合等候行动"的活着单位（含当前）
func get_pending_units() -> Array[_Unit]:
	var arr: Array[_Unit] = []
	if _current_unit != null and _current_unit.is_alive():
		arr.append(_current_unit)
	for u in _turn_queue:
		if u.is_alive() and u != _current_unit:
			arr.append(u)
	return arr


## 取"下回合预备行动"的所有活着单位（按 Initiative 排序）
func get_next_round_queue() -> Array[_Unit]:
	return _build_round_queue()


## 兼容旧 UI：原 get_ct(unit) 返回 0..100。新调度无 CT 概念，
## 返回 100（即"满"）作为默认；若有调用方需要进度条，应改用 has_acted/is_current 接口
func get_ct(unit:_Unit) -> int:
	if _acted_this_round.has(unit):
		return 0
	if _current_unit == unit:
		return 100
	return 100


## 当前单位是否已使用本回合的等待
func has_waited(unit:_Unit) -> bool:
	return _waited_this_round.has(unit)
