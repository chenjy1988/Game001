extends RefCounted
class_name AIEngageScorer

const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")
const _TargetScorer = preload("res://scripts/ai/scoring/target_scorer.gd")
const _Behavior = preload("res://scripts/ai/behaviors/behavior_base.gd")
const _Unit = preload("res://scripts/core/Unit.gd")

# 默认权重（AIConfigDB 未加载时的 fallback）
const D_W_PROXIMITY: float  = 1.0
const D_W_FLANK: float      = 0.3
const D_W_OA_COST: float    = 0.5
const D_W_END_THREAT: float = 0.4
const D_W_SURROUND: float = 0.85
const D_W_TERRAIN: float    = 0.15
const D_W_ELEVATION: float  = 0.30
const D_CANDIDATE_CAP: int  = 60
const SETUP_OA_WEIGHT: float = 1.5
const DEFER_OPPORTUNITY_SCALE: float = 0.4
const OA_ARMOR_REF: float = 120.0
const OA_STRIP_WEIGHT: float = 1.2
const OA_BREAK_BONUS: float = 0.35

static func _cfg(): return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null

static func _utility_scale() -> float:
	var db = _cfg()
	return db.attack_utility_scale() if db else 100.0

## 从配置读取 weight，缺省用默认值
static func _w(key: String, fallback: float) -> float:
	var db = _cfg()
	if db == null: return fallback
	var tbl: Dictionary = db._get_nested("engage_scoring/weights", {})
	return float(tbl.get(key, fallback)) if tbl else fallback


## CANDIDATE_CAP 也读配置（兼容外部引用）
static func candidate_cap() -> int:
	var db = _cfg()
	if db: return int(db._get_nested("engage_scoring/candidate_cap", 60))
	return 60


static func _action_scorer():
	return load("res://scripts/ai/scoring/action_scorer.gd")


static func score_path(view, path: Array, weapon_range: int = 1, profile = null) -> Dictionary:
	if path.is_empty() or view.unit == null:
		return _zero_result(path)
	var dest: Vector2i = path[-1]
	var attacker = view.unit
	var result = {"score": 0.0, "path": path, "dest": dest, "proximity": 0.0, "flank": 0.0, "oa": 0.0, "threat": 0.0, "surround": 0.0, "self_state": 0.0}

	var nearest = _nearest_enemy_to_tile(view, dest)
	var dist: int = nearest.get("distance", 99)
	# proximity：偏好最佳距离（range_max），但不阻止已在射程内时 Attack 接管
	var prox_score: float = 1.0 / (1.0 + abs(float(dist) - float(weapon_range))) * _w("proximity", D_W_PROXIMITY)
	result["proximity"] = prox_score

	var reach_bias: float = _Behavior.reach_position_bias(attacker, dist)
	result["reach"] = reach_bias

	var flank_m: float = profile.flank_mult() if profile != null else 1.0
	var nearest_unit = nearest.get("unit", null)
	if nearest_unit != null and dist == 1 and not _Behavior.is_reach_weapon(attacker):
		result["flank"] = _flank_bonus(attacker, nearest_unit, dest) * _w("flank", D_W_FLANK) * flank_m
	elif nearest_unit != null and dist == 1 and _Behavior.is_reach_weapon(attacker):
		result["flank"] = -0.12 * _w("flank", D_W_FLANK)

	var oa_sens: float = profile.oa_sensitivity(attacker) if profile != null else 1.0
	var threat_sens: float = profile.threat_sensitivity(attacker) if profile != null else 1.0
	var oa_pen: float = oa_utility_penalty(view, attacker, path, profile)
	result["oa"] = -oa_pen / maxf(1.0, _utility_scale()) * _w("oa_cost", D_W_OA_COST) * oa_sens
	result["threat"] = -_end_threat(view, dest) * _w("end_threat", D_W_END_THREAT) * threat_sens
	var entry: Dictionary = _action_scorer().compute_entry_costs(view, path, profile)
	var scale_u: float = _utility_scale()
	result["surround"] = -float(entry.get("surround_cost", 0.0)) / maxf(1.0, scale_u) * _w("surround", D_W_SURROUND)
	result["self_state"] = float(entry.get("self_state", 0.0)) / maxf(1.0, scale_u) * 0.45

	var elev_score: float = _elevation_bonus(view, dest)
	result["elevation"] = elev_score * _w("elevation", 0.30)
	result["score"] = prox_score + result["flank"] + result["oa"] + result["threat"] \
		+ result["surround"] + result["self_state"] + result["elevation"] + reach_bias
	return result


