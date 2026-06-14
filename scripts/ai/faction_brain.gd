extends RefCounted
class_name FactionBrain
##
## FactionBrain.gd — 阵营态势快照（ai-system §八）
##

const _HexCoord = preload("res://scripts/core/HexCoord.gd")


static func compute_all(all_units: Array, hex_grid) -> Dictionary:
	return {
		0: compute(0, all_units, hex_grid),
		1: compute(1, all_units, hex_grid),
	}


static func compute(faction: int, all_units: Array, hex_grid) -> Dictionary:
	var allies: Array = []
	var enemies: Array = []
	for u in all_units:
		if u == null or not u.is_alive():
			continue
		if u.get_faction() == faction:
			allies.append(u)
		else:
			enemies.append(u)

	var focus_marks: Array = []
	for ally in allies:
		for d in range(6):
			var nb: Vector2i = _HexCoord.neighbor(ally.axial_pos, d)
			var occ = hex_grid.get_occupant(nb) if hex_grid != null else null
			if occ != null and occ.is_alive() and occ.get_faction() != faction:
				if not occ in focus_marks:
					focus_marks.append(occ)

	var power_self: float = _estimate_power(allies)
	var power_enemy: float = _estimate_power(enemies)
	var power_ratio: float = power_self / max(1.0, power_enemy)

	var engaged: int = 0
	for a in allies:
		for e in enemies:
			if _HexCoord.distance(a.axial_pos, e.axial_pos) <= 2:
				engaged += 1
				break

	var nearest_gap: int = 99
	if allies.is_empty() or enemies.is_empty():
		nearest_gap = 0 if allies.is_empty() or enemies.is_empty() else 99
	else:
		for a in allies:
			for e in enemies:
				nearest_gap = mini(nearest_gap, _HexCoord.distance(a.axial_pos, e.axial_pos))

	var stance: String = "hold"
	if power_ratio >= 1.25:
		stance = "attack"
	elif power_ratio < 0.6:
		stance = "retreat"
	elif power_ratio >= 0.85 and power_ratio <= 1.15:
		stance = "attack"

	return {
		"focus_marks": focus_marks,
		"power_ratio": power_ratio,
		"engaged_count": engaged,
		"ally_total": allies.size(),
		"enemy_total": enemies.size(),
		"nearest_gap": nearest_gap,
		"stance": stance,
	}


static func _estimate_power(units: Array) -> float:
	var total: float = 0.0
	for u in units:
		if u == null or not u.is_alive() or u.stats == null:
			continue
		var dmg: float = float(u.weapon.damage_base) if u.weapon else 30.0
		var hp: float = float(u.stats.hp)
		var armor: float = float(u.stats.body_armor + u.stats.head_armor)
		total += hp * 0.5 + armor * 0.3 + dmg * 2.0
	return total
