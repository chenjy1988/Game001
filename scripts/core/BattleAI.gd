extends RefCounted
class_name BattleAI
##
## BattleAI.gd — 评分式 AI 决策器（纯静态）
##
## 输入：当前 AI 单位 + 战场上下文（HexGrid + 所有单位）
## 输出：一份 Plan = { path, target, end_turn }，由 BattleScene 异步执行
##
## 评分项：
##   + 命中率 × 期望 HP 伤害   ......... 攻击收益
##   + 击杀奖励 (50)           ......... 终结弱目标
##   + 目标 HP 越低权重越高     ......... 集火
##   - 路径触发借机攻击次数惩罚  ......... 规避 OA
##   - 移动距离的轻微惩罚       ......... 节约 AP
##   - 落点处于敌方 ZoC 的惩罚   ......... 避免反被围殴
##   ± 自身坦度（护甲/盾/HP）     ......... 高防单位敢冲阵、卡 ZoC；脆皮更畏威胁、会等待
##

const SCORE_KILL_BONUS: float = 50.0
const SCORE_OA_PER_HIT: float = -50.0          ## 移动后攻击：每个借机命中 -50 分
const SCORE_OA_ADVANCE_MULT: float = 0.2       ## 纯推进时折减（近战必须敢进 ZoC，否则 1 格武器永远站桩）
const SCORE_PER_MOVE_HEX: float = -0.4         ## 移动一格小惩罚
const SCORE_END_IN_ENEMY_ZOC: float = -6.0     ## 落点处在另一个 ZoC 中 -6
const SCORE_LOW_HP_FOCUS_WEIGHT: float = 0.5   ## 目标HP越低，伤害权重提升
const SCORE_IN_RANGE_ATTACK_BONUS: float = 30.0 ## 已在射程内优先出手（力竭也应攻击，规则不禁打）
const SCORE_THREAT_PER_POINT: float = 0.14     ## 落点敌方威胁值 → 分数扣减系数
const THREAT_WAIT_MIN: float = 52.0            ## 威胁超过此值且无法安全换血时考虑等待
const THREAT_TWO_HANDED_MULT: float = 1.45     ## 双手武器威胁加成
const THREAT_RANGE2_MULT: float = 1.22         ## 2 格近战（长杆）威胁加成
const TANK_BLOCK_SHIELD: int = 12              ## block_value ≥ 此值视为持盾/高格挡
const SCORE_TANK_CHOKE_BONUS: float = 16.0     ## 坦度单位贴脸/ZoC 卡位加分
const SCORE_TANK_CHARGE_MULT: float = 1.5      ## 坦度单位冲锋 proximity 倍率上限


