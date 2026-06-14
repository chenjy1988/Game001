extends RefCounted
class_name AITargetScorer

const _DamageSystem = preload("res://scripts/core/DamageSystem.gd")

# ── 默认值（配置未加载时的回退）──
const DEFAULT_W_HIT: float  = 0.45
const DEFAULT_W_DMG: float  = 0.25
const DEFAULT_W_LOWHP: float = 0.30
const DEFAULT_HIT_POWER: float = 1.1
const DEFAULT_MULT_KILL: float    = 3.0
const DEFAULT_MULT_COUNTER: float = 0.6
const DEFAULT_MULT_RANGED: float  = 1.25
const DEFAULT_MULT_FOCUS: float   = 1.3


static func _config():
	return Engine.get_main_loop().root.get_node_or_null("AIConfigDB")


static func _get_weight(key: String, fallback: float) -> float:
	var db = _config()
	if db: return db.target_weight(key) if db.target_weight(key) != 0.0 else fallback
	return fallback


static func _get_mult(key: String, fallback: float) -> float:
	var db = _config()
	if db: return db.target_mult(key) if db.target_mult(key) != 1.0 else fallback
	return fallback


static func build_damage_options(attacker, options: Dictionary = {}) -> Dictionary:
	var opts: Dictionary = _DamageSystem.normalize_attack_options(options)
	if not opts.has("mastery_dmg") and attacker != null and attacker.has_method("has_unfamiliar_weapon"):
		opts["mastery_dmg"] = 0.9 if attacker.has_unfamiliar_weapon() else 1.0
	return opts


## 对单个目标评分
static func score(attacker, target, options: Dictionary = {}, ally_focus: bool = false) -> float:
	if attacker == null or target == null or not target.is_alive():
		return 0.0

	var opts: Dictionary = build_damage_options(attacker, options)
	var hit_chance: float = _hit_chance(attacker, target, opts)
	if hit_chance <= 0.01:
		return 0.0

	var expected_dmg: float = _estimate_damage(attacker, target, opts) * hit_chance
	var target_max_hp: float = float(max(1, target.stats.max_hp))
	var target_hp_ratio: float = float(target.stats.hp) / target_max_hp

	var w_hit: float = _get_weight("hit", DEFAULT_W_HIT)
	var w_dmg: float = _get_weight("damage", DEFAULT_W_DMG)
	var w_lowhp: float = _get_weight("low_hp", DEFAULT_W_LOWHP)

	var s: float = pow(hit_chance, DEFAULT_HIT_POWER) * w_hit \
	             + (expected_dmg / target_max_hp) * w_dmg \
	             + (1.0 - target_hp_ratio) * w_lowhp

	if expected_dmg >= float(target.stats.hp) or target_hp_ratio < 0.5:
		s *= _get_mult("kill", DEFAULT_MULT_KILL)
	if _target_has_counter(target):
		s *= _get_mult("counter", DEFAULT_MULT_COUNTER)
	if _target_is_ranged(target):
		s *= _get_mult("ranged", DEFAULT_MULT_RANGED)
	if ally_focus:
		s *= _get_mult("ally_focus", DEFAULT_MULT_FOCUS)

	# 残局收刀（enemy_total≤2）：低血优先、可斩杀加权
	var et: int = int(options.get("enemy_total", 99))
	if et > 0 and et <= 2:
		s *= 1.45
		s += (1.0 - target_hp_ratio) * 0.40
		if expected_dmg >= float(target.stats.hp):
			s *= 1.65
		elif target_hp_ratio < 0.35:
			s *= 1.40
	if et == 1:
		s *= 1.25

	# 低甲优先：残血之外再偏软目标
	var armor_total: float = float(target.stats.body_armor + target.stats.head_armor)
	var soft_mult: float = 1.0 + 0.25 * (1.0 - clampf(armor_total / 80.0, 0.0, 1.0))
	s *= soft_mult

	return max(0.0, s)


static func _hit_chance(attacker, target, options: Dictionary) -> float:
	return _DamageSystem.calculate_hit_chance(attacker, target, options)


## 命中后期望 HP 伤害（不含命中率）
static func _estimate_damage(attacker, target, options: Dictionary) -> float:
	return _DamageSystem.estimate_hp_damage_on_hit(attacker, target, options)


static func _target_has_counter(target) -> bool:
	if target.weapon == null: return false
	return target.weapon.weapon_type == "melee"


static func _target_is_ranged(target) -> bool:
	if target.weapon == null: return false
	return target.weapon.weapon_type == "ranged"
