extends RefCounted
class_name PassiveEffect

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")
const _PassiveCondition = preload("res://scripts/core/passives/PassiveCondition.gd")
##
## PassiveEffect — 被动技能描述符（扩展 CombatModifier）
##
## 战斗中学了就一直生效的被动技，通过 Unit.add_passive() 注册。
## fold 出口对接 CombatModifier，让 DamageSystem 零改动消费。
##

# ── fold 字段（与 CombatModifier 1:1 对齐）──
var id: String = ""
var display_name: String = ""
var hit_pct: float = 0.0
var defense_flat: float = 0.0
var defense_pct: float = 0.0
var damage_mult_min: float = 1.0
var damage_mult_max: float = 1.0
var stamina_cost_mult: float = 1.0
var armor_damage_mult: float = 1.0
var damage_taken_mult: float = 1.0
var hp_max_pct: float = 0.0
var wound_threshold_pct: float = 0.0

# ── 触发条件 ──
var kind: String = "permanent"       ## permanent / conditional / triggered
var condition_expr: String = ""      ## conditional 用（PassiveCondition eval）
var trigger_event: String = ""       ## triggered 用（on_kill / on_dodge_success …）
var trigger_phase: String = ""       ## 限定阶段（on_take_hit / on_attack …）
var stamina_cost_per_trigger: int = 0
var mutex_with: Array = []

# ── 钩子 ──
var hooks: Array = []

# ── 元信息 ──
var source: String = ""              ## job / weapon_jp / trait
var ai_hint: Dictionary = {}


## 当前是否激活（给定 unit + 可选 context）
func is_active(unit, context: Dictionary = {}) -> bool:
	if kind == "permanent":
		return true
	if kind == "conditional":
		return _PassiveCondition.eval(condition_expr, unit, context)
	if kind == "triggered":
		return false
	return false


## 转为 CombatModifier 供 DamageSystem fold
func to_combat_modifier() -> CombatModifier:
	var m = _CombatModifier.new()
	m.id = id
	m.display_name = display_name
	m.hit_pct = hit_pct
	m.defense_flat = defense_flat
	m.defense_pct = defense_pct
	m.damage_mult_min = damage_mult_min
	m.damage_mult_max = damage_mult_max
	m.stamina_cost_mult = stamina_cost_mult
	m.armor_damage_mult = armor_damage_mult
	m.damage_taken_mult = damage_taken_mult
	m.hp_max_pct = hp_max_pct
	m.wound_threshold_pct = wound_threshold_pct
	return m
