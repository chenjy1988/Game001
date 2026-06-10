extends SceneTree
##
## test_damage_system.gd — DamageSystem v3.1 自检
##
## 跑法：
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --script scripts/tools/test_damage_system.gd --headless
##
## 验证项：
##   T1. weight_modifier 公式：1 + max(0, (weight-4)/6)
##   T2. ARMOR_MULT / HP_MULT / BASE_PEN 表查询正确
##   T3. 暴击率公式：5 + max(0, wisdom-40)*0.2，软上限 50%
##   T4. 气力档位系数：>50% 满 / 20-50% 中疲劳 / 0-20% 低气力
##   T5. 多次 execute_attack 跑陌刀手 vs 重甲（Slash 普攻）期望 base_damage ≈ 文档 § 6.4
##   T6. 多次 execute_attack 跑跳荡 + 长矛 vs 中甲（Pierce 普攻）期望伤害符合
##

class TestUnit extends Unit:
	func _init(name: String, melee_skill: int = 60, defense_val: int = 30, fatigue: int = 0,
			max_hp: int = 60, head_armor: int = 0, body_armor: int = 0,
			weapon_id: String = "", armor_id: String = "", wisdom: int = 30,
			faction_id: int = 0) -> void:
		stats = Stats.new()
		stats.unit_name = name
		stats.melee_skill = melee_skill
		stats.ranged_skill = melee_skill
		stats.defense = defense_val
		stats.melee_defense = defense_val
		stats.ranged_defense = defense_val
		stats.max_hp = max_hp
		stats.max_head_armor = head_armor
		stats.max_body_armor = body_armor
		stats.wisdom = wisdom
		stats.faction = faction_id
		stats.init_runtime(0)
		stats.fatigue = fatigue
		# 武器/护甲通过 SceneTree 取 autoload（class_name WeaponArmorDB 在 SceneTree 子脚本内不可直接访问）
		var db: Node = Engine.get_main_loop().get_root().get_node_or_null("WeaponArmorDB")
		if weapon_id != "" and db != null:
			weapon = db.call("get_weapon", weapon_id)
		if armor_id != "" and db != null:
			armor = db.call("get_armor", armor_id)


var pass_count: int = 0
var fail_count: int = 0


func _initialize() -> void:
	print("=== DamageSystem v3.1 自检 ===\n")
	# autoload 的 _ready 在 SceneTree --script 模式下排在 _initialize 之后才执行；
	# 手动触发让 _weapons / _armors 现在就可用
	var db: Node = get_root().get_node_or_null("WeaponArmorDB")
	if db != null and db.call("get_weapon", "modao") == null:
		db.call("_load_weapons")
		db.call("_load_armors")
	_t1_weight_modifier()
	_t2_lookup_tables()
	_t3_crit_chance()
	_t4_stamina_tier()
	_t5_modao_vs_heavy_armor()
	_t6_javelin_vs_mid_armor()
	print("\n──────── 总结 ────────")
	print("PASS %d / FAIL %d" % [pass_count, fail_count])
	if fail_count > 0:
		print("❌ 有失败用例")
		quit(1)
	else:
		print("✅ 全部通过")
		quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		pass_count += 1
		print("  [PASS] " + msg)
	else:
		fail_count += 1
		print("  [FAIL] " + msg)


func _approx(a: float, b: float, tol: float = 0.01) -> bool:
	return abs(a - b) <= tol


# ────────────────────────────── tests ──────────────────────────────

func _t1_weight_modifier() -> void:
	print("[T1] weight_modifier")
	var w := WeaponData.new()
	w.weight = 4
	_expect(_approx(w.weight_modifier(), 1.0), "weight 4 → 1.0，实际 %.3f" % w.weight_modifier())
	w.weight = 14   # 陌刀
	_expect(_approx(w.weight_modifier(), 2.667, 0.01), "weight 14 → 2.667，实际 %.3f" % w.weight_modifier())
	w.weight = 16   # 双手战锤
	_expect(_approx(w.weight_modifier(), 3.0), "weight 16 → 3.0，实际 %.3f" % w.weight_modifier())
	w.weight = 0    # 匕首
	_expect(_approx(w.weight_modifier(), 1.0), "weight 0 → 1.0，实际 %.3f" % w.weight_modifier())


func _t2_lookup_tables() -> void:
	print("[T2] ARMOR_MULT / HP_MULT / BASE_PEN")
	_expect(DamageSystem.ARMOR_MULT_BY_TYPE["slash"] == 1.0, "Slash armor_mult = 1.0")
	_expect(DamageSystem.ARMOR_MULT_BY_TYPE["pierce"] == 0.7, "Pierce armor_mult = 0.7")
	_expect(DamageSystem.ARMOR_MULT_BY_TYPE["crush"] == 1.5, "Crush armor_mult = 1.5")
	_expect(DamageSystem.HP_MULT_BY_TYPE["slash"] == 1.0, "Slash hp_mult = 1.0")
	_expect(DamageSystem.HP_MULT_BY_TYPE["crush"] == 0.7, "Crush hp_mult = 0.7")
	_expect(DamageSystem.BASE_PEN_BY_TYPE["slash"] == 0.10, "Slash base_pen = 0.10")
	_expect(DamageSystem.BASE_PEN_BY_TYPE["pierce"] == 0.15, "Pierce base_pen = 0.15")
	_expect(DamageSystem.BASE_PEN_BY_TYPE["crush"] == 0.08, "Crush base_pen = 0.08")


