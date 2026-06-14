extends RefCounted
class_name AbilityMovementSpec

const _HexCoord = preload("res://scripts/core/HexCoord.gd")

##
## AbilityMovementSpec — 能力施加的位移描述（声明式，不含执行逻辑）
##
## 仿 AbilityEffectSpec 的设计：能力子类在 gather_movement_specs() 返回规格，
## 由 MovementSystem.execute() 统一执行。
##
## 设计原则：
##   - Spec 是数据，纯字段；不含路径计算（PUSH/PULL 在工厂方法中算落点）
##   - 不扣 AP / 气力（由 Ability.spend_resources() 负责）
##   - 与 ZoC / 镇阵 / 地形等规则的交互全部交给 MovementSystem
##
## 5 种位移类型覆盖未来所有位移技能：
##   TELEPORT  - 滑步、移形、战术跳跃、瞬步惊芒
##   PUSH      - 推撞、扫杆逼退、冲锋推退、击退
##   PULL      - 擒拿拉拽、钩拉
##   SWAP      - 换位（自身与友军互换）
##   DASH      - 突击冲锋、骑乘冲锋（沿路径移动，触发 ZoC）
##

enum Kind {
	TELEPORT,        ## 瞬移：忽略路径、ZoC、障碍
	PUSH,            ## 击退：单向推
	PULL,            ## 拉拽：单向拉
	SWAP,            ## 换位：两单位互换
	DASH,            ## 突进：沿路径移动，触发 ZoC
}

enum OnBlock {
	STOP,            ## 撞墙/单位 → 停在前一格
	DAMAGE,          ## 撞击 → 双方各受伤害
	CHAIN_PUSH,      ## 连锁推：撞到的单位也被推一格
}

# ── 通用字段 ──
var kind: int = Kind.TELEPORT
var unit = null                     ## 被移动的单位（自己/友/敌）
var dest: Vector2i = Vector2i.ZERO  ## 目标格（TELEPORT/SWAP 直填；PUSH/PULL/DASH 由工厂算）
var distance: int = 1               ## 推/拉/冲锋的格数

# ── 规则修饰 ──
var ignore_zoc: bool = false        ## 是否免疫借机攻击（TELEPORT/SWAP 默认 true）
var ignore_terrain: bool = false    ## 是否无视地形阻挡（仅 TELEPORT）

# ── 撞击规则（PUSH/PULL/DASH）──
var on_block: int = OnBlock.STOP
var on_block_damage: int = 0
var on_block_chain: bool = false

# ── 配对单位（SWAP）──
var partner = null                  ## 与 unit 互换的另一单位

# ── 元信息 ──
var source = null                   ## 施法者（日志归因）
var ability_id: String = ""         ## 关联的能力 id


# ──────────── 工厂方法 ────────────

static func teleport(p_unit, p_dest: Vector2i, p_ignore_zoc: bool = true, p_ignore_terrain: bool = true):
	var s = new()
	s.kind = Kind.TELEPORT
	s.unit = p_unit
	s.dest = p_dest
	s.ignore_zoc = p_ignore_zoc
	s.ignore_terrain = p_ignore_terrain
	return s


## PUSH：把 target 沿「from_pos → target」方向推出 distance 格
##   from_pos: 推力源的位置（通常是施法者的 axial_pos）
static func push(target, from_pos: Vector2i, p_distance: int = 1, p_on_block_damage: int = 0):
	var s = new()
	s.kind = Kind.PUSH
	s.unit = target
	s.distance = max(1, p_distance)
	s.on_block_damage = p_on_block_damage
	s.on_block = OnBlock.DAMAGE if p_on_block_damage > 0 else OnBlock.STOP
	s.dest = _compute_push_dest(target.axial_pos, from_pos, s.distance)
	return s


## PULL：把 target 沿「target → to_pos」方向拉过来 distance 格
##   to_pos: 牵引终点的位置（通常是施法者的 axial_pos）
static func pull(target, to_pos: Vector2i, p_distance: int = 1, p_ignore_zoc: bool = true):
	var s = new()
	s.kind = Kind.PULL
	s.unit = target
	s.distance = max(1, p_distance)
	s.ignore_zoc = p_ignore_zoc
	s.dest = _compute_pull_dest(target.axial_pos, to_pos, s.distance)
	return s


## SWAP：unit_a 与 unit_b 互换位置
static func swap(unit_a, unit_b, p_ignore_zoc: bool = true):
	var s = new()
	s.kind = Kind.SWAP
	s.unit = unit_a
	s.partner = unit_b
	s.ignore_zoc = p_ignore_zoc
	return s


