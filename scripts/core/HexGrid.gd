extends Node2D
class_name HexGrid
##
## HexGrid.gd — 六边形战场
##

const HEX_SIZE: float = 36.0  ## 六边形外接圆半径

@export var map_radius: int = 6  ## 地图半径（hex 个数，圆形地图）
@export var skip_obstacle_generation: bool = false  ## 仿真/调试：跳过随机障碍，保证出生区连通

# ─── 地形纹理 ───
const _TILE_DIR: String = "res://assets/terrain/ai/"
const _ATLAS_DIR: String = "res://assets/terrain/ai/atlas/"
var _atlas_by_biome: Dictionary = {}
var _hex_biome: Dictionary = {}
var _obstacles: Dictionary = {}         ## axial → int(0-2)，障碍格 + 随机纹理索引
var _obstacle_textures: Array = []      ## rocky_0/1/2.png
var _transition_textures: Dictionary = {}  ## biome → { dir_index → Texture2D }
var _hex_border_cache: Dictionary = {}  ## axial → PackedVector2Array，预计算地形顶点缓存
var _terrain_layer: Node2D = null       ## 独立地形层：只在初始化时绘制一次
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
var _elevation: Dictionary = {}        ## Vector2i -> int (0=平地 1=高地 -1=低地)

# ─── 战争迷雾 ───
var fog_enabled: bool = true           ## 是否启用战争迷雾
var _visible_hexes: Dictionary = {}    ## axial -> true（当前帧可见）
var _explored_hexes: Dictionary = {}   ## axial -> true（历史上曾可见）
const DEFAULT_SIGHT_RANGE: int = 5     ## 默认视野半径（hex 格数）

## 获取地形高度（未设置默认 0）
func get_elevation(axial: Vector2i) -> int:
	return _elevation.get(axial, 0)

## 设置地形高度
func set_elevation(axial: Vector2i, level: int) -> void:
	if level == 0:
		_elevation.erase(axial)
	else:
		_elevation[axial] = level

# 高亮缓存（用于 _draw）
var _highlight_move: Array[Vector2i] = []
var _highlight_attack_markers: Array[Vector2i] = [] ## 射程内非敌方格（小灰标）
var _highlight_attack_enemy: Array[Vector2i] = []   ## 射程内可攻击敌方格（小红标）
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
	if not skip_obstacle_generation:
		_generate_obstacles()   # 随机障碍（含连通性验证）
	_build_astar()
	_load_terrain_textures()
	_assign_hex_tiles()

	# 地形层：独立子节点，只绘制一次，之后不再重绘
	_terrain_layer = Node2D.new()
	_terrain_layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_terrain_layer.show_behind_parent = true  # 渲染在父节点 _draw()（高亮层）之后
	add_child(_terrain_layer)
	_terrain_layer.draw.connect(_draw_terrain)
	_terrain_layer.queue_redraw()

	queue_redraw()  # 高亮层首次绘制


# ──────────── 地形加载 ────────────
func _load_terrain_textures() -> void:
	for b in ["grass", "leaf", "rocky", "dirt"]:
		var path := "%s%s.png" % [_ATLAS_DIR, b]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_atlas_by_biome[b] = tex
	# 障碍物纹理：rocky_0/1/2（随机选一个让每个障碍格看起来不同）
	_obstacle_textures.clear()
	for i in range(3):
		var path := "%srocky_%d.png" % [_TILE_DIR, i]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_obstacle_textures.append(tex)

	# 过渡纹理：transition/<biome>_dir<n>.png（4种地形 × 6方向 = 24张）
	var trans_dir: String = _TILE_DIR + "transition/"
	for b in ["grass", "leaf", "rocky", "dirt"]:
		_transition_textures[b] = {}
		for d in range(6):
			var path := "%s%s_dir%d.png" % [trans_dir, b, d]
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex != null:
					_transition_textures[b][d] = tex


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

	# 预计算每个格子的地形顶点（避免 _draw 每帧重算噪声）
	var tile_radius: float = HEX_SIZE + 3.5
	_hex_border_cache.clear()
	for axial in _hexes.keys():
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		_hex_border_cache[axial] = _wavy_hex_polygon(center, tile_radius)


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


