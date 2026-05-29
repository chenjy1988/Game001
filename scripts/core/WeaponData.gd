extends Resource
class_name WeaponData
##
## WeaponData.gd — 武器数据类
##
## 战兄弟武器关键属性：基础伤害、对甲效率、穿甲率。
## 不同武器倾向不同战术：
##   - 锤/斧：高对甲效率（armor_effectiveness > 1.0），擅长破甲
##   - 矛/穿刺武器：高穿甲率（armor_penetration），无视部分护甲直击 HP
##   - 剑：平衡型
##   - 匕首 Puncture：极高穿甲，用于无视护甲直击肉体（剥甲战术保留盔甲）
##

@export var id: String = "sword"
@export var display_name: String = "短剑"

## 基础伤害（每次攻击 roll 之前的基准值）
@export var damage_min: int = 35
@export var damage_max: int = 50

## 对甲效率：基础伤害 × 此值 = 对护甲造成的伤害
## > 1.0 表示破甲特化（锤/斧），< 1.0 表示对甲拙劣（穿刺武器）
@export var armor_effectiveness: float = 1.0

## 穿甲率：基础伤害 × 此值 = 直接绕过护甲打到 HP 的伤害
## 0.0 表示完全无穿甲（普通钝器），1.0 表示完全无视护甲（极少见）
@export var armor_penetration: float = 0.0

## AP / Fatigue 消耗
@export var ap_cost: int = 4
@export var fatigue_cost: int = 6

## 攻击距离（hex 格数），近战为 1，长矛为 2，远程更远
@export var attack_range: int = 1

## 头部命中伤害倍率（战兄弟规则：头部伤害 +50%）
@export var head_damage_mult: float = 1.5

## 武器类型：melee / ranged
@export var weapon_type: String = "melee"


func roll_base_damage() -> int:
	return randi_range(damage_min, damage_max)


func to_string_brief() -> String:
	return "%s(伤%d-%d 对甲%.0f%% 穿甲%.0f%% AP%d)" % [
		display_name, damage_min, damage_max,
		armor_effectiveness * 100, armor_penetration * 100, ap_cost
	]
