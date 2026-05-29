extends Node2D
class_name HexGrid
##
## HexGrid.gd — 六边形战场
##
## 职责：
##   - 渲染六边形地图（_draw 直接绘制，无需 TileSet 资源）
##   - 维护地图数据（哪些格子可走/被占用）
##   - 鼠标拾取 → 发出 hex_clicked 信号
##   - AStar2D 寻路、可达格 BFS、高亮渲染
##

const HEX_SIZE: float = 36.0  ## 六边形外接圆半径

@export var map_radius: int = 6  ## 地图半径（hex 个数，圆形地图）

# 信号
signal hex_clicked(axial: Vector2i)
signal hex_hovered(axial: Vector2i)

# 地图数据
var _hexes: Dictionary = {}            ## Vector2i -> bool (是否可走)
var _occupants: Dictionary = {}        ## Vector2i -> Unit (谁站在上面)

# 高亮缓存（用于 _draw）
var _highlight_move: Array[Vector2i] = []
var _highlight_attack: Array[Vector2i] = []
var _highlight_path: Array[Vector2i] = []
var _highlight_zoc: Array[Vector2i] = []  ## 敌方控制区（弱橙叠加）
var _highlight_oa_steps: Array[Vector2i] = []  ## 路径中会触发借机攻击的格子
var _highlight_selected: Vector2i = Vector2i(99999, 99999)
var _hover_hex: Vector2i = Vector2i(99999, 99999)

# AStar
var _astar: AStar2D = AStar2D.new()


func _ready() -> void:
	_generate_map()
	_build_astar()
	queue_redraw()


# ──────────── 地图生成 ────────────
func _generate_map() -> void:
	# 生成圆形地图（六边形围成的圆）
	for q in range(-map_radius, map_radius + 1):
		var r1: int = max(-map_radius, -q - map_radius)
		var r2: int = min(map_radius, -q + map_radius)
		for r in range(r1, r2 + 1):
			_hexes[Vector2i(q, r)] = true


func _build_astar() -> void:
	_astar.clear()
	# 添加所有 hex 为节点
	for axial in _hexes.keys():
		var id: int = HexCoord.axial_to_id(axial)
		var pixel: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		_astar.add_point(id, pixel)
	# 添加邻居连接
	for axial in _hexes.keys():
		var id: int = HexCoord.axial_to_id(axial)
		for n in HexCoord.neighbors(axial):
			if _hexes.has(n):
				var nid: int = HexCoord.axial_to_id(n)
				if not _astar.are_points_connected(id, nid):
					_astar.connect_points(id, nid)


# ──────────── 占用管理 ────────────
func is_walkable(axial: Vector2i) -> bool:
	return _hexes.has(axial) and not _occupants.has(axial)


func is_in_map(axial: Vector2i) -> bool:
	return _hexes.has(axial)


func get_occupant(axial: Vector2i):
	return _occupants.get(axial, null)


func set_occupant(axial: Vector2i, unit) -> void:
	if unit == null:
		_occupants.erase(axial)
	else:
		_occupants[axial] = unit
	# 占用变化要刷新 AStar 禁用状态
	_refresh_astar_disabled()


func move_occupant(from_axial: Vector2i, to_axial: Vector2i, unit) -> void:
	_occupants.erase(from_axial)
	_occupants[to_axial] = unit
	_refresh_astar_disabled()


func _refresh_astar_disabled() -> void:
	for axial in _hexes.keys():
		var id: int = HexCoord.axial_to_id(axial)
		_astar.set_point_disabled(id, _occupants.has(axial))


# ──────────── 寻路 ────────────
## 找路径（不含起点；含终点）
## ignore_occupant_at: 暂时把这个格子的占用解除（用于让单位自己出发时不被自己阻挡）
func find_path(from_axial: Vector2i, to_axial: Vector2i, ignore_occupant_at: Vector2i = Vector2i(99999, 99999)) -> Array[Vector2i]:
	if not _hexes.has(from_axial) or not _hexes.has(to_axial):
		return []
	var from_id: int = HexCoord.axial_to_id(from_axial)
	var to_id: int = HexCoord.axial_to_id(to_axial)

	# 临时解禁起点（自己站着也得能从起点出发）
	var from_was_disabled: bool = _astar.is_point_disabled(from_id)
	_astar.set_point_disabled(from_id, false)
	var ignore_was_disabled: bool = false
	var ignore_id: int = -1
	if ignore_occupant_at != Vector2i(99999, 99999) and _hexes.has(ignore_occupant_at):
		ignore_id = HexCoord.axial_to_id(ignore_occupant_at)
		ignore_was_disabled = _astar.is_point_disabled(ignore_id)
		_astar.set_point_disabled(ignore_id, false)

	var id_path: PackedInt64Array = _astar.get_id_path(from_id, to_id)

	# 还原
	_astar.set_point_disabled(from_id, from_was_disabled)
	if ignore_id != -1:
		_astar.set_point_disabled(ignore_id, ignore_was_disabled)

	if id_path.size() <= 1:
		return []
	# 转回 axial（去掉起点）
	var result: Array[Vector2i] = []
	for i in range(1, id_path.size()):
		var p: Vector2 = _astar.get_point_position(id_path[i])
		result.append(_pixel_to_axial_lookup(p))
	return result


