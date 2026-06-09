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

@export var map_radius: int = 9  ## 地图半径（hex 个数，圆形地图）。需足够大以覆盖常见分辨率下屏幕四角，避免留空。

# ─── Terrain（地形）：AI 生成的战兄弟风无缝大纹理 + hex 世界坐标 UV 采样 ───
## 关键架构（2026-05 重构）：
##   • 每个 biome 共享一张 512×512 的"无缝大纹理"（atlas/<biome>.png）。
##   • 每个 hex 用 draw_polygon + 世界坐标 UV 采样 atlas（texture_repeat=ENABLED 自动 wrap）。
##   • 同 biome 相邻 hex 在边界处采样到的就是源图上**连续相邻的像素** → 物理上不存在接缝。
##   • 不同 biome 边界仍叠加 transition/<biome>_dir<n>.png 让边界自然过渡。
##
## biome 划分：低频噪声把地图切成大区块
##   • grass（草地，主基调）  • leaf（枯叶/林地）
##   • rocky（碎石/硬地）     • dirt （泥地，少量）
const _TILE_DIR: String = "res://assets/terrain/ai/"
const _ATLAS_DIR: String = "res://assets/terrain/ai/atlas/"

## biome -> Texture2D （无缝大纹理）
var _atlas_by_biome: Dictionary = {}
## axial -> String（每个 hex 的 biome 名，用于 transition 计算）
var _hex_biome: Dictionary = {}
## (biome_idx, dir_idx) -> Texture2D 的过渡 tile：
## 当本 hex 的方向 idx 邻居 biome 与本 hex 不同时，把这张过渡 tile 叠在本 hex 上方
var _transition_tiles: Dictionary = {}

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

# ─── 地形边界波纹（让不同 biome 之间的 hex 直边变成不规则曲线） ───
## 思路：每条 hex 边细分成 EDGE_SUBDIV+1 段，每个细分点沿 noise(world_pos) 扰动。
## 因为相邻 hex 在共享边上的 corner / 中间点世界坐标相同，喂同一 noise 得到相同扰动
## → 两个多边形在共享边上的顶点序列完全一致，边界无缝。
const EDGE_SUBDIV: int = 10        # 每条边在两个 corner 之间插入的中间点个数（越多越平滑）
const CORNER_JITTER: float = 7.0   # corner 的 2D 扰动幅度（ inward 最大约 ~10px；必须与 tile_radius 配合防缝隙）
const EDGE_JITTER: float = 14.0    # 中间点沿"边法线"方向的扰动幅度（仅垂直方向 → 不会自相交）
var _terrain_noise: FastNoiseLite


func _ready() -> void:
	# 普通 REPEAT（不是 MIRROR）。
	# atlas 通过 offset+feather 已经做成真正无缝（边缘=中心内容混合），
	# 平铺时左右/上下边缘像素天然连续，根本不需要靠镜像消接缝。
	# 用 MIRROR 反而会在每个 wrap 边界引入对称轴，形成"万花筒"伪影。
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 地形边界扰动 noise：低频 → 一条 hex 边上的扰动连贯，不会把直线打成锯齿
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


## 同一世界坐标 → 同一偏移向量。
## 实现：x 通道直接采样，y 通道用大偏移再采样一次（错开后两个轴之间不相关）。
## 相邻 hex 在共享 corner / 共享边中间点上世界坐标相同 → 偏移完全一致 → 边界重合。
func _terrain_offset(p: Vector2) -> Vector2:
	var nx: float = _terrain_noise.get_noise_2d(p.x, p.y)
	var ny: float = _terrain_noise.get_noise_2d(p.x + 1024.7, p.y - 873.3)
	return Vector2(nx, ny)


## 边中间点专用的"高频"noise 采样：一条 36px 的 hex 边内能产生 3~5 个明显起伏，
## 这样同一条边上不同中间点会得到**显著不同**的位移量 → 视觉上是曲线而不是平移直线。
## 注意仍然只依赖世界坐标 → 共享边上的同一中间点在两个 hex 中得到完全相同的值。
func _terrain_edge_wave(p: Vector2) -> float:
	# 两层 noise：低频做大起伏 + 高频消直边，偏移种子避免与 corner noise 相关
	var low: float = _terrain_noise.get_noise_2d(p.x * 5.0, p.y * 5.0)
	var high: float = _terrain_noise.get_noise_2d(p.x * 14.0 + 777.3, p.y * 14.0 - 555.1)
	return low * 0.60 + high * 0.40


