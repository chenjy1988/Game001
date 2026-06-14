extends RefCounted
class_name DamageSystem

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")
const _Unit = preload("res://scripts/core/Unit.gd")
const _HexCoord = preload("res://scripts/core/HexCoord.gd")
const _Stats = preload("res://scripts/core/Stats.gd")
const _WeaponData = preload("res://scripts/core/WeaponData.gd")
const _PassiveHookRegistry = preload("res://scripts/core/passives/PassiveHookRegistry.gd")
##
## DamageSystem.gd — 战斗模型 v3.2 伤害管线（纯静态工具类）
##
## 实现 design/weapon-system.md § 6.1 的 9 步流程：
##   Step 1: 选攻击模式（attack_modes[0]，能力框架就绪后由 Ability 注入）
##   Step 2: 命中检定（final_def 合成 + 一次掷骰；miss 时 roll 区间按 防御:闪避:格挡 归因供 UI，§6.1.1）
##   Step 3: 部位检定（单手 25% / 双手 15% / 瞄头 70% / 精准 50% 等）
##   Step 4: 暴击检定（5 + 武器 + 精通 + max(0,wisdom-40)*0.2，软上限 50%）
##   Step 5: 基础伤害（damage_base × 气力档 × 微波 × 专精 × 词条 × 能力 × 双手握持）
##   Step 6: 暴击 + 头部加法叠加（× 1.0 / 1.5 / 1.5 / 2.0）
##   Step 7: 伤害分配（甲伤×armor_mult；透甲=实际扣甲×渗透率；击穿后=(final−扣甲)×hp_mult）
##   Step 8: 气力消耗（base_stamina × weight_mult + 隐藏气力消耗，由 Unit 实际扣减）
##
## 互斥规则：一次攻击只能选 1 个职业能力。当前未接入能力框架时默认普攻。
##

# ──────────── 命中相关常量 ────────────
const HIT_CHANCE_MIN: float = 0.05
const HIT_CHANCE_MAX: float = 0.95
const HIGH_DEF_PENALTY_THRESHOLD: float = 45.0
const HIGH_DEF_PENALTY_MULT: float = 0.5

# Overwhelm（围攻）
const OVERWHELM_PER_ALLY: float = 0.05
const OVERWHELM_MAX: float = 0.25        ## 上限 25%（原 20%）

# 地形修正
const HIT_BONUS_HIGH_GROUND: float = 0.10  ## 高地打低地 +10%
const HIT_PENALTY_LOW_GROUND: float = -0.10 ## 低地打高地 −10%

# ──────────── 部位检定 ────────────
const HEAD_CHANCE_ONE_HAND: int = 25   ## 单手武器 25% 头部
const HEAD_CHANCE_TWO_HAND: int = 15   ## 双手武器 15% 头部

# ──────────── 暴击 ────────────
const CRIT_BASE: float = 5.0           ## 基础暴击率（百分点）
const CRIT_SOFT_CAP: float = 50.0      ## 软上限

# ──────────── 攻击类型 → armor_mult / hp_mult / base_pen ────────────
## armor_mult：base_damage × armor_mult = 应扣对应部位护甲（破甲快慢）
##   Slash 1.0 / Pierce 0.7（戳刺破甲弱）/ Crush 1.5（钝击震碎甲叶）
const ARMOR_MULT_BY_TYPE: Dictionary = {
	"slash":  1.0,
	"pierce": 0.7,
	"crush":  1.5,
}

## hp_mult：破甲后溢出量 × hp_mult = 溢出 HP 伤害
##   Crush 0.7 略低（钝击破甲后内伤稍少）；Slash/Pierce 1.0
const HP_MULT_BY_TYPE: Dictionary = {
	"slash":  1.0,
	"pierce": 1.0,
	"crush":  0.7,
}

## 基础渗透率（普攻）：破甲前透甲 HP = 实际扣甲 × (base_pen × weight_modifier)
const BASE_PEN_BY_TYPE: Dictionary = {
	"slash":  0.10,
	"pierce": 0.15,
	"crush":  0.08,
}

# ──────────── 气力消耗（design.md §三 / weapon-system.md §九）────────────
## 任何动作 = ceil(base × weight_mult)；weight_mult = 1 + 装备总重 × 0.02
const MOVE_STAMINA_BASE: int = 2
const ONE_HAND_ATTACK_STAMINA_BASE: int = 4
const TWO_HAND_ATTACK_STAMINA_BASE: int = 6
const BOW_ATTACK_STAMINA_BASE: int = 5
const CROSSBOW_ATTACK_STAMINA_BASE: int = 5
const CROSSBOW_RELOAD_STAMINA_BASE: int = 10  ## 弩上弦（发射后再次装填）
const ATTACK_STAMINA_BASE: int = ONE_HAND_ATTACK_STAMINA_BASE  ## 兼容旧引用
const WAIT_STAMINA_BASE: int = 5
const OA_ATTACK_STAMINA_BASE: int = 4
## 被攻击基础气力消耗（命中/闪避/格挡均触发）
const DEFEND_FATIGUE_BASE: int = 2