## 随机生成障碍格（不可走），含 BFS 连通性验证。
## 保护区：中央核心 + 双方出生带 不放障碍。
## 障碍密度目标约 12%，若连通性不足则逐步恢复障碍直到满足阈值。
func _generate_obstacles() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = randi()                        # 每局随机种子
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.35
	noise.fractal_octaves = 2

	var candidates: Array[Vector2i] = []
	for axial in _hexes.keys():
		# 中央核心保护（半径 2 内不放障碍）
		if HexCoord.distance(axial, Vector2i.ZERO) <= 2:
			continue
		# 双方出生带保护（按地图半径推算左右对峙区，避免出生点被随机障碍占用）
		var spawn_margin: int = max(3, map_radius - 6)
		if axial.x <= -spawn_margin or axial.x >= spawn_margin:
			continue
		var v: float = noise.get_noise_2d(float(axial.x), float(axial.y))
		if v > 0.38:       # ~12% 概率成为障碍
			candidates.append(axial)

	# 移除候选障碍
	for axial in candidates:
		_hexes.erase(axial)

	# BFS 连通性验证：从中心出发，统计可达格数
	# 若可达率 < 阈值，逐步恢复障碍直到满足要求
	const CONNECTIVITY_THRESHOLD: float = 0.82
	var total_before: int = _hexes.size() + candidates.size()
	candidates.shuffle()   # 随机顺序恢复，避免系统性偏差
	var restore_idx: int = 0
	while true:
		var reachable: int = _count_reachable(Vector2i.ZERO)
		if float(reachable) / float(max(1, _hexes.size())) >= CONNECTIVITY_THRESHOLD:
			break
		if restore_idx >= candidates.size():
			break   # 所有候选都恢复了，放弃强制验证
		_hexes[candidates[restore_idx]] = true
		restore_idx += 1

	var obstacle_count: int = candidates.size() - restore_idx
	# 记录最终障碍格（用于渲染）
	_obstacles.clear()
	for i in range(restore_idx, candidates.size()):
		_obstacles[candidates[i]] = randi() % 3   # 随机纹理索引 0/1/2
	print("[HexGrid] 地图生成完成：总格数=%d 障碍=%d(%.0f%%)" % [
		_hexes.size(), obstacle_count,
		float(obstacle_count) / float(total_before) * 100.0
	])


## BFS 统计从 origin 出发可达的格子数（仅用于连通性验证）
func _count_reachable(origin: Vector2i) -> int:
	if not _hexes.has(origin):
		# origin 被移除，找最近的有效格
		for axial in _hexes.keys():
			origin = axial
			break
	var visited: Dictionary = {}
	var queue: Array = [origin]
	visited[origin] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for n in HexCoord.neighbors(cur):
			if _hexes.has(n) and not visited.has(n):
				visited[n] = true
				queue.append(n)
	return visited.size()


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


func is_obstacle(axial: Vector2i) -> bool:
	return _obstacles.has(axial)


## 寻找距 preferred 最近的可站立格（可走且未被占用）；找不到则返回 preferred。
func find_nearest_standable(preferred: Vector2i, exclude_occupied: bool = true) -> Vector2i:
	if _is_standable(preferred, exclude_occupied):
		return preferred
	var visited: Dictionary = {preferred: true}
	var queue: Array = [preferred]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for n in HexCoord.neighbors(cur):
			if visited.has(n):
				continue
			visited[n] = true
			if _is_standable(n, exclude_occupied):
				return n
			queue.append(n)
	push_warning("[HexGrid] 找不到可站立格，保留原坐标 %s" % preferred)
	return preferred


func _is_standable(axial: Vector2i, exclude_occupied: bool) -> bool:
	if not _hexes.has(axial):
		return false
	if exclude_occupied and _occupants.has(axial):
		return false
	return true


func get_occupant(axial: Vector2i):
	return _occupants.get(axial, null)


