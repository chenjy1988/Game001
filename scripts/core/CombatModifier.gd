extends RefCounted
class_name CombatModifier
##
## CombatModifier.gd — 战斗修正描述符（Buff / Debuff）
##
## 所有命中、防御、伤害修正统一经此结构汇总；`Unit.get_active_debuffs()` 供 UI 外显。
##

const _SELF := preload("res://scripts/core/CombatModifier.gd")

var id: String = ""
var display_name: String = ""
var show_in_ui: bool = true       ## 是否在单位状态栏外显（气力档 / 手拙等）
var duration_hint: String = ""    ## UI 用持续说明（如「剩余气力 >50%」）
var hit_pct: float = 0.0          ## 命中率修正（-0.10 = -10%）
var defense_flat: float = 0.0     ## 防御 flat 修正（点，进 final_def def_flat）
var defense_pct: float = 0.0      ## 防御百分比修正（-0.10 = -10%，进 def_mult 乘算）
var damage_mult_min: float = 1.0  ## 伤害系数下限（与 max 相等时为定值）
var damage_mult_max: float = 1.0
var stamina_cost_mult: float = 1.0  ## 气力消耗倍率（手拙 +10%）
var block_weapon_attack: bool = false  ## 缴械：禁止武器攻击（仍可移动/道具/等待）
var skip_turn: bool = false            ## 眩晕：跳过本回合行动
var turns_remaining: int = 0           ## 限时状态剩余回合（0 = 由来源决定或不限时）

# ── PassiveEffect fold 扩展字段（默认值不影响既有行为）──
var armor_damage_mult: float = 1.0     ## 受击时护甲伤害倍率（铁骨 0.85）
var damage_taken_mult: float = 1.0     ## 受击时 HP 伤害倍率（镇阵 0.5 / 气海回旋）
var hp_max_pct: float = 0.0            ## HP 上限 % 修正（健壮 0.25）
var wound_threshold_pct: float = 0.0   ## 伤势阈值修正（健壮 -0.33）


static func _remaining_ratio(stats) -> float:
	if stats == null or stats.max_stamina <= 0:
		return 0.0
	return stats.stamina_ratio()


## 气力档 debuff：随剩余气力比例切换，经 get_active_debuffs() 外显（design/weapon-system.md §6.2）
static func stamina_tier_for(stats):
	var m = _SELF.new()
	var ratio: float = _remaining_ratio(stats)
	if ratio > 0.5:
		m.id = "stamina_fresh"
		m.display_name = "精力充沛"
		m.duration_hint = "剩余气力 >50%"
		return m
	if ratio > 0.2:
		m.id = "stamina_tired"
		m.display_name = "疲劳"
		m.duration_hint = "剩余气力 20%-50%"
		m.hit_pct = -0.10
		m.defense_flat = -5.0
		m.damage_mult_min = 0.80
		m.damage_mult_max = 0.90
		return m
	m.id = "stamina_exhausted"
	m.display_name = "力竭"
	m.duration_hint = "剩余气力 ≤20%"
	m.hit_pct = -0.20
	m.defense_flat = -10.0
	m.damage_mult_min = 0.70
	m.damage_mult_max = 0.80
	return m


static func clumsy():
	var m = _SELF.new()
	m.id = "clumsy"
	m.display_name = "手拙"
	m.duration_hint = "装备非熟练武器期间"
	m.hit_pct = -0.10
	m.stamina_cost_mult = 1.10
	return m


## 缴械：不能武器攻击，持续 1 回合（design/status-effects.md）
static func disarmed(turns: int = 1):
	var m = _SELF.new()
	m.id = "disarmed"
	m.display_name = "缴械"
	m.duration_hint = "%d 回合" % turns
	m.block_weapon_attack = true
	m.turns_remaining = turns
	return m


static func has_block_weapon_attack(mods: Array) -> bool:
	for raw in mods:
		if raw is CombatModifier and raw.block_weapon_attack:
			return true
	return false


static func sum_hit_pct(mods: Array) -> float:
	var total: float = 0.0
	for raw in mods:
		if raw is CombatModifier:
			total += raw.hit_pct
	return total


static func sum_defense_flat(mods: Array) -> float:
	var total: float = 0.0
	for raw in mods:
		if raw is CombatModifier:
			total += raw.defense_flat
	return total


## 防御百分比乘算因子 Π(1 + defense_pct)；无 modifier 时 1.0
static func product_defense_pct(mods: Array) -> float:
	var mult: float = 1.0
	for raw in mods:
		if raw is CombatModifier and raw.defense_pct != 0.0:
			mult *= 1.0 + raw.defense_pct
	return mult


## 多来源伤害倍率连乘；带区间的 modifier 在调用时 roll 一次
static func roll_damage_mult(mods: Array) -> float:
	var mult: float = 1.0
	for raw in mods:
		if raw is CombatModifier:
			if raw.damage_mult_min == raw.damage_mult_max:
				mult *= raw.damage_mult_min
			else:
				mult *= randf_range(raw.damage_mult_min, raw.damage_mult_max)
	return mult


static func roll_stamina_damage_mult(stats) -> float:
	return roll_damage_mult([stamina_tier_for(stats)])
