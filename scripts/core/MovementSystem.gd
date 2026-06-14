extends RefCounted
class_name MovementSystem

const _Spec = preload("res://scripts/core/abilities/AbilityMovementSpec.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")
# 注意：不 preload HexGrid（它依赖 CombatPalette autoload，--script 模式编译失败）
# HEX_SIZE 直接用字面值；类型用鸭子类型（hex_grid 参数）
const HEX_SIZE: float = 36.0

##
## MovementSystem.gd — 位移执行器（纯静态，状态全在 Spec 与 grid 中）
##
## 设计原则：
##   - 所有「该不该位移、撞到怎么办、是否触发借机」的判断集中在此
##   - 位移完成后只更新 axial_pos / sprite position / occupant 表 / 触发 moved 信号
##   - 不扣 AP / 气力（Ability.spend_resources() 已扣）
##   - 与 ZoC、镇阵、地形的交互由本文件统一处理
##
## 返回字典约定：
##   { ok: bool, reason: String, from: Vector2i, to: Vector2i,
##     blocked: bool, block_target: Unit, damage_dealt: int }
##

# ──────────── 入口 ────────────

static func execute(spec, hex_grid) -> Dictionary:
	if spec == null or spec.unit == null or hex_grid == null:
		return _fail("invalid_spec")

	# 镇阵 / displacement_immune 守卫（除 SWAP 用 partner 校验外，所有类型校验 unit）
	if _is_displacement_immune(spec.unit):
		return _fail("rooted", spec.unit.axial_pos, spec.unit.axial_pos)

	match spec.kind:
		_Spec.Kind.TELEPORT:
			return _do_teleport(spec, hex_grid)
		_Spec.Kind.PUSH:
			return _do_push(spec, hex_grid)
		_Spec.Kind.PULL:
			return _do_pull(spec, hex_grid)
		_Spec.Kind.SWAP:
			return _do_swap(spec, hex_grid)
		_Spec.Kind.DASH:
			return _do_dash(spec, hex_grid)
	return _fail("unknown_kind")


# ──────────── TELEPORT ────────────

static func _do_teleport(spec, hex_grid) -> Dictionary:
	var unit = spec.unit
	var from_axial: Vector2i = unit.axial_pos
	var dest: Vector2i = spec.dest

	# 落点必须是合法格
	if not hex_grid._hexes.has(dest):
		return _fail("dest_invalid", from_axial, dest)
	# 障碍格除非 ignore_terrain
	if hex_grid.is_obstacle(dest) and not spec.ignore_terrain:
		return _fail("dest_obstacle", from_axial, dest)
	# 落点不能被占（瞬移不能与他人重叠）
	if hex_grid.get_occupant(dest) != null:
		return _fail("dest_occupied", from_axial, dest)

	_relocate(unit, from_axial, dest, hex_grid)
	return _ok(from_axial, dest)


# ──────────── PUSH ────────────

static func _do_push(spec, hex_grid) -> Dictionary:
	var target = spec.unit
	var from_axial: Vector2i = target.axial_pos
	# 沿 dest 方向逐格推；spec.dest 是「理想终点」，遇阻可能停在中途
	var dir_idx: int = _HexCoord.direction_index(from_axial, _first_step(from_axial, spec.dest))
	if dir_idx < 0:
		dir_idx = _HexCoord.approx_direction(from_axial, spec.dest)

	var current: Vector2i = from_axial
	var damage_dealt: int = 0
	var block_target = null

	for i in range(spec.distance):
		var next: Vector2i = _HexCoord.neighbor(current, dir_idx)
		if not hex_grid._hexes.has(next):
			# 推到地图边缘：撞墙
			block_target = null  # 墙没有 target
			damage_dealt = _apply_block_damage(target, null, spec)
			break
		if hex_grid.is_obstacle(next):
			damage_dealt = _apply_block_damage(target, null, spec)
			break
		var occ = hex_grid.get_occupant(next)
		if occ != null:
			block_target = occ
			# CHAIN_PUSH：被推单位也被推一格
			if spec.on_block == _Spec.OnBlock.CHAIN_PUSH and not _is_displacement_immune(occ):
				var chain_spec = _Spec.push(occ, current, 1, 0)
				_do_push(chain_spec, hex_grid)
				# 重新检查 next 是否空了
				if hex_grid.get_occupant(next) == null:
					current = next
					continue
			damage_dealt = _apply_block_damage(target, occ, spec)
			break
		current = next

	if current != from_axial:
		_relocate(target, from_axial, current, hex_grid)

	var blocked: bool = (current != spec.dest)
	return {
		"ok": true,
		"reason": "blocked" if blocked else "",
		"from": from_axial,
		"to": current,
		"blocked": blocked,
		"block_target": block_target,
		"damage_dealt": damage_dealt,
	}


