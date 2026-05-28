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


func set_selected(axial: Vector2i) -> void:
	_highlight_selected = axial
	queue_redraw()


func clear_highlights() -> void:
	_highlight_move.clear()
	_highlight_attack.clear()
	_highlight_path.clear()
	_highlight_selected = Vector2i(99999, 99999)
	queue_redraw()


# ──────────── 坐标工具（对外） ────────────
func axial_to_world(axial: Vector2i) -> Vector2:
	return HexCoord.axial_to_pixel(axial, HEX_SIZE) + position


func world_to_axial(world_pos: Vector2) -> Vector2i:
	return HexCoord.pixel_to_axial(world_pos - position, HEX_SIZE)


# ──────────── 输入处理 ────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var ax: Vector2i = world_to_axial(event.position)
		if _hover_hex != ax:
			_hover_hex = ax
			queue_redraw()
			if _hexes.has(ax):
				hex_hovered.emit(ax)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ax: Vector2i = world_to_axial(event.position)
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
