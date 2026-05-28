extends Resource
class_name Stats
##
## Stats.gd — 角色属性数据类
##
## 战兄弟核心属性面板：HP、头/身护甲、AP、Fatigue、Resolve、Initiative、近战/远程技能与防御。
## 用 Resource 而非 Dictionary，以便在 Godot 编辑器中直接配置初始值，并支持 .tres 序列化。
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
@export var max_fatigue: int = 100  ## 受护甲重量影响，会被运行时减去 armor.weight

var ap: int = 9
var fatigue: int = 0  ## 当前累积疲劳，越高 Initiative 越低

# ──────────── 心理与速度 ────────────
@export var resolve: int = 40
@export var base_initiative: int = 100

# ──────────── 战斗技能 ────────────
@export var melee_skill: int = 55      ## 近战命中基础值
@export var ranged_skill: int = 50     ## 远程命中基础值
@export var melee_defense: int = 5     ## 近战闪避，>45 后收益递减
@export var ranged_defense: int = 5    ## 远程闪避

# ──────────── 显示信息 ────────────
@export var unit_name: String = "Mercenary"
@export var faction: int = 0  ## 0=友方 1=敌方


## 初始化运行时值（首次进入战斗时调用）
func init_runtime(armor_weight: int = 0) -> void:
	hp = max_hp
	head_armor = max_head_armor
	body_armor = max_body_armor
	ap = max_ap
	fatigue = 0
	# 护甲重量降低最大可用疲劳值（战兄弟规则）
	max_fatigue = max(40, max_fatigue - armor_weight)


## 当前 Initiative = 基础值 - 当前疲劳 - 护甲重量惩罚（重量已影响 max_fatigue 间接体现）
## 简化版：直接 base - fatigue
func current_initiative() -> int:
	return base_initiative - fatigue


## 是否存活
func is_alive() -> bool:
	return hp > 0


## 近战防御收益递减：>45 部分效果减半
func effective_melee_defense() -> float:
	if melee_defense <= 45:
		return float(melee_defense)
	return 45.0 + (melee_defense - 45) * 0.5


func effective_ranged_defense() -> float:
	if ranged_defense <= 45:
		return float(ranged_defense)
	return 45.0 + (ranged_defense - 45) * 0.5


## 回合开始：AP 回满，Fatigue 自然恢复 15
func reset_ap() -> void:
	ap = max_ap


func recover_fatigue(amount: int = 15) -> void:
	fatigue = max(0, fatigue - amount)


## 累积疲劳（行动消耗）
func add_fatigue(amount: int) -> void:
	fatigue = min(max_fatigue, fatigue + amount)


## 消耗 AP；返回是否消耗成功
func spend_ap(amount: int) -> bool:
	if ap < amount:
		return false
	ap -= amount
	return true


## 受到伤害（HP 直接扣，护甲扣减由 DamageSystem 处理后回写）
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


## 复制一份（用于运行时与配置分离）
func clone() -> Stats:
	var s := Stats.new()
	s.max_hp = max_hp
	s.max_head_armor = max_head_armor
	s.max_body_armor = max_body_armor
	s.max_ap = max_ap
	s.max_fatigue = max_fatigue
	s.resolve = resolve
	s.base_initiative = base_initiative
	s.melee_skill = melee_skill
	s.ranged_skill = ranged_skill
	s.melee_defense = melee_defense
	s.ranged_defense = ranged_defense
	s.unit_name = unit_name
	s.faction = faction
	s.hp = hp
	s.head_armor = head_armor
	s.body_armor = body_armor
	s.ap = ap
	s.fatigue = fatigue
	return s
