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
@export var max_stamina: int = 100  ## 气力上限（design.md § 一：60-150，独立可升级属性）
@export var move_range: int = 4     ## 移动力（design.md § 一：3-6，职业基础值）

var ap: int = 9
var fatigue: int = 0  ## 当前累积疲劳，越高 Initiative 越低；remaining_stamina = max_stamina - fatigue

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
@export var defense: int = 30          ## 基础防御（subject to 收益递减）
## [DEPRECATED] 旧字段，兼容过渡期，Phase 2 末删除
@export var melee_defense: int = 5
@export var ranged_defense: int = 5    ## [DEPRECATED] 无远程防御概念，已废弃

# 运行时加值（无递减，来自技能/武器词条）
var dodge_bonus: int = 0               ## 闪避加值（技能/武器词条赋予，每回合/战斗开始清零）

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
	# 护甲重量降低最大可用气力值（战兄弟规则）
	max_stamina = max(40, max_stamina - armor_weight)


## 当前 Initiative = 基础值 - 当前疲劳 - 护甲重量惩罚（重量已影响 max_stamina 间接体现）
## 简化版：直接 base - fatigue
func current_initiative() -> int:
	return base_initiative - fatigue


## 【旧版】有效 Initiative：base - fatigue - 武器/护甲重量直接进入 Initiative 公式（TO 风格）
## 已弃用，仅保留兼容性。Phase 2 后期改用 effective_initiative_v2
##   armor_weight：护甲重量（每 4 点 -1 init）
##   weapon_weight：武器重量（每 4 点 -1 init）
func effective_initiative(armor_weight: int = 0, weapon_weight: int = 0) -> int:
	var v: int = base_initiative - fatigue
	v -= int(floor(float(armor_weight) / 4.0))
	v -= int(floor(float(weapon_weight) / 4.0))
	return max(1, v)


## 【新版】有效 Initiative（性能优化版）
## 公式：(base_initiative - all_weight) × (1.0 - fatigue_ratio) × rand(0.9, 1.0)
##   all_weight = armor.weight + weapon.weight + items.weight（全身重量）
##   fatigue_ratio = fatigue / max_stamina（0.0~1.0，越疲劳比例越高）
##   1.0 - fatigue_ratio = 气力充沛度（1.0 满气 / 0.0 力竭）
##   rand(0.9, 1.0) = ±5% 随机抖动，避免 init 完全相同卡顿
##
## 返回值：float（精度更高，避免排序卡顿）
## 最小值保护：max(1.0, result)，确保即使重甲力竭也能最终轮到
func effective_initiative_v2(all_weight: int = 0) -> float:
	if max_stamina <= 0:
		max_stamina = 1  # 防守，避免除以零

	# 气力充沛度（1.0 = 满气，0.0 = 力竭）
	var fatigue_ratio: float = float(fatigue) / float(max_stamina)
	var fatigue_mult: float = 1.0 - fatigue_ratio

	# 随机抖动（±5%）
	var jitter: float = randf_range(0.9, 1.0)

	var result: float = float(base_initiative - all_weight) * fatigue_mult * jitter
	return max(1.0, result)


## 是否存活
func is_alive() -> bool:
	return hp > 0


## 有效防御值（含递减 + block + dodge）
## block_bonus：来自装备武器/盾牌的 block_value，由调用方传入
## dodge_bonus：运行时闪避加值，不受递减影响
func effective_defense(block_bonus: int = 0) -> float:
	# 基础 defense 收益递减：≤45 直接值，>45 超出部分 ×0.5
	var base: float
	if defense <= 45:
		base = float(defense)
	else:
		base = 45.0 + float(defense - 45) * 0.5
	# block 和 dodge 直接叠加，不受递减影响
	return base + float(block_bonus) + float(dodge_bonus)


## [DEPRECATED] 兼容旧调用，Phase 2 末删除
func effective_melee_defense() -> float:
	return effective_defense(0)


