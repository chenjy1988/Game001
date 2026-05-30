extends Node2D
class_name Unit
##
## Unit.gd — 战场单位
##
## 持有 Stats / WeaponData / ArmorData，处理移动、攻击、回合开始/结束。
## 通过信号与 TurnManager / BattleScene 通信。
##

signal action_completed(unit)              ## 单位本回合行动完毕（主动结束 turn）
signal unit_died(unit)                     ## 单位死亡
signal moved(unit, from_axial, to_axial)   ## 单位完成一次移动
signal attacked(unit, target, result)      ## 单位完成一次攻击
signal stats_changed(unit)                 ## 属性变化（用于 UI 刷新）

@export var stats: Stats
@export var weapon: WeaponData
@export var armor: ArmorData

var axial_pos: Vector2i = Vector2i.ZERO
var hex_grid: HexGrid = null               ## 由 BattleScene 注入

const MOVE_SPEED_PX_PER_SEC: float = 220.0
const FATIGUE_PER_HEX: int = 3             ## 每移动 1 hex 消耗的疲劳
const AP_PER_HEX: int = 2                  ## 每移动 1 hex 消耗的 AP（战兄弟标准节奏）


func _ready() -> void:
	if stats:
		stats.init_runtime(armor.weight if armor else 0)


# ──────────── 接口 ────────────
func get_faction() -> int:
	return stats.faction if stats else 0


func get_unit_name() -> String:
	return stats.unit_name if stats else "?"


func is_alive() -> bool:
	return stats and stats.is_alive()


func place_at(axial: Vector2i, grid: HexGrid) -> void:
	hex_grid = grid
	axial_pos = axial
	position = HexCoord.axial_to_pixel(axial, HexGrid.HEX_SIZE)
	hex_grid.set_occupant(axial, self)


# ──────────── 回合 ────────────
func start_turn() -> void:
	if not is_alive():
		return
	stats.reset_ap()
	stats.recover_fatigue(15)
	stats_changed.emit(self)


func end_turn() -> void:
	action_completed.emit(self)


# ──────────── 移动 ────────────
## 沿路径异步移动；返回是否成功开始移动。
## 每走一步检查"是否离开了某个敌人的 ZoC"，触发借机攻击；
## 借机攻击命中（或打死）→ 中断剩余路径，未消耗的 AP/疲劳保留。
func move_along_path(path: Array[Vector2i]) -> bool:
	if path.is_empty() or not is_alive():
		return false
	var ap_needed: int = path.size() * AP_PER_HEX
	if stats.ap < ap_needed:
		return false

	# 异步动画 + 逐步 OA 检查
	_animate_path(path)
	return true


func _animate_path(path: Array[Vector2i]) -> void:
	var from: Vector2i = axial_pos
	for step in path:
		# 1) 出发前：本格被哪些敌人控制？
		var prev_ctrls: Array = hex_grid.get_zoc_controllers(axial_pos, get_faction())

		# 2) 预扣本步 AP / 疲劳（命中即停时退还）
		stats.spend_ap(AP_PER_HEX)
		stats.add_fatigue(FATIGUE_PER_HEX)

		# 3) 触发借机攻击：本格被任意敌人控制就触发该敌人一次借机攻击
		#    （比战兄弟原版更严格 —— 在 ZoC 内任何方向移动都触发，不只是"离开"）
		var hit_blocked: bool = false
		for ctrl in prev_ctrls:
			if not is_alive():
				break
			var oa_result: Dictionary = DamageSystem.execute_attack(ctrl, self)
			oa_result["is_opportunity_attack"] = true
			_apply_attack_result(ctrl, self, oa_result)
			ctrl.attacked.emit(ctrl, self, oa_result)
			# 命中即停：被任意一次借机攻击命中 → 中断剩余路径
			if oa_result.get("hit", false):
				hit_blocked = true
			if not is_alive():
				break

		# 被打死或被命中阻挡 → 退还本步 AP/疲劳，不进入新格
		if hit_blocked or not is_alive():
			stats.ap += AP_PER_HEX
			stats.fatigue = max(0, stats.fatigue - FATIGUE_PER_HEX)
			stats_changed.emit(self)
			return

		# 4) tween 到下一格
		var target_pos: Vector2 = HexCoord.axial_to_pixel(step, HexGrid.HEX_SIZE)
		var distance: float = position.distance_to(target_pos)
		var duration: float = max(0.05, distance / MOVE_SPEED_PX_PER_SEC)
		var tween := create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		await tween.finished

		# 5) 更新占用
		hex_grid.move_occupant(axial_pos, step, self)
		axial_pos = step
		moved.emit(self, from, step)
		from = step
	stats_changed.emit(self)


