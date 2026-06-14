extends RefCounted
class_name PassiveHookRegistry
##
## PassiveHookRegistry — 被动钩子收集器
##
## 外部（DamageSystem / Ability）只在需要时调 collect()，
## 返回匹配 hook_type 的全部 modifier 字典列表。
##
## 白名单：
##   self_overwhelm_bonus     — 修改自己作为攻击者时的围攻系数
##   incoming_overwhelm_bonus — 修改自己作为受击者时对方围攻系数
##   ability_ap_cost          — 修改 Ability.get_ap_cost
##   ability_stamina_cost     — 修改 Ability.get_fatigue_cost
##   crit_damage_mult         — 暴击伤害倍率
##   armor_break_chance       — 卸甲触发率
##   kill_restore_ap          — 击杀回 AP
##

const _PassiveCondition = preload("res://scripts/core/passives/PassiveCondition.gd")


static func collect(unit, hook_type: String, context: Dictionary) -> Array:
	var result: Array = []
	if unit == null: return result
	var passives = unit.get_active_passives(context) if unit.has_method("get_active_passives") else []
	for p in passives:
		if p == null: continue
		for hook in p.hooks:
			if not (hook is Dictionary): continue
			if String(hook.get("hook", "")) != hook_type: continue
			var cond: String = String(hook.get("condition", ""))
			if not cond.is_empty():
				if not _PassiveCondition.eval(cond, unit, context):
					continue
			result.append(hook.get("modifier", {}))
	return result
