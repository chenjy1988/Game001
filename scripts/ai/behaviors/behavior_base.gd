extends RefCounted
class_name AIBehavior

const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _Unit = preload("res://scripts/core/Unit.gd")

var order: int = 500
var behavior_id: String = ""
## 风格分类：attack / defend / support / reposition / retreat
## 用于 IntentWeights 缩放评分（详见 design/ai-decision-logic.md §三）
var category: String = "attack"

func evaluate(_view, _profile = null) -> Dictionary:
	return { "score": 0.0, "action": null }


## 剩余气力占比 [0,1]（fatigue 越高越低）
static func stamina_remaining_ratio(unit) -> float:
	if unit == null or unit.stats == null or unit.stats.max_stamina <= 0:
		return 1.0
	var remain: int = unit.stats.stamina
	return clamp(float(remain) / float(unit.stats.max_stamina), 0.0, 1.0)


## 任意敌人在当前武器射程内
static func in_attack_range(view) -> bool:
	var u = view.unit
	if u == null or u.weapon == null:
		return false
	for e in view.alive_enemies:
		var d: int = _HexCoord.distance(u.axial_pos, e.axial_pos)
		if d >= u.weapon.range_min and d <= u.weapon.range_max:
			return true
	return false


## 本回合 AP 足够发动一次普攻
static func can_attack_now(view) -> bool:
	var u = view.unit
	if u == null or u.weapon == null or u.stats == null:
		return false
	if u.stats.ap < u.get_weapon_ap_cost():
		return false
	return in_attack_range(view)


## 在射程内但 AP 不足以发动一次普攻（常见：长矛走 2 格后剩 5 AP）
static func in_range_ap_short(view) -> bool:
	if in_attack_range(view):
		return not can_attack_now(view)
	return false


## 已在偏好接敌距离（长杆=range_max，近战=最近可攻距）
static func at_preferred_engagement(view) -> bool:
	var u = view.unit
	if u == null or u.weapon == null or view.alive_enemies.is_empty():
		return false
	var nd: int = nearest_enemy_distance_at(view, u.axial_pos)
	if is_reach_weapon(u):
		return nd == preferred_engagement_distance(u)
	return nd <= u.weapon.range_max


## 射程内 AP 不足且已在偏好位 → Wait 侧收手；Engage 仍走 setup/OA 综合评分
static func should_hold_for_next_attack(view) -> bool:
	return in_range_ap_short(view) and at_preferred_engagement(view)


## 接敌偏好距离：长杆等多格射程武器保持在 range_max，避免无意义贴脸
static func preferred_engagement_distance(unit) -> int:
	if unit == null or unit.weapon == null:
		return 1
	return unit.weapon.range_max


static func is_reach_weapon(unit) -> bool:
	if unit == null or unit.weapon == null:
		return false
	return unit.weapon.range_max > unit.weapon.range_min


## 落点对最近敌人的距离 vs 偏好距离：>0 奖励，<0 惩罚（仅 reach 武器）
static func reach_position_bias(unit, nearest_dist: int) -> float:
	if not is_reach_weapon(unit):
		return 0.0
	var pref: int = preferred_engagement_distance(unit)
	var delta: int = pref - nearest_dist
	if delta == 0:
		return 0.35
	if delta > 0:
		return -float(delta) * 0.45
	return -float(-delta) * 0.12


static func move_ap_cost(path: Array) -> int:
	if path.is_empty():
		return 0
	return path.size() * _Unit.AP_PER_HEX


static func can_attack_after_move(ap: int, path: Array, atk_ap: int) -> bool:
	return ap - move_ap_cost(path) >= atk_ap


static func nearest_enemy_distance_at(view, tile: Vector2i) -> int:
	var best: int = 99
	if view == null:
		return best
	for e in view.alive_enemies:
		best = mini(best, _HexCoord.distance(tile, e.axial_pos))
	return best


## 长杆走+打：若存在「落点在 range_max 且本回合可攻」的方案，丢弃更近的贴脸方案
static func filter_reach_move_attack_setups(view, setups: Array) -> Array:
	if not is_reach_weapon(view.unit) or setups.is_empty():
		return setups
	var pref: int = preferred_engagement_distance(view.unit)
	var preferred: Array = []
	for setup in setups:
		var dest: Vector2i = setup.get("dest", Vector2i.ZERO)
		if nearest_enemy_distance_at(view, dest) == pref:
			preferred.append(setup)
	return preferred if not preferred.is_empty() else setups


