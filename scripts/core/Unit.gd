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
const AP_PER_HEX: int = 1                  ## 每移动 1 hex 消耗的 AP


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
## 沿路径异步移动；返回是否成功开始移动
func move_along_path(path: Array[Vector2i]) -> bool:
	if path.is_empty() or not is_alive():
		return false
	var ap_needed: int = path.size() * AP_PER_HEX
	if stats.ap < ap_needed:
		return false

	# 扣 AP / Fatigue（先扣，移动失败不会发生因为路径已校验）
	stats.spend_ap(ap_needed)
	stats.add_fatigue(path.size() * FATIGUE_PER_HEX)

	# 异步动画
	_animate_path(path)
	return true


func _animate_path(path: Array[Vector2i]) -> void:
	var from: Vector2i = axial_pos
	for step in path:
		var target_pos: Vector2 = HexCoord.axial_to_pixel(step, HexGrid.HEX_SIZE)
		var distance: float = position.distance_to(target_pos)
		var duration: float = distance / MOVE_SPEED_PX_PER_SEC
		var tween := create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		await tween.finished
		# 更新占用
		hex_grid.move_occupant(axial_pos, step, self)
		axial_pos = step
		moved.emit(self, from, step)
		from = step
	stats_changed.emit(self)


# ──────────── 攻击 ────────────
## 对目标执行一次攻击（含命中、伤害管线计算）
## 返回 DamageResult 字典
func attack_target(target: Unit) -> Dictionary:
	if not is_alive() or not target.is_alive() or weapon == null:
		return {}
	if stats.ap < weapon.ap_cost:
		return {"reason": "not_enough_ap"}
	var dist: int = HexCoord.distance(axial_pos, target.axial_pos)
	if dist > weapon.range:
		return {"reason": "out_of_range"}

	stats.spend_ap(weapon.ap_cost)
	stats.add_fatigue(weapon.fatigue_cost)

	var result: Dictionary = DamageSystem.execute_attack(self, target)
	# 应用伤害到 target
	if result.get("hit", false):
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

	stats_changed.emit(self)
	attacked.emit(self, target, result)
	return result


# ──────────── 渲染 ────────────
const UNIT_RADIUS: float = 16.0


func _draw() -> void:
	if not is_alive():
		return
	# 阵营颜色
	var body_color: Color
	var border_color: Color
	if get_faction() == 0:
		body_color = Color(0.29, 0.56, 0.85)         # 友方蓝
		border_color = Color(0.85, 0.92, 1.0)
	else:
		body_color = Color(0.78, 0.22, 0.22)         # 敌方红
		border_color = Color(1.0, 0.85, 0.85)
	# 阴影
	draw_circle(Vector2(2, 2), UNIT_RADIUS, Color(0, 0, 0, 0.55))
	# 主体
	draw_circle(Vector2.ZERO, UNIT_RADIUS, body_color)
	# 边框
	draw_arc(Vector2.ZERO, UNIT_RADIUS, 0, TAU, 32, border_color, 2.0, true)
	# HP 微条（在脚下）
	var hp_ratio: float = clamp(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
	var bar_w: float = 28.0
	var bar_h: float = 4.0
	var bar_origin := Vector2(-bar_w * 0.5, UNIT_RADIUS + 4.0)
	draw_rect(Rect2(bar_origin, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.7), true)
	draw_rect(Rect2(bar_origin, Vector2(bar_w * hp_ratio, bar_h)), Color(0.85, 0.22, 0.22), true)
