extends RefCounted
class_name AIAgent

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _AIProfile = preload("res://scripts/ai/ai_profile.gd")
const _IntentWeights = preload("res://scripts/ai/intent_weights.gd")
const _BRetreat = preload("res://scripts/ai/behaviors/behavior_retreat.gd")
const _BEngage = preload("res://scripts/ai/behaviors/behavior_engage.gd")
const _BAdvance = preload("res://scripts/ai/behaviors/behavior_advance.gd")
const _BDisengage = preload("res://scripts/ai/behaviors/behavior_disengage.gd")
const _BAttack = preload("res://scripts/ai/behaviors/behavior_attack.gd")
const _BDefend = preload("res://scripts/ai/behaviors/behavior_defend.gd")
const _BAbility = preload("res://scripts/ai/behaviors/behavior_ability.gd")
const _BWait = preload("res://scripts/ai/behaviors/behavior_wait.gd")
const _BBreath = preload("res://scripts/ai/behaviors/behavior_breath.gd")
const _BPreempt = preload("res://scripts/ai/behaviors/behavior_preempt.gd")
const _AIBehavior = preload("res://scripts/ai/behaviors/behavior_base.gd")

var unit = null
var _rng: RandomNumberGenerator
var _behaviors: Array = []
var _max_actions: int = 6


func _init(p_unit, p_rng: RandomNumberGenerator) -> void:
	unit = p_unit
	_rng = p_rng
	_register_behaviors()
	var db = _cfg()
	if db:
		_max_actions = db.max_actions_per_turn()
		_deterministic = db.is_deterministic() if db.has_method("is_deterministic") else db._get_nested("weighted_pick/deterministic", false)
		_consider_cutoff = db.consider_cutoff()
		_min_pool_score = db.min_pool_score()
		_debug_decisions = bool(db._get_nested("debug/log_decisions", false))
	else:
		_max_actions = 6
		_deterministic = false
		_consider_cutoff = 0.25
		_min_pool_score = 10.0
		_debug_decisions = false


var _deterministic: bool = false
var _consider_cutoff: float = 0.25
var _min_pool_score: float = 10.0
var _debug_decisions: bool = false


static func _cfg(): return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null


func _register_behaviors() -> void:
	_behaviors = [
		_BRetreat.new(),
		_BEngage.new(),
		_BAdvance.new(),
		_BDisengage.new(),
		_BAttack.new(),
		_BPreempt.new(),
		_BAbility.new(),
		_BBreath.new(),
		_BDefend.new(),
		_BWait.new(),
	]
	_behaviors.sort_custom(func(a, b): return a.order < b.order)


func decide_next_action(view):
	if unit == null or not unit.is_alive():
		return _AT.end_turn("dead")
	if unit.stats != null and unit.stats.ap <= 0:
		return _AT.end_turn("no_ap")
	var profile = _AIProfile.build(unit)
	# 风格权重表：把 5 类候选缩放到合理量级（详见 design/ai-decision-logic.md §二）
	var weights: Dictionary = _IntentWeights.compute(unit, view, profile)
	var scored: Array = []
	for b in _behaviors:
		var r: Dictionary = b.evaluate(view, profile)
		if r.score > 0.0 and r.action != null:
			r.score *= profile.behavior_mult(b.behavior_id, unit)
			# IntentWeights 缩放
			var cat: String = b.category if b.category != "" else "attack"
			r.score *= float(weights.get(cat, 1.0))
			r["category"] = cat
			scored.append(r)
	if scored.is_empty():
		var delay_action = _prefer_delay_action(view, profile)
		if delay_action != null:
			return delay_action
		var forced = _fallback_spend_ap(view, profile)
		if forced != null:
			return forced
		var breath_r: Dictionary = _BBreath.new().evaluate(view, profile)
		if breath_r.score > 0.0 and breath_r.action != null:
			return breath_r.action
		if _debug_decisions and view.unit.stats.ap > 0:
			_log_empty_scored(view, profile)
		return _AT.end_turn("no action available")
	scored.sort_custom(func(a, b): return a.score > b.score)
	if _debug_decisions:
		_log_pick(scored, profile)
	var action = _pick_weighted(scored)
	return _enforce_ap_spend(view, profile, action, scored)


func _log_pick(scored: Array, profile) -> void:
	var parts: PackedStringArray = []
	for i in range(mini(scored.size(), 5)):
		var r: Dictionary = scored[i]
		parts.append("%s %.0f" % [_behavior_label(r.action), r.score])
	print("[AI] %s [%s×%s] → %s" % [
		unit.get_unit_name(),
		profile.archetype_id,
		profile.disposition_id,
		", ".join(parts),
	])


func _behavior_label(action) -> String:
	match action.type:
		_AT.MOVE: return "Move"
		_AT.ATTACK: return "Attack"
		_AT.WAIT: return "Wait"
		_AT.ABILITY:
			var ab_id: String = action.payload.get("ability_id", "")
			if ab_id == "breath_regulation":
				return "Breath"
			if ab_id == "preempt":
				return "Preempt"
			return "Ability" if ab_id.is_empty() else "Abil:%s" % ab_id
		_AT.DEFEND: return "Defend"
		_: return "End"