func _t3_crit_chance() -> void:
	print("[T3] 暴击率公式（5 + max(0,wisdom-40)*0.2，软上限 50%%）")
	# 武器为 null 时也要可工作
	var u30 := TestUnit.new("LowWisdom", 60, 30, 0, 60, 0, 0, "", "", 30)
	u30.weapon = null
	get_root().add_child(u30)
	_expect(_approx(DamageSystem.calculate_crit_chance(u30), 0.05, 0.001),
		"wisdom=30 → 5pct，实际 %.3f" % DamageSystem.calculate_crit_chance(u30))
	var u60 := TestUnit.new("MidWisdom", 60, 30, 0, 60, 0, 0, "", "", 60)
	u60.weapon = null
	get_root().add_child(u60)
	# 5 + (60-40)*0.2 = 5 + 4 = 9
	_expect(_approx(DamageSystem.calculate_crit_chance(u60), 0.09, 0.001),
		"wisdom=60 → 9pct，实际 %.3f" % DamageSystem.calculate_crit_chance(u60))
	var u200 := TestUnit.new("HighWisdom", 60, 30, 0, 60, 0, 0, "", "", 300)
	u200.weapon = null
	get_root().add_child(u200)
	# 5 + (300-40)*0.2 = 5 + 52 = 57 → cap 50%
	_expect(_approx(DamageSystem.calculate_crit_chance(u200), 0.5, 0.001),
		"wisdom=300 → 50pct (cap)，实际 %.3f" % DamageSystem.calculate_crit_chance(u200))
	u30.queue_free()
	u60.queue_free()
	u200.queue_free()


func _t4_stamina_tier() -> void:
	print("[T4] 气力档位系数")
	var s := Stats.new()
	s.max_stamina = 100
	s.fatigue = 0   # 满气力（剩余 100%）
	_expect(DamageSystem.stamina_tier_multiplier(s) == 1.0, "满气力 → 1.0")
	s.fatigue = 100   # 力竭
	var exhausted := DamageSystem.stamina_tier_multiplier(s)
	_expect(exhausted >= 0.70 and exhausted <= 0.80, "力竭 ∈ [0.70,0.80]，实际 %.3f" % exhausted)
	s.fatigue = 60    # 剩 40%（中度疲劳，0.80~0.90）
	var mid := DamageSystem.stamina_tier_multiplier(s)
	_expect(mid >= 0.80 and mid <= 0.90, "中度疲劳 ∈ [0.80,0.90]，实际 %.3f" % mid)
	s.fatigue = 90    # 剩 10%（低气力，0.70~0.80）
	var low := DamageSystem.stamina_tier_multiplier(s)
	_expect(low >= 0.70 and low <= 0.80, "低气力 ∈ [0.70,0.80]，实际 %.3f" % low)
	s.fatigue = 0
	_expect(_approx(s.get_hit_modifier(), 0.0), "满气力命中修正 = 0")
	_expect(_approx(s.get_defense_modifier(), 0.0), "满气力防御修正 = 0")
	s.fatigue = 60
	_expect(_approx(s.get_hit_modifier(), -0.05), "剩余 40% 气力命中修正 = -5%")
	_expect(_approx(s.get_defense_modifier(), -5.0), "剩余 40% 气力防御修正 = -5")
	s.fatigue = 90
	_expect(_approx(s.get_hit_modifier(), -0.10), "剩余 10% 气力命中修正 = -10%")
	_expect(_approx(s.get_defense_modifier(), -10.0), "剩余 10% 气力防御修正 = -10")
	s.fatigue = 100
	_expect(_approx(s.get_hit_modifier(), -0.10), "力竭命中修正 = -10%")
	_expect(_approx(s.get_defense_modifier(), -10.0), "力竭防御修正 = -10")