## DASH：unit 沿路径移动到 dest（路径由 MovementSystem 计算）
static func dash(p_unit, p_dest: Vector2i, p_ignore_zoc: bool = false):
	var s = new()
	s.kind = Kind.DASH
	s.unit = p_unit
	s.dest = p_dest
	s.ignore_zoc = p_ignore_zoc
	return s


## 从 JSON 字典构造（数据驱动技能用）
## 注意：cfg 只声明「位移类型 + 参数」，目标/落点由调用方在运行时根据 user/target 计算并传入。
##   cfg = {
##     "kind":           "PUSH" | "PULL" | "SWAP" | "TELEPORT" | "DASH",
##     "distance":       1,                   # PUSH/PULL/DASH 用
##     "ignore_zoc":     true/false,
##     "ignore_terrain": true/false,          # 仅 TELEPORT
##     "on_block":       "STOP"|"DAMAGE"|"CHAIN_PUSH",
##     "on_block_damage": 0,
##     "min_dist":       2,                   # DASH：最小起跑距离（runtime 检查）
##   }
##
## 参数：
##   user   = 施法者（用于 SWAP/TELEPORT 的发起方、PUSH/PULL 的方向参考点）
##   target = 主要目标（PUSH/PULL/SWAP 的对象；TELEPORT/DASH 时可为 null）
##   dest   = TELEPORT/DASH 的预计落点；其他 kind 由工厂自动计算
static func from_dict(cfg: Dictionary, user, target = null, dest: Vector2i = Vector2i.ZERO):
	var kind_str: String = String(cfg.get("kind", "TELEPORT")).to_upper()
	var distance: int = int(cfg.get("distance", 1))
	var on_block_damage: int = int(cfg.get("on_block_damage", 0))
	var ignore_zoc: bool = bool(cfg.get("ignore_zoc", false))
	var ignore_terrain: bool = bool(cfg.get("ignore_terrain", false))

	var s = null
	match kind_str:
		"TELEPORT":
			s = teleport(user, dest, true if not cfg.has("ignore_zoc") else ignore_zoc, \
				true if not cfg.has("ignore_terrain") else ignore_terrain)
		"PUSH":
			if target == null:
				return null
			s = push(target, user.axial_pos, distance, on_block_damage)
			if cfg.has("ignore_zoc"):
				s.ignore_zoc = ignore_zoc
		"PULL":
			if target == null:
				return null
			s = pull(target, user.axial_pos, distance, true if not cfg.has("ignore_zoc") else ignore_zoc)
		"SWAP":
			if target == null:
				return null
			s = swap(user, target, true if not cfg.has("ignore_zoc") else ignore_zoc)
		"DASH":
			s = dash(user, dest, false if not cfg.has("ignore_zoc") else ignore_zoc)
		_:
			return null

	# 通用 on_block 覆盖
	if cfg.has("on_block"):
		var ob: String = String(cfg.get("on_block")).to_upper()
		match ob:
			"STOP":       s.on_block = OnBlock.STOP
			"DAMAGE":     s.on_block = OnBlock.DAMAGE
			"CHAIN_PUSH": s.on_block = OnBlock.CHAIN_PUSH
	return s


# ──────────── 辅助方法 ────────────

## 计算 PUSH 落点：target 沿 (target - from) 方向走 distance 格
static func _compute_push_dest(target_pos: Vector2i, from_pos: Vector2i, p_distance: int) -> Vector2i:
	var dir_idx: int = _HexCoord.approx_direction(from_pos, target_pos)
	var pos: Vector2i = target_pos
	for i in range(p_distance):
		pos = _HexCoord.neighbor(pos, dir_idx)
	return pos


## 计算 PULL 落点：target 沿 (to - target) 方向走 distance 格（被拉向 to_pos）
static func _compute_pull_dest(target_pos: Vector2i, to_pos: Vector2i, p_distance: int) -> Vector2i:
	if target_pos == to_pos:
		return target_pos
	var dir_idx: int = _HexCoord.approx_direction(target_pos, to_pos)
	var pos: Vector2i = target_pos
	# 拉拽：目标向 to_pos 方向移动，但最多到 to_pos 相邻格（不会与施法者重叠）
	for i in range(p_distance):
		var next_pos: Vector2i = _HexCoord.neighbor(pos, dir_idx)
		if next_pos == to_pos:
			break
		pos = next_pos
	return pos