## 留给走位后还能攻击的最大移动 AP（长矛 9AP/攻6/走2 → 最多 3）
static func max_move_ap_for_attack(view) -> int:
	var u = view.unit
	if u == null or u.stats == null or u.weapon == null:
		return 0
	return maxi(0, u.stats.ap - u.get_weapon_ap_cost())


## 本回合最优攻击效用（与 Attack 同量纲：TargetScore × utility_scale）
static func best_attack_utility(view, profile = null, include_move_setup: bool = true) -> Dictionary:
	const Scorer = preload("res://scripts/ai/scoring/target_scorer.gd")
	const Dmg = preload("res://scripts/core/DamageSystem.gd")
	var unit = view.unit
	var out: Dictionary = {
		"utility": 0.0,
		"best_target_score": 0.0,
		"best_hit": 0.0,
	}
	if unit == null or unit.weapon == null or unit.stats == null:
		return out

	var db = _ai_cfg()
	var scale: float = db.attack_utility_scale() if db else 100.0

	var focus_units: Array = view.faction_brain.get("focus_marks", [])
	var rmin: int = unit.weapon.range_min
	var rmax: int = unit.weapon.range_max
	var modes: Array = unit.weapon.attack_modes
	if modes.is_empty():
		modes = ["slash"]

	var attack_tiles: Array = []
	if unit.stats.ap >= unit.get_weapon_ap_cost() and in_attack_range(view):
		attack_tiles.append(unit.axial_pos)
	if include_move_setup:
		for setup in find_move_attack_setups(view):
			var dest: Vector2i = setup["dest"]
			if dest not in attack_tiles:
				attack_tiles.append(dest)

	for tile in attack_tiles:
		for target in view.alive_enemies:
			var dist: int = _HexCoord.distance(tile, target.axial_pos)
			if dist < rmin or dist > rmax:
				continue
			for mode in modes:
				var opt: Dictionary = {}
				if mode != "":
					opt["mode"] = mode
				var opts: Dictionary = Scorer.build_damage_options(unit, opt)
				var hit: float = Dmg.calculate_hit_chance(unit, target, opts)
				out["best_hit"] = maxf(out["best_hit"], hit)
				var ts: float = Scorer.score(unit, target, opt, target in focus_units)
				if profile != null:
					ts *= profile.target_mult()
				out["best_target_score"] = maxf(out["best_target_score"], ts)
				out["utility"] = maxf(out["utility"], ts * scale)

	return out


## situation 分扣除本回合攻击机会成本（击杀收益已含于 TargetScore×kill_mult）
static func subtract_attack_opportunity(
	situation_score: float,
	view,
	profile = null,
	include_move_setup: bool = true,
) -> float:
	var opp: Dictionary = best_attack_utility(view, profile, include_move_setup)
	var db = _ai_cfg()
	var weight: float = db.attack_opportunity_weight() if db else 1.0
	return maxf(0.0, situation_score - weight * float(opp.get("utility", 0.0)))


## 吐纳需满 9 AP 才可执行（与移动/攻击/技能花残 AP 不同）
static func can_spend_breath_now(view) -> bool:
	var u = view.unit if view else null
	return u != null and u.has_method("can_use_breath_regulation") and u.can_use_breath_regulation()


## 吐纳气力恢复效用（Δremaining/max × scale；低于阈值才 >0；不含 AP 门控）
static func compute_breath_recovery_utility(view, profile = null) -> float:
	var u = view.unit
	if u == null or u.stats == null:
		return 0.0
	var db = _ai_cfg()
	var threshold: float = db.breath_stamina_threshold() if db else 0.20
	if stamina_remaining_ratio(u) > threshold:
		return 0.0
	var remain: int = u.stats.stamina
	var after_remain: int = u.breath_regulation_stamina()
	var gain: int = after_remain - remain
	if gain <= 0:
		return 0.0
	var ratio: float = stamina_remaining_ratio(u)
	var urgency: float = clamp((threshold - ratio) / maxf(0.01, threshold), 0.0, 1.0)
	var gain_ratio: float = float(gain) / float(max(1, u.stats.max_stamina))
	var scale: float = db.breath_recovery_utility_scale() if db else 120.0
	return (gain_ratio + urgency * 2.0) * scale


## 先发制人：1 AP + 20/32 气力，下回合 Init +40；使用后不得陷入力竭档
static func can_spend_preempt_now(view) -> bool:
	var u = view.unit if view else null
	if u == null or not u.has_method("can_use_ability_preempt") or not u.can_use_ability_preempt():
		return false
	if u.has_method("would_preempt_cause_exhaustion") and u.would_preempt_cause_exhaustion():
		return false
	return true


