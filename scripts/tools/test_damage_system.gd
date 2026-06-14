extends SceneTree
##
## test_damage_system.gd — DamageSystem v3.2 自检
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
		stats.init_runtime()
		stats.stamina = max(0, stats.max_stamina - (fatigue))
		# 武器/护甲通过 SceneTree 取 autoload（class_name WeaponArmorDB 在 SceneTree 子脚本内不可直接访问）
		var db: Node = Engine.get_main_loop().get_root().get_node_or_null("WeaponArmorDB")
		if weapon_id != "" and db != null:
			weapon = db.call("get_weapon", weapon_id)
		if armor_id != "" and db != null:
			armor = db.call("get_armor", armor_id)


var pass_count: int = 0
var fail_count: int = 0


func _initialize() -> void:
	print("=== DamageSystem v3.2 自检 ===\n")
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
	_t4b_stamina_weight_cost()
	_t5_modao_vs_heavy_armor()
	_t6_javelin_vs_mid_armor()
	_t_def_breakdown()
	_t_penalty()
	_t_miss_attrib()
	_t_ignore_dodge_block()
	_t_equipment_block()
	_t_nimble_body_dodge()
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
	s.stamina = 100   # 满气力
	_expect(DamageSystem.stamina_tier_multiplier(s) == 1.0, "满气力 → 1.0")
	s.stamina = 0   # 力竭
	var exhausted := DamageSystem.stamina_tier_multiplier(s)
	_expect(exhausted >= 0.70 and exhausted <= 0.80, "力竭 ∈ [0.70,0.80]，实际 %.3f" % exhausted)
	s.stamina = 40    # 剩 40%（中度疲劳，0.80~0.90）
	var mid := DamageSystem.stamina_tier_multiplier(s)
	_expect(mid >= 0.80 and mid <= 0.90, "中度疲劳 ∈ [0.80,0.90]，实际 %.3f" % mid)
	s.stamina = 10    # 剩 10%（低气力，0.70~0.80）
	var low := DamageSystem.stamina_tier_multiplier(s)
	_expect(low >= 0.70 and low <= 0.80, "低气力 ∈ [0.70,0.80]，实际 %.3f" % low)
	s.stamina = 100
	_expect(_approx(s.get_hit_modifier(), 0.0), "满气力命中修正 = 0")
	_expect(_approx(s.get_defense_modifier(), 0.0), "满气力防御修正 = 0")
	s.stamina = 40
	_expect(_approx(s.get_hit_modifier(), -0.10), "剩余 40% 气力命中修正 = -10%")
	_expect(_approx(s.get_defense_modifier(), -5.0), "剩余 40% 气力防御修正 = -5")
	s.stamina = 10
	_expect(_approx(s.get_hit_modifier(), -0.20), "剩余 10% 气力命中修正 = -20%")
	_expect(_approx(s.get_defense_modifier(), -10.0), "剩余 10% 气力防御修正 = -10")
	s.stamina = 0
	_expect(_approx(s.get_hit_modifier(), -0.20), "力竭命中修正 = -20%")
	_expect(_approx(s.get_defense_modifier(), -10.0), "力竭防御修正 = -10")


