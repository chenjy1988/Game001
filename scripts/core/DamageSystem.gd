extends RefCounted
class_name DamageSystem

const _CombatModifier = preload("res://scripts/core/CombatModifier.gd")
##
## DamageSystem.gd — 战斗模型 v3.1 伤害管线（纯静态工具类）
##
## 实现 design/weapon-system.md § 6.1 的 9 步流程：
##   Step 1: 选攻击模式（attack_modes[0]，能力框架就绪后由 Ability 注入）
##   Step 2: 命中检定（减法制 + 围攻 + 攻击类型修正 + 高地/距离 - 预留）
##   Step 3: 格挡检定（独立概率，weapon.block_value）
##   Step 4: 部位检定（单手 25% / 双手 15% / 瞄头 70% / 精准 50% 等）
##   Step 5: 暴击检定（5 + 武器 + 精通 + max(0,wisdom-40)*0.2，软上限 50%）
##   Step 6: 基础伤害（damage_base × 气力档 × 微波 × 专精 × 词条 × 能力 × 双手握持）
##   Step 7: 暴击 + 头部加法叠加（× 1.0 / 1.5 / 1.5 / 2.0）
##   Step 8: 伤害分配（甲伤×armor_mult；透甲=实际扣甲×渗透率；击穿后=(final−扣甲)×hp_mult）
##   Step 9: 气力消耗（base_stamina × weight_mult + 隐藏气力消耗，由 Unit 实际扣减）
##
## 互斥规则：一次攻击只能选 1 个职业能力。当前未接入能力框架时默认普攻。
##

# ──────────── 命中相关常量 ────────────
const HIT_CHANCE_MIN: float = 0.05
const HIT_CHANCE_MAX: float = 0.95

# Overwhelm（围攻）
const OVERWHELM_PER_ALLY: float = 0.05
const OVERWHELM_MAX: float = 0.25        ## 上限 25%（原 20%）

# 地形修正
const HIT_BONUS_HIGH_GROUND: float = 0.15  ## 高地打低地 +15%

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

# ──────────── 受击疲劳（design.md § 三 气力系统） ────────────
## 被攻击基础气力消耗（命中/闪避/格挡均触发）
const DEFEND_FATIGUE_BASE: int = 2

## 计算防守方被攻击时的气力消耗：ceil(base × weight_mult)
## weight_mult = 1 + target_total_weight × 0.02
static func calculate_defend_fatigue(target: Unit) -> int:
	if target == null:
		return 0
	var total_weight: int = target.get_total_weight()
	var weight_mult: float = 1.0 + float(total_weight) * 0.02
	return int(ceil(float(DEFEND_FATIGUE_BASE) * weight_mult))

# ──────────── 气力档位 → 伤害系数 ────────────

# ──────────── 微小波动 ────────────
const DAMAGE_JITTER: Vector2 = Vector2(0.95, 1.05)


# =====================================================================
# 公开接口
# =====================================================================

## 数攻击方阵营、与目标相邻、且不是攻击者自己的单位个数。用于 Overwhelm。
static func count_overwhelm_allies(attacker: Unit, target: Unit) -> int:
	if attacker == null or target == null:
		return 0
	if attacker.hex_grid == null:
		return 0
	var faction: int = attacker.get_faction()
	var n: int = 0
	for cell in HexCoord.neighbors(target.axial_pos):
		var u = attacker.hex_grid.get_occupant(cell)
		if u == null or u == attacker:
			continue
		if not u.is_alive():
			continue
		if u.get_faction() == faction:
			n += 1
	return n


## 计算命中率（0~1）。BattleAI / UnitTooltip 调用。
## Hit% = (atk - def)/100 + 围攻 + 地形 + 技能修正 + buff/debuff修正
## 攻击类型不再有命中修正（已移除）
static func calculate_hit_chance(attacker: Unit, target: Unit, options: Dictionary = {}) -> float:
	# 基础：攻防差
	var atk: float = float(attacker.stats.melee_skill) \
		if attacker.weapon == null or attacker.weapon.weapon_type == "melee" \
		else float(attacker.stats.ranged_skill)
	# 防御：基础 defense 递减 + 目标武器 block + dodge（由 Stats.effective_defense 统一处理）
	var target_block: int = target.weapon.block_value if target.weapon else 0
	var def: float = target.stats.effective_defense(target_block)
	var raw: float = (atk - def) / 100.0

	# 围攻加成（上限 25%）
	var allies: int = count_overwhelm_allies(attacker, target)
	var overwhelm_bonus: float = min(float(allies) * OVERWHELM_PER_ALLY, OVERWHELM_MAX)

	# 地形修正：高地打低地 +15%
	var terrain_bonus: float = 0.0
	if attacker.hex_grid != null:
		var atk_elev: int = attacker.hex_grid.get_elevation(attacker.axial_pos)
		var def_elev: int = attacker.hex_grid.get_elevation(target.axial_pos)
		if atk_elev > def_elev:
			terrain_bonus = HIT_BONUS_HIGH_GROUND

	# 技能修正（ability_hit_modifier 单位：百分点，如 +15 / -10）
	var skill_bonus: float = float(options.get("ability_hit_modifier", 0)) / 100.0

	# Buff/Debuff 修正（气力档 + 手拙等，经 get_active_debuffs 汇总）
	var status_bonus: float = 0.0
	if attacker is Unit:
		status_bonus += _CombatModifier.sum_hit_pct(attacker.get_active_debuffs())
	elif attacker.stats != null:
		status_bonus += attacker.stats.get_hit_modifier()

	return clamp(raw + overwhelm_bonus + terrain_bonus + skill_bonus + status_bonus,
		HIT_CHANCE_MIN, HIT_CHANCE_MAX)


