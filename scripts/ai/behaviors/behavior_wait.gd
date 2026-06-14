extends "res://scripts/ai/behaviors/behavior_base.gd"
class_name AIBehavior_Wait

const _AT = preload("res://scripts/ai/_ai_action.gd")
const _AIWorldView = preload("res://scripts/ai/world_view.gd")
const _HC = preload("res://scripts/core/HexCoord.gd")
const _TurnManager = preload("res://scripts/core/TurnManager.gd")
const _U = preload("res://scripts/core/Unit.gd")

# ── Wait 门控阈值 ──
const THREAT_WAIT_MAX: int = 2   ## 周围 2 个以内敌人才考虑等

func _init() -> void: order = 40; behavior_id = "wait"; category = "defend"

func evaluate(view, profile = null) -> Dictionary:
	if not view.can_wait(): return { "score": 0.0, "action": null }
	if profile != null and profile.is_hanging_back(view):
		return { "score": 0.0, "action": null }

	# 接敌后能打 / 能走+打 / 有可执行技能 / 可抢先手 → 禁止 Q
	if (
		has_attack_option(view, profile)
		or has_move_attack_setup(view)
		or has_ability_spend_option(view, profile)
		or has_preempt_spend_option(view, profile)
	):
		return { "score": 0.0, "action": null }

	# 已在偏好射程、AP 不够攻 → 结束回合（AP 下回合补满；Wait 仅同回合重排，无收益）
	if should_hold_for_next_attack(view):
		return { "score": 0.0, "action": null }

	# 门控 1：力竭且满 AP → 不等待（改由 BehaviorBreath 吐纳）
	if (
		view.unit.stats.stamina_spent() >= view.unit.stats.max_stamina
		and can_spend_breath_now(view)
	):
		return { "score": 0.0, "action": null }

	# 门控 2：被围 → 等不了
	var threat: int = _nearby_enemy_count(view)
	if threat > THREAT_WAIT_MAX:
		return { "score": 0.0, "action": null }

	# 门控 3：无远程优势 + 远距 + 还能前压 → 应 Engage/Advance，不等
	# 例外：散兵/匕首等友军未接敌前，允许远距 Q 让前排先上
	var bal: int = view.ranged_balance()
	var delaying: bool = profile != null and profile.should_delay_for_allies(view)
	if not delaying and bal != _AIWorldView.RangedBalance.ALLY_ADVANTAGE and _should_block_far_wait(view):
		return { "score": 0.0, "action": null }

	var score: float = _cfg().behavior_baseline(behavior_id) if _cfg() else 35.0
	if score <= 0.0:
		score = 35.0

	# 威胁越大 → 越不该等
	if threat > 0:
		score *= max(0.2, 1.0 - 0.3 * threat)

	# 散兵/斥候：友军前排未贴脸前，优先 Q 让队友先上
	if profile != null and profile.should_delay_for_allies(view):
		score += 50.0

	score += faction_hold_bonus(view, profile)

	# ── 远程优劣势修正 ──
	if bal == _AIWorldView.RangedBalance.ENEMY_ADVANTAGE:
		score *= 0.3
	elif bal == _AIWorldView.RangedBalance.ALLY_ADVANTAGE:
		score *= 2.0

	score = subtract_attack_opportunity(score, view, profile)
	score = subtract_ap_hold_opportunity(score, view, profile)
	# Wait 固定消耗 WAIT_STAMINA_COST 气力，折入机会成本
	score -= float(_TurnManager.WAIT_STAMINA_COST) * 2.0
	if score <= 0.0:
		return { "score": 0.0, "action": null }
	return { "score": score, "action": _AT.wait("wait") }


## 无远程优势时：射程外且本回合还能走位 → 禁止远距站桩 Wait
static func _should_block_far_wait(view) -> bool:
	var u = view.unit
	if u == null or u.weapon == null or u.stats == null:
		return false
	if in_attack_range(view):
		return false
	var dist: int = view.nearest_enemy().get("distance", 999)
	if dist <= u.weapon.range_max:
		return false
	return u.stats.ap >= _U.AP_PER_HEX


## 周围 1 格内敌方数量
static func _nearby_enemy_count(view) -> int:
	var count: int = 0
	var pos = view.unit.axial_pos
	for d in range(6):
		var nb = _HC.neighbor(pos, d)
		var occ = view.get_occupant(nb)
		if occ != null and occ.is_alive() and occ.get_faction() != view.unit.get_faction():
			count += 1
	return count


static func _cfg(): return Engine.get_main_loop().root.get_node_or_null("AIConfigDB") if Engine.get_main_loop() else null
