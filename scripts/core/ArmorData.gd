extends Resource
class_name ArmorData
##
## ArmorData.gd — 护甲数据类
##
## 战兄弟护甲：头/身分离，重量影响 Initiative 和最大 Fatigue。
##

@export var id: String = "no_armor"
@export var display_name: String = "无甲"

@export var head_armor: int = 0
@export var body_armor: int = 0

## 重量：直接从 Stats.max_fatigue 中扣除，越重越累
@export var weight: int = 0

## 流派标记：nimble（轻甲缓冲 HP）/ battle_forged（重甲免疫弱伤害）
## Phase 1 仅作显示，Phase 2 实装机制
@export var combat_style: String = "none"


func to_string_brief() -> String:
	return "%s(头%d 身%d 重%d)" % [display_name, head_armor, body_armor, weight]
