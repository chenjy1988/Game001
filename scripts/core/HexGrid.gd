extends Node2D
class_name HexGrid
##
## HexGrid.gd — 六边形战场
##

const HEX_SIZE: float = 36.0  ## 六边形外接圆半径

@export var map_radius: int = 6  ## 地图半径（hex 个数，圆形地图）

# ─── 地形纹理 ───
const _TILE_DIR: String = "res://assets/terrain/ai/"
const _ATLAS_DIR: String = "res://assets/terrain/ai/atlas/"
var _atlas_by_biome: Dictionary = {}
var _hex_biome: Dictionary = {}
const EDGE_SUBDIV: int = 6     # 每条边插 6 个中间点
const CORNER_JITTER: float = 4.0
const EDGE_JITTER: float = 10.0  # 三角扇方式下可以大幅扰动，不会自交
var _terrain_noise: FastNoiseLite

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
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = 7531
	_terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_terrain_noise.frequency = 0.025
	_terrain_noise.fractal_octaves = 2
	_generate_map()
	_build_astar()
	_load_terrain_textures()
	_assign_hex_tiles()
	queue_redraw()


# ──────────── 地形加载 ────────────
func _load_terrain_textures() -> void:
	for b in ["grass", "leaf", "rocky", "dirt"]:
		var path := "%s%s.png" % [_ATLAS_DIR, b]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_atlas_by_biome[b] = tex


func _assign_hex_tiles() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 20260531
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.10
	noise.fractal_octaves = 2
	for axial in _hexes.keys():
		var v: float = noise.get_noise_2d(float(axial.x), float(axial.y))
		var biome: String
		if v < -0.45:
			biome = "dirt"
		elif v < -0.15:
			biome = "leaf"
		elif v > 0.35:
			biome = "rocky"
		else:
			biome = "grass"
		_hex_biome[axial] = biome
	# majority filter 消除孤立 hex
	for _pass in range(2):
		var new_biome: Dictionary = {}
		for axial in _hexes.keys():
			var counts: Dictionary = {}
			var self_b: String = _hex_biome[axial]
			counts[self_b] = 1
			for n in HexCoord.neighbors(axial):
				if not _hexes.has(n):
					continue
				var nb: String = _hex_biome[n]
				counts[nb] = counts.get(nb, 0) + 1
			var best_b: String = self_b
			var best_c: int = counts[self_b]
			for b in counts.keys():
				if counts[b] > best_c:
					best_c = counts[b]
					best_b = b
			new_biome[axial] = best_b
		_hex_biome = new_biome


func _terrain_offset(p: Vector2) -> Vector2:
	var nx: float = _terrain_noise.get_noise_2d(p.x, p.y)
	var ny: float = _terrain_noise.get_noise_2d(p.x + 1024.7, p.y - 873.3)
	return Vector2(nx, ny)


func _terrain_edge_wave(p: Vector2) -> float:
	# 中低频混合：在 36px 格子上产生可见的有机曲线
	var low: float = _terrain_noise.get_noise_2d(p.x * 2.5, p.y * 2.5)
	var mid: float = _terrain_noise.get_noise_2d(p.x * 6.0 + 333.1, p.y * 6.0 - 111.7)
	return low * 0.6 + mid * 0.4


