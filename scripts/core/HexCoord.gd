extends RefCounted
class_name HexCoord
##
## HexCoord.gd — 六边形坐标静态工具类（pointy-top 朝向）
##
## 使用 Axial 坐标 (q, r)，与 Cube 坐标 (x=q, y=-q-r, z=r) 互转。
## 参考：https://www.redblobgames.com/grids/hexagons/
##

# 六个方向（pointy-top）：右上、右、右下、左下、左、左上
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(+1,  0),  # 0 East
	Vector2i(+1, -1),  # 1 NorthEast
	Vector2i( 0, -1),  # 2 NorthWest
	Vector2i(-1,  0),  # 3 West
	Vector2i(-1, +1),  # 4 SouthWest
	Vector2i( 0, +1),  # 5 SouthEast
]


## Axial 坐标转像素（pointy-top）
## hex_size: 六边形外接圆半径（中心到顶点距离）
static func axial_to_pixel(axial: Vector2i, hex_size: float) -> Vector2:
	var x: float = hex_size * (sqrt(3.0) * axial.x + sqrt(3.0) / 2.0 * axial.y)
	var y: float = hex_size * (3.0 / 2.0 * axial.y)
	return Vector2(x, y)


## 像素转 Axial（带四舍五入）
static func pixel_to_axial(pixel: Vector2, hex_size: float) -> Vector2i:
	var q_f: float = (sqrt(3.0) / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / hex_size
	var r_f: float = (2.0 / 3.0 * pixel.y) / hex_size
	return _cube_round(q_f, -q_f - r_f, r_f)


## 立方体坐标四舍五入到最近 hex
static func _cube_round(x: float, y: float, z: float) -> Vector2i:
	var rx: float = round(x)
	var ry: float = round(y)
	var rz: float = round(z)
	var dx: float = abs(rx - x)
	var dy: float = abs(ry - y)
	var dz: float = abs(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


## 两个 hex 之间的距离
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (abs(dq) + abs(dq + dr) + abs(dr)) / 2


## 取邻居（6 个方向）
static func neighbors(axial: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in DIRECTIONS:
		result.append(axial + dir)
	return result


## 取从 from -> to 方向的索引（仅当二者相邻时有意义；不相邻返回 -1）
static func direction_index(from: Vector2i, to: Vector2i) -> int:
	var d: Vector2i = to - from
	for i in range(6):
		if DIRECTIONS[i] == d:
			return i
	return -1


## 取 axial 在某方向"对面"的那个格子（用于夹击判定）
static func opposite_across(from_axial: Vector2i, target_axial: Vector2i) -> Vector2i:
	var d_idx: int = direction_index(from_axial, target_axial)
	if d_idx < 0:
		var dq: int = target_axial.x - from_axial.x
		var dr: int = target_axial.y - from_axial.y
		var best: int = 0
		var best_dot: float = -INF
		var v := Vector2(float(dq), float(dr))
		if v.length() > 0.0:
			v = v.normalized()
		for i in range(6):
			var dv := Vector2(float(DIRECTIONS[i].x), float(DIRECTIONS[i].y)).normalized()
			var d_dot: float = dv.dot(v)
			if d_dot > best_dot:
				best_dot = d_dot
				best = i
		return target_axial + DIRECTIONS[best]
	return target_axial + DIRECTIONS[d_idx]


## 单方向邻居
static func neighbor(axial: Vector2i, direction: int) -> Vector2i:
	return axial + DIRECTIONS[direction % 6]


## 六边形顶点（pointy-top，6 个角点）
static func corners(center: Vector2, hex_size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var angle_rad: float = PI / 180.0 * (60.0 * i - 30.0)  # pointy-top
		pts.append(Vector2(
			center.x + hex_size * cos(angle_rad),
			center.y + hex_size * sin(angle_rad)
		))
	return pts


## 给 axial 编码为 AStar2D 用的 int id（保证唯一）
## 用 (q + 1000) * 10000 + (r + 1000)，支持 ±1000 范围
static func axial_to_id(axial: Vector2i) -> int:
	return (axial.x + 1000) * 10000 + (axial.y + 1000)
