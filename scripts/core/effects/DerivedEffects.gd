extends RefCounted
class_name DerivedEffects
##
## 无实例派生效果 — 气力档、手拙等（fold 时注入，不占 effects[]）

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")


static func apply_to_stats(unit, stats) -> void:
	if unit == null or stats == null:
		return
	var mods: Array = []
	if unit.stats != null:
		mods.append(_CombatModifier.stamina_tier_for(unit.stats))
	if unit.has_method("has_unfamiliar_weapon") and unit.has_unfamiliar_weapon():
		mods.append(_CombatModifier.clumsy())
	for raw in mods:
		if raw is CombatModifier:
			_apply_modifier(stats, raw)


static func _apply_modifier(stats, m: CombatModifier) -> void:
	if m.hit_pct != 0.0:
		stats.apply_hit_pct(m.hit_pct)
	if m.defense_flat != 0.0:
		stats.apply_defense_flat(m.defense_flat)
	if m.damage_mult_min != 1.0 or m.damage_mult_max != 1.0:
		var dm: float = m.damage_mult_min
		if m.damage_mult_min != m.damage_mult_max:
			dm = (m.damage_mult_min + m.damage_mult_max) * 0.5
		stats.apply_damage_mult(dm)
	if m.stamina_cost_mult != 1.0:
		stats.apply_stamina_cost_mult(m.stamina_cost_mult)
	if m.block_weapon_attack:
		stats.can_weapon_attack = false
	if m.skip_turn:
		stats.skip_turn = true
