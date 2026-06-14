extends RefCounted
##
## 战斗折叠快照 — DamageSystem / AI 只读此结构（CombatEffectContainer 产出）

var melee_skill: int = 0
var defense: float = 0.0
var hit_pct: float = 0.0
var damage_mult: float = 1.0
var stamina_cost_mult: float = 1.0
var can_weapon_attack: bool = true
var skip_turn: bool = false


static func from_stats(stats):
	var s = load("res://scripts/core/EffectiveCombatStats.gd").new()
	if stats == null:
		return s
	s.melee_skill = int(stats.melee_skill)
	s.defense = float(stats.defense)
	return s


func clone():
	var c = load("res://scripts/core/EffectiveCombatStats.gd").new()
	c.melee_skill = melee_skill
	c.defense = defense
	c.hit_pct = hit_pct
	c.damage_mult = damage_mult
	c.stamina_cost_mult = stamina_cost_mult
	c.can_weapon_attack = can_weapon_attack
	c.skip_turn = skip_turn
	return c


func apply_hit_pct(delta: float) -> void:
	hit_pct += delta


func apply_defense_flat(delta: float) -> void:
	defense += delta


func apply_damage_mult(mult: float) -> void:
	damage_mult *= mult


func apply_stamina_cost_mult(mult: float) -> void:
	stamina_cost_mult *= mult