## 决策入口；返回 plan 字典：
##   { "path": Array[Vector2i], "target": Unit | null, "end_turn": bool, "score": float, "reason": String }
## 若返回 end_turn=true，BattleScene 直接结束当前回合
static func decide(unit: Unit, all_units: Array, hex_grid: HexGrid, opts: Dictionary = {}) -> Dictionary:
	if not unit.is_alive():
		return {"path": [], "target": null, "end_turn": true, "score": 0.0, "reason": "dead"}

	var can_wait: bool = opts.get("can_wait", false)
	var has_waited: bool = opts.get("has_waited", false)

	var enemies: Array = []
	for u in all_units:
		if u.is_alive() and u.get_faction() != unit.get_faction():
			enemies.append(u)
	if enemies.is_empty():
		return {"path": [], "target": null, "end_turn": true, "score": 0.0, "reason": "no enemies"}

	@warning_ignore("integer_division")
	var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
	var reachable: Array[Vector2i] = hex_grid.get_reachable(unit.axial_pos, max_steps, unit.get_faction())
	# 把"原地"也作为候选（不动）
	var candidates_pos: Array[Vector2i] = [unit.axial_pos]
	candidates_pos.append_array(reachable)

	var best: Dictionary = {"path": [] as Array[Vector2i], "target": null, "end_turn": true, "score": -INF, "reason": "idle"}

	for pos in candidates_pos:
		# 通往 pos 的路径（pos == 自己 axial 时为空数组，相当于不动）
		var path: Array[Vector2i] = []
		if pos != unit.axial_pos:
			path = hex_grid.find_path(unit.axial_pos, pos, unit.axial_pos, unit.get_faction())
			if path.is_empty():
				continue  # 不可达
		# AP 校验：移动 + 至少一次攻击 才有意义；不能攻击就只算"无攻击移动"分支
		var move_ap: int = path.size() * Unit.AP_PER_HEX
		var ap_after_move: int = unit.stats.ap - move_ap
		if ap_after_move < 0:
			continue

		# 评估借机攻击次数 + 期望额外 HP 损失
		var oa_count: int = 0
		var oa_expected_dmg: float = 0.0
		if not path.is_empty():
			var oa_steps: Array = hex_grid.analyze_path_oa(unit.axial_pos, path, unit.get_faction(), unit)
			for s in oa_steps:
				for ctrl in s["oa_attackers"]:
					oa_count += 1
					oa_expected_dmg += _expected_hp_damage(ctrl, unit)

		# 候选 1：到达 pos 后不攻击（站桩/推进）
		var idle_score: float = _score_position_only(unit, pos, enemies, hex_grid, path.size())
		var oa_absorb: float = 1.0 - _threat_sensitivity(unit) * 0.45
		idle_score += SCORE_OA_PER_HIT * SCORE_OA_ADVANCE_MULT * float(oa_count) - oa_expected_dmg * 0.15 * oa_absorb
		if idle_score > best["score"]:
			best = {
				"path": path,
				"target": null,
				"end_turn": true,
				"score": idle_score,
				"reason": "advance/idle",
			}

		# 候选 2：到达 pos 后攻击射程内的某个敌人
		var attack_ap: int = unit.get_weapon_ap_cost()
		if ap_after_move >= attack_ap:
			for tgt in enemies:
				var d: int = HexCoord.distance(pos, tgt.axial_pos)
				if d > unit.weapon.attack_range:
					continue
				# 估算 AP 范围内能打几下
				var attacks_possible: int = ap_after_move / attack_ap
				var hit_chance: float = _hit_chance_after_fatigue(unit, tgt, path.size())
				var dmg_per_hit: float = _expected_hp_damage(unit, tgt)
				var total_dmg: float = dmg_per_hit * float(attacks_possible) * hit_chance

				var atk_score: float = total_dmg
				# 集火：目标 HP 越低，权重越高
				var hp_ratio: float = float(tgt.stats.hp) / float(max(1, tgt.stats.max_hp))
				atk_score *= 1.0 + (1.0 - hp_ratio) * SCORE_LOW_HP_FOCUS_WEIGHT
				# 击杀奖励
				if total_dmg >= float(tgt.stats.hp):
					atk_score += SCORE_KILL_BONUS
				# 移动惩罚
				atk_score += SCORE_PER_MOVE_HEX * float(path.size())
				# 借机攻击惩罚
				atk_score += SCORE_OA_PER_HIT * float(oa_count) - oa_expected_dmg * 0.5 * oa_absorb
				# 落点处在另一个敌人 ZoC（除目标外）
				var threats: Array = hex_grid.get_zoc_controllers(pos, unit.get_faction())
				atk_score += SCORE_END_IN_ENEMY_ZOC * float(max(0, threats.size() - 1))
				atk_score -= _threat_penalty_at_pos(unit, pos, enemies, tgt)
				# 已在攻击距离内：保证力竭/低期望伤害时仍会出手（规则允许攻击）
				if path.is_empty():
					atk_score += SCORE_IN_RANGE_ATTACK_BONUS

				if atk_score > best["score"]:
					best = {
						"path": path,
						"target": tgt,
						"end_turn": true,
						"score": atk_score,
						"reason": "attack %s @ %s" % [tgt.get_unit_name(), pos],
					}

	# 射程外且本回合打不到：仅在威胁可接受时向最近敌人推进
	var atk_range: int = unit.weapon.attack_range if unit.weapon else 1
	var cur_dist: int = _nearest_enemy_distance(unit.axial_pos, enemies)
	var threat_here: float = aggregate_threat_at_position(unit, unit.axial_pos, enemies)
	if best.get("target", null) == null and cur_dist > atk_range:
		var forced: Dictionary = _plan_advance_toward(unit, enemies, hex_grid, threat_here)
		if not forced.is_empty():
			best = forced

	# 高威胁且本回合换血不划算 → 等待，让友军先消耗对方 AP
	if _should_wait(unit, enemies, hex_grid, best, can_wait, has_waited, threat_here):
		return {
			"path": [] as Array[Vector2i],
			"target": null,
			"end_turn": false,
			"wait": true,
			"score": best.get("score", 0.0) + 35.0,
			"reason": "wait high threat",
		}

	# 力竭且已在近战威胁距离内才吐纳；否则应先贴近（见上）
	if best.get("target", null) == null and unit.stats:
		var ratio: float = unit.get_fatigue_ratio()
		if ratio >= 0.85 and unit.can_use_breath_regulation() and cur_dist <= atk_range + 1:
			return {
				"path": [] as Array[Vector2i],
				"target": null,
				"end_turn": true,
				"score": best["score"] + 40.0,
				"reason": "breath_regulation",
				"breath_regulation": true,
			}

	return best


