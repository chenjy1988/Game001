extends Resource
class_name Stats

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")
##
## Stats.gd — 角色属性数据类
##
## HP、头/身护甲、AP、Stamina（气力）、Resolve、Initiative、近战技能与防御。
## 用 Resource 以便在 Godot 编辑器中直接配置初始值，并支持 .tres 序列化。
##

# ──────────── 生命与护甲 ────────────
@export var max_hp: int = 60
@export var max_head_armor: int = 0
@export var max_body_armor: int = 0

var hp: int = 60
var head_armor: int = 0
var body_armor: int = 0

# ──────────── 行动经济 ────────────
@export var max_ap: int = 9
@export var max_stamina: int = 100  ## 气力上限（design.md § 一：60-150，独立可升级属性）
@export var move_range: int = 4     ## 移动力（design.md § 一：3-6，职业基础值）

var ap: int = 9
var stamina: int = 100  ## 当前剩余气力（design.md § 三；战斗开始 = max_stamina）


## 剩余气力（与 stamina 同义，供 UI / AI 统一读取）
func remaining_stamina() -> int:
	return max(0, stamina)


## 已消耗气力（用于 Init 排序等）
func stamina_spent() -> int:
	return max(0, max_stamina - stamina)


## 剩余气力比例 [0, 1]
func stamina_ratio() -> float:
	if max_stamina <= 0:
		return 0.0
	return clampf(float(stamina) / float(max_stamina), 0.0, 1.0)

# ──────────── 心理与速度 ────────────
@export var resolve: int = 40       ## 决心（抗士气检定 + 抗 debuff + 辅助命中防御）
@export var base_initiative: int = 100

# ──────────── 战斗技能（攻击命中类） ────────────
@export var melee_skill: int = 55      ## 近战命中基础值
## 远程命中已移除（design.md § 一），由 melee_skill × 0.6 + bow_mastery 派生
## ranged_skill 保留为过渡兼容，Phase 2 末删除
@export var ranged_skill: int = 50     ## [DEPRECATED] 过渡期保留
@export var wisdom: int = 30           ## 智识（辅助/治疗命中 + 学识）—— Phase 3 起广泛使用

# ──────────── 防御综合 ────────────
@export var defense: int = 30          ## 基础防御（面板值；递减在 final_def 合成后，见 weapon-system §6.1.1）
## [DEPRECATED] 旧字段，兼容过渡期，Phase 2 末删除
@export var melee_defense: int = 5
@export var ranged_defense: int = 5    ## [DEPRECATED] 无远程防御概念，已废弃

# 运行时加值（无递减，来自技能/武器词条）
var dodge_bonus: int = 0               ## 闪避加值（技能/武器词条赋予，每回合/战斗开始清零）

# ──────────── 显示信息 ────────────
@export var unit_name: String = "Mercenary"
@export var faction: int = 0  ## 0=友方 1=敌方


## 初始化运行时值（首次进入战斗时调用）
func init_runtime() -> void:
	hp = max_hp
	head_armor = max_head_armor
	body_armor = max_body_armor
	ap = max_ap
	stamina = max_stamina


## 当前 Initiative = 基础值 − 已消耗气力
func current_initiative() -> int:
	return base_initiative - stamina_spent()


## 【旧版】有效 Initiative：base − 已消耗气力 − 武器/护甲重量（TO 风格）
## 已弃用，仅保留兼容性。Phase 2 后期改用 effective_initiative_v2
func effective_initiative(armor_weight: int = 0, weapon_weight: int = 0) -> int:
	var v: int = base_initiative - stamina_spent()
	v -= int(floor(float(armor_weight) / 4.0))
	v -= int(floor(float(weapon_weight) / 4.0))
	return max(1, v)


## 【新版】有效 Initiative（性能优化版）
## 公式：(base_initiative - all_weight) × stamina_ratio × rand(0.9, 1.0)
func effective_initiative_v2(all_weight: int = 0) -> float:
	if max_stamina <= 0:
		max_stamina = 1  # 防守，避免除以零

	var jitter: float = randf_range(0.9, 1.0)
	var result: float = float(base_initiative - all_weight) * stamina_ratio() * jitter
	return max(1.0, result)


## 是否存活
func is_alive() -> bool:
	return hp > 0