static func stamina_weight_mult(unit: _Unit) -> float:
	if unit == null:
		return 1.0
	return 1.0 + float(unit.get_total_weight()) * 0.02


static func calculate_action_stamina_cost(unit: _Unit, base: int) -> int:
	if unit == null or base <= 0:
		return 0
	return int(ceil(float(base) * stamina_weight_mult(unit)))


## 普攻 base：单手 4 / 双手 6 / 弓 5 / 弩射击 5（再 × 装备总重 weight_mult）
static func is_crossbow_weapon(weapon: _WeaponData) -> bool:
	return weapon != null and weapon.reload_ap > 0


static func attack_stamina_base_for(unit: _Unit) -> int:
	if unit == null or unit.weapon == null:
		return ONE_HAND_ATTACK_STAMINA_BASE
	var w = unit.weapon
	if w.weapon_type == "ranged":
		if is_crossbow_weapon(w):
			return CROSSBOW_ATTACK_STAMINA_BASE
		return BOW_ATTACK_STAMINA_BASE
	if w.two_handed:
		return TWO_HAND_ATTACK_STAMINA_BASE
	return ONE_HAND_ATTACK_STAMINA_BASE


static func reload_stamina_base_for(unit: _Unit) -> int:
	if unit == null or unit.weapon == null:
		return 0
	if is_crossbow_weapon(unit.weapon):
		return CROSSBOW_RELOAD_STAMINA_BASE
	return 0


static func calculate_attack_stamina_cost(unit: _Unit) -> int:
	return calculate_action_stamina_cost(unit, attack_stamina_base_for(unit))


static func calculate_reload_stamina_cost(unit: _Unit) -> int:
	var base: int = reload_stamina_base_for(unit)
	if base <= 0:
		return 0
	return calculate_action_stamina_cost(unit, base)


## 计算防守方被攻击时的气力消耗
static func calculate_defend_stamina_cost(target:_Unit) -> int:
	return calculate_action_stamina_cost(target, DEFEND_FATIGUE_BASE)

# ──────────── 气力档位 → 伤害系数 ────────────

# ──────────── 微小波动 ────────────
const DAMAGE_JITTER: Vector2 = Vector2(0.95, 1.05)


# =====================================================================
# 公开接口
# =====================================================================

## 数攻击方阵营、与目标相邻、且不是攻击者自己的单位个数。用于 Overwhelm。
static func count_overwhelm_allies(attacker:_Unit, target:_Unit) -> int:
	if attacker == null or target == null:
		return 0
	if attacker.hex_grid == null:
		return 0
	var faction: int = attacker.get_faction()
	var n: int = 0
	for cell in _HexCoord.neighbors(target.axial_pos):
		var u = attacker.hex_grid.get_occupant(cell)
		if u == null or u == attacker:
			continue
		if not u.is_alive():
			continue
		if u.get_faction() == faction:
			n += 1
	return n


## 高防惩罚：仅作用于合成后的 with_mult（weapon-system §6.1.1）
static func apply_high_def_penalty(with_mult: float) -> float:
	if with_mult <= HIGH_DEF_PENALTY_THRESHOLD:
		return with_mult
	return HIGH_DEF_PENALTY_THRESHOLD \
		+ (with_mult - HIGH_DEF_PENALTY_THRESHOLD) * HIGH_DEF_PENALTY_MULT


## 闪避防御点（1:1）；可被 ignore_dodge 清零
static func compute_dodge_pts(target:_Unit, options: Dictionary = {}) -> float:
	if bool(options.get("ignore_dodge", false)):
		return 0.0
	if target == null or target.stats == null:
		return 0.0
	var pts: float = target.get_init_dodge_pts() + float(target.stats.dodge_bonus)
	return clamp(pts, 0.0, 50.0)


## 格挡防御点（1:1）；可被 ignore_block / block_mult 调整
static func compute_block_pts(target:_Unit, options: Dictionary = {}) -> float:
	if bool(options.get("ignore_block", false)):
		return 0.0
	if target == null or target.stats == null:
		return 0.0
	var equip_block: int = target.get_equipment_block_pts()
	# TODO: 技能 +N 格挡（CombatModifier / Ability）累加
	var mult: float = float(options.get("block_mult", 1.0))
	return clamp(target.stats.block_chance(equip_block) * mult, 0.0, 60.0)