static func _nearest_enemy_distance(pos: Vector2i, enemies: Array) -> int:
	var min_d: int = 9999
	for e in enemies:
		if e != null and e.is_alive():
			min_d = mini(min_d, HexCoord.distance(pos, e.axial_pos))
	return min_d


## 评估敌方单位对观察者的威胁（数值越大越危险，可比较、可叠加）
## observer_pos：观察者（通常是 AI 自身）落点，用于距离衰减
static func estimate_unit_threat(hostile: Unit, observer_pos: Vector2i) -> float:
	if hostile == null or not hostile.is_alive() or hostile.weapon == null:
		return 0.0
	var w: WeaponData = hostile.weapon
	var dist: int = HexCoord.distance(observer_pos, hostile.axial_pos)
	var atk_range: int = w.attack_range
	var range_factor: float = 1.0
	if dist > atk_range:
		range_factor = maxf(0.12, 1.0 - float(dist - atk_range) * 0.28)
	elif dist == atk_range:
		range_factor = 1.0
	else:
		range_factor = 0.85 + float(atk_range - dist) * 0.08

	var threat: float = float(w.damage_base)
	if w.two_handed:
		threat *= THREAT_TWO_HANDED_MULT
	if atk_range >= 2:
		threat *= THREAT_RANGE2_MULT
	if hostile.stats:
		threat *= 1.0 + float(hostile.stats.melee_skill) * 0.008
		var ap_ratio: float = float(hostile.stats.ap) / float(max(1, hostile.stats.max_ap))
		threat *= clampf(ap_ratio, 0.35, 1.0)
	return threat * range_factor


## 某落点处所有敌方威胁之和
static func aggregate_threat_at_position(_unit: Unit, pos: Vector2i, hostiles: Array) -> float:
	var total: float = 0.0
	for h in hostiles:
		if h != null and h.is_alive():
			total += estimate_unit_threat(h, pos)
	return total


## 自身承伤/卡位能力（护甲池 + 防御 + 盾格挡 + HP），数值越大越敢顶前线
static func estimate_self_bulwark(unit: Unit) -> float:
	if unit == null or unit.stats == null:
		return 0.0
	var score: float = 0.0
	score += float(unit.stats.body_armor) * 0.09
	score += float(unit.stats.head_armor) * 0.035
	score += float(unit.stats.max_hp) * 0.11
	var block: int = unit.weapon.block_value if unit.weapon else 0
	score += unit.stats.effective_defense(block) * 0.32
	if block >= TANK_BLOCK_SHIELD:
		score += 20.0
	elif block >= 8:
		score += 9.0
	if unit.armor:
		match unit.armor.armor_class:
			"heavy":
				score += 30.0
			"medium":
				score += 14.0
			"light":
				score += 4.0
	return score