## @deprecated 旧 AI 承伤评分用；命中请用 DamageSystem.compute_defense_breakdown
func effective_defense(block_bonus: int = 0) -> float:
	return max(0.0, float(defense) + float(block_bonus) + float(dodge_bonus))


## [DEPRECATED] 兼容旧调用，Phase 2 末删除
func effective_melee_defense() -> float:
	return effective_defense(0)


## [DEPRECATED] 已废弃，远程无单独防御
func effective_ranged_defense() -> float:
	return effective_defense(0)


# ────────────────────────────────────────────────────────────
# 战斗模型 v3 派生数值（design.md 顶部"战斗模型 v3"章节）
# ────────────────────────────────────────────────────────────

const ARMOR_CLASS_DEF_MULT: Dictionary = {
	"light": 1.0,
	"medium": 0.7,
	"heavy": 0.4,
	"none": 1.0,
}


func eff_init(armor_weight: int = 0) -> int:
	var v: int = base_initiative
	v -= int(floor(float(armor_weight) / 4.0))
	return max(1, v)


func eff_defense_for_derivation(armor_class: String = "light") -> float:
	var mult: float = ARMOR_CLASS_DEF_MULT.get(armor_class, 1.0)
	return max(0.0, float(defense) * mult)


func eff_defense(armor_class: String = "light") -> float:
	return eff_defense_for_derivation(armor_class)


func dodge_chance(_armor_weight: int = 0, _armor_class: String = "light") -> float:
	return 0.0


const NIMBLE_INIT_DODGE_RATE: float = 0.2


static func nimble_dodge_pts(base_init: int, total_weight: int) -> float:
	var margin: float = float(base_init) - float(total_weight)
	return clampf(max(0.0, margin) * NIMBLE_INIT_DODGE_RATE, 0.0, 50.0)


func block_chance(weapon_base_block: int, _armor_class: String = "light") -> float:
	if weapon_base_block <= 0:
		return 0.0
	return clamp(float(weapon_base_block), 0.0, 60.0)


func reset_ap() -> void:
	ap = max_ap


func get_combat_modifiers(extra: Array = []) -> Array:
	var mods: Array = [_CombatModifier.stamina_tier_for(self)]
	mods.append_array(extra)
	return mods


func get_hit_modifier(extra: Array = []) -> float:
	return _CombatModifier.sum_hit_pct(get_combat_modifiers(extra))


func get_defense_modifier(extra: Array = []) -> float:
	return _CombatModifier.sum_defense_flat(get_combat_modifiers(extra))


func get_defense_pct_multiplier(extra: Array = []) -> float:
	if extra.is_empty():
		return _CombatModifier.product_defense_pct(get_combat_modifiers())
	return _CombatModifier.product_defense_pct(extra)


func restore_stamina(amount: int = 15) -> void:
	if amount <= 0:
		return
	stamina = min(max_stamina, stamina + amount)


func spend_stamina(amount: int) -> void:
	if amount <= 0:
		return
	stamina = max(0, stamina - amount)


func spend_ap(amount: int) -> bool:
	if ap < amount:
		return false
	ap -= amount
	return true


func take_hp_damage(amount: int) -> void:
	hp = max(0, hp - amount)


func take_head_armor_damage(amount: int) -> int:
	var actual: int = min(head_armor, amount)
	head_armor -= actual
	return actual


func take_body_armor_damage(amount: int) -> int:
	var actual: int = min(body_armor, amount)
	body_armor -= actual
	return actual


func clone():
	var s = preload("res://scripts/core/Stats.gd").new()
	s.max_hp = max_hp
	s.max_head_armor = max_head_armor
	s.max_body_armor = max_body_armor
	s.max_ap = max_ap
	s.max_stamina = max_stamina
	s.move_range = move_range
	s.resolve = resolve
	s.base_initiative = base_initiative
	s.melee_skill = melee_skill
	s.ranged_skill = ranged_skill
	s.wisdom = wisdom
	s.defense = defense
	s.melee_defense = melee_defense
	s.ranged_defense = ranged_defense
	s.unit_name = unit_name
	s.faction = faction
	s.hp = hp
	s.head_armor = head_armor
	s.body_armor = body_armor
	s.ap = ap
	s.stamina = stamina
	return s