## 本回合走不完攻 AP 时：仅当为下回合贴近高价值目标净正收益才给分（扣 OA）
static func score_setup_path(view, path: Array, profile = null) -> float:
	if path.is_empty() or view.unit == null or view.unit.weapon == null:
		return 0.0
	var unit = view.unit
	var origin: Vector2i = unit.axial_pos
	var dest: Vector2i = path[-1]
	if dest == origin:
		return 0.0
	var scale: float = _utility_scale()
	var rmin: int = unit.weapon.range_min
	var rmax: int = unit.weapon.range_max
	var focus_units: Array = view.faction_brain.get("focus_marks", [])
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	var best_gain: float = 0.0
	for target in view.alive_enemies:
		var d0: int = _HexCoord.distance(origin, target.axial_pos)
		var d1: int = _HexCoord.distance(dest, target.axial_pos)
		var in_before: bool = d0 >= rmin and d0 <= rmax
		var in_after: bool = d1 >= rmin and d1 <= rmax
		var ts: float = 0.0
		for mode in modes:
			var opt: Dictionary = {}
			if mode != "":
				opt["mode"] = mode
			var s: float = _TargetScorer.score(unit, target, opt, target in focus_units)
			if profile != null:
				s *= profile.target_mult()
			ts = maxf(ts, s)
		if ts <= 0.0:
			continue
		var gain: float = 0.0
		if in_after and not in_before:
			gain = ts
			if rmax > rmin:
				gain *= 1.0 if d1 == rmax else 0.5
		elif not in_before and d1 < d0:
			if rmax > rmin:
				if d1 >= rmin and d1 <= rmax:
					gain = ts * (1.0 if d1 == rmax else 0.45)
				elif d1 < rmin:
					gain = 0.0
				else:
					gain = ts * float(d0 - d1) / maxf(1.0, float(d0)) * 0.35
			else:
				gain = ts * float(d0 - d1) / maxf(1.0, float(d0))
		elif in_before and in_after and d1 < d0:
			if rmax > rmin and d1 < rmax:
				gain = 0.0
			else:
				gain = ts * 0.25 * float(d0 - d1)
		best_gain = maxf(best_gain, gain)
	if best_gain <= 0.0:
		return 0.0
	best_gain = _apply_adjacent_setup_gate(view, origin, dest, profile, best_gain)
	if best_gain <= 0.0:
		return 0.0
	var finalized: Dictionary = _action_scorer().finalize_move_net(
		view, path, best_gain * scale, profile)
	return _apply_defer_opportunity_cost(
		view, profile, float(finalized.get("net", 0.0)), origin, dest)


## 残 AP 战术走位：已在射程但本回合不够攻 → 侧翼/掩体/角度（同距或略退），长杆禁止贴脸
static func score_residual_reposition(view, path: Array, weapon_range: int, profile = null) -> float:
	if path.is_empty() or view.unit == null or view.unit.weapon == null or view.unit.stats == null:
		return 0.0
	var unit = view.unit
	if not _Behavior.in_range_ap_short(view):
		return 0.0
	var ap: int = unit.stats.ap
	if ap < _Unit.AP_PER_HEX:
		return 0.0
	var dest: Vector2i = path[-1]
	var nd0: int = _Behavior.nearest_enemy_distance_at(view, unit.axial_pos)
	var nd1: int = _Behavior.nearest_enemy_distance_at(view, dest)
	if _Behavior.is_reach_weapon(unit):
		var pref: int = _Behavior.preferred_engagement_distance(unit)
		if nd1 < pref:
			return 0.0
		if nd1 == pref:
			var r_same = score_path(view, path, weapon_range, profile)
			return maxf(0.0, r_same.score * _utility_scale() * 0.25 - oa_utility_penalty(view, unit, path, profile))
	var r = score_path(view, path, weapon_range, profile)
	if r.score <= 0.0:
		return 0.0
	# 邻格同距：无侧翼/掩体收益不算战术微调（OA 降低后尤需此门控）
	if nd1 == nd0 and not _Behavior.adjacent_enemies(view).is_empty():
		if float(r.get("flank", 0.0)) <= 0.05 and float(r.get("elevation", 0.0)) <= 0.05:
			return 0.0
	var scale: float = _utility_scale()
	if nd1 > nd0:
		return 0.0
	var finalized: Dictionary = _action_scorer().finalize_move_net(
		view, path, maxf(0.0, r.score * scale * 0.55), profile)
	return maxf(0.0, float(finalized.get("net", 0.0)))


