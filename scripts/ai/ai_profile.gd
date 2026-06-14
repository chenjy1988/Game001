extends RefCounted
class_name AIProfile
##
## AIProfile.gd — archetype × disposition × 士气档 × 气力档（ai-system §七）
##

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")

var archetype_id: String = "infantry"
var disposition_id: String = "default"

var _archetype: Dictionary = {}
var _disposition: Dictionary = {}


static func build(unit):
	var p = preload("res://scripts/ai/ai_profile.gd").new()
	if unit == null:
		return p
	p.archetype_id = unit.get_ai_archetype_id() if unit.has_method("get_ai_archetype_id") else "infantry"
	p.disposition_id = unit.get_ai_disposition_id() if unit.has_method("get_ai_disposition_id") else "default"
	var arch_db = _arch_db()
	var disp_db = _disp_db()
	p._archetype = arch_db.get_archetype(p.archetype_id) if arch_db else {}
	p._disposition = disp_db.get_disposition(p.disposition_id) if disp_db else {}
	return p


static func _arch_db():
	if Engine.get_main_loop() == null:
		return null
	return Engine.get_main_loop().root.get_node_or_null("ArchetypeDB")


static func _disp_db():
	if Engine.get_main_loop() == null:
		return null
	return Engine.get_main_loop().root.get_node_or_null("DispositionDB")


func behavior_mult(behavior_id: String, unit = null) -> float:
	var a_tbl: Dictionary = _archetype.get("behavior_mult", {})
	var d_tbl: Dictionary = _disposition.get("behavior_mult", {})
	var mult: float = float(a_tbl.get(behavior_id, 1.0)) * float(d_tbl.get(behavior_id, 1.0))
	mult *= _morale_mult(behavior_id)
	mult *= _fatigue_mult(behavior_id, unit)
	return mult


func target_mult() -> float:
	return float(_disposition.get("target_mult", 1.0))


func flank_mult() -> float:
	return float(_archetype.get("flank_mult", 1.0))


func oa_sensitivity(unit) -> float:
	var base: float = float(_archetype.get("oa_sensitivity", 0.5))
	return base * _tank_factor(unit)


func threat_sensitivity(unit) -> float:
	var base: float = float(_archetype.get("threat_sensitivity", 0.5))
	return base * _tank_factor(unit)


## 散兵/斥候/弓手/匕首：友军前排贴脸前不抢先进攻
func delays_for_allies(unit = null) -> bool:
	if archetype_id in ["skirmisher", "scout", "archer"]:
		return true
	if unit != null and unit.weapon != null and str(unit.weapon.id) == "dagger":
		return true
	return false


## 是否应延后进攻（有坦克友军在场、且尚未贴脸接敌）
func should_delay_for_allies(view) -> bool:
	if view == null or view.unit == null:
		return false
	if not delays_for_allies(view.unit):
		return false
	if _ally_adjacent_to_enemy(view):
		return false
	var front = _leading_frontline_ally(view)
	if front == null:
		return false
	# 仅当自己在前排友军之后（更远离敌）才 Q；同距/更前不延后，避免镜像互等
	var my_dist: int = _nearest_enemy_dist(view, view.unit.axial_pos)
	var front_dist: int = _nearest_enemy_dist(view, front.axial_pos)
	return my_dist > front_dist


## 重步兵：友军已更靠前、自己未贴脸 → 不应在后排 Wait/吃 hold 加成
func is_hanging_back(view) -> bool:
	if archetype_id != "heavy_infantry" or view == null or view.unit == null:
		return false
	if _self_adjacent_to_enemy(view):
		return false
	var my_dist: int = _nearest_enemy_dist(view, view.unit.axial_pos)
	for a in view.alive_allies:
		if a == view.unit:
			continue
		if _nearest_enemy_dist(view, a.axial_pos) < my_dist:
			return true
	return false


## 后排重甲应前压：补给 Engage/Advance 额外分（压过远距 Wait+hold）
func frontline_push_bonus(view) -> float:
	if not is_hanging_back(view):
		return 0.0
	return 55.0


## 进攻型目标优选：非守势时启用（射程内目标 + 走+打净效用扣 OA）
func uses_offensive_target_selection(view = null) -> bool:
	if view != null and _is_defensive_posture(view):
		return false
	return true


## 被围且重甲 → 守势，不走进攻换目标逻辑
func _is_defensive_posture(view) -> bool:
	if view == null or view.unit == null:
		return false
	if archetype_id != "heavy_infantry":
		return false
	return _adjacent_enemy_count(view) >= 2


static func _adjacent_enemy_count(view) -> int:
	var n: int = 0
	var pos = view.unit.axial_pos
	for d in range(6):
		var nb = _HexCoord.neighbor(pos, d)
		var occ = view.get_occupant(nb)
		if occ != null and occ.is_alive() and occ.get_faction() != view.unit.get_faction():
			n += 1
	return n


static func _self_adjacent_to_enemy(view) -> bool:
	var self_u = view.unit
	for e in view.alive_enemies:
		if _HexCoord.distance(self_u.axial_pos, e.axial_pos) <= 1:
			return true
	return false


static func _nearest_enemy_dist(view, tile: Vector2i) -> int:
	var best: int = 99
	for e in view.alive_enemies:
		best = mini(best, _HexCoord.distance(tile, e.axial_pos))
	return best


static func _ally_adjacent_to_enemy(view) -> bool:
	var self_u = view.unit
	for a in view.alive_allies:
		if a == self_u:
			continue
		for e in view.alive_enemies:
			if _HexCoord.distance(a.axial_pos, e.axial_pos) <= 1:
				return true
	return false


static func _leading_frontline_ally(view):
	var self_u = view.unit
	var best = null
	var best_dist: int = 99
	for a in view.alive_allies:
		if a == self_u:
			continue
		var arch: String = a.get_ai_archetype_id() if a.has_method("get_ai_archetype_id") else "infantry"
		if arch not in ["infantry", "heavy_infantry", "bandit"]:
			continue
		var d: int = _nearest_enemy_dist(view, a.axial_pos)
		if d < best_dist:
			best_dist = d
			best = a
	return best


static func _tank_factor(unit) -> float:
	if unit == null or unit.stats == null:
		return 1.0
	var hp_ratio: float = float(unit.stats.hp) / float(max(1, unit.stats.max_hp))
	var armor_ratio: float = 0.0
	if unit.stats.max_body_armor > 0:
		armor_ratio = float(unit.stats.body_armor) / float(unit.stats.max_body_armor)
	var block_pts: float = float(unit.get_equipment_block_pts()) if unit.has_method("get_equipment_block_pts") else 0.0
	var tank: float = hp_ratio * 0.35 + armor_ratio * 0.45 + clamp(block_pts / 25.0, 0.0, 1.0) * 0.2
	return clampf(1.0 - (tank - 0.2) * 0.58, 0.22, 1.0)


func _morale_mult(_behavior_id: String) -> float:
	# H2 士气未实装
	return 1.0


func _fatigue_mult(behavior_id: String, unit) -> float:
	if unit == null or unit.stats == null:
		return 1.0
	var ratio: float = float(max(0, unit.stats.max_stamina - unit.stats.stamina_spent())) \
		/ float(max(1, unit.stats.max_stamina))
	if ratio <= 0.2:
		if behavior_id in ["attack", "engage", "advance"]:
			return 0.75
	if ratio <= 0.5:
		if behavior_id == "attack":
			return 0.9
	return 1.0