## 把一次攻击结果应用到 target 上（用于借机攻击和正规攻击共用）
static func _apply_attack_result(_attacker: Unit, target: Unit, result: Dictionary) -> void:
	if not result.get("hit", false):
		return
	var loc: String = result.get("hit_location", "body")
	var armor_dmg: int = result.get("armor_damage", 0)
	var hp_dmg: int = result.get("hp_damage", 0)
	if loc == "head":
		target.stats.take_head_armor_damage(armor_dmg)
	else:
		target.stats.take_body_armor_damage(armor_dmg)
	target.stats.take_hp_damage(hp_dmg)
	target.stats_changed.emit(target)
	if not target.is_alive():
		target.unit_died.emit(target)


# ──────────── 攻击 ────────────
## 对目标执行一次攻击（含命中、伤害管线计算）
## 返回 DamageResult 字典
func attack_target(target: Unit) -> Dictionary:
	if not is_alive() or not target.is_alive() or weapon == null:
		return {}
	if stats.ap < weapon.ap_cost:
		return {"reason": "not_enough_ap"}
	var dist: int = HexCoord.distance(axial_pos, target.axial_pos)
	if dist > weapon.attack_range:
		return {"reason": "out_of_range"}

	stats.spend_ap(weapon.ap_cost)
	stats.add_fatigue(weapon.fatigue_cost)

	var result: Dictionary = DamageSystem.execute_attack(self, target)
	_apply_attack_result(self, target, result)

	stats_changed.emit(self)
	attacked.emit(self, target, result)
	return result


# ──────────── 渲染 ────────────
const UNIT_RADIUS: float = 16.0

## 当前回合标记（由 BattleScene 设置），决定要不要画顶部箭头
var is_active_turn: bool = false


func set_active_turn(active: bool) -> void:
	if is_active_turn == active:
		return
	is_active_turn = active
	queue_redraw()


# ──────────── 攻击/受击反馈动画 ────────────
## 视觉 offset（独立于 position，由抖动/lunge tween 控制，_draw 时叠加到所有绘制偏移）
var _visual_offset: Vector2 = Vector2.ZERO :
	set(value):
		_visual_offset = value
		queue_redraw()


## 受击：左右抖动 + modulate 闪红/闪灰
func play_hit_reaction(hit_strength: float = 0.6, was_hit: bool = true) -> void:
	if not is_alive():
		return
	# 受击染色
	var flash_color: Color
	if was_hit:
		flash_color = Color(2.0, 0.5, 0.5)  # 强烈偏红
	else:
		flash_color = Color(1.4, 1.4, 1.4)
	var color_tween := create_tween()
	color_tween.tween_property(self, "modulate", flash_color, 0.05)
	color_tween.tween_property(self, "modulate", Color(1, 1, 1), 0.20)

	# 抖动 _visual_offset 而不是 position，避免和 _animate_path 冲突
	var amp: float = lerp(4.0, 10.0, clamp(hit_strength, 0.0, 1.0))
	var shake_tween := create_tween()
	shake_tween.tween_property(self, "_visual_offset", Vector2(-amp, 0), 0.04)
	shake_tween.tween_property(self, "_visual_offset", Vector2( amp, 0), 0.05)
	shake_tween.tween_property(self, "_visual_offset", Vector2(-amp * 0.5, 0), 0.05)
	shake_tween.tween_property(self, "_visual_offset", Vector2.ZERO, 0.06)


