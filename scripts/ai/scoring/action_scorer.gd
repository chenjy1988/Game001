extends RefCounted
class_name AIActionScorer

## 统一 Move/setup 净分合成（方案 B / I4 前置）。
## 扩展点（后续 PlanGenerator / Ability 投影）：
##   1. 各 Plan 只算 gross_utility，最终一律走 finalize_move_net()
##   2. breakdown 字典供 [AI] 日志与单测断言分量
##   3. finalize_attack_net() 预留原地攻（当前仅 self_state）

const _EngageScorer = preload("res://scripts/ai/scoring/engage_scorer.gd")
const _SelfState = preload("res://scripts/ai/scoring/self_state_score.gd")
const _SurroundCost = preload("res://scripts/ai/scoring/surround_cost.gd")


static func _utility_scale() -> float:
	var db = Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
	return db.attack_utility_scale() if db else 100.0


## 路径类行动的进入成本（utility 尺度，均为减分项）
static func compute_entry_costs(view, path: Array, profile = null) -> Dictionary:
	if view == null or view.unit == null or path.is_empty():
		return _zero_costs()
	var origin: Vector2i = view.unit.axial_pos
	var dest: Vector2i = path[-1]
	var adj_now: int = _SurroundCost.adjacent_enemy_count(view, origin)
	var self_raw: float = _SelfState.delta(view.unit, profile, adj_now)
	# 进场成本：仅不良状态扣分；良好状态加成留给 gross/Attack（避免 thin move 被整体抬高）
	var self_entry: float = minf(0.0, self_raw)
	var surround: float = _SurroundCost.compute(view, origin, dest, profile)
	var oa: float = _EngageScorer.oa_utility_penalty(view, view.unit, path, profile)
	return {
		"self_state": self_entry,
		"self_state_raw": self_raw,
		"surround_cost": surround,
		"oa_cost": oa,
		"total_cost": surround + oa - self_entry,
	}


## gross_utility 已在 utility 尺度（如 TargetScore × scale）
static func finalize_move_net(
	view,
	path: Array,
	gross_utility: float,
	profile = null,
) -> Dictionary:
	var costs: Dictionary = compute_entry_costs(view, path, profile)
	var net: float = gross_utility - float(costs.get("surround_cost", 0.0)) \
		- float(costs.get("oa_cost", 0.0)) + float(costs.get("self_state", 0.0))
	return {
		"net": net,
		"gross": gross_utility,
		"breakdown": {
			"gross": gross_utility,
			"self_state": costs.get("self_state", 0.0),
			"surround_cost": costs.get("surround_cost", 0.0),
			"oa_cost": costs.get("oa_cost", 0.0),
			"net_before_defer": net,
		},
	}


## 原地攻击：当前仅叠加 self_state（I4 再扩 opportunity cost）
static func finalize_attack_net(gross_utility: float, unit, profile = null) -> Dictionary:
	var self_net: float = _SelfState.delta(unit, profile)
	var net: float = gross_utility + self_net
	return {
		"net": net,
		"gross": gross_utility,
		"breakdown": {
			"gross": gross_utility,
			"self_state": self_net,
			"surround_cost": 0.0,
			"oa_cost": 0.0,
			"net_before_defer": net,
		},
	}


static func entry_costs_to_path_score(costs: Dictionary, profile, unit) -> Dictionary:
	var scale: float = _utility_scale()
	var oa_sens: float = profile.oa_sensitivity(unit) if profile != null else 1.0
	var surround_norm: float = -float(costs.get("surround_cost", 0.0)) / maxf(1.0, scale)
	var oa_norm: float = -float(costs.get("oa_cost", 0.0)) / maxf(1.0, scale) * 0.5 * oa_sens
	var self_norm: float = float(costs.get("self_state", 0.0)) / maxf(1.0, scale)
	return {"surround": surround_norm, "oa_extra": oa_norm, "self_state": self_norm}


static func _zero_costs() -> Dictionary:
	return {
		"self_state": 0.0,
		"surround_cost": 0.0,
		"oa_cost": 0.0,
		"total_cost": 0.0,
	}
