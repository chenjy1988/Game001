extends Resource
class_name WeaponData
##
## WeaponData.gd — 武器数据类（v3.1 schema）
##
## 字段定义见 design/weapon-system.md § 3.1。
## 数据源：data/weapons.json（autoload `WeaponArmorDB` 启动时反序列化）。
##
## 攻击类型 + weight × 渗透公式（Phase 2 重构核心）：
##   - attack_modes：武器支持的攻击模式列表（slash / pierce / crush）
##   - damage_base：单一基础伤害（取消 min/max，浮动来自气力档位）
##   - weight：武器重量；既影响 Initiative 惩罚，又驱动渗透公式
##       penetration = base_rate(by_type) × (1 + max(0, (weight - 4) / 6))
##

# ──────────── 基础标识 ────────────
@export var id: String = "sword"
@export var display_name: String = "短剑"

# ──────────── 战斗模型 v3.1 核心字段（新）────────────

## 武器支持的攻击模式列表，元素来自 {"slash", "pierce", "crush"}
## 单模式武器（如横刀只有 slash）= ["slash"]
## 双模式武器（如剑/陌刀 = slash + pierce）= ["slash", "pierce"]
@export var attack_modes: Array[String] = ["slash"]

## 基础伤害（取消 min/max；浮动来自气力档位 + 微小波动）
@export var damage_base: int = 40

## 武器重量（决定 Init 惩罚 + 渗透 weight_modifier）
## 范围 0~16；典型值：匕首 0 / 横刀 6 / 陌刀 14 / 双手战锤 16
@export var weight: int = 6

## 命中修正（单模式武器使用）
@export var hit_modifier: int = 0

## 命中修正（双模式武器使用，按 mode 字符串映射；为空则回落到 hit_modifier）
@export var hit_modifier_by_mode: Dictionary = {}

## 头部命中基础概率（百分比）—— 25% 单手 / 15% 双手
@export var head_chance: int = 25

## 瞄头时的命中惩罚（单模式）
@export var aim_head_penalty: int = -20

## 瞄头时的命中惩罚（双模式按 mode 字符串映射；为空则回落到 aim_head_penalty）
@export var aim_head_penalty_by_mode: Dictionary = {}

## 是否双手武器（占用副手槽，禁用瞄头单手专属能力）
@export var two_handed: bool = false

## 是否拥有 great_swing（横扫千军接口预留）
@export var great_swing: bool = false

## 远程武器发射后再次发射所需的上弦 AP（弩用；其他为 0）
@export var reload_ap: int = 0

## 武器自带 base_block（用于格挡公式）
##   设计参考：盾 25 / 陌刀 15 / 双手剑 12 / 长矛 10 / 横刀 8 / 单手斧 5 / 匕首 3 / 战锤 0 / 弓弩 0
@export var block_value: int = 0

# ──────────── 通用字段 ────────────

## 攻击 AP 消耗（普攻 base_ap_cost；具体能力从 Ability 加附加 AP）
@export var ap_cost: int = 4

## 攻击距离范围 [min, max]（hex 格数）；近战 [1,1]，长矛 [1,2]，弓 [2,5]，弩 [2,6]
@export var range_min: int = 1
@export var range_max: int = 1

## 武器类型："melee" / "ranged"
@export var weapon_type: String = "melee"

## 武器在角色身上的 sprite 路径
@export var sprite: String = ""

# ──────────── 旧字段（DEPRECATED，过渡期保留 1 版）────────────
##
## 以下字段在 weapons.json v3.1 schema 已不存在，但代码层（DamageSystem 旧版 calculate_damage、
## SidePanel 显示）可能仍在引用。Phase 2 A2 完成后清理。
## 新代码请使用 damage_base / attack_modes / weight 等新字段。

## DEPRECATED：旧 min/max 伤害（v3.1 用 damage_base 替代）
@export var damage_min: int = 35
@export var damage_max: int = 50

## DEPRECATED：旧对甲效率（v3.1 用 attack_modes + armor_mult 表替代）
@export var armor_effectiveness: float = 1.0

## DEPRECATED：旧穿甲率（v3.1 用 weight × 渗透公式替代）
@export var armor_penetration: float = 0.0

## DEPRECATED：旧 fatigue_cost（v3.1 用 base_stamina × weight_mult 公式替代）
@export var fatigue_cost: int = 6

## DEPRECATED：旧 attack_range（v3.1 用 range_min/range_max 替代）
@export var attack_range: int = 1

## DEPRECATED：旧头部伤害倍率（v3.1 全局 1.5，不再每武器配置）
@export var head_damage_mult: float = 1.5

## DEPRECATED：旧暴击倍率（v3.1 全局 1.5）
@export var crit_mult: float = 1.5

## DEPRECATED：旧额外暴击概率（v3.1 用职业精通 + Wisdom 取代）
@export var bonus_crit_chance: float = 0.0

## DEPRECATED：旧"伤害类型"字段（v3.1 升级为 attack_modes 数组）
##   仍由旧 DamageSystem 代码读取以查 9 格 HP 渗透表；
##   过渡期：若 attack_modes 非空则取首项填充本字段以保持兼容
@export var damage_type: String = "slash"

## DEPRECATED：旧 base_block 字段（v3.1 用 block_value）
@export var base_block: int = 0


# ──────────── 工具方法 ────────────

## 取武器在指定 mode 下的命中修正
func get_hit_modifier(mode: String) -> int:
	if hit_modifier_by_mode and hit_modifier_by_mode.has(mode):
		return int(hit_modifier_by_mode[mode])
	return hit_modifier


## 取武器在指定 mode 下的瞄头命中惩罚
func get_aim_head_penalty(mode: String) -> int:
	if aim_head_penalty_by_mode and aim_head_penalty_by_mode.has(mode):
		return int(aim_head_penalty_by_mode[mode])
	return aim_head_penalty


## 武器是否支持指定攻击模式
func supports_mode(mode: String) -> bool:
	return mode in attack_modes


## 取主攻击模式（attack_modes[0]，无则回落到 damage_type 兼容字段）
func primary_mode() -> String:
	if not attack_modes.is_empty():
		return attack_modes[0]
	return damage_type


## 渗透 weight_modifier：破甲前透甲 HP = 实际扣甲 × (base_rate × weight_modifier)
func weight_modifier() -> float:
	return 1.0 + max(0.0, (float(weight) - 4.0) / 6.0)


## DEPRECATED：旧伤害 roll；新公式用 damage_base，过渡期保留
func roll_base_damage() -> int:
	if damage_base > 0:
		return damage_base
	return randi_range(damage_min, damage_max)


func to_string_brief() -> String:
	var modes: String = ",".join(attack_modes) if not attack_modes.is_empty() else damage_type
	return "%s(base %d / wt %d / %s / AP %d / blk %d)" % [
		display_name, damage_base, weight, modes, ap_cost, block_value
	]