## 攻击者前冲：朝目标方向 lunge ~35% 距离再回来；也用 _visual_offset
func play_attack_lunge(target_axial: Vector2i) -> void:
	if not is_alive():
		return
	var dir: Vector2 = (HexCoord.axial_to_pixel(target_axial, HexGrid.HEX_SIZE)
		- HexCoord.axial_to_pixel(axial_pos, HexGrid.HEX_SIZE)).normalized()
	var lunge_off: Vector2 = dir * (HexGrid.HEX_SIZE * 0.45)
	var tween := create_tween()
	tween.tween_property(self, "_visual_offset", lunge_off, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_visual_offset", Vector2.ZERO, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _process(_delta: float) -> void:
	# 当前回合单位有箭头呼吸动画，需要持续重绘
	if is_active_turn and is_alive():
		queue_redraw()


func _draw() -> void:
	if not is_alive():
		return
	# 应用视觉 offset（受击抖动、出击 lunge）
	if _visual_offset != Vector2.ZERO:
		draw_set_transform(_visual_offset, 0.0, Vector2.ONE)

	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)

	# 阵营色板
	var tunic_color: Color
	var tunic_dark: Color
	var trim_color: Color
	var glow_color: Color
	if get_faction() == 0:
		tunic_color = Color(0.30, 0.52, 0.82)
		tunic_dark  = Color(0.18, 0.32, 0.55)
		trim_color  = Color(0.83, 0.70, 0.30)
		glow_color  = Color(0.45, 0.75, 1.0)
	else:
		tunic_color = Color(0.72, 0.24, 0.24)
		tunic_dark  = Color(0.45, 0.13, 0.13)
		trim_color  = Color(0.20, 0.18, 0.14)
		glow_color  = Color(1.0, 0.45, 0.40)

	var skin_color := Color(0.92, 0.78, 0.62)
	var skin_dark  := Color(0.70, 0.55, 0.42)
	var helmet_color: Color
	var helmet_visible: bool = true
	var w: int = armor.weight if armor else 0
	if w <= 0:
		helmet_visible = false
		helmet_color = Color(0.6, 0.5, 0.4)
	elif w <= 6:
		helmet_color = Color(0.40, 0.28, 0.18)
	elif w <= 14:
		helmet_color = Color(0.55, 0.55, 0.60)
	else:
		helmet_color = Color(0.75, 0.76, 0.80)

	# 1) 投影
	var shadow_y: float = 18.0
	draw_circle(Vector2(1, shadow_y), 14.0, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(0, shadow_y + 1), 10.0, Color(0, 0, 0, 0.40))

	# 2) 当前回合：脚下扇形柔光
	if is_active_turn:
		var glow_r: float = 18.0 + breath * 3.0
		draw_circle(Vector2(0, shadow_y), glow_r,
			Color(glow_color.r, glow_color.g, glow_color.b, 0.20 + 0.10 * breath))

	# 3) 腿
	var pants_color := Color(0.22, 0.18, 0.14)
	var pants_hl    := Color(0.32, 0.27, 0.22)
	draw_rect(Rect2(Vector2(-5, 6), Vector2(4, 12)), pants_color, true)
	draw_rect(Rect2(Vector2( 1, 6), Vector2(4, 12)), pants_color, true)
	draw_line(Vector2(-5, 6), Vector2(-5, 17), pants_hl, 1.0)
	draw_line(Vector2( 1, 6), Vector2( 1, 17), pants_hl, 1.0)
	draw_rect(Rect2(Vector2(-6, 16), Vector2(5, 3)), Color(0.10, 0.08, 0.06), true)
	draw_rect(Rect2(Vector2( 1, 16), Vector2(5, 3)), Color(0.10, 0.08, 0.06), true)

	# 4) 躯干（梯形）
	var torso_pts := PackedVector2Array([
		Vector2(-6, -6), Vector2( 6, -6),
		Vector2( 8,  6), Vector2(-8,  6),
	])
	draw_colored_polygon(torso_pts, tunic_color)
	var torso_shadow_pts := PackedVector2Array([
		Vector2( 2, -6), Vector2( 6, -6),
		Vector2( 8,  6), Vector2( 4,  6),
	])
	draw_colored_polygon(torso_shadow_pts, tunic_dark)
	draw_rect(Rect2(Vector2(-8, 4), Vector2(16, 2.5)), trim_color, true)
	if w > 8:
		var plate_pts := PackedVector2Array([
			Vector2(-4, -4), Vector2( 4, -4),
			Vector2( 5,  3), Vector2(-5,  3),
		])
		draw_colored_polygon(plate_pts,
			Color(helmet_color.r, helmet_color.g, helmet_color.b, 0.55))
		draw_line(Vector2(-3, -3), Vector2(0, 2), Color(0, 0, 0, 0.4), 1.0)
		draw_line(Vector2( 3, -3), Vector2(0, 2), Color(0, 0, 0, 0.4), 1.0)

	# 5) 头 + 脖子
	draw_rect(Rect2(Vector2(-2, -8), Vector2(4, 2)), skin_dark, true)
	draw_circle(Vector2(0, -12), 5.0, skin_color)
	draw_rect(Rect2(Vector2(-2.5, -13), Vector2(1, 1)), Color(0.1, 0.05, 0.0), true)
	draw_rect(Rect2(Vector2( 1.5, -13), Vector2(1, 1)), Color(0.1, 0.05, 0.0), true)

	# 6) 头盔
	if helmet_visible:
		draw_circle(Vector2(0, -13), 5.5, helmet_color)
		draw_rect(Rect2(Vector2(-6, -11), Vector2(12, 1.5)),
			Color(helmet_color.r * 0.7, helmet_color.g * 0.7, helmet_color.b * 0.7), true)
		if w > 14:
			draw_line(Vector2(0, -13), Vector2(0, -9),
				Color(helmet_color.r * 0.5, helmet_color.g * 0.5, helmet_color.b * 0.5), 1.5)

	# 7) 武器
	_draw_weapon()

	# 8) HP 微条
	var hp_ratio: float = clamp(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
	var bar_w: float = 30.0
	var bar_h: float = 4.0
	var bar_origin := Vector2(-bar_w * 0.5, 22.0)
	draw_rect(Rect2(bar_origin - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)),
		Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(bar_origin, Vector2(bar_w, bar_h)),
		Color(0.18, 0.10, 0.10, 1.0), true)
	var fill_color: Color = Color(0.85, 0.22, 0.22)
	if hp_ratio < 0.3:
		fill_color = Color(0.65, 0.15, 0.15)
	elif hp_ratio < 0.6:
		fill_color = Color(0.95, 0.45, 0.20)
	draw_rect(Rect2(bar_origin, Vector2(bar_w * hp_ratio, bar_h)), fill_color, true)

	# 9) 当前回合：头顶箭头
	if is_active_turn:
		var arrow_y: float = -22.0 - breath * 3.0
		var arrow_pts := PackedVector2Array([
			Vector2(-6, arrow_y), Vector2( 6, arrow_y), Vector2( 0, arrow_y + 8),
		])
		var shadow_pts := PackedVector2Array([
			arrow_pts[0] + Vector2(1, 1),
			arrow_pts[1] + Vector2(1, 1),
			arrow_pts[2] + Vector2(1, 1),
		])
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.55))
		draw_colored_polygon(arrow_pts, Color(0.95, 0.82, 0.35, 0.95))
		var arrow_outline := arrow_pts.duplicate()
		arrow_outline.append(arrow_pts[0])
		draw_polyline(arrow_outline, Color(0.55, 0.40, 0.10, 0.9), 1.2, true)