## 模拟"陌刀手 + 陌刀（Slash）打重甲"期望 base 在文档 § 6.4 范围
##   期望 base = weapon.damage_base × 1.0（满气力）× 1.2（精通）× jitter ±5%
##   当前 data/weapons.json 陌刀 damage_base=85 → 名义 102，区间 [96.9, 107.1]
func _t5_modao_vs_heavy_armor() -> void:
	print("[T5] 陌刀手 vs 重甲：均值符合 § 6.4")
	var atk := TestUnit.new("Modao", 80, 30, 0, 60, 0, 0, "modao", "", 30, 0)
	# 重甲：head 140 / body 200（文档示例）；横刀提供 block，格挡计入命中统计
	var dst := TestUnit.new("Heavy", 50, 30, 0, 130, 140, 200, "saber", "", 30, 1)
	get_root().add_child(atk)
	get_root().add_child(dst)

	if atk.weapon == null:
		_expect(false, "无法加载 modao 武器")
		atk.queue_free()
		dst.queue_free()
		return

	var mastery_dmg: float = 1.2
	var nominal: float = float(atk.weapon.damage_base) * mastery_dmg
	var low: float = nominal * 0.95
	var high: float = nominal * 1.05
	var hit_chance: float = DamageSystem.calculate_hit_chance(atk, dst, {"mode": "slash"})
	var block_chance: float = float(dst.weapon.block_value) / 100.0 if dst.weapon else 0.0
	var pass_rate: float = hit_chance * (1.0 - block_chance)

	# 跑 200 次，统计命中后 base_damage 均值（精通 1.2 系数 + 满气力）
	var samples: Array[int] = []
	var hits: int = 0
	for i in range(200):
		dst.stats.head_armor = 140
		dst.stats.body_armor = 200
		var r: Dictionary = DamageSystem.execute_attack(atk, dst, {
			"mastery_dmg": mastery_dmg,
			"mode": "slash",
		})
		if r.get("hit", false) and not r.get("blocked", false):
			samples.append(int(r.get("base_damage", 0)))
			hits += 1
	var avg: float = 0.0
	for v in samples:
		avg += float(v)
	avg = avg / max(1, samples.size())
	_expect(avg >= low and avg <= high,
		"base 均值 ≈ %.1f (±5%% jitter)，实际 %.2f（样本 %d）" % [nominal, avg, samples.size()])
	# 命中且未被格挡：200 × hit_chance × (1 - block)，允许 ±30% 随机波动
	var min_hits: int = int(200.0 * pass_rate * 0.7)
	_expect(hits >= min_hits, "200 次至少 %d 命中，实际 %d（hit=%.0f%%, block=%.0f%%）" % [
		min_hits, hits, hit_chance * 100.0, block_chance * 100.0])

	# 单次精确演示：固定 mastery_dmg = 1.2 + 强制头部 + force "命中" 不容易（randf 内部）；
	# 转而验证 weight_modifier 在 result 中正确：
	var demo: Dictionary = DamageSystem.execute_attack(atk, dst, {"mastery_dmg": 1.2, "mode": "slash"})
	_expect(_approx(float(demo.get("weight_modifier", 0)), 2.667, 0.01),
		"陌刀 weight_modifier=2.667，实际 %.3f" % float(demo.get("weight_modifier", 0)))
	_expect(_approx(float(demo.get("base_pen", 0)), 0.10),
		"Slash base_pen=0.10，实际 %.3f" % float(demo.get("base_pen", 0)))

	atk.queue_free()
	dst.queue_free()


## 跳荡 + 长矛（Pierce）vs 中甲：weight 12 → mod 2.333，pen_rate = 0.15 × 2.333 = 0.35
func _t6_javelin_vs_mid_armor() -> void:
	print("[T6] 跳荡 + 长矛 vs 中甲：渗透 0.35")
	var atk := TestUnit.new("Tiao", 60, 30, 0, 60, 0, 0, "spear", "", 30, 0)
	var dst := TestUnit.new("Mid", 50, 30, 0, 90, 80, 130, "saber", "", 30, 1)
	get_root().add_child(atk)
	get_root().add_child(dst)

	if atk.weapon == null:
		_expect(false, "无法加载 spear 武器")
		atk.queue_free(); dst.queue_free()
		return

	# 长矛 weight 12 → mod = 1 + (12-4)/6 = 2.333
	_expect(_approx(atk.weapon.weight_modifier(), 2.333, 0.01),
		"长矛 weight_modifier=2.333，实际 %.3f" % atk.weapon.weight_modifier())
	# Pierce 普攻：pen_rate = 0.15 × 2.333 = 0.35；透甲 HP = 甲伤 × pen_rate
	var demo: Dictionary = DamageSystem.execute_attack(atk, dst, {"mode": "pierce"})
	if demo.get("hit", false) and not demo.get("blocked", false):
		if not demo.get("critical", false):
			_expect(_approx(float(demo.get("penetration_rate", 0)), 0.35, 0.01),
				"Pierce 普攻 pen_rate=0.35，实际 %.3f" % float(demo.get("penetration_rate", 0)))
			var armor_dmg: float = float(demo.get("armor_damage", 0))
			var pen_hp: float = float(demo.get("penetration_hp", 0))
			if armor_dmg > 0 and demo.get("armor_state") != "broken":
				_expect(_approx(pen_hp / armor_dmg, 0.35, 0.02),
					"未击穿：透甲 HP = 实际扣甲×35%%，实际 pen/扣甲=%.3f" % (pen_hp / armor_dmg))
	# armor_mult / hp_mult 验证
	_expect(_approx(float(demo.get("armor_mult", 0)), 0.7),
		"Pierce armor_mult=0.7，实际 %.3f" % float(demo.get("armor_mult", 0)))
	_expect(_approx(float(demo.get("hp_mult", 0)), 1.0),
		"Pierce hp_mult=1.0，实际 %.3f" % float(demo.get("hp_mult", 0)))

	atk.queue_free()
	dst.queue_free()