func _wavy_hex_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var corners: PackedVector2Array = HexCoord.corners(center, radius)
	var poly: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var c0: Vector2 = corners[i]
		var c1: Vector2 = corners[(i + 1) % 6]
		# canonical edge direction（确保相邻 hex 算出相同法线）
		var a: Vector2 = c0
		var b: Vector2 = c1
		if (b.x < a.x) or (b.x == a.x and b.y < a.y):
			var tmp: Vector2 = a; a = b; b = tmp
		var edge_dir: Vector2 = (b - a).normalized()
		var edge_normal: Vector2 = Vector2(-edge_dir.y, edge_dir.x)
		# corner：用世界坐标 noise 偏移（3 hex 共享同一 corner，偏移相同，无缝隙）
		poly.append(c0 + _terrain_offset(c0) * CORNER_JITTER)
		# 中间点：仅沿法线方向位移（低频 noise，不会自交）
		for s in range(1, EDGE_SUBDIV + 1):
			var t: float = float(s) / float(EDGE_SUBDIV + 1)
			var p: Vector2 = c0.lerp(c1, t)
			poly.append(p + edge_normal * (_terrain_edge_wave(p) * EDGE_JITTER))
	return poly



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
func find_path(from_axial: Vector2i, to_axial: Vector2i, ignore_occupant_at: Vector2i = Vector2i(99999, 99999), self_faction: int = -1) -> Array[Vector2i]:
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

	# 临时解禁同阵营友方占用格子（允许路径穿过，但终点不能停在友方格）
	var ally_restores: Array = []
	if self_faction >= 0:
		for axial in _occupants.keys():
			if axial == ignore_occupant_at:
				continue
			var u = _occupants[axial]
			if u == null or not u.has_method("get_faction") or u.get_faction() != self_faction:
				continue
			if not u.has_method("is_alive") or not u.is_alive():
				continue
			var aid: int = HexCoord.axial_to_id(axial)
			if _astar.is_point_disabled(aid):
				ally_restores.append([aid, axial])
				_astar.set_point_disabled(aid, false)

	var id_path: PackedInt64Array = _astar.get_id_path(from_id, to_id)

	# 还原
	_astar.set_point_disabled(from_id, from_was_disabled)
	if ignore_id != -1:
		_astar.set_point_disabled(ignore_id, ignore_was_disabled)
	for pair in ally_restores:
		_astar.set_point_disabled(pair[0], true)

	if id_path.size() <= 1:
		return []
	# 转回 axial（去掉起点；终点若是友方格则返回空——不能停在友方格）
	var result: Array[Vector2i] = []
	for i in range(1, id_path.size()):
		var p: Vector2 = _astar.get_point_position(id_path[i])
		result.append(_pixel_to_axial_lookup(p))
	# 终点不能是友方占用格
	if result.size() > 0 and _occupants.has(result[-1]):
		var end_occ = _occupants[result[-1]]
		if end_occ != null and end_occ.has_method("get_faction") \
				and self_faction >= 0 and end_occ.get_faction() == self_faction:
			return []
	return result


## 反查：根据 AStar 存的 pixel 找到对应 axial（精确匹配避免 pixel_to_axial 浮点误差）
func _pixel_to_axial_lookup(pixel: Vector2) -> Vector2i:
	# 直接用数学反推（精确，因为 axial_to_pixel 是注入式映射）
	return HexCoord.pixel_to_axial(pixel, HEX_SIZE)


## 取从 origin 出发，AP/距离不超过 max_steps 的所有可达格（BFS）
func get_reachable(origin: Vector2i, max_steps: int, self_faction: int = -1) -> Array[Vector2i]:
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
				var occ = _occupants[n]
				# 友方活着的单位：可穿越但不能停留
				var is_passable_ally: bool = self_faction >= 0 and occ != null \
					and occ.has_method("get_faction") and occ.get_faction() == self_faction \
					and occ.has_method("is_alive") and occ.is_alive()
				if not is_passable_ally:
					continue  # 敌方或死亡单位：不可通行
				# 友方格子：加入搜索队列但不加入可停留结果
				visited[n] = cur_step + 1
				queue.append(n)
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
	# ZoC 固定为周身 1 格，与武器射程无关
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
	# ZoC 固定为周身 1 格，与武器射程无关
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
## 规则：出发格在敌人周身 1 格内就触发，无任何例外。
## moving_unit 使用滑步（ignore_oa_this_move=true）时返回空列表
func analyze_path_oa(start: Vector2i, path: Array[Vector2i], self_faction: int, moving_unit = null) -> Array:
	var steps: Array = []
	var prev: Vector2i = start
	var ignore_oa: bool = moving_unit != null and moving_unit.get("ignore_oa_this_move") == true
	for step in path:
		var oa_list: Array = [] if ignore_oa else get_zoc_controllers(prev, self_faction)
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