## 计算暴击率（0~1）—— A3 公式
##   crit% = 5（基础）+ 武器加成 + 武器精通 + max(0, wisdom-40) * 0.2
##   软上限 50%
##   武器精通系数尚未接入（B3）；当前从 weapon.bonus_crit_chance 兼容旧字段
static func calculate_crit_chance(attacker: Unit) -> float:
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
static func stamina_tier_multiplier(stats: Stats) -> float:
	return _CombatModifier.roll_stamina_damage_mult(stats)


## 武器渗透 weight_modifier
static func weight_modifier_for(weapon: WeaponData) -> float:
	if weapon == null:
		return 1.0
	return weapon.weight_modifier()


## UI 用：主模式渗透率预览（base_pen × weight_modifier）
static func penetration_rate_for(weapon: WeaponData, mode: String = "") -> float:
	if weapon == null:
		return 0.0
	var m: String = mode
	if m.is_empty():
		m = weapon.attack_modes[0] if not weapon.attack_modes.is_empty() else "slash"
	return BASE_PEN_BY_TYPE.get(m, 0.10) * weight_modifier_for(weapon)


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
static func execute_attack(attacker: Unit, target: Unit, options: Dictionary = {}) -> Dictionary:
	var weapon: WeaponData = attacker.weapon

	# ── Step 1：选模式 ──
	var mode: String = options.get("mode", weapon.primary_mode() if weapon else "slash")

	# ── Step 2：命中检定 ──
	var hit_chance: float = calculate_hit_chance(attacker, target, options)

	var hit_roll: float = randf()
	var did_hit: bool = hit_roll < hit_chance

	var overwhelm_count: int = count_overwhelm_allies(attacker, target)
	var overwhelm_bonus: float = min(float(overwhelm_count) * OVERWHELM_PER_ALLY, OVERWHELM_MAX)

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
		# ── v3.1 新字段 ──
		"attack_mode": mode,
		"blocked": false,
		"block_chance": 0.0,
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
		return result

	# ── Step 3：格挡（仅当目标装备的武器有 block_value 或盾）──
	var block_chance: float = 0.0
	if target.weapon != null:
		# block_value 是百分点（例：盾 25 = 25%）
		block_chance = float(target.weapon.block_value) / 100.0
	# TODO: 盾牌 base_block 累加（armor.combat_style == "shield" 时）
	result["block_chance"] = block_chance
	if block_chance > 0.0 and randf() < block_chance:
		result["blocked"] = true
		result["armor_state"] = "blocked"
		return result

	# ── Step 4：部位检定 ──
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

	# ── Step 5：暴击检定（独立于部位）──
	var crit_chance: float = calculate_crit_chance(attacker)
	# 武器精通额外暴击（B3 接入 JobClass 后传入）
	crit_chance += float(options.get("mastery_crit_bonus", 0.0)) / 100.0
	crit_chance = clamp(crit_chance, 0.0, CRIT_SOFT_CAP / 100.0)
	var is_crit: bool = randf() < crit_chance
	result["critical"] = is_crit
	result["crit_chance"] = crit_chance

	# ── Step 6：基础伤害 ──
	var damage_base: int = weapon.damage_base if (weapon and weapon.damage_base > 0) else weapon.roll_base_damage()
	var stamina_mult: float = _CombatModifier.roll_damage_mult(attacker.get_active_debuffs()) \
		if attacker is Unit \
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

	# Step 9 气力消耗：由 Unit/Ability 在外层处理（attacker.consume_ap_fatigue）
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

	# Miss
	if not result.get("hit", false):
		return "%s%s[color=#888888]%s 使用%s攻击 %s，未命中（几率:%d，掷出:%d）[/color]" % [
			prefix, ow_tag, attacker, weapon_name, target, chance_pct, roll_pct
		]

	# Block
	if result.get("blocked", false):
		var bc: int = int(round(float(result.get("block_chance", 0.0)) * 100.0))
		return "%s%s[color=#7BA8C9]%s 使用%s攻击 %s，被格挡（格挡几率:%d）[/color]" % [
			prefix, ow_tag, attacker, weapon_name, target, bc
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
