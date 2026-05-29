extends RefCounted
class_name DamageSystem
##
## DamageSystem.gd — 战兄弟风格三段式伤害管线（纯静态工具类）
##
## 流程：
##   1) 命中判定：hit_chance = clamp(攻击者近战 - 防御者有效近战防御, 5, 95)
##   2) 命中部位：head ~ 5% / body ~ 95%
##   3) 基础伤害 = 武器 roll
##   4) 对甲伤害 = 基础 × 武器对甲效率 → 扣相应部位护甲
##   5) 穿甲伤害 = 基础 × 武器穿甲率 → 直接进入 HP 池
##   6) 非穿甲剩余部分被剩余护甲(扣前)的 10% 抵消
##   7) HP 伤害 = 穿甲 + (1 - armor_pen) × 基础 × armor_factor，头部再 ×1.5
##

const HEAD_HIT_CHANCE: float = 0.05  ## 头部命中概率（战兄弟约 5%）
const HIT_CHANCE_MIN: float = 0.05
const HIT_CHANCE_MAX: float = 0.95


## 计算命中率（0-1）
static func calculate_hit_chance(attacker: Unit, target: Unit) -> float:
	var atk: float = float(attacker.stats.melee_skill)
	var def: float = target.stats.effective_melee_defense()
	var raw: float = (atk - def) / 100.0
	return clamp(raw, HIT_CHANCE_MIN, HIT_CHANCE_MAX)


## 执行一次完整攻击 → 返回 result 字典
## 字段：hit, hit_location, base_damage, armor_damage, hp_damage, hit_chance, location_label
static func execute_attack(attacker: Unit, target: Unit) -> Dictionary:
	var hit_chance: float = calculate_hit_chance(attacker, target)
	var roll: float = randf()
	var did_hit: bool = roll < hit_chance

	var result: Dictionary = {
		"attacker_name": attacker.get_unit_name(),
		"target_name": target.get_unit_name(),
		"hit_chance": hit_chance,
		"roll": roll,
		"hit": did_hit,
		"hit_location": "body",
		"base_damage": 0,
		"armor_damage": 0,
		"hp_damage": 0,
	}
	if not did_hit:
		return result

	# 命中部位
	var loc: String = "head" if randf() < HEAD_HIT_CHANCE else "body"
	result["hit_location"] = loc

	# 基础伤害
	var weapon: WeaponData = attacker.weapon
	var base_dmg: int = weapon.roll_base_damage()
	result["base_damage"] = base_dmg

	# 1) 对甲伤害（扣对应部位护甲）
	var armor_dmg_raw: int = int(round(float(base_dmg) * weapon.armor_effectiveness))
	var current_armor: int = target.stats.head_armor if loc == "head" else target.stats.body_armor
	var armor_actually_taken: int = min(current_armor, armor_dmg_raw)
	result["armor_damage"] = armor_actually_taken
	var armor_remaining_after: int = current_armor - armor_actually_taken

	# 2) 穿甲伤害（直接进 HP）
	var pen_dmg: float = float(base_dmg) * weapon.armor_penetration

	# 3) 非穿甲剩余伤害 = 基础 × (1 - 穿甲率)；被剩余护甲 10% 抵消
	var non_pen_raw: float = float(base_dmg) * (1.0 - weapon.armor_penetration)
	# 仅当目标还有护甲时，才有 10% 抵消
	var armor_factor: float = 1.0
	if armor_remaining_after > 0:
		# 战兄弟规则：剩余护甲值 / 100 × 10% = 减伤比例（粗略）；这里简化为 fixed 10% off
		armor_factor = 0.9
	# 如果对甲伤害已经把护甲打穿（current_armor < armor_dmg_raw），多余的对甲伤害也会渗透到 HP（用 1.0 处理）
	var overflow_to_hp: float = 0.0
	if armor_dmg_raw > current_armor:
		overflow_to_hp = float(armor_dmg_raw - current_armor) * 0.33  # 溢出按 1/3 进 HP（避免破甲一次秒杀）

	var hp_damage_f: float = pen_dmg + non_pen_raw * armor_factor + overflow_to_hp
	# 头部 ×1.5
	if loc == "head":
		hp_damage_f *= weapon.head_damage_mult

	var hp_dmg: int = max(1, int(round(hp_damage_f))) if did_hit else 0
	# 但如果完全没破甲且穿甲率 0（典型钝器砸全甲），HP 伤害可能很低，这是设计预期
	result["hp_damage"] = hp_dmg
	return result


## 用于 UI 显示的格式化日志
static func format_attack_log(result: Dictionary) -> String:
	if result.is_empty():
		return ""
	var attacker: String = result.get("attacker_name", "?")
	var target: String = result.get("target_name", "?")
	var chance: float = result.get("hit_chance", 0.0)
	var oa: bool = result.get("is_opportunity_attack", false)
	var prefix: String = "[color=#FF8C42][借机攻击][/color] " if oa else ""
	if not result.get("hit", false):
		return "%s[color=#888888]%s 攻击 %s — Miss (命中%.0f%%)[/color]" % [prefix, attacker, target, chance * 100]
	var loc: String = result.get("hit_location", "body")
	var loc_cn: String = "头部" if loc == "head" else "身体"
	var armor_dmg: int = result.get("armor_damage", 0)
	var hp_dmg: int = result.get("hp_damage", 0)
	return "%s[color=#D4AF37]%s 命中 %s 的%s[/color] — 护甲 -%d  生命 [color=#D94A4A]-%d[/color]" % [
		prefix, attacker, target, loc_cn, armor_dmg, hp_dmg
	]