## 长杆纯接近（本回合 AP 不够走+打）：强偏好落在 range_max，贴脸 Setup 极低分
static func score_reach_approach_path(view, path: Array, profile = null) -> float:
	if path.is_empty() or view.unit == null or view.unit.weapon == null:
		return 0.0
	if not _Behavior.is_reach_weapon(view.unit):
		return score_setup_path(view, path, profile)
	var unit = view.unit
	var origin: Vector2i = unit.axial_pos
	var dest: Vector2i = path[-1]
	if dest == origin:
		return 0.0
	var scale: float = _utility_scale()
	var rmax: int = unit.weapon.range_max
	var d0: int = _Behavior.nearest_enemy_distance_at(view, origin)
	var d1: int = _Behavior.nearest_enemy_distance_at(view, dest)
	if d1 >= d0:
		return 0.0
	var ts: float = _best_target_score_at_dest(view, dest, profile)
	if ts <= 0.0:
		return 0.0
	var gain: float = 0.0
	if d1 == rmax:
		gain = ts * 1.25
		if d0 > rmax:
			gain += ts * 0.4
	elif d1 > rmax:
		gain = ts * float(d0 - d1) / maxf(1.0, float(d0)) * 0.55
	else:
		gain = ts * 0.08
	gain += _Behavior.reach_position_bias(unit, d1) * 2.0
	var finalized: Dictionary = _action_scorer().finalize_move_net(view, path, gain * scale, profile)
	return _apply_defer_opportunity_cost(
		view, profile, float(finalized.get("net", 0.0)), origin, dest)


## 落点邻敌数（legacy 名 end_threat；I4 包围成本见 AISurroundCost）
static func _end_threat(view, tile: Vector2i) -> int:
	var count: int = 0
	for d in range(6):
		var nb: Vector2i = _HexCoord.neighbor(tile, d)
		var occ = view.get_occupant(nb)
		if occ != null and occ != view.unit and occ.is_alive() \
			and occ.get_faction() != view.unit.get_faction():
			count += 1
	return count


## 邻格残 AP：禁止「最近敌仍贴脸、仅远目标部分接近」；长杆需换打进 pref 距
static func _apply_adjacent_setup_gate(
	view,
	origin: Vector2i,
	dest: Vector2i,
	profile,
	best_gain: float,
) -> float:
	if best_gain <= 0.0 or _Behavior.adjacent_enemies(view).is_empty():
		return best_gain
	var unit = view.unit
	var nd0: int = _Behavior.nearest_enemy_distance_at(view, origin)
	var nd1: int = _Behavior.nearest_enemy_distance_at(view, dest)
	if nd1 > nd0:
		return best_gain
	if nd1 < nd0:
		return best_gain
	if _Behavior.is_reach_weapon(unit):
		var pref: int = _Behavior.preferred_engagement_distance(unit)
		if nd1 < pref and not _has_reach_swap_into_pref_range(view, origin, dest, profile):
			return 0.0
		return best_gain
	return _setup_gain_swap_in_only(view, origin, dest, profile)