# ──────────── PULL ────────────

static func _do_pull(spec, hex_grid) -> Dictionary:
	var target = spec.unit
	var from_axial: Vector2i = target.axial_pos
	var dest: Vector2i = spec.dest

	# 落点合法性
	if not hex_grid._hexes.has(dest):
		return _fail("dest_invalid", from_axial, dest)
	if hex_grid.is_obstacle(dest):
		return _fail("dest_obstacle", from_axial, dest)
	if hex_grid.get_occupant(dest) != null:
		# 拉到一半被挡，停在前一格
		# 拉拽方向：from → dest
		var dir_idx: int = _HexCoord.approx_direction(from_axial, dest)
		var stop_at: Vector2i = from_axial
		var current: Vector2i = from_axial
		for i in range(spec.distance):
			var next: Vector2i = _HexCoord.neighbor(current, dir_idx)
			if next == dest or hex_grid.get_occupant(next) != null or hex_grid.is_obstacle(next) or not hex_grid._hexes.has(next):
				break
			stop_at = next
			current = next
		if stop_at != from_axial:
			_relocate(target, from_axial, stop_at, hex_grid)
		return {
			"ok": true,
			"reason": "blocked" if stop_at != dest else "",
			"from": from_axial,
			"to": stop_at,
			"blocked": stop_at != dest,
			"block_target": null,
			"damage_dealt": 0,
		}

	_relocate(target, from_axial, dest, hex_grid)
	return _ok(from_axial, dest)


# ──────────── SWAP ────────────

static func _do_swap(spec, hex_grid) -> Dictionary:
	var a = spec.unit
	var b = spec.partner
	if a == null or b == null:
		return _fail("missing_partner")
	if _is_displacement_immune(b):
		return _fail("partner_rooted", a.axial_pos, a.axial_pos)

	var pos_a: Vector2i = a.axial_pos
	var pos_b: Vector2i = b.axial_pos

	# 交换：先清两边占位，再各自落地
	hex_grid.set_occupant(pos_a, null)
	hex_grid.set_occupant(pos_b, null)

	a.axial_pos = pos_b
	a.position = _HexCoord.axial_to_pixel(pos_b, HEX_SIZE)
	hex_grid.set_occupant(pos_b, a)

	b.axial_pos = pos_a
	b.position = _HexCoord.axial_to_pixel(pos_a, HEX_SIZE)
	hex_grid.set_occupant(pos_a, b)

	# 触发信号（双方都 moved）
	a.moved.emit(a, pos_a, pos_b)
	b.moved.emit(b, pos_b, pos_a)

	return _ok(pos_a, pos_b)


# ──────────── DASH ────────────