## 残 AP 场景：不够完整一击，或已在偏好位等下回合
static func is_leftover_ap_for_preempt(view) -> bool:
	var u = view.unit if view else null
	if u == null or u.stats == null:
		return false
	var atk_ap: int = u.get_weapon_ap_cost() if u.has_method("get_weapon_ap_cost") else 999
	if u.stats.ap < atk_ap:
		return true
	if should_hold_for_next_attack(view):
		return true
	return false


## 相邻存活敌方（hex 距离 1）
static func adjacent_enemies(view) -> Array:
	var out: Array = []
	var u = view.unit if view else null
	if u == null:
		return out
	for e in view.alive_enemies:
		if _HexCoord.distance(u.axial_pos, e.axial_pos) == 1:
			out.append(e)
	return out


## 先发制人抢下回合先手效用（仅当能超车至少一名相邻敌时 >0）
static func compute_preempt_initiative_utility(view) -> float:
	var u = view.unit if view else null
	if u == null or not can_spend_preempt_now(view) or not is_leftover_ap_for_preempt(view):
		return 0.0
	var adj: Array = adjacent_enemies(view)
	if adj.is_empty():
		return 0.0
	const TS = preload("res://scripts/core/TurnScheduler.gd")
	const _Unit = preload("res://scripts/core/Unit.gd")
	var alive: Array[_Unit] = []
	for unit in view.all_units:
		if unit is _Unit and unit.is_alive():
			alive.append(unit)
	var base_order: Array = TS.calculate_turn_order(alive, true)
	var pre_order: Array = TS.calculate_order_after_preempt(alive, u)
	var my_base: int = base_order.find(u)
	var my_pre: int = pre_order.find(u)
	if my_base < 0 or my_pre < 0 or my_pre >= my_base:
		return 0.0
	var beaten: int = 0
	for e in adj:
		var eb: int = base_order.find(e)
		var ep: int = pre_order.find(e)
		if eb < 0 or ep < 0:
			continue
		if eb < my_base and my_pre < ep:
			beaten += 1
	if beaten <= 0:
		return 0.0
	var db = _ai_cfg()
	var per_enemy: float = db.preempt_utility_per_enemy_beaten() if db else 95.0
	var slot_scale: float = db.preempt_slot_gain_scale() if db else 12.0
	return float(beaten) * per_enemy + float(my_base - my_pre) * slot_scale


## 当前 AP 下最佳「花 AP」备选效用（攻击 / 技能 / setup 走位 / 先发；满 9 AP 时才比吐纳）
static func best_ap_spend_utility(view, profile = null) -> float:
	var breath_u: float = 0.0
	if can_spend_breath_now(view):
		breath_u = compute_breath_recovery_utility(view, profile)
	var move_u: float = estimate_move_spend_utility(view, profile)
	var abil_u: float = estimate_ability_spend_utility(view, profile)
	var preempt_u: float = estimate_preempt_spend_utility(view, profile)
	var atk_u: float = 0.0
	if can_attack_now(view):
		atk_u = float(best_attack_utility(view, profile, true).get("utility", 0.0))
	return maxf(maxf(maxf(breath_u, move_u), maxf(abil_u, preempt_u)), atk_u)


## 残 AP / setup 走位效用（供 Wait 机会成本；不调用 Behavior.evaluate）
static func estimate_move_spend_utility(view, profile = null) -> float:
	const ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
	return ES.estimate_best_path_utility(view, profile)


## 职业技能效用（运行时 load 避免与 behavior_ability 解析期循环依赖）
static func estimate_ability_spend_utility(view, profile = null) -> float:
	var babil_script = load("res://scripts/ai/behaviors/behavior_ability.gd")
	if babil_script == null:
		return 0.0
	const Prof = preload("res://scripts/ai/ai_profile.gd")
	if profile == null and view != null and view.unit != null:
		profile = Prof.build(view.unit)
	var r: Dictionary = babil_script.new().evaluate(view, profile)
	return maxf(0.0, float(r.get("score", 0.0)))


## 存在可执行的职业技能（score>0）
static func has_ability_spend_option(view, profile = null) -> bool:
	return estimate_ability_spend_utility(view, profile) > 0.0


## 先发制人效用（运行时 load 避免解析期循环）
static func estimate_preempt_spend_utility(view, profile = null) -> float:
	var bpre_script = load("res://scripts/ai/behaviors/behavior_preempt.gd")
	if bpre_script == null:
		return 0.0
	const Prof = preload("res://scripts/ai/ai_profile.gd")
	if profile == null and view != null and view.unit != null:
		profile = Prof.build(view.unit)
	var r: Dictionary = bpre_script.new().evaluate(view, profile)
	return maxf(0.0, float(r.get("score", 0.0)))