## [DEPRECATED] 已废弃，远程无单独防御
func effective_ranged_defense() -> float:
	return effective_defense(0)


# ────────────────────────────────────────────────────────────
# 战斗模型 v3 派生数值（design.md 顶部"战斗模型 v3"章节）
# ────────────────────────────────────────────────────────────

## 装甲材质对 effective_defense 的系数
##   皮甲 light  ×1.0（不影响灵活性）
##   锁甲 medium ×0.7（限制行动）
##   板甲 heavy  ×0.4（重甲党靠护甲池硬抗，闪避格挡基本无效）
const ARMOR_CLASS_DEF_MULT: Dictionary = {
	"light": 1.0,
	"medium": 0.7,
	"heavy": 0.4,
	"none": 1.0,  # 无甲（如布衣）
}


## Effective Initiative：base - 装甲重量/4（重甲拖慢）
func eff_init(armor_weight: int = 0) -> int:
	var v: int = base_initiative
	v -= int(floor(float(armor_weight) / 4.0))
	return max(1, v)


## Effective Defense：defense × 装甲材质系数
##   armor_class："light" / "medium" / "heavy" / "none"
##   重甲 ×0.4 让重甲党 dodge / block 大幅降低，靠护甲池抗
func eff_defense(armor_class: String = "light") -> float:
	var mult: float = ARMOR_CLASS_DEF_MULT.get(armor_class, 1.0)
	return float(defense) * mult


## 闪避率（%）：Init 和 Defense 共同决定（你的设计：协同效应）
##   Dodge% = max(0, (eff_init - 80) × 0.2 + eff_def × 0.3)
##   cap: 50%
##   - eff_init ≤ 80 时 init 部分为 0（迟钝就是迟钝）
##   - eff_def 直接贡献 30% 系数
func dodge_chance(armor_weight: int = 0, armor_class: String = "light") -> float:
	var ei: int = eff_init(armor_weight)
	var ed: float = eff_defense(armor_class)
	var d: float = max(0.0, (float(ei) - 80.0) * 0.2) + ed * 0.3
	return clamp(d, 0.0, 50.0)


## 格挡率（%）：武器/盾的 base_block + Effective_Defense × 0.5
##   weapon_base_block：来自武器组合（盾 25 / 双武器+精通 15 / 陌刀 15 / 长矛 10 / 横刀 8 / 匕首 3 / 锤 0 / 弓 0）
##   cap: 60%
##   - base_block ≤ 0 时返回 0（远程武器 / 战锤 等钝重 / 拳头无法格挡）
##     这是物理直觉：没有"挡的器具"就没有格挡
##   - 仅当 base_block > 0 时，Defense 才贡献格挡（防御技巧需要"用什么挡"）
func block_chance(weapon_base_block: int, armor_class: String = "light") -> float:
	if weapon_base_block <= 0:
		return 0.0
	var ed: float = eff_defense(armor_class)
	var b: float = float(weapon_base_block) + ed * 0.5
	return clamp(b, 0.0, 60.0)


## 回合开始：AP 回满，Fatigue 自然恢复 15
func reset_ap() -> void:
	ap = max_ap


## 气力档位 → 命中率修正
## 0-60%：无惩罚  60-80%：-5%  80-95%：-10%  95%+（力竭）：-20%
func get_hit_modifier() -> float:
	if max_stamina <= 0:
		return -0.20
	var ratio: float = float(fatigue) / float(max_stamina)
	if ratio >= 0.95:
		return -0.20   # 力竭
	elif ratio >= 0.80:
		return -0.10
	elif ratio >= 0.60:
		return -0.05
	return 0.0


func recover_fatigue(amount: int = 15) -> void:
	fatigue = max(0, fatigue - amount)


## 累积疲劳（行动消耗）
func add_fatigue(amount: int) -> void:
	fatigue = min(max_stamina, fatigue + amount)


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
	s.fatigue = fatigue
	return s