static func _do_dash(spec, hex_grid) -> Dictionary:
	# DASH 走 Unit.move_along_path 的现成管线（含 ZoC / 借机），不走 _relocate
	var unit = spec.unit
	var from_axial: Vector2i = unit.axial_pos
	var dest: Vector2i = spec.dest

	# 路径：直线尝试，遇阻退化为 A* find_path
	var path: Array[Vector2i] = _build_dash_path(unit, from_axial, dest, hex_grid)
	if path.is_empty():
		return _fail("no_path", from_axial, dest)

	# ignore_zoc：临时设置 unit.ignore_oa_this_move（与现有滑步机制一致）
	var prev_ignore: bool = unit.ignore_oa_this_move if "ignore_oa_this_move" in unit else false
	if spec.ignore_zoc and "ignore_oa_this_move" in unit:
		unit.ignore_oa_this_move = true

	# 调用 Unit 现有的同步移动接口（不消耗 AP；MovementSystem 不扣资源）
	var moved: bool = unit.move_along_path_sync(path)

	# 还原标志
	if "ignore_oa_this_move" in unit:
		unit.ignore_oa_this_move = prev_ignore

	if not moved:
		return _fail("dash_failed", from_axial, unit.axial_pos)
	return _ok(from_axial, unit.axial_pos)


# ──────────── 辅助：核心 _relocate ────────────

## 通用重定位：清旧 occupant、设新 occupant、更新 axial_pos / position、触发 moved
## 不触发借机（TELEPORT/PUSH/PULL/SWAP 默认无借机；DASH 走另一条路）
static func _relocate(unit, from_axial: Vector2i, to_axial: Vector2i, hex_grid) -> void:
	hex_grid.set_occupant(from_axial, null)
	unit.axial_pos = to_axial
	unit.position = _HexCoord.axial_to_pixel(to_axial, HEX_SIZE)
	hex_grid.set_occupant(to_axial, unit)
	unit.moved.emit(unit, from_axial, to_axial)


# ──────────── 辅助 ────────────

static func _is_displacement_immune(unit) -> bool:
	if unit == null:
		return false
	# 优先 status-effects 接口（Phase 2.5 接入后此处会自动生效）
	if unit.has_method("has_status"):
		if unit.has_status("displacement_immune") or unit.has_status("rooted"):
			return true
	# 兼容：直接读字段
	if "displacement_immune" in unit and unit.displacement_immune:
		return true
	if "rooted" in unit and unit.rooted:
		return true
	return false


static func _apply_block_damage(target, blocker, spec) -> int:
	if spec.on_block != _Spec.OnBlock.DAMAGE or spec.on_block_damage <= 0:
		return 0
	if target != null and target.stats != null:
		target.stats.hp = max(0, target.stats.hp - spec.on_block_damage)
		target.stats_changed.emit(target)
	if blocker != null and blocker.stats != null:
		blocker.stats.hp = max(0, blocker.stats.hp - spec.on_block_damage)
		blocker.stats_changed.emit(blocker)
	return spec.on_block_damage


static func _first_step(from_pos: Vector2i, dest: Vector2i) -> Vector2i:
	# dest 距离 from 大于 1 时，沿主方向取第一格
	var dir_idx: int = _HexCoord.approx_direction(from_pos, dest)
	return _HexCoord.neighbor(from_pos, dir_idx)


static func _build_dash_path(unit, from_axial: Vector2i, dest: Vector2i, hex_grid) -> Array[Vector2i]:
	# 优先走 A*；不通则空
	if hex_grid.has_method("find_path"):
		var p = hex_grid.find_path(from_axial, dest, from_axial, unit.get_faction())
		if p is Array and not p.is_empty():
			var typed: Array[Vector2i] = []
			for v in p:
				if v is Vector2i:
					typed.append(v)
			return typed
	return [] as Array[Vector2i]


static func _ok(from_axial: Vector2i, to_axial: Vector2i) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"from": from_axial,
		"to": to_axial,
		"blocked": false,
		"block_target": null,
		"damage_dealt": 0,
	}


static func _fail(reason: String, from_axial: Vector2i = Vector2i.ZERO, to_axial: Vector2i = Vector2i.ZERO) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"from": from_axial,
		"to": to_axial,
		"blocked": true,
		"block_target": null,
		"damage_dealt": 0,
	}