## 归一化坦度：约 0.15（脆皮）~ 1.5（重甲+盾）
static func self_bulwark_ratio(unit: Unit) -> float:
	return clampf(estimate_self_bulwark(unit) / 48.0, 0.15, 1.55)


## 对敌方威胁的敏感系数：坦度越高越小（更敢吃伤害换站位）
static func _threat_sensitivity(unit: Unit) -> float:
	var tank: float = self_bulwark_ratio(unit)
	return clampf(1.0 - (tank - 0.2) * 0.58, 0.22, 1.0)


static func _threat_penalty_at_pos(unit: Unit, pos: Vector2i, hostiles: Array, attack_target: Unit) -> float:
	var total: float = aggregate_threat_at_position(unit, pos, hostiles)
	if attack_target != null:
		total -= estimate_unit_threat(attack_target, pos) * 0.35
	return total * SCORE_THREAT_PER_POINT * _threat_sensitivity(unit)


static func _should_wait(
	unit: Unit,
	hostiles: Array,
	hex_grid: HexGrid,
	best: Dictionary,
	can_wait: bool,
	has_waited: bool,
	threat_here: float,
) -> bool:
	if not can_wait or has_waited:
		return false
	if hostiles.is_empty():
		return false
	if self_bulwark_ratio(unit) >= 0.82:
		return false

	var has_melee_threat: bool = false
	for h in hostiles:
		if h == null or not h.is_alive() or h.weapon == null:
			continue
		var d: int = HexCoord.distance(unit.axial_pos, h.axial_pos)
		if d <= h.weapon.attack_range + 1 and estimate_unit_threat(h, unit.axial_pos) >= THREAT_WAIT_MIN * 0.85:
			if h.weapon.two_handed or h.weapon.attack_range >= 2:
				has_melee_threat = true
				break
	if not has_melee_threat and threat_here < THREAT_WAIT_MIN:
		return false

	var target: Unit = best.get("target", null)
	if target != null:
		var trade: float = _expected_hp_damage(unit, target)
		var counter: float = estimate_unit_threat(target, unit.axial_pos)
		if trade >= counter * 0.75 or best.get("score", 0.0) >= 40.0:
			return false

	var reason: String = str(best.get("reason", ""))
	var path: Array = best.get("path", [])
	var end_pos: Vector2i = unit.axial_pos
	if not path.is_empty() and path[-1] is Vector2i:
		end_pos = path[-1]
	var threat_end: float = aggregate_threat_at_position(unit, end_pos, hostiles)
	var rushing: bool = reason.begins_with("forced advance") or (not path.is_empty() and threat_end > threat_here * 1.15)
	if rushing and threat_end >= THREAT_WAIT_MIN:
		return true
	if threat_here >= THREAT_WAIT_MIN * 1.25 and target == null and not path.is_empty():
		return true
	return false


## 无攻击计划时：选一步（或多步）最接近敌人的落点（威胁过高则放弃冲锋）
static func _plan_advance_toward(unit: Unit, enemies: Array, hex_grid: HexGrid, threat_here: float) -> Dictionary:
	@warning_ignore("integer_division")
	var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
	if max_steps <= 0:
		return {}
	var reachable: Array[Vector2i] = hex_grid.get_reachable(unit.axial_pos, max_steps, unit.get_faction())
	var candidates: Array[Vector2i] = [unit.axial_pos]
	candidates.append_array(reachable)

	var start_dist: int = _nearest_enemy_distance(unit.axial_pos, enemies)
	var best_pos: Vector2i = unit.axial_pos
	var best_dist: int = start_dist
	var best_path: Array[Vector2i] = []

	for pos in candidates:
		var d: int = _nearest_enemy_distance(pos, enemies)
		if d >= best_dist:
			continue
		var path: Array[Vector2i] = []
		if pos != unit.axial_pos:
			path = hex_grid.find_path(unit.axial_pos, pos, unit.axial_pos, unit.get_faction())
			if path.is_empty():
				continue
		best_dist = d
		best_pos = pos
		best_path = path

	if best_pos == unit.axial_pos or best_path.is_empty():
		return {}

	var tank: float = self_bulwark_ratio(unit)
	var threat_end: float = aggregate_threat_at_position(unit, best_pos, enemies)
	var rush_ratio: float = lerpf(1.35, 1.9, clampf((tank - 0.4) / 1.0, 0.0, 1.0))
	var threat_cap: float = THREAT_WAIT_MIN * (1.0 + tank * 0.85)
	if threat_end > threat_here * rush_ratio and threat_end >= threat_cap:
		return {}
	if threat_end >= threat_cap * 1.35 and start_dist > 2 and tank < 0.7:
		return {}

	return {
		"path": best_path,
		"target": null,
		"end_turn": true,
		"score": 0.0,
		"reason": "forced advance dist=%d->%d" % [start_dist, best_dist],
	}