## 返回地图在世界坐标下的 AABB（供相机自适应使用）
func get_map_bounds() -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var margin: float = HEX_SIZE + 4.0
	for axial in _hexes.keys():
		var c: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		min_v.x = min(min_v.x, c.x - margin)
		min_v.y = min(min_v.y, c.y - margin)
		max_v.x = max(max_v.x, c.x + margin)
		max_v.y = max(max_v.y, c.y + margin)
	if min_v.x == INF:
		return Rect2(Vector2.ZERO, Vector2(100, 100))
	return Rect2(min_v, max_v - min_v)

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
			# 永远 emit（即便光标离开地图），让上层决定如何处理"无效格"
			hex_hovered.emit(ax)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hexes.has(ax):
			hex_clicked.emit(ax)


# ──────────── 渲染 ────────────
## 60Hz 推动重绘，用于高亮呼吸/路径动画
func _process(_delta: float) -> void:
	if not _highlight_move.is_empty() or not _highlight_attack.is_empty() \
			or not _highlight_oa_steps.is_empty() or not _highlight_path.is_empty():
		queue_redraw()


func _draw() -> void:
	# 颜色定义
	var color_base_top := Color(0.24, 0.21, 0.18)
	var color_base_bot := Color(0.13, 0.11, 0.09)
	var color_border   := Color(0.42, 0.36, 0.26, 0.75)
	var color_inner_hi := Color(0.55, 0.47, 0.32, 0.18)
	var color_hover    := Color(0.95, 0.80, 0.30, 0.22)
	var color_move     := Color(0.29, 0.56, 0.85, 0.40)
	var color_attack   := Color(0.85, 0.29, 0.29, 0.50)
	var color_path     := Color(0.95, 0.78, 0.30, 0.85)
	var color_zoc      := Color(0.95, 0.55, 0.25, 0.16)
	var color_oa       := Color(1.0, 0.40, 0.25, 0.92)
	var color_selected := Color(0.95, 0.90, 0.78, 0.95)

	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)
	var fast_breath: float = 0.5 + 0.5 * sin(t_ms / 220.0)

	# ---- 1) 地形纹理（有纹理时用纹理，否则回退到着色多边形） ----
	var tile_radius: float = HEX_SIZE + 3.5
	var atlas_uv_scale: float = 1.0 / 256.0
	var tri_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])

	for axial in _hexes.keys():
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var biome: String = _hex_biome.get(axial, "grass")
		var atlas: Texture2D = _atlas_by_biome.get(biome, null)
		var border_pts: PackedVector2Array = _wavy_hex_polygon(center, tile_radius)
		var n: int = border_pts.size()
		if atlas != null:
			# 三角扇绘制：center → edge[i] → edge[i+1]
			# 每个三角形单独调用，保证不会自交
			for i in range(n):
				var v0: Vector2 = center
				var v1: Vector2 = border_pts[i]
				var v2: Vector2 = border_pts[(i + 1) % n]
				var pts := PackedVector2Array([v0, v1, v2])
				var uvs := PackedVector2Array([
					v0 * atlas_uv_scale,
					v1 * atlas_uv_scale,
					v2 * atlas_uv_scale
				])
				draw_polygon(pts, tri_colors, uvs, atlas)
		else:
			# 回退：着色多边形
			var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
			draw_colored_polygon(pts, color_base_bot)
			var pts_inner: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 3.5)
			draw_colored_polygon(pts_inner, color_base_top)
			_draw_top_highlight(pts_inner, color_inner_hi)
			var pts_closed := pts.duplicate()
			pts_closed.append(pts[0])
			draw_polyline(pts_closed, color_border, 1.6, true)

	# ---- 2) 敌方 ZoC（最底层叠加） ----
	for axial in _highlight_zoc:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, color_zoc)

	# ---- 3) 移动范围（呼吸动画） ----
	var move_alpha: float = color_move.a * (0.7 + 0.3 * breath)
	for axial in _highlight_move:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, Color(color_move.r, color_move.g, color_move.b, move_alpha))

	# ---- 4) 攻击范围（呼吸 + 内部短描边） ----
	var atk_alpha: float = color_attack.a * (0.7 + 0.3 * breath)
	for axial in _highlight_attack:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, Color(color_attack.r, color_attack.g, color_attack.b, atk_alpha))
		# 红色细边强化
		var pts_atk_edge: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 4.0)
		var pts_closed := pts_atk_edge.duplicate()
		pts_closed.append(pts_atk_edge[0])
		draw_polyline(pts_closed, Color(0.95, 0.35, 0.30, 0.5), 1.2, true)

	# ---- 5) 路径（朝下一格的渐进金色三角） ----
	for i in range(_highlight_path.size()):
		var axial: Vector2i = _highlight_path[i]
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		# 越靠近终点越亮
		var t: float = (float(i) + 1.0) / float(_highlight_path.size())
		var alpha: float = lerp(0.4, 0.95, t)
		draw_circle(center, 6.0 + breath * 1.5, Color(color_path.r, color_path.g, color_path.b, alpha))

	# ---- 6) 借机攻击触发点（强烈呼吸 + 双层描边警示） ----
	var oa_color := Color(color_oa.r, color_oa.g, color_oa.b, color_oa.a * (0.6 + 0.4 * fast_breath))
	for axial in _highlight_oa_steps:
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts_outer: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 2.0)
		var pts_inner_warn: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 5.0)
		var po := pts_outer.duplicate(); po.append(pts_outer[0])
		var pi := pts_inner_warn.duplicate(); pi.append(pts_inner_warn[0])
		draw_polyline(po, oa_color, 3.0, true)
		draw_polyline(pi, Color(oa_color.r, oa_color.g, oa_color.b, oa_color.a * 0.5), 1.2, true)

	# ---- 7) Hover ----
	if _hexes.has(_hover_hex):
		var center: Vector2 = HexCoord.axial_to_pixel(_hover_hex, HEX_SIZE)
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		draw_colored_polygon(pts, color_hover)

	# ---- 8) 选中（白金边 + 慢呼吸 + 外圈柔光） ----
	if _hexes.has(_highlight_selected):
		var center: Vector2 = HexCoord.axial_to_pixel(_highlight_selected, HEX_SIZE)
		# 外柔光（更大六边形，alpha 极低）
		var glow_pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE + 4.0)
		draw_colored_polygon(glow_pts, Color(1.0, 0.95, 0.75, 0.10 + 0.06 * breath))
		# 描边
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		var pts_closed := pts.duplicate()
		pts_closed.append(pts[0])
		draw_polyline(pts_closed, color_selected, 2.8, true)


## 在六边形"上半"3 条边沿内侧画一条更亮的细线，营造"内凹光照"感
func _draw_top_highlight(pts: PackedVector2Array, color: Color) -> void:
	# pointy-top 六边形的顶点顺序：12点-2点-4点-6点-8点-10点
	# 上半边 = [10点→12点, 12点→2点, 2点→4点]
	# 对应索引（HexCoord.corners 从右上开始？）我们保守画 3 段相邻边
	# 找出 y 最小的顶点作为"顶"，然后向两侧各延伸一条边
	var top_idx: int = 0
	for i in range(pts.size()):
		if pts[i].y < pts[top_idx].y:
			top_idx = i
	var idx_prev: int = (top_idx - 1 + pts.size()) % pts.size()
	var idx_next: int = (top_idx + 1) % pts.size()
	var idx_prev2: int = (top_idx - 2 + pts.size()) % pts.size()
	# 画 3 段
	draw_line(pts[idx_prev2], pts[idx_prev], color, 1.2, true)
	draw_line(pts[idx_prev],  pts[top_idx],  color, 1.2, true)
	draw_line(pts[top_idx],   pts[idx_next], color, 1.2, true)