## 生成一个被 noise 扰动的"hex 多边形轮廓"。
## - corner：用低频 2D noise(world_pos) 偏移，3 个共享 corner 的 hex 看到同一偏移
##   → 收敛到同一新点；低频保证 corner 之间的位移连贯，整体形状像"被风吹软的"。
## - 每条边的中间点：**只沿"边法线方向"位移**（标量高频 noise），有三层好处：
##     1) 同一条边的所有中间点全都沿同一直线滑动 → 任意幅度都不会自相交
##     2) 高频 noise 让一条边上的多个点取到不同值 → 形成可见的弯曲曲线（而非平移直线）
##     3) 边法线必须独立于"哪个 hex 在查询"——用按字典序确定的 canonical 方向
##        即可保证两边邻居算出的法线一致 → 共享边两个多边形的中间点完全重合，无缝
## - 总顶点数 = 6 * (1 + EDGE_SUBDIV)
func _wavy_hex_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var corners: PackedVector2Array = HexCoord.corners(center, radius)
	var poly: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var c0: Vector2 = corners[i]
		var c1: Vector2 = corners[(i + 1) % 6]
		# canonical edge direction：按字典序排序两 corner 后的方向，
		# 邻居 hex 看到同一条边，c0/c1 顺序相反，但排序后方向一致 → 法线一致。
		var a: Vector2 = c0
		var b: Vector2 = c1
		if (b.x < a.x) or (b.x == a.x and b.y < a.y):
			var tmp: Vector2 = a
			a = b
			b = tmp
		var edge_dir: Vector2 = (b - a).normalized()
		var edge_normal: Vector2 = Vector2(-edge_dir.y, edge_dir.x)
		# corner（3-way 共享，必须是世界坐标决定的 2D 偏移）
		poly.append(c0 + _terrain_offset(c0) * CORNER_JITTER)
		# 边上中间点：仅沿 edge_normal 位移（高频标量 noise → 一条边内多次起伏）
		for s in range(1, EDGE_SUBDIV + 1):
			var t: float = float(s) / float(EDGE_SUBDIV + 1)
			var p: Vector2 = c0.lerp(c1, t)
			var nval: float = _terrain_edge_wave(p)
			poly.append(p + edge_normal * (nval * EDGE_JITTER))
	return poly


# ──────────── 地图包围盒（供相机自适应使用） ────────────
## 返回地图在世界坐标下的 AABB（相对于 HexGrid 自身 position）。
## 包含 CORNER_JITTER 的余量，确保不规则边界也完整可见。
func get_map_bounds() -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	# tile_radius = HEX_SIZE + 3.5 是绘制时用的外接圆半径；
	# EDGE_JITTER = 14 是边中点最大向外扰动。margin 必须覆盖两者。
	var margin: float = HEX_SIZE + 3.5 + EDGE_JITTER
	for axial in _hexes.keys():
		var c: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		min_v.x = min(min_v.x, c.x - margin)
		min_v.y = min(min_v.y, c.y - margin)
		max_v.x = max(max_v.x, c.x + margin)
		max_v.y = max(max_v.y, c.y + margin)
	if min_v.x == INF:
		return Rect2(Vector2.ZERO, Vector2(100, 100))
	return Rect2(min_v, max_v - min_v)


# ──────────── 地图生成 ────────────
func _generate_map() -> void:
	# 生成圆形地图（六边形围成的圆）
	for q in range(-map_radius, map_radius + 1):
		var r1: int = max(-map_radius, -q - map_radius)
		var r2: int = min(map_radius, -q + map_radius)
		for r in range(r1, r2 + 1):
			_hexes[Vector2i(q, r)] = true


# ──────────── Terrain 加载 ────────────
## 加载 4 张 biome 无缝大纹理 + 24 张 transition tile
func _load_terrain_textures() -> void:
	for b in ["grass", "leaf", "rocky", "dirt"]:
		var path := "%s%s.png" % [_ATLAS_DIR, b]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				_atlas_by_biome[b] = tex
		else:
			push_warning("[HexGrid] missing biome atlas: %s" % path)
	_load_transition_tiles()