func set_occupant(axial: Vector2i, unit) -> void:
	if unit != null and not _hexes.has(axial):
		push_warning("[HexGrid] 拒绝在非可走格放置单位: %s" % axial)
		return
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

	# 临时禁用敌方占用格（保证 AStar 不会规划穿越敌军的路线）
	var enemy_disables: Array = []
	if self_faction >= 0:
		for axial in _occupants.keys():
			var u = _occupants[axial]
			if u == null or not u.has_method("get_faction") or u.get_faction() == self_faction:
				continue
			if not u.has_method("is_alive") or not u.is_alive():
				continue
			var eid: int = HexCoord.axial_to_id(axial)
			if _astar.has_point(eid) and not _astar.is_point_disabled(eid):
				enemy_disables.append([eid, false])
				_astar.set_point_disabled(eid, true)

	var id_path: PackedInt64Array = _astar.get_id_path(from_id, to_id)
	var _log_path: bool = OS.is_debug_build() and DisplayServer.get_name() != "headless"
	if _log_path:
		print("[DEBUG find_path] from=", from_axial, " to=", to_axial, " self_faction=", self_faction, " id_path.size=", id_path.size(), " from_disabled=", from_was_disabled, " ally_restores=", ally_restores.size(), " enemy_disables=", enemy_disables.size())

	# 还原
	_astar.set_point_disabled(from_id, from_was_disabled)
	if ignore_id != -1:
		_astar.set_point_disabled(ignore_id, ignore_was_disabled)
	for pair in ally_restores:
		_astar.set_point_disabled(pair[0], true)
	for pair in enemy_disables:
		_astar.set_point_disabled(pair[0], false)

	if id_path.size() <= 1:
		if _log_path:
			print("[DEBUG find_path] id_path too short, return []")
		return []
	# 转回 axial（去掉起点；终点若是友方格则返回空——不能停在友方格）
	var result: Array[Vector2i] = []
	for i in range(1, id_path.size()):
		var p: Vector2 = _astar.get_point_position(id_path[i])
		result.append(_pixel_to_axial_lookup(p))
	# 终点不能是友方占用格，也不能是敌方占用格
	if result.size() > 0 and _occupants.has(result[-1]):
		var end_occ = _occupants[result[-1]]
		if _log_path:
			print("[DEBUG find_path] end occupied by ", end_occ)
		if end_occ != null and end_occ.has_method("get_faction") and self_faction >= 0:
			# 无论友方还是敌方，都不能停在有单位的格子
			if _log_path:
				print("[DEBUG find_path] end occupied, return []")
			return []
	# 中间路径不能穿过敌方格子（保险检查）
	for i in range(0, result.size() - 1):
		if _occupants.has(result[i]):
			var mid_occ = _occupants[result[i]]
			if mid_occ != null and mid_occ.has_method("get_faction") \
					and self_faction >= 0 and mid_occ.get_faction() != self_faction \
					and mid_occ.has_method("is_alive") and mid_occ.is_alive():
				if _log_path:
					print("[DEBUG find_path] crossing enemy at ", result[i], " return []")
				return []  # 路径穿越敌方格，视为不可达
	if _log_path:
		print("[DEBUG find_path] result=", result)
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
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		print("[DEBUG get_reachable] origin=", origin, " max_steps=", max_steps, " self_faction=", self_faction, " result_count=", result.size(), " result=", result)
	return result