func _t4b_stamina_weight_cost() -> void:
	print("[T4b] 气力消耗 × weight_mult（design.md §三）")
	var light = TestUnit.new("轻", 60, 30, 0, 60, 0, 0, "saber", "leather_armor")
	# saber 6 + 皮甲 8 = 14 → mult 1.28
	_expect(DamageSystem.attack_stamina_base_for(light) == 4, "横刀单手普攻 base=4")
	var atk_light: int = DamageSystem.calculate_attack_stamina_cost(light)
	_expect(atk_light == 6, "轻甲横刀普攻 ceil(4×1.28)=6，实际 %d" % atk_light)
	var heavy = TestUnit.new("重", 60, 30, 0, 60, 0, 0, "battle_axe", "plate_armor")
	# 战斧14+札甲35=49 → mult 1.98
	_expect(DamageSystem.attack_stamina_base_for(heavy) == 6, "双手战斧普攻 base=6")
	var atk_heavy: int = DamageSystem.calculate_attack_stamina_cost(heavy)
	_expect(atk_heavy == 12, "重甲战斧普攻 ceil(6×1.98)=12，实际 %d" % atk_heavy)
	var bow = TestUnit.new("弓", 60, 30, 0, 60, 0, 0, "bow", "leather_armor")
	# bow 4 + 皮甲 8 = 12 → mult 1.24
	_expect(DamageSystem.attack_stamina_base_for(bow) == 5, "步弓射击 base=5")
	_expect(DamageSystem.calculate_attack_stamina_cost(bow) == 7, "轻甲步弓 ceil(5×1.24)=7，实际 %d" % DamageSystem.calculate_attack_stamina_cost(bow))
	var xbow = TestUnit.new("弩", 60, 30, 0, 60, 0, 0, "crossbow", "leather_armor")
	# crossbow 12 + 皮甲 8 = 20 → mult 1.40
	_expect(DamageSystem.attack_stamina_base_for(xbow) == 5, "弩射击 base=5")
	_expect(DamageSystem.calculate_attack_stamina_cost(xbow) == 7, "轻甲弩射 ceil(5×1.36)=7，实际 %d" % DamageSystem.calculate_attack_stamina_cost(xbow))
	_expect(DamageSystem.reload_stamina_base_for(xbow) == 10, "弩上弦 base=10")
	_expect(DamageSystem.calculate_reload_stamina_cost(xbow) == 14, "轻甲弩上弦 ceil(10×1.40)=14，实际 %d" % DamageSystem.calculate_reload_stamina_cost(xbow))
	_expect(DamageSystem.calculate_reload_stamina_cost(bow) == 0, "弓无上弦气力")
	var move_heavy: int = DamageSystem.calculate_action_stamina_cost(heavy, DamageSystem.MOVE_STAMINA_BASE)
	_expect(move_heavy == 4, "重甲移动 ceil(2×1.98)=4，实际 %d" % move_heavy)
	var def_heavy: int = DamageSystem.calculate_defend_stamina_cost(heavy)
	_expect(def_heavy == 4, "重甲受击 ceil(2×1.98)=4，实际 %d" % def_heavy)
	light.queue_free()
	heavy.queue_free()
	bow.queue_free()
	xbow.queue_free()


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
	var block_chance: float = DamageSystem.target_block_chance(dst, {"mode": "slash"})
	var pass_rate: float = hit_chance

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
		if r.get("hit", false):
			samples.append(int(r.get("base_damage", 0)))
			hits += 1
	var avg: float = 0.0
	for v in samples:
		avg += float(v)
	avg = avg / max(1, samples.size())
	_expect(avg >= low and avg <= high,
		"base 均值 ≈ %.1f (±5%% jitter)，实际 %.2f（样本 %d）" % [nominal, avg, samples.size()])
	# 命中：200 × hit_chance（格挡/闪避已计入 hit_chance），允许 ±30% 随机波动
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
	if demo.get("hit", false):
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


func _t_def_breakdown() -> void:
	print("[T_def] final_def 合成")
	var dst := TestUnit.new("Def", 50, 50, 0, 60, 0, 0, "saber", "heavy_armor", 30, 1)
	get_root().add_child(dst)
	dst.stats.dodge_bonus = 5
	var bd: Dictionary = DamageSystem.compute_defense_breakdown(dst, {})
	_expect(bd.base_def == 50.0, "base_def=50，实际 %.1f" % bd.base_def)
	_expect(_approx(bd.dodge_pts, 5.0), "无天赋仅技能 dodge_bonus=5，实际 %.1f" % bd.dodge_pts)
	_expect(bd.block_pts > 0.0, "block_pts>0（横刀有 block），实际 %.1f" % bd.block_pts)
	_expect(bd.def_flat == 0.0, "满气力 def_flat=0，实际 %.1f" % bd.def_flat)
	_expect(bd.def_mult == 1.0, "def_mult=1.0，实际 %.3f" % bd.def_mult)
	var composed: float = bd.base_def + bd.dodge_pts + bd.block_pts + bd.def_flat
	_expect(_approx(bd.composed, composed), "composed 一致，实际 %.2f" % bd.composed)
	_expect(_approx(bd.with_mult, composed * bd.def_mult), "with_mult 一致")
	dst.stats.stamina = 10
	var bd2: Dictionary = DamageSystem.compute_defense_breakdown(dst, {})
	_expect(_approx(bd2.def_flat, -10.0), "力竭 def_flat=-10，实际 %.1f" % bd2.def_flat)
	dst.queue_free()


func _t_penalty() -> void:
	print("[T_penalty] 高防惩罚 with_mult=60 → final=52.5")
	_expect(_approx(DamageSystem.apply_high_def_penalty(44.0), 44.0), "≤45 无惩罚")
	_expect(_approx(DamageSystem.apply_high_def_penalty(60.0), 52.5), "60 → 45+7.5=52.5")


