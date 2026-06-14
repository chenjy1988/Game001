extends RefCounted
class_name PassiveEventBus
##
## PassiveEventBus — 被动事件总线（分散 + 集中分发）
##
## DamageSystem / Unit 在关键节点 emit("on_kill", ...)，
## 由 PassiveEventBus 检查触发型被动并调用 on_event。
##
## 支持的事件：
##   on_kill            — 击杀敌方单位时
##   on_dodge_success   — 闪避成功后
##   on_critical_hit    — 暴击结算后
##

const _PassiveLibrary = preload("res://scripts/core/passives/PassiveLibrary.gd")
const _DamageSystem   = preload("res://scripts/core/DamageSystem.gd")


static func emit(event_name: String, unit, context: Dictionary) -> void:
	if unit == null: return
	var passives = unit.passives if "passives" in unit else []
	for pid in passives:
		var p = _PassiveLibrary.get_by_id(pid)
		if p == null or p.kind != "triggered": continue
		if p.trigger_event != event_name: continue

		var result: Dictionary = {}
		if p.has_method("on_event"):
			result = p.on_event(event_name, unit, context)
		_handle_result(unit, result, context)


static func _handle_result(unit, result: Dictionary, context: Dictionary) -> void:
	if result.is_empty(): return
	match String(result.get("type", "")):
		"restore_ap":
			var amt: int = int(result.get("amount", 0))
			var limit: int = int(result.get("limit_per_turn", 1))
			# limit 记录在 unit 临时字段（简化实现）
			var used: int = _context_int(context, "_trig_kill_ap", 0)
			if used >= limit: return
			context["_trig_kill_ap"] = used + 1
			if unit.stats != null:
				unit.stats.ap = mini(unit.stats.ap + amt, unit.stats.base_ap)
				print("[PassiveEventBus] %s +%d AP (kill restore)" % [unit.get_unit_name(), amt])

		"counter_attack":
			var atk = context.get("attacker")
			if atk == null or not atk.is_alive(): return
			var mult: float = float(result.get("damage_mult", 0.5))
			_DamageSystem.execute_attack(unit, atk, { "damage_mult": mult })

		"buff_self":
			var eff_id: String = String(result.get("effect_id", ""))
			if not eff_id.is_empty() and unit.has_method("apply_effect_spec"):
				var spec = preload("res://scripts/core/abilities/AbilityEffectSpec.gd").buff(eff_id, unit, unit, int(result.get("duration", 1)))
				unit.apply_effect_spec(spec, unit)
			pass


static func _context_int(ctx: Dictionary, key: String, default_value: int) -> int:
	return int(ctx.get(key, default_value))