## 反查：根据 AStar 存的 pixel 找到对应 axial（精确匹配避免 pixel_to_axial 浮点误差）
func _pixel_to_axial_lookup(pixel: Vector2) -> Vector2i:
	# 直接用数学反推（精确，因为 axial_to_pixel 是注入式映射）
	return HexCoord.pixel_to_axial(pixel, HEX_SIZE)


## 取从 origin 出发，AP/距离不超过 max_steps 的所有可达格（BFS）
func get_reachable(origin: Vector2i, max_steps: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if max_steps <= 0:
		return result
	var visited: Dictionary = {origin: 0}
	var queue: Array = [origin]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		var cur_step: int = visited[cur]
		if cur_step >= max_steps:
			continue
		for n in HexCoord.neighbors(cur):
			if not _hexes.has(n):
				continue
			if visited.has(n):
				continue
			if _occupants.has(n):
				continue
			visited[n] = cur_step + 1
			queue.append(n)
			result.append(n)
	return result


## 取攻击范围（距离 <= range 且有敌方单位的格子）
func get_attack_targets(origin: Vector2i, attack_range: int, attacker_faction: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for axial in _occupants.keys():
		if axial == origin:
			continue
		if HexCoord.distance(origin, axial) > attack_range:
			continue
		var unit = _occupants[axial]
		if unit and unit.has_method("get_faction") and unit.get_faction() != attacker_faction:
			result.append(axial)
	return result


# ──────────── 控制区（Zone of Control） ────────────
## 站在 cell 的单位 / 即将进入 cell 的单位，会被哪些敌方单位的 ZoC 控制？
## 规则：装备近战武器、还活着、阵营不同的单位，距离恰好 1 视为控制 cell。
## 不传 self_faction 时把所有敌方都算上（用于纯查询）。
func get_zoc_controllers(cell: Vector2i, self_faction: int) -> Array:
	var result: Array = []
	for n in HexCoord.neighbors(cell):
		var u = _occupants.get(n, null)
		if u == null:
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		if not u.has_method("get_faction") or u.get_faction() == self_faction:
			continue
		# 远程单位不产生 ZoC
		if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
			continue
		result.append(u)
	return result


## 取所有产生 ZoC 的格子（用于敌方阵营的"威胁地图"高亮）
func get_zoc_cells_of(enemy_faction: int) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var result: Array[Vector2i] = []
	for axial in _occupants.keys():
		var u = _occupants[axial]
		if u == null or not u.has_method("is_alive") or not u.is_alive():
			continue
		if not u.has_method("get_faction") or u.get_faction() != enemy_faction:
			continue
		if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
			continue
		for n in HexCoord.neighbors(axial):
			if not _hexes.has(n):
				continue
			if seen.has(n):
				continue
			seen[n] = true
			result.append(n)
	return result


## 沿一条路径走，识别每一步会触发哪些敌人借机攻击。
## 返回 Array[Dictionary]，每一步一个：{from, to, oa_attackers: Array[Unit]}
## 触发条件：上一格被某敌人控制，下一格不再被同一敌人控制（= 离开 ZoC）。
func analyze_path_oa(start: Vector2i, path: Array[Vector2i], self_faction: int) -> Array:
	var steps: Array = []
	var prev: Vector2i = start
	for step in path:
		var oa_list: Array = []
		var prev_ctrls: Array = get_zoc_controllers(prev, self_faction)
		for ctrl in prev_ctrls:
			# 离开 ctrl 的 ZoC = step 不再与 ctrl 相邻
			if HexCoord.distance(step, ctrl.axial_pos) > 1:
				oa_list.append(ctrl)
		steps.append({"from": prev, "to": step, "oa_attackers": oa_list})
		prev = step
	return steps


# ──────────── 高亮 API ────────────
func set_highlight_move(hexes: Array[Vector2i]) -> void:
	_highlight_move = hexes
	queue_redraw()


func set_highlight_attack(hexes: Array[Vector2i]) -> void:
	_highlight_attack = hexes
	queue_redraw()


func set_highlight_path(hexes: Array[Vector2i]) -> void:
	_highlight_path = hexes
	queue_redraw()


func set_highlight_zoc(hexes: Array[Vector2i]) -> void:
	_highlight_zoc = hexes
	queue_redraw()


func set_highlight_oa_steps(hexes: Array[Vector2i]) -> void:
	_highlight_oa_steps = hexes
	queue_redraw()


func set_selected(axial: Vector2i) -> void:
	_highlight_selected = axial
	queue_redraw()


func clear_highlights() -> void:
	_highlight_move.clear()
	_highlight_attack.clear()
	_highlight_path.clear()
	_highlight_zoc.clear()
	_highlight_oa_steps.clear()
	_highlight_selected = Vector2i(99999, 99999)
	queue_redraw()


# ──────────── 坐标工具（对外） ────────────
func axial_to_world(axial: Vector2i) -> Vector2:
	return HexCoord.axial_to_pixel(axial, HEX_SIZE) + position


func world_to_axial(world_pos: Vector2) -> Vector2i:
	return HexCoord.pixel_to_axial(world_pos - position, HEX_SIZE)


# ──────────── 输入处理 ────────────
## 注意：event.position 是 viewport 坐标，不是世界坐标。
## 用 get_global_mouse_position() 拿到真正的世界坐标（已包含 Camera 偏移修正）。
## 用 _input 而非 _unhandled_input，避免被 Control 节点（如 ColorRect 背景）静默拦截。
## 我们靠 _hexes.has(ax) 自己判断是否在地图内，UI 区域的过滤交给 BattleScene 用更精确的方式做。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hover_hex != ax:
			_hover_hex = ax
			queue_redraw()
			if _hexes.has(ax):
				hex_hovered.emit(ax)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hexes.has(ax):
			hex_clicked.emit(ax)


# ──────────── 渲染 ────────────
func _draw() -> void:
	# 设计风格：暗黑中世纪，土壤/石板配色
	var color_base := Color(0.18, 0.16, 0.14)        # 深棕
	var color_border := Color(0.35, 0.30, 0.22, 0.6) # 暗金边框
	var color_hover := Color(0.85, 0.69, 0.22, 0.18) # 暗金 hover
	var color_move := Color(0.29, 0.56, 0.85, 0.35)  # 蓝色移动
	var color_attack := Color(0.85, 0.29, 0.29, 0.45) # 红色攻击
	var color_path := Color(0.85, 0.69, 0.22, 0.55)  # 暗金路径
	var color_zoc := Color(0.95, 0.55, 0.25, 0.20)   # 弱橙：敌方 ZoC
	var color_oa := Color(1.0, 0.35, 0.25, 0.85)     # 强橙红：借机攻击触发点
	var color_selected := Color(0.91, 0.88, 0.81, 0.9) # 选中白边

	# 绘制所有 hex
	for axial in _hexes.keys():
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		# 底色
		draw_colored_polygon(pts, color_base)
		# 边框
		var pts_closed := pts.duplicate()
		pts_closed.append(pts[0])
		draw_polyline(pts_closed, color_border, 1.5, true)

	# 高亮：敌方 ZoC（先画，让 move 蓝叠在上面更直观）
	for axial in _highlight_zoc:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, color_zoc)

	# 高亮：移动范围
	for axial in _highlight_move:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, color_move)

	# 高亮：攻击范围
	for axial in _highlight_attack:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, color_attack)

	# 高亮：预览路径
	for axial in _highlight_path:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		draw_circle(center, 5.0, color_path)

	# 高亮：会触发借机攻击的步格（粗描边警示）
	for axial in _highlight_oa_steps:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 2.5)
		var pts_closed := pts.duplicate()
		pts_closed.append(pts[0])
		draw_polyline(pts_closed, color_oa, 2.5, true)

	# Hover
	if _hexes.has(_hover_hex):
		var center: Vector2 = HexCoord.axial_to_pixel(_hover_hex, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, color_hover)

	# 选中
	if _hexes.has(_highlight_selected):
		var center: Vector2 = HexCoord.axial_to_pixel(_highlight_selected, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		var pts_closed := pts.duplicate()
		pts_closed.append(pts[0])
		draw_polyline(pts_closed, color_selected, 2.5, true)