# ──────────── 武器绘制（区分类型） ────────────
func _draw_weapon() -> void:
	if weapon == null:
		return
	var hand: Vector2 = Vector2(8, -2)
	var wid: String = weapon.id
	match wid:
		"short_sword":
			_draw_sword(hand, 14.0, 2.4, 8.0, Color(0.78, 0.80, 0.85))
		"war_hammer":
			_draw_hammer(hand, 14.0, Color(0.45, 0.42, 0.38))
		"dagger":
			_draw_sword(hand, 8.0, 2.0, 5.0, Color(0.85, 0.86, 0.90))
		"spear":
			_draw_spear(hand, 20.0)
		"battle_axe":
			_draw_axe(hand, 14.0)
		_:
			_draw_sword(hand, 12.0, 2.0, 6.0, Color(0.75, 0.78, 0.82))


func _draw_sword(hand: Vector2, length: float, blade_w: float, guard_w: float, blade_color: Color) -> void:
	draw_rect(Rect2(hand + Vector2(-1, -1), Vector2(2.5, 5)), Color(0.30, 0.20, 0.10), true)
	draw_rect(Rect2(hand + Vector2(-guard_w * 0.5, -2), Vector2(guard_w, 1.5)),
		Color(0.50, 0.40, 0.20), true)
	var blade_top: Vector2 = hand + Vector2(0.25, -2 - length)
	var blade_rect := Rect2(hand + Vector2(-blade_w * 0.5 + 0.25, -2 - length), Vector2(blade_w, length))
	draw_rect(blade_rect, blade_color, true)
	draw_line(blade_top, blade_top + Vector2(blade_w * 0.5, 2),
		Color(blade_color.r * 0.6, blade_color.g * 0.6, blade_color.b * 0.6), 1.0)
	draw_line(blade_top + Vector2(-blade_w * 0.5, 1),
		blade_top + Vector2(-blade_w * 0.5, length - 1),
		Color(1, 1, 1, 0.6), 1.0)


