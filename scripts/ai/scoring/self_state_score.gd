extends RefCounted
class_name AISelfStateScore

## 自身状态对 Move/攻前净分的连续 ± 修正（utility 尺度）。
## I4 扩展：PlanGenerator 在 finalize 前可读取 breakdown 做日志。

const D_HP_WEIGHT: float = 0.35
const D_ARMOR_WEIGHT: float = 0.25
const D_STAMINA_WEIGHT: float = 0.15
const D_ALREADY_SURROUNDED: float = 0.20

static func _cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null


static func _utility_scale() -> float:
	var db = _cfg()
	return db.attack_utility_scale() if db else 100.0


static func _f(key: String, fallback: float) -> float:
	var db = _cfg()
	if db == null:
		return fallback
	return float(db._get_nested("action_scoring/self_state/%s" % key, fallback))


## 返回 utility 尺度的净修正（正=更敢打，负=更保守）
static func delta(unit, profile = null, adjacent_enemy_count: int = -1) -> float:
	if unit == null or unit.stats == null:
		return 0.0
	var scale: float = _utility_scale()
	var st = unit.stats
	var hp_ratio: float = float(st.hp) / float(max(1, st.max_hp))
	var armor_ratio: float = 0.0
	if st.max_body_armor > 0:
		armor_ratio = float(st.body_armor) / float(st.max_body_armor)
	var stam_ratio: float = 1.0
	if st.max_stamina > 0:
		stam_ratio = float(max(0, st.max_stamina - st.stamina_spent())) / float(st.max_stamina)

	var hp_w: float = _f("hp_weight", D_HP_WEIGHT)
	var armor_w: float = _f("armor_weight", D_ARMOR_WEIGHT)
	var stam_w: float = _f("stamina_weight", D_STAMINA_WEIGHT)
	var net: float = 0.0
	net += (hp_ratio - 0.5) * hp_w * scale
	net += (armor_ratio - 0.5) * armor_w * scale
	net += (stam_ratio - 0.5) * stam_w * scale

	if adjacent_enemy_count < 0:
		adjacent_enemy_count = _count_adjacent_enemies(unit)
	var surround_pen: float = _f("already_surrounded", D_ALREADY_SURROUNDED)
	if adjacent_enemy_count >= 2:
		net -= surround_pen * scale

	if profile != null and profile.has_method("behavior_mult"):
		pass
	return net


static func breakdown(unit, adjacent_enemy_count: int = -1) -> Dictionary:
	if unit == null or unit.stats == null:
		return {"net": 0.0, "hp": 0.0, "armor": 0.0, "stamina": 0.0, "surrounded": 0.0}
	var scale: float = _utility_scale()
	var st = unit.stats
	var hp_ratio: float = float(st.hp) / float(max(1, st.max_hp))
	var armor_ratio: float = 0.0
	if st.max_body_armor > 0:
		armor_ratio = float(st.body_armor) / float(st.max_body_armor)
	var stam_ratio: float = 1.0
	if st.max_stamina > 0:
		stam_ratio = float(max(0, st.max_stamina - st.stamina_spent())) / float(st.max_stamina)
	if adjacent_enemy_count < 0:
		adjacent_enemy_count = _count_adjacent_enemies(unit)
	var hp_w: float = _f("hp_weight", D_HP_WEIGHT)
	var armor_w: float = _f("armor_weight", D_ARMOR_WEIGHT)
	var stam_w: float = _f("stamina_weight", D_STAMINA_WEIGHT)
	var hp_term: float = (hp_ratio - 0.5) * hp_w * scale
	var armor_term: float = (armor_ratio - 0.5) * armor_w * scale
	var stam_term: float = (stam_ratio - 0.5) * stam_w * scale
	var surround_term: float = 0.0
	if adjacent_enemy_count >= 2:
		surround_term = -_f("already_surrounded", D_ALREADY_SURROUNDED) * scale
	return {
		"net": hp_term + armor_term + stam_term + surround_term,
		"hp": hp_term,
		"armor": armor_term,
		"stamina": stam_term,
		"surrounded": surround_term,
	}


static func _count_adjacent_enemies(unit) -> int:
	const HC = preload("res://scripts/core/HexCoord.gd")
	if unit == null or unit.hex_grid == null:
		return 0
	var n: int = 0
	var pos: Vector2i = unit.axial_pos
	for d in range(6):
		var occ = unit.hex_grid.get_occupant(HC.neighbor(pos, d))
		if occ != null and occ != unit and occ.is_alive() \
				and occ.get_faction() != unit.get_faction():
			n += 1
	return n
