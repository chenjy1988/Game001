extends RefCounted
class_name AIWorldView

const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _Self = preload("res://scripts/ai/world_view.gd")
##
## AIWorldView.gd — 只读世界快照
##
## 设计目标：
##   1. AI 引擎只读此快照，不直接操作 Unit/HexGrid/TurnManager。
##   2. capture() 每次决策前重新构建，保证世界状态是最新的。
##   3. 方便将来替换为纯数据（无头 sim 无需真实 Node）。
##
## 边界：
##   - 不包含 AI 内部状态（如 Intentions），那是 AIAgent 的事。
##   - 不缓存 —— 每次 capture 重新构建，内存开销可接受（≤12 单位）。
##

var unit = null             ## 当前决策单位
var all_units: Array = []         ## Array[Unit]（含己，含死）
var alive_allies: Array = []      ## 存活友方
var alive_enemies: Array = []     ## 存活敌方
var hex_grid = null               ## HexGrid（坐标/寻路/视野/迷雾查询）
var turn_manager = null           ## TurnManager（can_wait / has_waited）
var faction_brain: Dictionary = {}  ## 阵营快照（FactionBrain 产出，M1 接入）

# ── 远程优劣势缓存（capture 时计算，决策时消费）──
enum RangedBalance { ENEMY_ADVANTAGE, ALLY_ADVANTAGE, NEUTRAL }
var _ranged_balance: int = RangedBalance.NEUTRAL  ## 敌方远程 > 我方？

# ── 单位缓存（性能优化：避免每候选格调用 get_occupant 上色） ──
var _occupancy: Dictionary = {}   ## Vector2i → Unit（快速查占位）


## 构建快照。调用时机：每次 AI 决策前。
static func capture(p_unit, p_all_units: Array, p_hex_grid, p_turn_manager, p_faction_brain: Dictionary = {}):
	var v = _Self.new()
	v.unit = p_unit
	v.all_units = p_all_units
	v.hex_grid = p_hex_grid
	v.turn_manager = p_turn_manager
	v.faction_brain = p_faction_brain

	if p_unit != null:
		var my_faction: int = p_unit.get_faction()
		for u in p_all_units:
			if not u.is_alive():
				continue
			if u.get_faction() == my_faction:
				v.alive_allies.append(u)
			else:
				v.alive_enemies.append(u)

	# 构建占位快查表
	if p_hex_grid != null:
		for u in p_all_units:
			if u.is_alive():
				v._occupancy[u.axial_pos] = u

	# ── 远程优劣势评估 ──
	v._ranged_balance = v._eval_ranged_balance()

	return v


## 某格是否被占用（敌对单位跳过，友方/中立占位）
func is_occupied(axial: Vector2i, skip_unit = null) -> bool:
	if not _occupancy.has(axial):
		return false
	var u = _occupancy[axial]
	return u != skip_unit and u.is_alive()


## 某格是否可通行（可走 hex + 未被占用）
func is_passable(axial: Vector2i, skip_unit = null) -> bool:
	if hex_grid == null:
		return false
	if not hex_grid.is_walkable(axial):
		return false
	return not is_occupied(axial, skip_unit)


## 某格在迷雾中是否可见（M0 暂不消费，M2 接入视野偏好）
func is_visible(axial: Vector2i) -> bool:
	if hex_grid == null:
		return true
	return hex_grid.is_hex_visible(axial)


## 获取在某格的单位
func get_occupant(axial: Vector2i):
	return _occupancy.get(axial, null)


## 敌方存活人数
func enemy_count() -> int:
	return alive_enemies.size()


## 友方存活人数
func ally_count() -> int:
	return alive_allies.size()


## 到指定单位距离（hex 格数，不限路径）
func distance_to(other) -> int:
	if unit == null or other == null:
		return 999
	return _HexCoord.distance(unit.axial_pos, other.axial_pos)


## 寻找最近敌方及其距离
func nearest_enemy() -> Dictionary:
	var best = null
	var best_dist: int = 999
	for e in alive_enemies:
		var d: int = distance_to(e)
		if d < best_dist:
			best_dist = d
			best = e
	return { "unit": best, "distance": best_dist }


## 远程优劣势：敌方远程 > 我方 → 必须冲；我方远程 > 敌方 → 可以等
func ranged_balance() -> int:
	return _ranged_balance


func _eval_ranged_balance() -> int:
	var enemy_ranged: int = 0
	var ally_ranged: int = 0
	for u in alive_enemies:
		if u.weapon != null and u.weapon.weapon_type == "ranged":
			enemy_ranged += 1
	for u in alive_allies:
		if u.weapon != null and u.weapon.weapon_type == "ranged":
			ally_ranged += 1
	if enemy_ranged > ally_ranged:
		return RangedBalance.ENEMY_ADVANTAGE
	elif ally_ranged > enemy_ranged:
		return RangedBalance.ALLY_ADVANTAGE
	return RangedBalance.NEUTRAL


## 当前单位能否等待（can_wait 无参，检查当前正在行动的单位）
func can_wait() -> bool:
	if turn_manager == null:
		return false
	# can_wait() 无参：TurnManager 已绑定 _current_unit，自动判断
	if not turn_manager.has_method("can_wait"):
		return false
	if not turn_manager.has_method("has_waited"):
		return false
	# 等待规则：未等待过且队列非空 → 可等待；已等待过 → 第二次 Q = 结束回合时也可
	return turn_manager.can_wait() and not turn_manager.has_waited(unit)


## 本回合是否已 Q 过（Wait 恢复行动后为 true）
func has_waited_this_turn() -> bool:
	if turn_manager == null or unit == null:
		return false
	if not turn_manager.has_method("has_waited"):
		return false
	return turn_manager.has_waited(unit)
