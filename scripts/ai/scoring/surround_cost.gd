extends RefCounted
class_name AISurroundCost

## 进入/加深包围的分数成本（utility 尺度，纯减法）。
## cost ≈ 新增邻敌「打我能得多少 TargetScore」之和 × scale × weight — 无固定 90 分阈值。

const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _TargetScorer = preload("res://scripts/ai/scoring/target_scorer.gd")

const D_MIN_ADJ: int = 2
const D_NEW_ADJ_WEIGHT: float = 1.0

static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null


static func _utility_scale() -> float:
	var db = _cfg()
	return db.attack_utility_scale() if db else 100.0


static func _f(key: String, fallback: float) -> float:
	var db = _cfg()
	if db == null:
		return fallback
	return float(db._get_nested("action_scoring/surround_cost/%s" % key, fallback))


static func _i(key: String, fallback: int) -> int:
	return int(_f(key, float(fallback)))


## 落点相对起点恶化的包围成本；gross 收益已在调用方，此处只做减法。
static func compute(view, origin: Vector2i, dest: Vector2i, profile = null) -> float:
	if view == null or view.unit == null:
		return 0.0
	var min_adj: int = _i("min_adjacent", D_MIN_ADJ)
	var n1: int = adjacent_enemy_count(view, dest)
	if n1 < min_adj:
		return 0.0
	var new_enemies: Array = _newly_adjacent_enemies(view, origin, dest)
	if new_enemies.is_empty():
		return 0.0
	var scale: float = _utility_scale()
	var weight: float = _f("per_new_adjacent_weight", D_NEW_ADJ_WEIGHT)
	var cost: float = 0.0
	var mover = view.unit
	for enemy in new_enemies:
		cost += _enemy_pressure_score(enemy, mover, view, profile) * scale * weight
	return cost


static func breakdown(view, origin: Vector2i, dest: Vector2i, profile = null) -> Dictionary:
	var new_enemies: Array = _newly_adjacent_enemies(view, origin, dest)
	var total: float = compute(view, origin, dest, profile)
	return {
		"cost": total,
		"delta_adjacent": new_enemies.size(),
		"dest_adjacent": adjacent_enemy_count(view, dest),
	}


static func adjacent_enemy_count(view, tile: Vector2i) -> int:
	var n: int = 0
	for d in range(6):
		var nb: Vector2i = _HexCoord.neighbor(tile, d)
		var occ = view.get_occupant(nb)
		if occ != null and occ != view.unit and occ.is_alive() \
				and occ.get_faction() != view.unit.get_faction():
			n += 1
	return n


static func _newly_adjacent_enemies(view, origin: Vector2i, dest: Vector2i) -> Array:
	var out: Array = []
	for e in view.alive_enemies:
		var was_adj: bool = _HexCoord.distance(origin, e.axial_pos) <= 1
		var now_adj: bool = _HexCoord.distance(dest, e.axial_pos) <= 1
		if now_adj and not was_adj:
			out.append(e)
	return out


static func _enemy_pressure_score(enemy, mover, view, profile) -> float:
	if enemy == null or mover == null or enemy.weapon == null:
		return 0.35
	var modes: Array = enemy.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	var best: float = 0.0
	for mode in modes:
		var opt: Dictionary = {"enemy_total": int(view.faction_brain.get("enemy_total", 99))}
		if mode != "":
			opt["mode"] = mode
		var s: float = _TargetScorer.score(enemy, mover, opt, false)
		best = maxf(best, s)
	return maxf(0.05, best)