## 取攻击射程内所有可走格（用于红色范围高亮；含空格）
func get_attack_range_hexes(origin: Vector2i, range_min: int, range_max: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var rmin: int = maxi(1, range_min)
	var rmax: int = maxi(rmin, range_max)
	for axial in _hexes.keys():
		if axial == origin:
			continue
		var d: int = HexCoord.distance(origin, axial)
		if d >= rmin and d <= rmax:
			result.append(axial)
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


## BB 风攻击选中态：敌方小红标 + 射程内其他格小灰标（不铺红底）
func set_highlight_attack_range(marker_hexes: Array[Vector2i], enemy_hexes: Array[Vector2i]) -> void:
	_highlight_attack_markers = marker_hexes
	_highlight_attack_enemy = enemy_hexes
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
	_highlight_attack_markers.clear()
	_highlight_attack_enemy.clear()
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
## 悬停用 _input；点击用 _unhandled_input，让 UI 按钮优先消费事件。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hover_hex != ax:
			_hover_hex = ax
			queue_redraw()
			hex_hovered.emit(ax)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hexes.has(ax):
			hex_clicked.emit(ax)
			get_viewport().set_input_as_handled()


## 地形层绘制（只在初始化时调用一次，连接到 _terrain_layer.draw 信号）
func _draw_terrain() -> void:
	var atlas_uv_scale: float = 1.0 / 256.0
	var tri_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	var color_base_top := Color(0.24, 0.21, 0.18)
	var color_base_bot := Color(0.13, 0.11, 0.09)
	var color_border   := Color(0.42, 0.36, 0.26, 0.75)
	var color_inner_hi := Color(0.55, 0.47, 0.32, 0.18)

	for axial in _hexes.keys():
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var biome: String = _hex_biome.get(axial, "grass")
		var atlas: Texture2D = _atlas_by_biome.get(biome, null)
		var border_pts: PackedVector2Array = _hex_border_cache.get(axial, PackedVector2Array())
		var n: int = border_pts.size()
		if atlas != null:
			for i in range(n):
				var v0: Vector2 = center
				var v1: Vector2 = border_pts[i]
				var v2: Vector2 = border_pts[(i + 1) % n]
				_terrain_layer.draw_polygon(
					PackedVector2Array([v0, v1, v2]),
					tri_colors,
					PackedVector2Array([v0 * atlas_uv_scale, v1 * atlas_uv_scale, v2 * atlas_uv_scale]),
					atlas
				)
		else:
			var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
			_terrain_layer.draw_colored_polygon(pts, color_base_bot)
			var pts_inner: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 3.5)
			_terrain_layer.draw_colored_polygon(pts_inner, color_base_top)
			var pts_closed := pts.duplicate()
			pts_closed.append(pts[0])
			_terrain_layer.draw_polyline(pts_closed, color_border, 1.6, true)

	# ── 过渡纹理叠加：相邻 biome 不同时，在边界方向叠过渡贴图 ──
	for axial in _hexes.keys():
		var biome: String = _hex_biome.get(axial, "grass")
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		for d in range(6):
			var nb_axial: Vector2i = HexCoord.neighbor(axial, d)
			if not _hexes.has(nb_axial):
				continue
			var nb_biome: String = _hex_biome.get(nb_axial, "grass")
			if nb_biome == biome:
				continue
			# 邻居 biome 不同 → 叠加邻居 biome 在方向 d 的过渡贴图
			var tex_dict: Dictionary = _transition_textures.get(nb_biome, {})
			var trans_tex: Texture2D = tex_dict.get(d, null)
			if trans_tex == null:
				continue
			# 过渡贴图 144×144 设计用于半径72px的hex，我们HEX_SIZE=36需缩放0.5
			var half: float = HEX_SIZE
			var dst_rect := Rect2(center.x - half, center.y - half, half * 2.0, half * 2.0)
			_terrain_layer.draw_texture_rect(trans_tex, dst_rect, false)

	# ── 障碍格渲染：rocky 纹理 + 深色叠加 ──
	var dark_overlay := Color(0.0, 0.0, 0.0, 0.55)
	for axial in _obstacles.keys():
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var tex_idx: int = _obstacles[axial]
		var obs_tex: Texture2D = null
		if tex_idx < _obstacle_textures.size():
			obs_tex = _obstacle_textures[tex_idx]
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE)
		if obs_tex != null:
			# 用矩形 UV 采样（障碍纹理通常是独立贴图，非无缝 atlas）
			var ts: Vector2 = obs_tex.get_size()
			var uvs := PackedVector2Array()
			for pt in pts:
				uvs.append(Vector2(
					(pt.x - center.x + HEX_SIZE) / (HEX_SIZE * 2.0),
					(pt.y - center.y + HEX_SIZE) / (HEX_SIZE * 2.0)
				) * ts)
			_terrain_layer.draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE,
				Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, obs_tex)
		else:
			# 无纹理时回退：深灰多边形
			_terrain_layer.draw_colored_polygon(pts, Color(0.25, 0.22, 0.20))
		# 深色叠加强化不可通行感
		_terrain_layer.draw_colored_polygon(pts, dark_overlay)


# ──────────── BB 风攻击射程小标 ────────────
func _draw_range_marker(center: Vector2, fill: Color, radius_scale: float) -> void:
	var r: float = HEX_SIZE * radius_scale
	var pts: PackedVector2Array = HexCoord.corners(center, r)
	draw_colored_polygon(pts, fill)
	var edge := pts.duplicate()
	edge.append(pts[0])
	draw_polyline(edge, CombatPalette.with_alpha(fill, minf(1.0, fill.a + 0.25)), 1.0, true)


# ──────────── 渲染（高亮层，每帧刷新） ────────────
## 60Hz 推动重绘，用于高亮呼吸/路径动画
func _process(_delta: float) -> void:
	if not _highlight_move.is_empty() or not _highlight_attack_markers.is_empty() \
			or not _highlight_attack_enemy.is_empty() \
			or not _highlight_oa_steps.is_empty() or not _highlight_path.is_empty():
		queue_redraw()