## 加载 transition/<biome>_dir<idx>.png（4 biome × 6 方向 = 24 张）
func _load_transition_tiles() -> void:
	var biomes := ["grass", "leaf", "rocky", "dirt"]
	for b in biomes:
		for d in range(6):
			var path := "%stransition/%s_dir%d.png" % [_TILE_DIR, b, d]
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex != null:
					_transition_tiles[Vector2i(biomes.find(b), d)] = tex


## biome 名 → int 索引（与 _load_transition_tiles 中 biomes 顺序一致）
func _biome_idx(biome: String) -> int:
	match biome:
		"grass": return 0
		"leaf":  return 1
		"rocky": return 2
		"dirt":  return 3
	return 0


## 给每个 hex 分配 biome（启动时一次性计算，渲染时直接查）
func _assign_hex_tiles() -> void:
	# biome 主分布：用低频噪声切大块（4~6 格连成片）
	var noise := FastNoiseLite.new()
	noise.seed = 20260531
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.10
	noise.fractal_octaves = 2

	# 阈值（基于 noise 分布大致 ±0.6）：
	#   grass  ~55%（主基调）
	#   leaf   ~20%（林地、过渡）
	#   rocky  ~15%（硬地、点缀）
	#   dirt   ~10%（泥地、稀有，主要在低洼连片区域）
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

	# Majority filter：消除孤立 hex（如 1 个 grass 被 5 个 rocky 包围 → 改成 rocky）。
	# 没有这步时，孤立 hex 在大片 biome 中显得突兀（颜色对比强 + 周围全是过渡 tile）。
	# 跑 2 次让"孤立点 → 邻居 biome"传播稳定下来。
	for _pass in range(2):
		var new_biome: Dictionary = {}
		for axial in _hexes.keys():
			var counts: Dictionary = {}
			var self_b: String = _hex_biome[axial]
			counts[self_b] = 1  # 自己算 1 票（避免和邻居 3:3 时反复翻转）
			for n in HexCoord.neighbors(axial):
				if not _hexes.has(n):
					continue
				var nb: String = _hex_biome[n]
				counts[nb] = counts.get(nb, 0) + 1
			# 找最多票的 biome
			var best_b: String = self_b
			var best_c: int = counts[self_b]
			for b in counts.keys():
				if counts[b] > best_c:
					best_c = counts[b]
					best_b = b
			new_biome[axial] = best_b
		_hex_biome = new_biome


## 公共接口：取指定 hex 的 terrain（暂不区分；保留 API 兼容）
func get_terrain(_axial: Vector2i) -> String:
	return "grass"


## 把 axial 映射为正整数（稳定哈希，用于在 tile 池里挑变体）
func _axial_hash_int(axial: Vector2i) -> int:
	var x: int = axial.x * 374761393 + axial.y * 668265263
	x = (x ^ (x >> 13)) * 1274126177
	return x & 0x7fffffff


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
## self_faction: 传入移动者阵营 → 允许穿过同阵营友方格子（不能停留）；-1 = 不区分友敌
func find_path(from_axial: Vector2i, to_axial: Vector2i, ignore_occupant_at: Vector2i = Vector2i(99999, 99999), self_faction: int = -1) -> Array[Vector2i]:
	if not _hexes.has(from_axial) or not _hexes.has(to_axial):
		return []
	# 终点被任何单位占用 → 不能停留
	if _occupants.has(to_axial) and to_axial != ignore_occupant_at:
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

	# 临时解禁同阵营友方占用格子（允许穿过但不能停留）
	var ally_disabled_restores: Array = []
	if self_faction >= 0:
		for axial in _occupants.keys():
			var u = _occupants[axial]
			if u == null or not u.has_method("get_faction") or u.get_faction() != self_faction:
				continue
			if axial == from_axial or axial == ignore_occupant_at:
				continue  # 已经在上面处理了
			var aid: int = HexCoord.axial_to_id(axial)
			if _astar.is_point_disabled(aid):
				ally_disabled_restores.append([aid, true])
				_astar.set_point_disabled(aid, false)

	var id_path: PackedInt64Array = _astar.get_id_path(from_id, to_id)

	# 还原
	_astar.set_point_disabled(from_id, from_was_disabled)
	if ignore_id != -1:
		_astar.set_point_disabled(ignore_id, ignore_was_disabled)
	for pair in ally_disabled_restores:
		_astar.set_point_disabled(pair[0], pair[1])

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
	
	# ✓ 修复：检查所有占用格子，按 weapon.range_max 筛选距离
	for axial in _occupants.keys():
		var u = _occupants[axial]
		if u == null:
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		if not u.has_method("get_faction") or u.get_faction() == self_faction:
			continue
		# 远程单位不产生 ZoC
		if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
			continue
		
		# ✓ 关键修复：按武器射程（range_max）计算 ZoC 范围
		var dist: int = HexCoord.distance(cell, axial)
		if dist <= 0:
			continue
		
		# 获取此单位武器的 ZoC 距离
		var zoc_distance: int = 1  # 默认 1 格
		if u.weapon != null and "range_max" in u.weapon:
			zoc_distance = u.weapon.range_max
		
		# 如果距离在 ZoC 范围内，加入结果
		if dist <= zoc_distance:
			result.append(u)
	
	return result