func _draw_hammer(hand: Vector2, shaft_len: float, head_color: Color) -> void:
	draw_line(hand, hand + Vector2(0, -shaft_len), Color(0.40, 0.28, 0.18), 2.0)
	var head_y: float = hand.y - shaft_len
	draw_rect(Rect2(Vector2(hand.x - 5, head_y - 3), Vector2(10, 6)), head_color, true)
	draw_rect(Rect2(Vector2(hand.x - 5, head_y - 3), Vector2(10, 1.5)),
		Color(head_color.r * 1.3, head_color.g * 1.3, head_color.b * 1.3), true)


func _draw_spear(hand: Vector2, shaft_len: float) -> void:
	draw_line(hand + Vector2(0, 2), hand + Vector2(0, -shaft_len),
		Color(0.40, 0.28, 0.18), 1.6)
	var tip: Vector2 = hand + Vector2(0, -shaft_len - 5)
	var head_pts := PackedVector2Array([
		tip,
		hand + Vector2(-2.5, -shaft_len),
		hand + Vector2( 2.5, -shaft_len),
	])
	draw_colored_polygon(head_pts, Color(0.80, 0.82, 0.86))
	var head_outline := head_pts.duplicate()
	head_outline.append(head_pts[0])
	draw_polyline(head_outline, Color(0.40, 0.42, 0.46), 1.0, true)


func _draw_axe(hand: Vector2, shaft_len: float) -> void:
	draw_line(hand, hand + Vector2(0, -shaft_len), Color(0.40, 0.28, 0.18), 2.0)
	var head_y: float = hand.y - shaft_len + 2
	var head_pts := PackedVector2Array([
		Vector2(hand.x + 1, head_y),
		Vector2(hand.x + 9, head_y - 3),
		Vector2(hand.x + 10, head_y + 1),
		Vector2(hand.x + 9, head_y + 5),
		Vector2(hand.x + 1, head_y + 4),
	])
	draw_colored_polygon(head_pts, Color(0.55, 0.55, 0.58))
	var head_outline := head_pts.duplicate()
	head_outline.append(head_pts[0])
	draw_polyline(head_outline, Color(0.30, 0.30, 0.32), 1.0, true)
	draw_line(Vector2(hand.x + 9, head_y - 2), Vector2(hand.x + 9, head_y + 4),
		Color(1, 1, 1, 0.6), 1.0)