func _t_miss_attrib() -> void:
	print("[T_miss_attrib] roll 区间归因（防御:闪避:格挡）")
	# 仅闪避+格挡（无面板防御）：60% 起 miss 带 40%，闪避:格挡=4:1
	_expect(DamageSystem.classify_miss_reason(0.6, 0.65, 0.0, 40.0, 10.0) == "dodge",
		"roll=0.65 → dodge（闪避区）")
	_expect(DamageSystem.classify_miss_reason(0.6, 0.95, 0.0, 40.0, 10.0) == "block",
		"roll=0.95 → block（格挡区）")
	# 含防御：50:40:10 → miss 带按 5:4:1
	_expect(DamageSystem.classify_miss_reason(0.6, 0.65, 50.0, 40.0, 10.0) == "miss",
		"roll=0.65 → miss（防御区）")
	_expect(DamageSystem.classify_miss_reason(0.6, 0.85, 50.0, 40.0, 10.0) == "dodge",
		"roll=0.85 → dodge")
	_expect(DamageSystem.classify_miss_reason(0.6, 0.50, 50.0, 40.0, 10.0) == "",
		"roll<Hit% → 空（命中）")
	_expect(DamageSystem.classify_miss_reason(0.6, 0.70, 80.0, 0.0, 0.0) == "miss",
		"仅防御 → miss")
	_expect(DamageSystem.classify_miss_reason(0.6, 0.70, 0.0, 0.0, 0.0) == "miss",
		"全 0 → miss")


func _t_ignore_dodge_block() -> void:
	print("[T_ignore] ignore_dodge / ignore_block")
	var dst := TestUnit.new("Tgt", 50, 40, 0, 60, 0, 0, "saber", "", 30, 1)
	get_root().add_child(dst)
	dst.stats.dodge_bonus = 20
	var normal: Dictionary = DamageSystem.compute_defense_breakdown(dst, {})
	var no_dodge: Dictionary = DamageSystem.compute_defense_breakdown(dst, {"ignore_dodge": true})
	_expect(no_dodge.dodge_pts == 0.0, "ignore_dodge → dodge_pts=0")
	_expect(no_dodge.final_def < normal.final_def, "ignore_dodge 降低 final_def")
	_expect(DamageSystem.classify_miss_reason(0.3, 0.5, 0.0, 0.0, 20.0) == "block",
		"仅 block 时 miss 归因 block")
	_expect(DamageSystem.classify_miss_reason(0.3, 0.5, 50.0, 0.0, 20.0) == "miss",
		"防御+格挡时 roll 落防御区 → miss")
	var mult: Dictionary = DamageSystem.compute_defense_breakdown(dst, {"block_mult": 2.0})
	_expect(mult.block_pts >= normal.block_pts, "block_mult 放大格挡点")
	dst.queue_free()


func _t_equipment_block() -> void:
	print("[T_equip_block] 配盾 / 双持 / 单手 block_pts")
	var db: Node = get_root().get_node_or_null("WeaponArmorDB")
	if db != null and db.call("get_shield", "round_shield") == null:
		db.call("_load_shields")

	var u := TestUnit.new("Blk", 50, 30, 0, 60, 0, 0, "saber", "", 30, 0)
	get_root().add_child(u)
	_expect(u.get_equipment_block_pts() == 8, "单手横刀 block=8")

	u.offhand_weapon = db.call("get_weapon", "dagger") if db else null
	_expect(u.get_equipment_block_pts() == 11, "双持横刀+匕首 block=8+3=11")

	u.offhand_weapon = null
	u.shield = db.call("get_shield", "round_shield") if db else null
	if u.shield != null:
		_expect(u.get_equipment_block_pts() == 25, "配盾 block=25（不含武器 8）")
		var bd: Dictionary = DamageSystem.compute_defense_breakdown(u, {})
		_expect(bd.block_pts == 25.0, "compute block_pts=25，实际 %.1f" % bd.block_pts)
	else:
		_expect(false, "无法加载 round_shield")

	u.queue_free()


func _t_nimble_body_dodge() -> void:
	print("[T_nimble] 身轻如燕 (init−全身重)×20%")
	var u := TestUnit.new("Nim", 50, 30, 0, 60, 0, 0, "dagger", "leather_armor", 30, 0)
	get_root().add_child(u)
	_expect(DamageSystem.compute_dodge_pts(u, {}) == 0.0, "默认无被动闪避")
	u.nimble_body_active = true
	u.stats.base_initiative = 100
	# 皮甲8+匕首0=8 → (100-8)*0.2=18.4
	_expect(_approx(DamageSystem.compute_dodge_pts(u, {}), 18.4), "轻装 init100 wt8 dodge=18.4")
	_expect(_approx(Stats.nimble_dodge_pts(100, 18), 16.4), "刺客 init100 wt18 dodge=16.4")
	_expect(_approx(Stats.nimble_dodge_pts(60, 45), 3.0), "重甲 init60 wt45 dodge=3")
	var db: Node = get_root().get_node_or_null("WeaponArmorDB")
	if db:
		u.stats.base_initiative = 60
		u.weapon = db.call("get_weapon", "modao")
		u.armor = db.call("get_armor", "plate_armor")
		# 35+14=49 → (60-49)*0.2=2.2
		_expect(_approx(DamageSystem.compute_dodge_pts(u, {}), 2.2), "札甲+陌刀 dodge=2.2")
	u.queue_free()