## 取所有产生 ZoC 的格子（用于敌方阵营的"威胁地图"高亮）
func get_zoc_cells_of(enemy_faction: int) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var result: Array[Vector2i] = []
	
	# ✓ 修复：按武器射程（range_max）计算每个敌人的 ZoC 范围
	for axial in _occupants.keys():
		var u = _occupants[axial]
		if u == null or not u.has_method("is_alive") or not u.is_alive():
			continue
		if not u.has_method("get_faction") or u.get_faction() != enemy_faction:
			continue
		if "weapon" in u and u.weapon != null and u.weapon.weapon_type != "melee":
			continue
		
		# ✓ 关键修复：获取武器的 ZoC 距离
		var zoc_distance: int = 1  # 默认 1 格
		if u.weapon != null and "range_max" in u.weapon:
			zoc_distance = u.weapon.range_max
		
		# 获取此单位周围 zoc_distance 范围内的所有格子
		var zoc_cells: Array[Vector2i] = []
		if zoc_distance == 1:
			zoc_cells = HexCoord.neighbors(axial)
		else:
			# 获取多个环的并集
			for dist in range(1, zoc_distance + 1):
				zoc_cells.append_array(HexCoord.ring(axial, dist))
		
		# 去重并添加到结果
		for cell in zoc_cells:
			if not _hexes.has(cell):
				continue
			if seen.has(cell):
				continue
			seen[cell] = true
			result.append(cell)
	
	return result


## 沿一条路径走，识别每一步会触发哪些敌人借机攻击。
## 返回 Array[Dictionary]，每一步一个：{from, to, oa_attackers: Array[Unit]}
##
## 规则（六边形版改良——与 Unit._animate_path 实际触发完全一致）：
##   敌人 X 之前与移动者相邻（移动者在 X 的 ZoC 内）→ 本步触发 X 的借机攻击：
##     • 在同一 X 的 ZoC 内绕侧（保持距离 1）→ 触发
##     • 脱离 X 的 ZoC（拉开距离 ≥2）         → 触发
##   敌人 X 之前不与移动者相邻 → 不触发：
##     • 进入 X 的 ZoC（本步开始相邻） → 不触发（拉近距离时敌人无机会）
##   友方掩护：from_cell 有同阵营单位与 ctrl 相邻 → 该 ctrl 不触发借机
##   moving_unit: 移动者（用于友方掩护判定），null 时跳过掩护检查
func analyze_path_oa(start: Vector2i, path: Array[Vector2i], self_faction: int, moving_unit = null) -> Array:
	var steps: Array = []
	var prev: Vector2i = start
	for step in path:
		var prev_ctrls: Array = get_zoc_controllers(prev, self_faction)
		# 友方掩护过滤
		var filtered: Array = []
		for ctrl in prev_ctrls:
			if moving_unit != null and moving_unit.has_method("_is_covered_by_ally"):
				if moving_unit._is_covered_by_ally(prev, ctrl):
					continue
			filtered.append(ctrl)
		steps.append({"from": prev, "to": step, "oa_attackers": filtered})
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
## 我们靠 _hexes.has(ax) 自己判断是否在地图内，UI 区域的过滤交给 _is_pointer_over_blocking_ui()
## ——通过 viewport.gui_get_hovered_control() 检测鼠标是否落在 visible Control 上。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hover_hex != ax:
			_hover_hex = ax
			queue_redraw()
			# 永远 emit（即便光标离开地图），让上层决定如何处理"无效格"
			hex_hovered.emit(ax)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 鼠标若停在任何阻挡型 UI Control 上（CombatMenu / SidePanel / TopBar 中的按钮等），
		# 点击归 UI，不视为点格子
		if _is_pointer_over_blocking_ui():
			return
		var ax: Vector2i = world_to_axial(get_global_mouse_position())
		if _hexes.has(ax):
			hex_clicked.emit(ax)