static func _has_reach_swap_into_pref_range(view, origin: Vector2i, dest: Vector2i, profile) -> bool:
	var unit = view.unit
	if unit == null or unit.weapon == null:
		return false
	var rmin: int = unit.weapon.range_min
	var rmax: int = unit.weapon.range_max
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	for target in view.alive_enemies:
		var d0: int = _HexCoord.distance(origin, target.axial_pos)
		var d1: int = _HexCoord.distance(dest, target.axial_pos)
		var in_before: bool = d0 >= rmin and d0 <= rmax
		var in_after: bool = d1 >= rmin and d1 <= rmax
		if not (in_after and not in_before and d1 == rmax):
			continue
		for mode in modes:
			var opt: Dictionary = {}
			if mode != "":
				opt["mode"] = mode
			var ts: float = _TargetScorer.score(unit, target, opt, target in view.faction_brain.get("focus_marks", []))
			if profile != null:
				ts *= profile.target_mult()
			if ts > 0.0:
				return true
	return false


## 仅本回合新进射程的换打收益（不含远距部分接近）
static func _setup_gain_swap_in_only(view, origin: Vector2i, dest: Vector2i, profile) -> float:
	var unit = view.unit
	if unit == null or unit.weapon == null:
		return 0.0
	var rmin: int = unit.weapon.range_min
	var rmax: int = unit.weapon.range_max
	var focus_units: Array = view.faction_brain.get("focus_marks", [])
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	var best: float = 0.0
	for target in view.alive_enemies:
		var d0: int = _HexCoord.distance(origin, target.axial_pos)
		var d1: int = _HexCoord.distance(dest, target.axial_pos)
		var in_before: bool = d0 >= rmin and d0 <= rmax
		var in_after: bool = d1 >= rmin and d1 <= rmax
		if not (in_after and not in_before):
			continue
		var ts: float = 0.0
		for mode in modes:
			var opt: Dictionary = {}
			if mode != "":
				opt["mode"] = mode
			var s: float = _TargetScorer.score(unit, target, opt, target in focus_units)
			if profile != null:
				s *= profile.target_mult()
			ts = maxf(ts, s)
		if ts <= 0.0:
			continue
		var gain: float = ts
		if rmax > rmin:
			gain *= 1.0 if d1 == rmax else 0.5
		best = maxf(best, gain)
	return best


static func _best_target_score_at_dest(view, dest: Vector2i, profile = null) -> float:
	var unit = view.unit
	var focus_units: Array = view.faction_brain.get("focus_marks", [])
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	var best: float = 0.0
	for target in view.alive_enemies:
		for mode in modes:
			var opt: Dictionary = {}
			if mode != "":
				opt["mode"] = mode
			var s: float = _TargetScorer.score(unit, target, opt, target in focus_units)
			if profile != null:
				s *= profile.target_mult()
			best = maxf(best, s)
	return best


## OA 决策效用惩罚：① 期望命中×冲击 ② 己方护甲缓冲 ③ 预期掉甲风险
static func oa_utility_penalty(view, mover, path: Array, profile = null) -> float:
	var threat: Dictionary = _estimate_oa_threat(view, mover, path)
	var impact: float = float(threat.get("impact", 0.0))
	var strip: float = float(threat.get("armor_strip", 0.0))
	if impact <= 0.0 and strip <= 0.0:
		return 0.0
	if mover == null or mover.stats == null:
		return 0.0

	var scale: float = _utility_scale()
	var sens: float = profile.oa_sensitivity(mover) if profile != null else 1.0
	var db = _cfg()
	var armor_ref: float = float(db._get_nested("engage_scoring/oa_penalty/armor_ref", OA_ARMOR_REF)) if db else OA_ARMOR_REF
	var strip_weight: float = float(db._get_nested("engage_scoring/oa_penalty/armor_strip_weight", OA_STRIP_WEIGHT)) if db else OA_STRIP_WEIGHT
	var break_bonus: float = float(db._get_nested("engage_scoring/oa_penalty/armor_break_bonus", OA_BREAK_BONUS)) if db else OA_BREAK_BONUS

	var own_armor: float = float(max(0, mover.stats.body_armor + mover.stats.head_armor))

	# ① 期望命中 × 冲击伤害（归一化到 max_hp 再 × utility_scale）
	var primary: float = impact / float(max(1, mover.stats.max_hp)) * scale

	# ② 己方护甲值连续缓冲（护甲越高，同等威胁下惩罚越低）
	var armor_buffer: float = 1.0 / (1.0 + own_armor / maxf(1.0, armor_ref))

	# ③ 预期掉甲：相对当前护甲的损耗比；甲将破额外加权（不单独评 HP）
	var strip_ratio: float = 0.0
	if own_armor > 0.0:
		strip_ratio = strip / own_armor
	elif strip > 0.0:
		strip_ratio = 1.0
	var strip_danger: float = 1.0 + clampf(strip_ratio, 0.0, 1.0) * strip_weight
	if own_armor > 0.0 and strip >= own_armor * 0.85:
		strip_danger += break_bonus

	return primary * armor_buffer * strip_danger * SETUP_OA_WEIGHT * sens


