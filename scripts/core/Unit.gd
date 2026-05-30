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
## 受击：左右抖动 + modulate 闪红/闪灰
##   hit_strength: 0~1，强度（暴击时传 1.0，轻击 0.4）
##   was_hit: true=染红, false=染浅灰（表示未命中/被格挡）
func play_hit_reaction(hit_strength: float = 0.6, was_hit: bool = true) -> void:
	if not is_alive():
		return
	# 受击染色：modulate 闪一下再回归
	var flash_color: Color
	if was_hit:
		flash_color = Color(1.6, 0.6, 0.6)  # 偏红
	else:
		flash_color = Color(1.4, 1.4, 1.4)  # 灰白（miss）
	var color_tween := create_tween()
	color_tween.tween_property(self, "modulate", flash_color, 0.05)
	color_tween.tween_property(self, "modulate", Color(1, 1, 1), 0.18)

	# 抖动：在 hex 中心附近 offset，结束后回归
	var base_pos: Vector2 = HexCoord.axial_to_pixel(axial_pos, HexGrid.HEX_SIZE)
	var shake_amp: float = lerp(2.0, 6.0, clamp(hit_strength, 0.0, 1.0))
	var shake_tween := create_tween()
	# 4 段抖动：左 → 右 → 左 → 回
	shake_tween.tween_property(self, "position", base_pos + Vector2(-shake_amp, 0), 0.04)
	shake_tween.tween_property(self, "position", base_pos + Vector2( shake_amp, 0), 0.05)
	shake_tween.tween_property(self, "position", base_pos + Vector2(-shake_amp * 0.5, 0), 0.05)
	shake_tween.tween_property(self, "position", base_pos, 0.06)


## 攻击者出击动画：朝目标方向冲出 ~30% 距离再回来
func play_attack_lunge(target_axial: Vector2i) -> void:
	if not is_alive():
		return
	var base_pos: Vector2 = HexCoord.axial_to_pixel(axial_pos, HexGrid.HEX_SIZE)
	var target_pos: Vector2 = HexCoord.axial_to_pixel(target_axial, HexGrid.HEX_SIZE)
	var dir: Vector2 = (target_pos - base_pos).normalized()
	var lunge_pos: Vector2 = base_pos + dir * (HexGrid.HEX_SIZE * 0.35)
	var tween := create_tween()
	tween.tween_property(self, "position", lunge_pos, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", base_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _process(_delta: float) -> void:
	# 当前回合单位有箭头呼吸动画，需要持续重绘
	if is_active_turn and is_alive():
		queue_redraw()


func _draw() -> void:
	if not is_alive():
		return
	# 阵营色
	var body_color: Color
	var border_color: Color
	var glow_color: Color
	if get_faction() == 0:
		body_color = Color(0.29, 0.56, 0.85)
		border_color = Color(0.85, 0.92, 1.0)
		glow_color = Color(0.45, 0.75, 1.0)
	else:
		body_color = Color(0.78, 0.22, 0.22)
		border_color = Color(1.0, 0.85, 0.85)
		glow_color = Color(1.0, 0.45, 0.40)

	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)

	# ---- 1) 投影（椭圆，更柔，多层叠加） ----
	var shadow_center := Vector2(2, UNIT_RADIUS - 2)
	# 外层柔（大半径，淡 alpha）
	draw_circle(shadow_center, UNIT_RADIUS * 1.1, Color(0, 0, 0, 0.18))
	# 内层实（小半径，深 alpha）
	draw_circle(shadow_center + Vector2(0, 1), UNIT_RADIUS * 0.85, Color(0, 0, 0, 0.42))

	# ---- 2) 当前回合：外圈柔光 ----
	if is_active_turn:
		var glow_r: float = UNIT_RADIUS + 6.0 + breath * 2.5
		draw_circle(Vector2.ZERO, glow_r,
			Color(glow_color.r, glow_color.g, glow_color.b, 0.20 + 0.12 * breath))

	# ---- 3) 主体（带渐变高光：先画暗色底，再叠亮色高光） ----
	# 底色（稍暗）
	draw_circle(Vector2.ZERO, UNIT_RADIUS,
		Color(body_color.r * 0.75, body_color.g * 0.75, body_color.b * 0.75))
	# 顶部高光（小圆偏上）
	draw_circle(Vector2(-3, -4), UNIT_RADIUS * 0.65, body_color)
	# 顶部白光点
	draw_circle(Vector2(-5, -6), UNIT_RADIUS * 0.22,
		Color(1.0, 1.0, 1.0, 0.35))

	# ---- 4) 描边 ----
	draw_arc(Vector2.ZERO, UNIT_RADIUS, 0, TAU, 36, border_color, 2.2, true)

	# ---- 5) HP 微条（脚下，带描边） ----
	var hp_ratio: float = clamp(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
	var bar_w: float = 30.0
	var bar_h: float = 5.0
	var bar_origin := Vector2(-bar_w * 0.5, UNIT_RADIUS + 5.0)
	# 背板
	draw_rect(Rect2(bar_origin - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)),
		Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(bar_origin, Vector2(bar_w, bar_h)),
		Color(0.18, 0.10, 0.10, 1.0), true)
	# 填充（根据 hp_ratio 变色：高=红，中=橙，低=深红）
	var fill_color: Color = Color(0.85, 0.22, 0.22)
	if hp_ratio < 0.3:
		fill_color = Color(0.65, 0.15, 0.15)
	elif hp_ratio < 0.6:
		fill_color = Color(0.95, 0.45, 0.20)
	draw_rect(Rect2(bar_origin, Vector2(bar_w * hp_ratio, bar_h)), fill_color, true)

	# ---- 6) 当前回合：头顶向下箭头（▼） ----
	if is_active_turn:
		var arrow_y: float = -UNIT_RADIUS - 12.0 - breath * 3.0
		var arrow_pts := PackedVector2Array([
			Vector2(-6, arrow_y),
			Vector2( 6, arrow_y),
			Vector2( 0, arrow_y + 8),
		])
		# 阴影
		var shadow_pts := PackedVector2Array([
			arrow_pts[0] + Vector2(1, 1),
			arrow_pts[1] + Vector2(1, 1),
			arrow_pts[2] + Vector2(1, 1),
		])
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.55))
		# 箭头本体（金色）
		draw_colored_polygon(arrow_pts, Color(0.95, 0.82, 0.35, 0.95))
		# 箭头描边
		var arrow_outline := arrow_pts.duplicate()
		arrow_outline.append(arrow_pts[0])
		draw_polyline(arrow_outline, Color(0.55, 0.40, 0.10, 0.9), 1.2, true)
