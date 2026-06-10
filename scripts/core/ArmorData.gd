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

## 重量：直接从 Stats.max_stamina 中扣除，越重越累
@export var weight: int = 0

## 流派标记：nimble（轻甲缓冲 HP）/ battle_forged（重甲免疫弱伤害）
## Phase 1 仅作显示，Phase 2 实装机制
@export var combat_style: String = "none"

# ────────────────────────────────────────────────────────────
# 战斗模型 v3 新增字段（design.md 顶部"战斗模型 v3"章节）
# ────────────────────────────────────────────────────────────

## 护甲材质："plate"（板甲/明光铠/札甲）/ "mail"（锁甲/棉甲）/ "leather"（皮甲/麻甲）/ "none"（无甲）
##   决定 9 格 HP 渗透表（武器类型 vs 此材质）
##     slash 克 leather / pierce 克 mail / crush 克 plate
@export var material: String = "leather"

## 护甲等级："light"（轻甲，影响 effective_defense ×1.0）
##           "medium"（中甲 ×0.7）
##           "heavy"（重甲 ×0.4，靠护甲池硬抗，闪避格挡基本失效）
##           "none"（无甲）
@export var armor_class: String = "light"

## [已废弃] 护甲对移动力的惩罚 —— 重甲已有先攻+气力倍率两重惩罚，移动惩罚不再叠加
@export var move_penalty: int = 0

## 护甲 overlay sprite 路径（图块拼接 Phase 2 末实施）
@export var overlay_sprite: String = ""


func to_string_brief() -> String:
	return "%s(头%d 身%d 重%d %s)" % [display_name, head_armor, body_armor, weight, armor_class]
