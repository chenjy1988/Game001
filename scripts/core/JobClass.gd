extends Resource
class_name JobClass
##
## JobClass.gd — 职业数据资源
##
## 从 data/jobs.json 反序列化，由 JobDB autoload 统一管理。
## Unit.job 字段持有当前职业引用。
##

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var tier: int = 1                    ## 1=基础职业，2=上级职业

# ──── 属性范围（生成单位时 randomize 用）────
@export var hp_min: int = 70
@export var hp_max: int = 90
@export var init_min: int = 60
@export var init_max: int = 80
@export var melee_min: int = 60
@export var melee_max: int = 80
@export var defense_min: int = 30
@export var defense_max: int = 45
@export var resolve_min: int = 35
@export var resolve_max: int = 50
@export var wisdom_min: int = 25
@export var wisdom_max: int = 40
@export var max_ap: int = 9
@export var move_range: int = 4

# ──── 武器池 ────
## 可熟练使用的武器 id 列表；不在池内装备触发「手拙」debuff
@export var weapon_pool: Array[String] = []

## 职业自带战斗技能 id（AbilityLibrary 查询）
@export var abilities: Array[String] = []


## 是否在武器池内
func has_weapon(weapon_id: String) -> bool:
	return weapon_pool.has(weapon_id)


## 固定属性（取范围中值，用于 Demo / 调试）
func fixed_stats() -> Dictionary:
	return {
		"max_hp":          (hp_min + hp_max) / 2,
		"base_initiative": (init_min + init_max) / 2,
		"melee_skill":     (melee_min + melee_max) / 2,
		"defense":         (defense_min + defense_max) / 2,
		"resolve":         (resolve_min + resolve_max) / 2,
		"wisdom":          (wisdom_min + wisdom_max) / 2,
		"max_ap":          max_ap,
		"move_range":      move_range,
	}


## 随机生成一组属性（取范围内随机值，供 Roguelike 循环使用）
func randomize_stats() -> Dictionary:
	return {
		"max_hp":          randi_range(hp_min, hp_max),
		"base_initiative": randi_range(init_min, init_max),
		"melee_skill":     randi_range(melee_min, melee_max),
		"defense":         randi_range(defense_min, defense_max),
		"resolve":         randi_range(resolve_min, resolve_max),
		"wisdom":          randi_range(wisdom_min, wisdom_max),
		"max_ap":          max_ap,
		"move_range":      move_range,
	}