## 不攻击只移动/站桩的位置评分：靠近最弱敌人
static func _score_position_only(unit: Unit, pos: Vector2i, enemies: Array, hex_grid: HexGrid, move_dist: int) -> float:
	var min_d: int = 9999
	var weakest_hp_ratio: float = 1.0
	for e in enemies:
		var d: int = HexCoord.distance(pos, e.axial_pos)
		if d < min_d:
			min_d = d
		var ratio: float = float(e.stats.hp) / float(max(1, e.stats.max_hp))
		if ratio < weakest_hp_ratio:
			weakest_hp_ratio = ratio
	var tank: float = self_bulwark_ratio(unit)
	# 越靠近最近敌人越好（距离 1 = +10，距离 2 = +5，距离 ≥7 = 0）
	var proximity_bonus: float = max(0.0, 12.0 - float(min_d) * 1.8)
	proximity_bonus *= lerpf(1.0, SCORE_TANK_CHARGE_MULT, clampf((tank - 0.35) / 0.95, 0.0, 1.0))
	# 弱敌存在时倾向推进
	proximity_bonus *= 1.0 + (1.0 - weakest_hp_ratio) * 0.4
	# 移动有小惩罚
	proximity_bonus += SCORE_PER_MOVE_HEX * float(move_dist)
	var threats: Array = hex_grid.get_zoc_controllers(pos, unit.get_faction())
	if tank >= 0.65:
		if min_d == 1:
			proximity_bonus += SCORE_TANK_CHOKE_BONUS * tank
		if threats.size() > 0:
			proximity_bonus += SCORE_TANK_CHOKE_BONUS * 0.5 * tank * float(threats.size())
			proximity_bonus -= SCORE_END_IN_ENEMY_ZOC * float(threats.size()) * (tank - 0.5)
	else:
		proximity_bonus += SCORE_END_IN_ENEMY_ZOC * float(threats.size())
	proximity_bonus -= _threat_penalty_at_pos(unit, pos, enemies, null)
	# 不攻击只推进 → 分数本身比较低，避免抢攻击候选的位置
	return proximity_bonus * 0.6


## 期望 HP 伤害（粗略）：基于武器均值伤害 + 命中率 + 头身差异
## 用于评分预估，不需要精确
static func _expected_hp_damage(attacker: Unit, target: Unit) -> float:
	if attacker.weapon == null or target == null or target.stats == null:
		return 0.0
	var base: float = float(attacker.weapon.damage_base)
	var armor_factor: float = 1.0
	if target.stats.body_armor > 80:
		armor_factor = 0.45
	elif target.stats.body_armor > 40:
		armor_factor = 0.65
	elif target.stats.body_armor > 0:
		armor_factor = 0.82
	return base * armor_factor


## 命中率粗算：直接复用 DamageSystem（包含气力/状态/手拙等修正）
static func _hit_chance_after_fatigue(attacker: Unit, target: Unit, _move_dist: int) -> float:
	return DamageSystem.calculate_hit_chance(attacker, target)