## 检测鼠标当前是否 hover 在阻挡型 Control 上。
## 阻挡型 = mouse_filter != IGNORE 且自身可见的 Control。
func _is_pointer_over_blocking_ui() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	# IGNORE 的 Control 即便 hover 也不算阻挡
	if hovered.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	return true


# ──────────── 渲染 ────────────
## 60Hz 推动重绘，用于高亮呼吸/路径动画
func _process(_delta: float) -> void:
	if not _highlight_move.is_empty() or not _highlight_attack.is_empty() \
			or not _highlight_oa_steps.is_empty() or not _highlight_path.is_empty():
		queue_redraw()


func _draw() -> void:
	# 暗黑中世纪石板配色
	var color_base_top := Color(0.24, 0.21, 0.18)      # 顶部稍亮（高光）
	var color_base_bot := Color(0.13, 0.11, 0.09)      # 底部更暗（阴影）
	var color_border   := Color(0.42, 0.36, 0.26, 0.75) # 暗金边框
	var color_inner_hi := Color(0.55, 0.47, 0.32, 0.18) # 内侧高光线
	var color_hover    := Color(0.95, 0.80, 0.30, 0.22) # 金色 hover
	var color_move     := Color(0.29, 0.56, 0.85, 0.40) # 蓝色移动
	var color_attack   := Color(0.85, 0.29, 0.29, 0.50) # 红色攻击
	var color_path     := Color(0.95, 0.78, 0.30, 0.85) # 金色路径
	var color_zoc      := Color(0.95, 0.55, 0.25, 0.16) # 弱橙：敌方 ZoC
	var color_oa       := Color(1.0, 0.40, 0.25, 0.92)  # 强橙红：借机触发点
	var color_selected := Color(0.95, 0.90, 0.78, 0.95) # 选中白金边

	# 呼吸动画系数（0~1 之间正弦缓动）
	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)   # 周期约 2.4s
	var fast_breath: float = 0.5 + 0.5 * sin(t_ms / 220.0) # 更急促，用于 OA/selected

	# ---- 0) 地图区域底色填充（覆盖地图 AABB，与地形基色一致，消除圆形地图外的黑缝） ----
	var base_fill_color := Color(0.16, 0.14, 0.11)
	var fill_margin: float = HEX_SIZE + 3.5 + EDGE_JITTER  # 与 _bounds() 一致
	var fill_min := Vector2(INF, INF)
	var fill_max := Vector2(-INF, -INF)
	for axial in _hexes.keys():
		var c: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		fill_min.x = min(fill_min.x, c.x - fill_margin)
		fill_min.y = min(fill_min.y, c.y - fill_margin)
		fill_max.x = max(fill_max.x, c.x + fill_margin)
		fill_max.y = max(fill_max.y, c.y + fill_margin)
	if fill_min.x != INF:
		draw_rect(Rect2(fill_min, fill_max - fill_min), base_fill_color, true)

	# ---- 1) 地形：每 biome 共享一张大纹理，按世界坐标 UV 采样 ----
	# 关键设计（2026-05-31 重构 v3：无万花筒）：
	#   • atlas 1024×1024，整张通过 offset+feather 做成真正无缝（gen_biome_atlas.py）。
	#     不含任何镜像/4×4 子图拼接，不会产生对称轴。
	#   • uv_scale = 1/256 → 一个 atlas 周期 = 256 world units。
	#     hex 72 world ≈ 28% atlas ≈ 1 个主体物大小 → 与单位 sprite 比例协调。
	#   • texture_repeat=ENABLED（普通 wrap，无镜像），靠 atlas 自身无缝实现连续。
	#   • 同 biome 相邻 hex 在共享边上 UV 完全一致 → 边界采样同一像素 → 无接缝。
	# 顶点外扩：corner 最大可内移 CORNER_JITTER*~1.4 ≈ 10px，
	# tile_radius 必须足够大，保证扰动后原 corner 位置仍被覆盖，否则三 hex 共享 corner
	# 同时内缩会产生三角黑缝。+3.5 提供安全余量。
	var tile_radius: float = HEX_SIZE + 3.5
	var atlas_uv_scale: float = 1.0 / 256.0
	var poly_vertex_count: int = 6 * (1 + EDGE_SUBDIV)
	var white_colors := PackedColorArray()
	for _i in range(poly_vertex_count):
		white_colors.append(Color.WHITE)

	# 第 1 步：用每 hex 自己 biome 的 atlas 画底（hex 轮廓被 noise 扰动成不规则曲线）
	# 关键：相邻 hex 共享的 corner / edge 中间点的世界坐标完全相同，
	# _terrain_offset 喂同一坐标 → 同一偏移 → 共享边界完全重合，没有缝隙。
	# 同 biome 内部 UV 仍按世界坐标采样 atlas，wrap 后保持纹理连续。
	for axial in _hexes.keys():
		var center: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		var biome: String = _hex_biome.get(axial, "grass")
		var atlas: Texture2D = _atlas_by_biome.get(biome, null)
		var pts: PackedVector2Array = _wavy_hex_polygon(center, tile_radius)
		if atlas != null:
			var uvs := PackedVector2Array()
			for p in pts:
				uvs.append(p * atlas_uv_scale)
			draw_polygon(pts, white_colors, uvs, atlas)
		else:
			draw_colored_polygon(pts, Color(0.22, 0.30, 0.14))

	# 第 2 步：biome 边界过渡叠加 —— 已禁用。
	# 之前为了让 biome 之间柔过渡，会在每个 hex 上叠 transition tile，
	# 但这些过渡贴图朝向邻居方向 alpha=1，反向 alpha=0，叠加结果就是
	# 在每个 hex 边缘留下一条亮带 → 视觉上等同于"hex 描边"。
	# 用户希望地形看起来是无边界的连续大地，所以移除这一层。
	# 不同 biome 之间的硬切换让位给"无格子感"。
	# var trans_diameter: float = 2.0 * HEX_SIZE
	# var trans_half: float = trans_diameter * 0.5
	# for axial in _hexes.keys():
	# 	...

	# ---- 1b) 整片暗色叠层（统一压色调，让单位 sprite 更突出） ----
	# 改为：覆盖整张地图的一个大菱形 / AABB 区域，只画一次。
	# 之前 per-hex 画暗色 polygon，相邻 polygon 边缘的 alpha 叠加在 GPU 浮点
	# 处理时会形成可见的 hex 边线，与"无格子"目标冲突。
	var battlefield_dim := Color(0.04, 0.03, 0.02, 0.10)
	var dim_min := Vector2(INF, INF)
	var dim_max := Vector2(-INF, -INF)
	for axial in _hexes.keys():
		var c: Vector2 = HexCoord.axial_to_pixel(axial, HEX_SIZE)
		dim_min.x = min(dim_min.x, c.x - HEX_SIZE)
		dim_min.y = min(dim_min.y, c.y - HEX_SIZE)
		dim_max.x = max(dim_max.x, c.x + HEX_SIZE)
		dim_max.y = max(dim_max.y, c.y + HEX_SIZE)
	if dim_min.x != INF:
		draw_rect(Rect2(dim_min, dim_max - dim_min), battlefield_dim, true)

	# ---- 1c) hex 格线已移除 ----
	# 让地形看起来像一片连续的大地。鼠标 hover、移动范围、攻击范围等功能性
	# 高亮仍按 hex 显示（在下面），玩家能感知格子位置而不被网格"框住"。

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
