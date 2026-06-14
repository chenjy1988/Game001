extends "res://scripts/core/effects/CombatEffect.gd"
##
## 模板驱动数值效果 — 由 data/effects.json + EffectDB 实例化

var hit_pct: float = 0.0
var defense_flat: float = 0.0
var damage_mult: float = 1.0
var stamina_cost_mult: float = 1.0
var block_weapon_attack: bool = false
var skip_turn_flag: bool = false


static func from_template(tmpl: Dictionary, turns: int = 1, p_source = null):
	var e = load("res://scripts/core/effects/StatCombatEffect.gd").new()
	e.id = String(tmpl.get("id", ""))
	e.display_name = String(tmpl.get("display_name", e.id))
	e.order = int(tmpl.get("order", 0))
	e.is_stacking = bool(tmpl.get("is_stacking", false))
	e.show_in_ui = bool(tmpl.get("show_in_ui", true))
	e.turns_remaining = turns
	e.source = p_source
	e.hit_pct = float(tmpl.get("hit_pct", 0.0))
	e.defense_flat = float(tmpl.get("defense_flat", 0.0))
	e.damage_mult = float(tmpl.get("damage_mult", 1.0))
	e.stamina_cost_mult = float(tmpl.get("stamina_cost_mult", 1.0))
	e.block_weapon_attack = bool(tmpl.get("block_weapon_attack", false))
	e.skip_turn_flag = bool(tmpl.get("skip_turn", false))
	return e


func on_update(stats) -> void:
	if hit_pct != 0.0:
		stats.apply_hit_pct(hit_pct)
	if defense_flat != 0.0:
		stats.apply_defense_flat(defense_flat)
	if damage_mult != 1.0:
		stats.apply_damage_mult(damage_mult)
	if stamina_cost_mult != 1.0:
		stats.apply_stamina_cost_mult(stamina_cost_mult)
	if block_weapon_attack:
		stats.can_weapon_attack = false
	if skip_turn_flag:
		stats.skip_turn = true