## 邻格残 AP：下回合满 AP 可退+打，薄 setup 扣机会成本（换打/斩杀豁免）
static func _apply_defer_opportunity_cost(
	view,
	profile,
	net_score: float,
	origin: Vector2i,
	dest: Vector2i,
) -> float:
	if net_score <= 0.0:
		return net_score
	var unit = view.unit
	if unit == null or unit.stats == null or unit.weapon == null:
		return net_score
	if unit.stats.ap >= unit.get_weapon_ap_cost():
		return net_score
	if _Behavior.adjacent_enemies(view).is_empty():
		return net_score
	if _is_defer_exempt_setup(view, origin, dest, profile):
		return net_score
	var nearest: Dictionary = _nearest_enemy_to_tile(view, origin)
	var nearest_unit = nearest.get("unit")
	if nearest_unit == null:
		return net_score
	var ts: float = _target_score_for(unit, nearest_unit, profile, view.faction_brain.get("focus_marks", []))
	if ts <= 0.0:
		return net_score
	var db = _cfg()
	var defer_scale: float = float(db._get_nested("engage_scoring/defer_opportunity/scale", DEFER_OPPORTUNITY_SCALE)) if db else DEFER_OPPORTUNITY_SCALE
	return net_score - ts * _utility_scale() * defer_scale


static func _is_defer_exempt_setup(view, origin: Vector2i, dest: Vector2i, profile) -> bool:
	if _setup_gain_swap_in_only(view, origin, dest, profile) > 0.0:
		return true
	if _has_reach_swap_into_pref_range(view, origin, dest, profile):
		return true
	if _has_kill_setup_at_dest(view, origin, dest, profile):
		return true
	return false


## 落点新进射程且期望伤害可斩杀 → 不因 defer 推迟
static func _has_kill_setup_at_dest(view, origin: Vector2i, dest: Vector2i, profile) -> bool:
	var unit = view.unit
	if unit == null or unit.weapon == null:
		return false
	var rmin: int = unit.weapon.range_min
	var rmax: int = unit.weapon.range_max
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	for target in view.alive_enemies:
		var d0: int = _HexCoord.distance(origin, target.axial_pos)
		var d1: int = _HexCoord.distance(dest, target.axial_pos)
		if not (d1 >= rmin and d1 <= rmax and not (d0 >= rmin and d0 <= rmax)):
			continue
		for mode in modes:
			var opt: Dictionary = {}
			if mode != "":
				opt["mode"] = mode
			opt = _TargetScorer.build_damage_options(unit, opt)
			var hit: float = _DamageSystem.calculate_hit_chance(unit, target, opt)
			var on_hit: float = _DamageSystem.estimate_hp_damage_on_hit(unit, target, opt)
			if hit * on_hit >= float(target.stats.hp) * 0.85:
				return true
	return false


static func _target_score_for(unit, target, profile, focus_units: Array = []) -> float:
	if unit == null or unit.weapon == null or target == null:
		return 0.0
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]
	var best: float = 0.0
	for mode in modes:
		var opt: Dictionary = {}
		if mode != "":
			opt["mode"] = mode
		var s: float = _TargetScorer.score(unit, target, opt, target in focus_units)
		if profile != null:
			s *= profile.target_mult()
		best = maxf(best, s)
	return best


static func _nearest_enemy_to_tile(view, tile: Vector2i) -> Dictionary:
	var best = null
	var best_dist: int = 99
	for e in view.alive_enemies:
		var d: int = _HexCoord.distance(tile, e.axial_pos)
		if d < best_dist:
			best_dist = d
			best = e
	return { "unit": best, "distance": best_dist }