## 存在可执行的先发制人（score>0）
static func has_preempt_spend_option(view, profile = null) -> bool:
	return estimate_preempt_spend_utility(view, profile) > 0.0


## 邻格残 AP：setup 净效用须显著高于 OA，否则收手优于薄 Move
static func should_prefer_end_over_move(view, profile, path: Array) -> bool:
	if view == null or view.unit == null or path.is_empty():
		return false
	if view.can_wait():
		return false
	var u = view.unit
	if u.stats == null or u.stats.ap <= 0:
		return false
	if u.stats.ap >= u.get_weapon_ap_cost():
		return false
	if adjacent_enemies(view).is_empty():
		return false
	const ES = preload("res://scripts/ai/scoring/engage_scorer.gd")
	var setup_u: float = 0.0
	if is_reach_weapon(u):
		setup_u = maxf(
			ES.score_reach_approach_path(view, path, profile),
			ES.score_setup_path(view, path, profile),
		)
	else:
		setup_u = ES.score_setup_path(view, path, profile)
	if setup_u <= 0.0:
		return true
	var oa_pen: float = ES.oa_utility_penalty(view, u, path, profile)
	var margin: float = maxf(15.0, oa_pen * 0.35)
	if view.has_waited_this_turn():
		var db = _ai_cfg()
		var wm: float = float(db._get_nested("engage_scoring/wait_resume_margin_mult", 1.5)) if db else 1.5
		margin *= wm
	return setup_u <= margin


## 不花 AP 的拖延行为（Wait/Defend）扣除握 AP 不用的机会成本。
## 仍可 Q 等待时延后本回合行动，不算空耗；仅本回合不能再等待时才扣 best_ap_spend。
static func subtract_ap_hold_opportunity(
	situation_score: float,
	view,
	profile = null,
) -> float:
	if view != null and view.can_wait():
		return situation_score
	var spend_u: float = best_ap_spend_utility(view, profile)
	if spend_u <= 0.0:
		return situation_score
	var db = _ai_cfg()
	var weight: float = db.ap_hold_opportunity_weight() if db else 1.0
	return maxf(0.0, situation_score - weight * spend_u)


static func faction_hold_bonus(view, profile = null) -> float:
	if view.faction_brain.get("stance", "") != "hold":
		return 0.0
	if profile != null and profile.is_hanging_back(view):
		return 0.0
	var db = _ai_cfg()
	return db.hold_stance_bonus() if db else 40.0


static func _ai_cfg():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null


## 存在可执行的 Attack 候选（比 can_attack_now 更严：TargetScore>0）
static func has_attack_option(view, profile = null) -> bool:
	const BAtk = preload("res://scripts/ai/behaviors/behavior_attack.gd")
	const Prof = preload("res://scripts/ai/ai_profile.gd")
	var atk = BAtk.new()
	if profile == null and view != null and view.unit != null:
		profile = Prof.build(view.unit)
	var r: Dictionary = atk.evaluate(view, profile)
	return r.get("action") != null


## 是否存在「移动后本回合还能攻击」的落点
static func has_move_attack_setup(view) -> bool:
	return not find_move_attack_setups(view).is_empty()


static func find_move_attack_setups(view) -> Array:
	var results: Array = []
	var unit = view.unit
	if unit == null or unit.hex_grid == null or unit.weapon == null or unit.stats == null:
		return results
	if can_attack_now(view):
		return results
	var ap: int = unit.stats.ap
	var atk_ap: int = unit.get_weapon_ap_cost()
	var faction: int = unit.get_faction()
	var max_steps: int = ap / _Unit.AP_PER_HEX
	if max_steps <= 0:
		return results
	var reachable = unit.hex_grid.get_reachable(unit.axial_pos, max_steps, faction)
	for dest in reachable:
		var path: Array = unit.hex_grid.find_path(unit.axial_pos, dest, unit.axial_pos, faction)
		if path.is_empty():
			continue
		var mc: int = move_ap_cost(path)
		if ap - mc < atk_ap:
			continue
		if not tile_in_attack_range(view, dest):
			continue
		results.append({"path": path, "dest": dest, "move_cost": mc})
	return results


## 落点是否在武器射程内（Engage 防「到位没 AP」）
static func tile_in_attack_range(view, tile: Vector2i) -> bool:
	var u = view.unit
	if u == null or u.weapon == null:
		return false
	for e in view.alive_enemies:
		var d: int = _HexCoord.distance(tile, e.axial_pos)
		if d >= u.weapon.range_min and d <= u.weapon.range_max:
			return true
	return false
