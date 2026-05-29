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
##

const SCORE_KILL_BONUS: float = 50.0
const SCORE_OA_PER_HIT: float = -18.0          ## 每个借机攻击 -18 分
const SCORE_PER_MOVE_HEX: float = -0.4         ## 移动一格小惩罚
const SCORE_END_IN_ENEMY_ZOC: float = -6.0     ## 落点处在另一个 ZoC 中 -6
const SCORE_LOW_HP_FOCUS_WEIGHT: float = 0.5   ## 目标HP越低，伤害权重提升


## 决策入口；返回 plan 字典：
##   { "path": Array[Vector2i], "target": Unit | null, "end_turn": bool, "score": float, "reason": String }
## 若返回 end_turn=true，BattleScene 直接结束当前回合
static func decide(unit: Unit, all_units: Array, hex_grid: HexGrid) -> Dictionary:
	if not unit.is_alive():
		return {"path": [], "target": null, "end_turn": true, "score": 0.0, "reason": "dead"}

	var enemies: Array = []
	for u in all_units:
		if u.is_alive() and u.get_faction() != unit.get_faction():
			enemies.append(u)
	if enemies.is_empty():
		return {"path": [], "target": null, "end_turn": true, "score": 0.0, "reason": "no enemies"}

	@warning_ignore("integer_division")
	var max_steps: int = unit.stats.ap / Unit.AP_PER_HEX
	var reachable: Array[Vector2i] = hex_grid.get_reachable(unit.axial_pos, max_steps)
	# 把"原地"也作为候选（不动）
	var candidates_pos: Array[Vector2i] = [unit.axial_pos]
	candidates_pos.append_array(reachable)

	var best: Dictionary = {"path": [] as Array[Vector2i], "target": null, "end_turn": true, "score": -INF, "reason": "idle"}

	for pos in candidates_pos:
		# 通往 pos 的路径（pos == 自己 axial 时为空数组，相当于不动）
		var path: Array[Vector2i] = []
		if pos != unit.axial_pos:
			path = hex_grid.find_path(unit.axial_pos, pos, unit.axial_pos)
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
			var oa_steps: Array = hex_grid.analyze_path_oa(unit.axial_pos, path, unit.get_faction())
			for s in oa_steps:
				for ctrl in s["oa_attackers"]:
					oa_count += 1
					oa_expected_dmg += _expected_hp_damage(ctrl, unit)

		# 候选 1：到达 pos 后不攻击（站桩/推进）
		var idle_score: float = _score_position_only(unit, pos, enemies, hex_grid, path.size())
		idle_score += SCORE_OA_PER_HIT * float(oa_count) - oa_expected_dmg * 0.4
		if idle_score > best["score"]:
			best = {
				"path": path,
				"target": null,
				"end_turn": true,
				"score": idle_score,
				"reason": "advance/idle",
			}

		# 候选 2：到达 pos 后攻击射程内的某个敌人
		if ap_after_move >= unit.weapon.ap_cost:
			for tgt in enemies:
				var d: int = HexCoord.distance(pos, tgt.axial_pos)
				if d > unit.weapon.attack_range:
					continue
				# 估算 AP 范围内能打几下
				var attacks_possible: int = ap_after_move / unit.weapon.ap_cost
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
				atk_score += SCORE_OA_PER_HIT * float(oa_count) - oa_expected_dmg * 0.5
				# 落点处在另一个敌人 ZoC（除目标外）
				var threats: Array = hex_grid.get_zoc_controllers(pos, unit.get_faction())
				atk_score += SCORE_END_IN_ENEMY_ZOC * float(max(0, threats.size() - 1))

				if atk_score > best["score"]:
					best = {
						"path": path,
						"target": tgt,
						"end_turn": true,
						"score": atk_score,
						"reason": "attack %s @ %s" % [tgt.get_unit_name(), pos],
					}

	return best


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
	# 越靠近最近敌人越好（距离 1 = +10，距离 2 = +5，距离 ≥7 = 0）
	var proximity_bonus: float = max(0.0, 12.0 - float(min_d) * 1.8)
	# 弱敌存在时倾向推进
	proximity_bonus *= 1.0 + (1.0 - weakest_hp_ratio) * 0.4
	# 移动有小惩罚
	proximity_bonus += SCORE_PER_MOVE_HEX * float(move_dist)
	# 落点处在敌方 ZoC 给小惩罚（推进式 AI 还是会进 ZoC，但优先不要）
	var threats: Array = hex_grid.get_zoc_controllers(pos, unit.get_faction())
	proximity_bonus += SCORE_END_IN_ENEMY_ZOC * float(threats.size())
	# 不攻击只推进 → 分数本身比较低，避免抢攻击候选的位置
	return proximity_bonus * 0.6


## 期望 HP 伤害（粗略）：基于武器均值伤害 + 命中率 + 头身差异
## 用于评分预估，不需要精确
static func _expected_hp_damage(attacker: Unit, target: Unit) -> float:
	if attacker.weapon == null:
		return 0.0
	var avg_base: float = float(attacker.weapon.damage_min + attacker.weapon.damage_max) * 0.5
	# 穿甲部分直接进 HP
	var pen: float = avg_base * attacker.weapon.armor_penetration
	# 非穿甲部分：考虑身体甲（头部命中率太低不计）
	var non_pen: float = avg_base * (1.0 - attacker.weapon.armor_penetration)
	var armor_factor: float = 0.9 if target.stats.body_armor > 0 else 1.0
	var expected: float = pen + non_pen * armor_factor
	return expected


## 命中率粗算（疲劳影响近战命中：每点疲劳 -1% 简化版）
## 这里不实现疲劳惩罚，直接复用 DamageSystem 的逻辑（保持一致）
static func _hit_chance_after_fatigue(attacker: Unit, target: Unit, _move_dist: int) -> float:
	return DamageSystem.calculate_hit_chance(attacker, target)