static func _flank_bonus(attacker, target, tile: Vector2i) -> float:
	if target == null: return 0.0
	var facing: int = target.facing_dir if target.has_method("facing_dir") else 0
	var back_dir: int = (facing + 3) % 6
	var back_hex: Vector2i = _HexCoord.neighbor(target.axial_pos, back_dir)
	if tile == back_hex: return 0.3
	var flank_l = _HexCoord.neighbor(target.axial_pos, (back_dir + 5) % 6)
	var flank_r = _HexCoord.neighbor(target.axial_pos, (back_dir + 1) % 6)
	if tile == flank_l or tile == flank_r: return 0.15
	return 0.0


static func _elevation_bonus(view, tile: Vector2i) -> float:
	if view.hex_grid == null: return 0.0
	var my_elv: int = view.hex_grid.get_elevation(tile)
	var best: float = 0.0
	for e in view.alive_enemies:
		var diff: int = my_elv - view.hex_grid.get_elevation(e.axial_pos)
		if diff > best: best = float(diff)
	return best


## 沿路径 ZoC 借机攻击威胁：Σ P(hit) × (冲击伤害, 护甲损耗)
static func _estimate_oa_threat(view, mover, path: Array) -> Dictionary:
	if view.hex_grid == null or mover == null or path.is_empty():
		return { "impact": 0.0, "armor_strip": 0.0 }
	var start: Vector2i = mover.axial_pos
	var faction: int = mover.get_faction()
	var oa_steps: Array = view.hex_grid.analyze_path_oa(start, path, faction, mover)
	var total_impact: float = 0.0
	var total_strip: float = 0.0
	for step in oa_steps:
		for ctrl in step.get("oa_attackers", []):
			if ctrl == null or not ctrl.is_alive():
				continue
			var opts: Dictionary = {"is_opportunity_attack": true}
			opts = _TargetScorer.build_damage_options(ctrl, opts)
			var hit: float = _DamageSystem.calculate_hit_chance(ctrl, mover, opts)
			var impact: float = _DamageSystem.estimate_impact_on_hit(ctrl, mover, opts)
			var strip: float = _DamageSystem.estimate_armor_strip_on_hit(ctrl, mover, opts)
			total_impact += hit * impact
			total_strip += hit * strip
	return { "impact": total_impact, "armor_strip": total_strip }


## 轻量估分：不经过 Behavior，供 Wait 机会成本 / 残 AP 判断（避免 evaluate 互递归）
static func estimate_best_path_utility(view, profile = null) -> float:
	var unit = view.unit
	if unit == null or unit.hex_grid == null or unit.weapon == null or unit.stats == null:
		return 0.0
	var ap: int = unit.stats.ap
	const U = preload("res://scripts/core/Unit.gd")
	if ap < U.AP_PER_HEX:
		return 0.0
	var atk_ap: int = unit.get_weapon_ap_cost()
	var faction: int = unit.get_faction()
	var wr: int = unit.weapon.range_max
	var reachable = unit.hex_grid.get_reachable(unit.axial_pos, ap / U.AP_PER_HEX, faction)
	var best: float = 0.0
	var cap: int = mini(reachable.size(), candidate_cap())
	for i in range(cap):
		var dest = reachable[i]
		var path: Array = unit.hex_grid.find_path(unit.axial_pos, dest, unit.axial_pos, faction)
		if path.is_empty():
			continue
		var u: float = 0.0
		if _Behavior.can_attack_after_move(ap, path, atk_ap):
			u = score_path(view, path, wr, profile).score * _utility_scale()
		elif _Behavior.in_range_ap_short(view):
			u = score_residual_reposition(view, path, wr, profile)
		else:
			u = score_setup_path(view, path, profile)
			if u <= 0.0 and _Behavior.is_reach_weapon(unit):
				u = score_reach_approach_path(view, path, profile)
		best = maxf(best, u)
	return best


static func _zero_result(path: Array) -> Dictionary:
	return { "score": 0.0, "path": path, "dest": Vector2i.ZERO,
		"proximity": 0.0, "flank": 0.0, "oa": 0.0, "threat": 0.0, "elevation": 0.0 }