## 不能再 Q 时：仅当存在正收益花 AP 选项才替换 end_turn；无收益允许结束
func _enforce_ap_spend(view, profile, action, scored: Array):
	if view.unit == null or view.unit.stats == null or view.unit.stats.ap <= 0:
		return action
	if action.type == _AT.ATTACK or action.type == _AT.MOVE or action.type == _AT.ABILITY:
		if action.type == _AT.MOVE:
			var path: Array = action.payload.get("path", [])
			if _AIBehavior.should_prefer_end_over_move(view, profile, path):
				return _AT.end_turn("thin_setup")
		return action
	if action.type == _AT.WAIT and action.reason == "defend":
		return action
	if action.type == _AT.END_TURN:
		var delay_action = _prefer_delay_action(view, profile)
		if delay_action != null:
			return delay_action
		var forced = _fallback_spend_ap(view, profile)
		if forced != null:
			return forced
	if view.can_wait():
		return action
	var spend_u: float = _AIBehavior.best_ap_spend_utility(view, profile)
	if spend_u <= 0.0:
		return action
	var breath_r: Dictionary = _BBreath.new().evaluate(view, profile)
	if breath_r.score > 0.0 and breath_r.action != null:
		return breath_r.action
	for r in scored:
		var a = r.action
		if r.score > 0.0 and (a.type == _AT.ATTACK or a.type == _AT.MOVE or a.type == _AT.ABILITY):
			return a
	return action


## 正收益兜底：攻 / 净正分 Engage·Advance / 吐纳（不走无视 OA 的贪心步）
func _fallback_spend_ap(view, profile):
	if view.unit == null or view.unit.stats == null or view.unit.stats.ap <= 0:
		return null
	if profile != null and profile.should_delay_for_allies(view):
		return null
	var atk: Dictionary = _BAttack.new().evaluate(view, profile)
	if atk.get("action") != null:
		return atk.action
	var abil: Dictionary = _BAbility.new().evaluate(view, profile)
	if float(abil.get("score", 0.0)) > 0.0 and abil.get("action") != null:
		return abil.action
	var pre: Dictionary = _BPreempt.new().evaluate(view, profile)
	if float(pre.get("score", 0.0)) > 0.0 and pre.get("action") != null:
		return pre.action
	var eng: Dictionary = _BEngage.new().evaluate(view, profile)
	if float(eng.get("score", 0.0)) > 0.0 and eng.get("action") != null:
		return eng.action
	var adv: Dictionary = _BAdvance.new().evaluate(view, profile)
	if float(adv.get("score", 0.0)) > 0.0 and adv.get("action") != null:
		return adv.action
	var breath: Dictionary = _BBreath.new().evaluate(view, profile)
	if float(breath.get("score", 0.0)) > 0.0 and breath.get("action") != null:
		return breath.action
	return null


## 轻甲/散兵：友军未贴脸接敌 → 优先 Q，不抢冲
func _prefer_delay_action(view, profile):
	if profile == null or not profile.should_delay_for_allies(view):
		return null
	var wait_r: Dictionary = _BWait.new().evaluate(view, profile)
	if wait_r.get("action") != null:
		return wait_r.action
	return null


func _pick_weighted(scored: Array):
	if _deterministic:
		return scored[0].action
	var top: float = scored[0].score
	var cutoff: float = top * _consider_cutoff
	var pool: Array = []
	var total_weight: float = 0.0
	for r in scored:
		if r.score < cutoff:
			break
		var w: float = max(r.score, _min_pool_score)
		pool.append({ "action": r.action, "weight": w })
		total_weight += w
	if pool.is_empty():
		return scored[0].action
	var roll: float = _rng.randf() * total_weight
	var accum: float = 0.0
	for entry in pool:
		accum += entry.weight
		if roll < accum:
			return entry.action
	return pool[-1].action


func _log_empty_scored(view, profile) -> void:
	var u = view.unit
	var parts: PackedStringArray = []
	for b in _behaviors:
		var r: Dictionary = b.evaluate(view, profile)
		if r.get("action") != null or r.score != 0.0:
			parts.append("%s=%.0f" % [b.behavior_id, r.score])
	var nd: int = view.nearest_enemy().get("distance", -1) if view.has_method("nearest_enemy") else -1
	print("[AI] %s EMPTY→end_turn ap=%d dist=%d can_wait=%s in_rng=%s can_atk=%s hold=%s [%s]" % [
		u.get_unit_name(),
		u.stats.ap,
		nd,
		view.can_wait(),
		_AIBehavior.in_attack_range(view),
		_AIBehavior.can_attack_now(view),
		_AIBehavior.should_hold_for_next_attack(view),
		", ".join(parts) if not parts.is_empty() else "all_zero",
	])