func _draw() -> void:
	var color_hover: Color = CombatPalette.hex_hover
	var color_move: Color = CombatPalette.hex_move
	var color_attack: Color = CombatPalette.hex_attack
	var color_path: Color = CombatPalette.hex_path
	var color_zoc: Color = CombatPalette.hex_zoc
	var color_oa: Color = CombatPalette.hex_oa
	var color_selected: Color = CombatPalette.hex_selected

	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)
	var fast_breath: float = 0.5 + 0.5 * sin(t_ms / 220.0)

	# ---- 1) 敌方 ZoC（最底层叠加） ----
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

	# ---- 4) 攻击射程（BB 风：灰标=射程内空格，红标=可攻击敌方） ----
	var marker_breath: float = 0.85 + 0.15 * breath
	for axial in _highlight_attack_markers:
		var center_g: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var gc: Color = CombatPalette.hex_attack_marker
		_draw_range_marker(center_g, Color(gc.r, gc.g, gc.b, gc.a * marker_breath), 0.26)
	for axial in _highlight_attack_enemy:
		var center_r: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var pts_en: PackedVector2Array = HexCoord.corners(center_r, HEX_SIZE - 1.0)
		var atk_fill: Color = color_attack
		var en_alpha: float = atk_fill.a * (0.72 + 0.28 * breath)
		draw_colored_polygon(pts_en, Color(atk_fill.r, atk_fill.g, atk_fill.b, en_alpha))
		var pts_edge: PackedVector2Array = HexCoord.corners(center_r, HEX_SIZE - 4.0)
		var pts_closed := pts_edge.duplicate()
		pts_closed.append(pts_edge[0])
		draw_polyline(pts_closed, CombatPalette.hex_attack_edge, 1.6, true)

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
		var glow_a: float = CombatPalette.hex_selected_glow.a + 0.06 * breath
		draw_colored_polygon(glow_pts, CombatPalette.with_alpha(CombatPalette.hex_selected_glow, glow_a))
		# 描边
		var pts: PackedVector2Array = HexCoord.corners(center, HEX_SIZE - 1.0)
		var pts_closed := pts.duplicate()
		pts_closed.append(pts[0])
		draw_polyline(pts_closed, color_selected, 2.8, true)

	# ---- 9) 战争迷雾（覆盖在所有高亮之上） ----
	if fog_enabled:
		# 迷雾遮罩半径：地形最大波浪半径(HEX_SIZE+3.5)+边缘扰动(EDGE_JITTER=10)≈HEX_SIZE+14
		# 用规则六边形保持迷雾边缘整齐，但要足够大以完全覆盖波浪地形外缘
		const FOG_RADIUS: float = HEX_SIZE + 14.0
		# 已探索但当前不可见：用与地形一致的无缝波浪边界画暗色。
		#   （之前用 FOG_RADIUS 规则大六边形，半径远大于格距 → 相邻遮罩大面积重叠，
		#    半透明叠加后形成菱形深色条纹；改用每格边界多边形后相邻格共享顶点，不重叠。）
		for axial in _explored_hexes.keys():
			if _visible_hexes.has(axial):
				continue
			var ex_pts: PackedVector2Array = _hex_border_cache.get(axial, PackedVector2Array())
			if ex_pts.is_empty():
				# 障碍格等无波浪缓存：用规则六边形（半径 HEX_SIZE 完美平铺，无重叠）
				var ex_center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
				ex_pts = HexCoord.corners(ex_center, HEX_SIZE)
			draw_colored_polygon(ex_pts, Color(0.02, 0.02, 0.04, 0.58))
		# 从未探索过：近黑大六边形遮罩（alpha 高，重叠不可见，确保格缝全黑）
		var fog_targets: Array = _hexes.keys() + _obstacles.keys()
		for axial in fog_targets:
			if _visible_hexes.has(axial) or _explored_hexes.has(axial):
				continue
			var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
			var pts: PackedVector2Array = HexCoord.corners(center, FOG_RADIUS)
			draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.92))


## ──────────── 战争迷雾 API ────────────

## 根据友方单位位置更新视野
##   friendly_units: 友方单位数组（通常 faction == 0）
##   sight_range: 视野半径，默认 5 格
func update_fog_of_war(friendly_units: Array, sight_range: int = DEFAULT_SIGHT_RANGE) -> void:
	_visible_hexes.clear()
	# 标记视野内所有格子可见（可走格 + 障碍格一视同仁，仅按位置判定）
	for u in friendly_units:
		if u == null or not u.is_alive():
			continue
		var axial: Vector2i = u.axial_pos
		var in_range: Array[Vector2i] = _get_hexes_in_range(axial, sight_range)
		for h in in_range:
			if _hexes.has(h) or _obstacles.has(h):
				_visible_hexes[h] = true
				_explored_hexes[h] = true
	queue_redraw()


## 获取某点周围 radius 范围内的所有 hex（环形范围，含中心）
func _get_hexes_in_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		var dr_min: int = max(-radius, -dq - radius)
		var dr_max: int = min(radius, -dq + radius)
		for dr in range(dr_min, dr_max + 1):
			result.append(center + Vector2i(dq, dr))
	return result


## 指定格子当前是否可见
func is_hex_visible(axial: Vector2i) -> bool:
	if not fog_enabled:
		return true
	return _visible_hexes.has(axial)


## 指定格子是否曾探索过（即使现在不可见）
func is_hex_explored(axial: Vector2i) -> bool:
	if not fog_enabled:
		return true
	return _explored_hexes.has(axial)


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