## 守方 final_def 拆解（weapon-system §6.1.1）
static func compute_defense_breakdown(target:_Unit, options: Dictionary = {}) -> Dictionary:
	var base_def: float = float(target.stats.defense) if target != null and target.stats else 0.0
	var dodge_pts: float = compute_dodge_pts(target, options)
	var block_pts: float = compute_block_pts(target, options)
	var def_mods: Array = target.get_defense_modifiers() if target != null else []
	var def_flat: float = _CombatModifier.sum_defense_flat(def_mods)
	var def_mult: float = 1.0
	if target != null and target.stats != null:
		def_mult = target.stats.get_defense_pct_multiplier(def_mods)
	def_mult *= 1.0 + target.get_morale_defense_pct() if target != null else 1.0
	var composed: float = base_def + dodge_pts + block_pts + def_flat
	var with_mult: float = composed * def_mult
	var final_def: float = apply_high_def_penalty(with_mult)
	return {
		"base_def": base_def,
		"dodge_pts": dodge_pts,
		"block_pts": block_pts,
		"def_flat": def_flat,
		"def_mult": def_mult,
		"composed": composed,
		"with_mult": with_mult,
		"final_def": final_def,
	}


static func _attacker_skill(attacker:_Unit) -> float:
	if attacker == null or attacker.stats == null:
		return 0.0
	if attacker.weapon == null or attacker.weapon.weapon_type == "melee":
		return float(attacker.stats.melee_skill)
	return float(attacker.stats.ranged_skill)


static func compute_hit_bonus(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> float:
	var bonus: float = 0.0
	var allies: int = count_overwhelm_allies(attacker, target)

	# ── 围攻系数：先看攻击者钩子（借势合击）──
	var per_ally: float = OVERWHELM_PER_ALLY
	var cap: float = OVERWHELM_MAX
	if attacker != null:
		var atk_hooks = _PassiveHookRegistry.collect(attacker, "self_overwhelm_bonus",
			{ "overwhelm_count": allies })
		for h in atk_hooks:
			if h.has("per_ally"): per_ally = float(h["per_ally"])
			if h.has("cap"):      cap      = float(h["cap"])

	var attacker_overwhelm: float = min(float(allies) * per_ally, cap)

	# ── 受击侧钩子（野战八方清零对方围攻加值）──
	if target != null:
		var def_hooks = _PassiveHookRegistry.collect(target, "incoming_overwhelm_bonus", {})
		for h in def_hooks:
			if h.has("set"):
				attacker_overwhelm = float(h["set"])

	bonus += attacker_overwhelm
	if attacker != null and attacker.hex_grid != null and target != null:
		var atk_elev: int = attacker.hex_grid.get_elevation(attacker.axial_pos)
		var def_elev: int = attacker.hex_grid.get_elevation(target.axial_pos)
		if atk_elev > def_elev:
			bonus += HIT_BONUS_HIGH_GROUND
		elif atk_elev < def_elev:
			bonus += HIT_PENALTY_LOW_GROUND
	bonus += float(options.get("ability_hit_modifier", 0)) / 100.0
	bonus += float(options.get("weather_hit_modifier", 0)) / 100.0
	if attacker != null:
		bonus += _CombatModifier.sum_hit_pct(attacker.get_active_debuffs())
	return bonus


## 未命中视觉归因：同一次 roll 在 miss 带内按 防御:闪避:格挡 权重切三段（无二次随机）
## defense_pts = base_def + def_flat；某池为 0 则不参与切分（不会出现对应归因）
static func classify_miss_reason(
	hit_chance: float,
	roll: float,
	defense_pts: float,
	dodge_pts: float,
	block_pts: float,
) -> String:
	if roll < hit_chance:
		return ""
	var miss_size: float = 1.0 - hit_chance
	var def_w: float = max(0.0, defense_pts)
	var dodge_w: float = max(0.0, dodge_pts)
	var block_w: float = max(0.0, block_pts)
	var total: float = def_w + dodge_w + block_w
	if total <= 0.0001:
		return "miss"
	var cursor: float = hit_chance
	if def_w > 0.0:
		cursor += miss_size * def_w / total
		if roll < cursor:
			return "miss"
	if dodge_w > 0.0:
		cursor += miss_size * dodge_w / total
		if roll < cursor:
			return "dodge"
	if block_w > 0.0:
		return "block"
	return "miss"


## 计算命中率（0~1）。BattleAI / UnitTooltip 调用。
## Hit% = (atk - final_def)/100 + hit_bonus；见 weapon-system §6.1.1
static func calculate_hit_chance(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> float:
	var breakdown: Dictionary = compute_defense_breakdown(target, options)
	var core: float = (_attacker_skill(attacker) - breakdown.final_def) / 100.0
	var hit_bonus: float = compute_hit_bonus(attacker, target, options)
	return clamp(core + hit_bonus, HIT_CHANCE_MIN, HIT_CHANCE_MAX)


static func _effective_hit_chance(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> float:
	var breakdown: Dictionary = compute_defense_breakdown(target, options)
	var base_def: float = float(breakdown.get("base_def", 0.0))
	var hit_adj: float = 0.0
	if target != null and target.has_method("get_effective_stats"):
		var te = target.get_effective_stats()
		if te != null:
			base_def = float(te.defense)
	if attacker != null and attacker.has_method("get_effective_stats"):
		var ae = attacker.get_effective_stats()
		if ae != null:
			hit_adj += float(ae.hit_pct)
	var composed: float = base_def + float(breakdown.get("dodge_pts", 0.0)) \
		+ float(breakdown.get("block_pts", 0.0)) + float(breakdown.get("def_flat", 0.0))
	var with_mult: float = composed * float(breakdown.get("def_mult", 1.0))
	var final_def: float = apply_high_def_penalty(with_mult)
	var core: float = (_attacker_skill(attacker) - final_def) / 100.0
	var hit_bonus: float = compute_hit_bonus(attacker, target, options) + hit_adj
	return clamp(core + hit_bonus, HIT_CHANCE_MIN, HIT_CHANCE_MAX)


## @deprecated 兼容旧调用；返回格挡点/100
static func target_block_chance(target:_Unit, options: Dictionary = {}) -> float:
	return compute_block_pts(target, options) / 100.0


## 计算暴击率（0~1）—— A3 公式
##   crit% = 5（基础）+ 武器加成 + 武器精通 + max(0, wisdom-40) * 0.2
##   软上限 50%
##   武器精通系数尚未接入（B3）；当前从 weapon.bonus_crit_chance 兼容旧字段
static func calculate_crit_chance(attacker:_Unit) -> float:
	var crit: float = CRIT_BASE
	if attacker.weapon != null:
		# 旧字段 bonus_crit_chance 是 0~1 浮点，转百分点
		crit += attacker.weapon.bonus_crit_chance * 100.0
	if attacker.stats != null:
		var wisdom: int = attacker.stats.wisdom
		crit += max(0, wisdom - 40) * 0.2
	# 武器精通解锁的 +5 暴击 → B3 接入 JobClass 后从 attacker.job 取
	return clamp(crit, 0.0, CRIT_SOFT_CAP) / 100.0


## 当前气力档 debuff 对伤害的系数（Step 6 的一项）
static func stamina_tier_multiplier(stats: _Stats) -> float:
	return _CombatModifier.roll_stamina_damage_mult(stats)


## 武器渗透 weight_modifier
static func weight_modifier_for(weapon: _WeaponData) -> float:
	if weapon == null:
		return 1.0
	return weapon.weight_modifier()


## UI 用：主模式渗透率预览（base_pen × weight_modifier）
static func penetration_rate_for(weapon: _WeaponData, mode: String = "") -> float:
	if weapon == null:
		return 0.0
	var m: String = mode
	if m.is_empty():
		m = weapon.attack_modes[0] if not weapon.attack_modes.is_empty() else "slash"
	return BASE_PEN_BY_TYPE.get(m, 0.10) * weight_modifier_for(weapon)


## AI / 评分：统一 attack_mode → mode
static func normalize_attack_options(options: Dictionary) -> Dictionary:
	var o: Dictionary = options.duplicate()
	if not o.has("mode") and o.has("attack_mode"):
		o["mode"] = o["attack_mode"]
	return o


## AI / 评分：debuff 伤害倍率期望（区间取中点，避免随机 roll）
static func expected_damage_mult(attacker:_Unit) -> float:
	if attacker == null:
		return 1.0
	var mult: float = 1.0
	for raw in attacker.get_active_debuffs():
		if raw is _CombatModifier:
			if raw.damage_mult_min == raw.damage_mult_max:
				mult *= raw.damage_mult_min
			else:
				mult *= (raw.damage_mult_min + raw.damage_mult_max) * 0.5
	return mult


## AI / 评分：共享期望伤害剖面（部位/暴击期望化，不含命中率）
static func _estimate_attack_damage_profile(
	attacker:_Unit,
	target:_Unit,
	options: Dictionary = {},
) -> Dictionary:
	if attacker == null or target == null or target.stats == null:
		return {}
	var weapon: _WeaponData = attacker.weapon
	if weapon == null:
		return {}
	var opts: Dictionary = normalize_attack_options(options)
	var mode: String = opts.get("mode", weapon.primary_mode())

	var head_chance_pct: int = HEAD_CHANCE_TWO_HAND if weapon.two_handed else HEAD_CHANCE_ONE_HAND
	if weapon.head_chance > 0:
		head_chance_pct = weapon.head_chance
	var force_head: float = float(opts.get("force_head_chance", -1.0))
	if force_head >= 0.0:
		head_chance_pct = int(round(force_head * 100.0))
	if bool(opts.get("force_body_only", false)):
		head_chance_pct = 0
	var p_head: float = float(head_chance_pct) / 100.0

	var crit_chance: float = calculate_crit_chance(attacker)
	crit_chance += float(opts.get("mastery_crit_bonus", 0.0)) / 100.0
	crit_chance = clamp(crit_chance, 0.0, CRIT_SOFT_CAP / 100.0)
	var loc_crit_mult: float = 1.0 + p_head * 0.5 + crit_chance * 0.5

	var damage_base: int = weapon.damage_base if weapon.damage_base > 0 else weapon.roll_base_damage()
	var jitter_avg: float = (DAMAGE_JITTER.x + DAMAGE_JITTER.y) * 0.5
	var mastery_dmg: float = float(opts.get("mastery_dmg", 1.0))
	var trait_bonus: float = float(opts.get("trait_damage_bonus", 0.0))
	var ability_dmg_mult: float = float(opts.get("ability_damage_mult", 1.0))
	var double_grip: float = 1.25 if bool(opts.get("double_grip", false)) else 1.0
	var base_f: float = float(damage_base) \
		* expected_damage_mult(attacker) \
		* jitter_avg \
		* mastery_dmg \
		* (1.0 + trait_bonus) \
		* ability_dmg_mult \
		* double_grip
	var final_damage_f: float = base_f * loc_crit_mult
	return {
		"final_damage": final_damage_f,
		"p_head": p_head,
		"mode": mode,
		"weapon": weapon,
		"ignore_armor": bool(opts.get("ignore_armor", false)) or bool(opts.get("hp_only", false)),
	}


## AI / 评分：命中后期望冲击伤害（武器输出，不拆 HP 渗透）
static func estimate_impact_on_hit(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> float:
	var prof: Dictionary = _estimate_attack_damage_profile(attacker, target, options)
	return float(prof.get("final_damage", 0.0))


## AI / 评分：命中后期望护甲损耗（头/身按部位概率加权）
static func estimate_armor_strip_on_hit(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> float:
	var prof: Dictionary = _estimate_attack_damage_profile(attacker, target, options)
	if prof.is_empty():
		return 0.0
	if bool(prof.get("ignore_armor", false)):
		return 0.0
	var final_damage_f: float = float(prof.get("final_damage", 0.0))
	var p_head: float = float(prof.get("p_head", 0.0))
	var mode: String = str(prof.get("mode", "slash"))
	var head_strip: float = _expected_armor_strip_for_loc(target, mode, final_damage_f, "head")
	var body_strip: float = _expected_armor_strip_for_loc(target, mode, final_damage_f, "body")
	return p_head * head_strip + (1.0 - p_head) * body_strip


static func _expected_armor_strip_for_loc(
	target:_Unit,
	mode: String,
	final_damage_f: float,
	loc: String,
) -> float:
	if target == null or target.stats == null:
		return 0.0
	var current_armor: int = target.stats.head_armor if loc == "head" else target.stats.body_armor
	if current_armor <= 0:
		return 0.0
	var armor_mult: float = ARMOR_MULT_BY_TYPE.get(mode, 1.0)
	return minf(float(current_armor), final_damage_f * armor_mult)


## AI / 评分：命中后期望 HP 伤害（不含命中率；部位/暴击/渗透按期望化）
static func estimate_hp_damage_on_hit(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> float:
	var prof: Dictionary = _estimate_attack_damage_profile(attacker, target, options)
	if prof.is_empty():
		return 0.0
	if bool(prof.get("ignore_armor", false)):
		return float(prof.get("final_damage", 0.0))
	var final_damage_f: float = float(prof.get("final_damage", 0.0))
	var p_head: float = float(prof.get("p_head", 0.0))
	var mode: String = str(prof.get("mode", "slash"))
	var weapon: _WeaponData = prof.get("weapon")
	var hp_head: float = _allocate_expected_hp_damage(target, weapon, mode, final_damage_f, "head")
	var hp_body: float = _allocate_expected_hp_damage(target, weapon, mode, final_damage_f, "body")
	return p_head * hp_head + (1.0 - p_head) * hp_body


static func _allocate_expected_hp_damage(
	target:_Unit,
	weapon: _WeaponData,
	mode: String,
	final_damage_f: float,
	loc: String,
) -> float:
	var armor_mult: float = ARMOR_MULT_BY_TYPE.get(mode, 1.0)
	var hp_mult: float = HP_MULT_BY_TYPE.get(mode, 1.0)
	var current_armor: int = target.stats.head_armor if loc == "head" else target.stats.body_armor
	var armor_damage_raw: float = final_damage_f * armor_mult
	var armor_damage_int: int = int(round(armor_damage_raw))
	if current_armor <= 0:
		return final_damage_f * hp_mult
	var absorbed_f: float = min(float(current_armor), armor_damage_raw)
	var pen_rate: float = BASE_PEN_BY_TYPE.get(mode, 0.10) * weight_modifier_for(weapon)
	var pen_hp_f: float = absorbed_f * pen_rate
	var overflow_hp_f: float = 0.0
	if armor_damage_int >= current_armor:
		overflow_hp_f = max(0.0, final_damage_f - absorbed_f) * hp_mult
	return pen_hp_f + overflow_hp_f


# =====================================================================
# execute_attack — 9 步主流程
# =====================================================================
##
## 输入：
##   attacker / target
##   options: Dictionary（可选）—— 用于 Phase 2.5 接入 Ability：
##     mode: "slash" | "pierce" | "crush"（默认武器主模式）
##     ability: 能力 id 字符串（默认 "basic_attack"）
##     ability_damage_mult: float（能力伤害修正，默认 1.0）
##     ability_hit_modifier: float（命中加成，默认 0；瞄头 / 全力一击等用）
##     weather_hit_modifier: float（远程天气百分点，stub 0）
##     ignore_dodge / ignore_block: bool（暗箭伤人等）
##     block_mult: float（格挡点倍率，锐不可当等）
##     force_head_chance: float（强制覆盖部位概率，0~1；默认 -1 = 不覆盖）
##     force_body_only: bool（穿心刺等强制身体；默认 false）
##     mastery_dmg: float（武器专精伤害系数，默认 1.0）
##     mastery_crit_bonus: float（精通额外暴击百分点，默认 0）
##     trait_damage_bonus: float（词条加成总和，默认 0）
##     double_grip: bool（单手 + 空副手 = 1.25；默认 false）
##     ignore_armor: bool（穿心刺：完全无视护甲；默认 false）
##     hp_only: bool（穿心刺：100% 转 HP；默认 false）
##
## 返回 result 字典：兼容旧字段 + 新增 v3.1 字段
##
static func execute_attack(attacker:_Unit, target:_Unit, options: Dictionary = {}) -> Dictionary:
	var weapon: _WeaponData = attacker.weapon

	# ── Step 1：选模式 ──
	var mode: String = options.get("mode", weapon.primary_mode() if weapon else "slash")

	# ── Step 2：命中检定 ──
	var breakdown: Dictionary = compute_defense_breakdown(target, options)
	var dodge_pts: float = breakdown.dodge_pts
	var block_pts: float = breakdown.block_pts
	var hit_chance: float = _effective_hit_chance(attacker, target, options)

	var hit_roll: float = randf()
	var did_hit: bool = hit_roll < hit_chance

	var overwhelm_count: int = count_overwhelm_allies(attacker, target)
	var ow_per_ally: float = OVERWHELM_PER_ALLY
	var ow_cap: float = OVERWHELM_MAX
	if attacker != null:
		for h in _PassiveHookRegistry.collect(attacker, "self_overwhelm_bonus", { "overwhelm_count": overwhelm_count }):
			if h.has("per_ally"): ow_per_ally = float(h["per_ally"])
			if h.has("cap"):      ow_cap      = float(h["cap"])
	var overwhelm_bonus: float = min(float(overwhelm_count) * ow_per_ally, ow_cap)
	if target != null:
		for h in _PassiveHookRegistry.collect(target, "incoming_overwhelm_bonus", {}):
			if h.has("set"): overwhelm_bonus = float(h["set"])

	var result: Dictionary = {
		# ── 兼容旧字段 ──
		"attacker_name": attacker.get_unit_name(),
		"target_name": target.get_unit_name(),
		"weapon_name": weapon.display_name if weapon else "武器",
		"hit_chance": hit_chance,
		"roll": hit_roll,
		"hit": did_hit,
		"critical": false,
		"hit_location": "body",
		"base_damage": 0,
		"armor_damage": 0,
		"hp_damage": 0,
		"armor_state": "intact",
		"lethal": false,
		"overwhelm_count": overwhelm_count,
		"overwhelm_bonus": overwhelm_bonus,
		# ── v3.2 命中拆解 ──
		"attack_mode": mode,
		"blocked": false,
		"dodged": false,
		"miss_reason": "",
		"final_def": breakdown.final_def,
		"dodge_pts": dodge_pts,
		"block_pts": block_pts,
		"defense_pts": breakdown.base_def + breakdown.def_flat,
		"def_flat": breakdown.def_flat,
		"def_mult": breakdown.def_mult,
		"dodge_chance": dodge_pts / 100.0,
		"block_chance": block_pts / 100.0,
		"multiplier": 1.0,
		"armor_mult": ARMOR_MULT_BY_TYPE.get(mode, 1.0),
		"hp_mult": HP_MULT_BY_TYPE.get(mode, 1.0),
		"base_pen": BASE_PEN_BY_TYPE.get(mode, 0.10),
		"weight_modifier": weight_modifier_for(weapon),
		"penetration_rate": 0.0,
		"penetration_hp": 0,
		"overflow_hp": 0,
		"final_damage": 0,
		# ── 兼容旧 9 格穿透字段（虽然 v3.1 用 weight × 渗透公式不依赖 material，
		#    但 UI/旧测试仍可能引用）──
		"pen_ratio": 0.0,
		"damage_type": mode,
		"armor_material": (target.armor.material if target.armor else "none"),
	}
	if not did_hit:
		var defense_pts: float = breakdown.base_def + breakdown.def_flat
		var reason: String = classify_miss_reason(hit_chance, hit_roll, defense_pts, dodge_pts, block_pts)
		result["miss_reason"] = reason
		result["blocked"] = reason == "block"
		result["dodged"] = reason == "dodge"
		return result

	# ── Step 3：部位检定 ──
	var head_chance_pct: int = HEAD_CHANCE_TWO_HAND if (weapon and weapon.two_handed) else HEAD_CHANCE_ONE_HAND
	if weapon != null and weapon.head_chance > 0:
		head_chance_pct = weapon.head_chance
	var force_head: float = float(options.get("force_head_chance", -1.0))
	if force_head >= 0.0:
		head_chance_pct = int(round(force_head * 100.0))
	var force_body: bool = bool(options.get("force_body_only", false))

	var loc: String = "body"
	if not force_body and randi_range(0, 99) < head_chance_pct:
		loc = "head"
	result["hit_location"] = loc

	# ── Step 4：暴击检定（独立于部位）──
	var crit_chance: float = calculate_crit_chance(attacker)
	# 武器精通额外暴击（B3 接入 JobClass 后传入）
	crit_chance += float(options.get("mastery_crit_bonus", 0.0)) / 100.0
	crit_chance = clamp(crit_chance, 0.0, CRIT_SOFT_CAP / 100.0)
	var is_crit: bool = randf() < crit_chance
	result["critical"] = is_crit
	result["crit_chance"] = crit_chance

	# ── Step 5：基础伤害 ──
	var damage_base: int = weapon.damage_base if (weapon and weapon.damage_base > 0) else weapon.roll_base_damage()
	var stamina_mult: float = _CombatModifier.roll_damage_mult(attacker.get_active_debuffs()) \
		if attacker is _Unit \
		else stamina_tier_multiplier(attacker.stats)
	var jitter: float = randf_range(DAMAGE_JITTER.x, DAMAGE_JITTER.y)
	var mastery_dmg: float = float(options.get("mastery_dmg", 1.0))
	var trait_bonus: float = float(options.get("trait_damage_bonus", 0.0))
	var ability_dmg_mult: float = float(options.get("ability_damage_mult", 1.0))
	var double_grip: float = 1.25 if bool(options.get("double_grip", false)) else 1.0

	var base_f: float = float(damage_base) \
		* stamina_mult \
		* jitter \
		* mastery_dmg \
		* (1.0 + trait_bonus) \
		* ability_dmg_mult \
		* double_grip

	result["base_damage"] = int(round(base_f))

	# ── Step 7：暴击 + 头部加法叠加 ──
	var multiplier: float = 1.0
	if loc == "head":
		multiplier += 0.5
	if is_crit:
		multiplier += 0.5
	result["multiplier"] = multiplier

	var final_damage_f: float = base_f * multiplier
	result["final_damage"] = int(round(final_damage_f))

	# ── Step 8：伤害分配 ──
	var ignore_armor: bool = bool(options.get("ignore_armor", false))
	var hp_only: bool = bool(options.get("hp_only", false))

	var armor_dealt: int = 0
	var hp_dealt_f: float = 0.0

	if ignore_armor or hp_only:
		# 穿心刺等：完全无视护甲，100% 转 HP
		hp_dealt_f = final_damage_f
		result["armor_state"] = "ignored"
	else:
		var armor_mult: float = ARMOR_MULT_BY_TYPE.get(mode, 1.0)
		var hp_mult: float = HP_MULT_BY_TYPE.get(mode, 1.0)
		var current_armor: int = target.stats.head_armor if loc == "head" else target.stats.body_armor

		# 应扣护甲
		var armor_damage_raw: float = final_damage_f * armor_mult
		var armor_damage_int: int = int(round(armor_damage_raw))

		var base_pen: float = BASE_PEN_BY_TYPE.get(mode, 0.10)
		var weight_mod: float = weight_modifier_for(weapon)
		var pen_rate: float = base_pen * weight_mod
		result["base_pen"] = base_pen
		result["penetration_rate"] = pen_rate

		# 攻甲前是否已无甲？
		if current_armor <= 0:
			# 无甲：HP 扣 = final_damage × hp_mult；护甲不动
			hp_dealt_f = final_damage_f * hp_mult
			armor_dealt = 0
			result["armor_state"] = "no_armor"
			result["penetration_hp"] = 0
		else:
			# 有甲：破甲前仅「实际扣甲 × 渗透率」；破甲后 final 余量照单全收（× hp_mult）
			var absorbed_f: float = min(float(current_armor), armor_damage_raw)
			var actually_taken: int = int(min(current_armor, armor_damage_int))
			armor_dealt = actually_taken
			var pen_hp_f: float = absorbed_f * pen_rate
			var overflow_hp_f: float = 0.0
			if armor_damage_int >= current_armor:
				overflow_hp_f = max(0.0, final_damage_f - absorbed_f) * hp_mult
			hp_dealt_f = pen_hp_f + overflow_hp_f
			result["penetration_hp"] = int(round(pen_hp_f))
			result["overflow_hp"] = int(round(overflow_hp_f))
			if armor_damage_int >= current_armor:
				result["armor_state"] = "broken"
			else:
				result["armor_state"] = "damaged"
		# 兼容旧字段
		result["pen_ratio"] = pen_rate

	var hp_damage_int: int = max(1, int(round(hp_dealt_f)))   ## 命中至少 1 HP（保留旧逻辑）
	result["armor_damage"] = armor_dealt
	result["hp_damage"] = hp_damage_int
	result["lethal"] = (target.stats.hp - hp_damage_int) <= 0

	# Step 9 气力消耗：由 Unit/Ability 在外层处理（attacker spend_stamina）
	return result


# =====================================================================
# UI 日志
# =====================================================================

## 战斗日志 v2 占位（Phase 2 D3 任务再做完整 BBCode 多行结构化）
##   保持旧两行格式 + 在 detail 行追加新公式信息
static func format_attack_log(result: Dictionary) -> String:
	if result.is_empty():
		return ""
	var attacker: String = result.get("attacker_name", "?")
	var target: String = result.get("target_name", "?")
	var chance: float = result.get("hit_chance", 0.0)
	var roll: float = result.get("roll", 0.0)
	var oa: bool = result.get("is_opportunity_attack", false)
	var pincer: bool = result.get("is_pincer_attack", false)
	var weapon_name: String = result.get("weapon_name", "武器")
	var mode: String = result.get("attack_mode", "")

	var prefix: String = ""
	if oa:
		prefix = "[color=#FF8C42][借机][/color] "
	elif pincer:
		prefix = "[color=#5BFFB0][夹击][/color] "

	var chance_pct: int = int(round(chance * 100.0))
	var roll_pct: int = int(round(roll * 100.0))

	var ow_count: int = result.get("overwhelm_count", 0)
	var ow_bonus_pct: int = int(round(float(result.get("overwhelm_bonus", 0.0)) * 100.0))
	var ow_tag: String = ""
	if ow_count > 0 and ow_bonus_pct > 0:
		ow_tag = "[color=#5BC8FF][围攻+%d][/color] " % ow_bonus_pct

	if not result.get("hit", false):
		var reason: String = result.get("miss_reason", "miss")
		if reason == "block":
			var bc: int = int(round(float(result.get("block_pts", result.get("block_chance", 0.0) * 100.0))))
			return "%s%s[color=#7BA8C9]%s 使用%s攻击 %s，被格挡（格挡:%d，几率:%d，掷出:%d）[/color]" % [
				prefix, ow_tag, attacker, weapon_name, target, bc, chance_pct, roll_pct
			]
		if reason == "dodge":
			var dc: int = int(round(float(result.get("dodge_pts", result.get("dodge_chance", 0.0) * 100.0))))
			return "%s%s[color=#9AD4A0]%s 使用%s攻击 %s，被闪避（闪避:%d，几率:%d，掷出:%d）[/color]" % [
				prefix, ow_tag, attacker, weapon_name, target, dc, chance_pct, roll_pct
			]
		if reason == "miss":
			var def_pts: int = int(round(float(result.get("defense_pts", result.get("final_def", 0.0)))))
			return "%s%s[color=#888888]%s 使用%s攻击 %s，未命中（防御:%d，几率:%d，掷出:%d）[/color]" % [
				prefix, ow_tag, attacker, weapon_name, target, def_pts, chance_pct, roll_pct
			]
		return "%s%s[color=#888888]%s 使用%s攻击 %s，未命中（几率:%d，掷出:%d）[/color]" % [
			prefix, ow_tag, attacker, weapon_name, target, chance_pct, roll_pct
		]

	var loc: String = result.get("hit_location", "body")
	var loc_cn: String = "头部" if loc == "head" else "身体"
	var armor_state: String = result.get("armor_state", "intact")
	var armor_dmg: int = result.get("armor_damage", 0)
	var hp_dmg: int = result.get("hp_damage", 0)
	var lethal: bool = result.get("lethal", false)
	var is_crit: bool = result.get("critical", false)
	var crit_tag: String = "[color=#FFD86B][b]【重击！】[/b][/color] " if is_crit else ""
	var mode_tag: String = ""
	if mode != "":
		mode_tag = "[color=#A0A0A0][%s][/color] " % mode

	var line1: String = "%s%s%s%s[color=#D4AF37]%s 使用%s击中了 %s 的%s[/color]（几率:%d，掷出:%d）" % [
		prefix, ow_tag, mode_tag, crit_tag, attacker, weapon_name, target, loc_cn, chance_pct, roll_pct
	]

	var armor_phrase: String = ""
	match armor_state:
		"no_armor":
			armor_phrase = "%s该部位无甲" % target
		"ignored":
			armor_phrase = "[color=#C44CFF]无视护甲[/color]"
		"broken":
			armor_phrase = "[color=#FFB347]%s 的%s甲被击穿[/color]（甲值 -%d）" % [target, loc_cn, armor_dmg]
		"damaged":
			armor_phrase = "%s 的%s甲破损（甲值 -%d）" % [target, loc_cn, armor_dmg]
		_:
			armor_phrase = "%s 的%s甲承受了攻击（甲值 -%d）" % [target, loc_cn, armor_dmg]

	var hp_phrase: String = "受到 [color=#D94A4A]%d[/color] 点伤害" % hp_dmg
	if lethal:
		hp_phrase += " — [color=#A03030]致命一击[/color]"

	return line1 + "\n    " + armor_phrase + "，" + hp_phrase
