extends SceneTree
##
## test_combat_v3.gd — 战斗模型 v3 自测脚本（独立运行）
##
## 验证：
##   1. Stats 派生公式：dodge_chance / block_chance / eff_init / eff_defense
##   2. 9 格 HP 渗透表（武器 damage_type × 护甲 material）
##   3. 武器 base_block 装备组合
##

func _init() -> void:
	print("\n========== 战斗模型 v3 自测 ==========\n")

	test_stats_derivations()
	test_hp_penetration_table()
	test_dodge_block_combinations()

	print("\n========== 测试完成 ==========\n")
	quit()


func test_stats_derivations() -> void:
	print("【测试 1】Stats 派生公式")
	print("---" .repeat(20))

	var s := Stats.new()
	s.base_initiative = 110
	s.defense = 50
	s.melee_skill = 60

	# 装皮甲（轻甲，weight 8, light）
	print("场景：阿尔伯特 base_init=110, def=50")
	print("  装皮甲（weight 8, class=light）：")
	print("    eff_init  = %d  (期望 108)" % s.eff_init(8))
	print("    eff_def   = %.1f (期望 50.0)" % s.eff_defense("light"))
	print("    dodge_pts  = %.1f (默认 0；身轻如燕另算)" % s.dodge_chance(8, "light"))

	print("  装锁子甲（weight 18, class=medium）：")
	print("    eff_init  = %d  (期望 105)" % s.eff_init(18))
	print("    eff_def   = %.1f (期望 35.0)" % s.eff_defense("medium"))
	print("    dodge_pts  = %.1f (默认 0)" % s.dodge_chance(18, "medium"))

	print("  装板甲（weight 35, class=heavy）：")
	print("    eff_init  = %d  (期望 101)" % s.eff_init(35))
	print("    eff_def   = %.1f (期望 20.0)" % s.eff_defense("heavy"))
	print("    dodge_pts  = %.1f (默认 0)" % s.dodge_chance(35, "heavy"))

	print("  装板甲 + 装盾（base_block 25）：")
	print("    block_pts  = %.1f (期望 25)" % s.block_chance(25, "heavy"))

	print("  装皮甲 + 双匕首+精通（base_block 21）：")
	print("    block_pts  = %.1f (期望 21)" % s.block_chance(21, "light"))

	print("")


func test_hp_penetration_table() -> void:
	print("【测试 2】9 格 HP 渗透表（武器 × 护甲材质）")
	print("---" .repeat(20))

	# 直接访问 DamageSystem 的常量
	var table = DamageSystem.HP_PENETRATION_TABLE

	print("                板甲   锁甲   皮甲")
	for w_type in ["slash", "pierce", "crush"]:
		var line := "%-8s |" % w_type
		for m in ["plate", "mail", "leather"]:
			var v: float = table[w_type][m]
			line += "  %.0f%%   " % (v * 100)
		print(line)

	print("")
	print("→ slash 克 leather (40%) / 弱 plate (5%)")
	print("→ pierce 克 mail (40%) / 中 plate (30%) / 弱 leather (20%)")
	print("→ crush 克 plate (50%) / 中 mail (30%) / 弱 leather (10%)")
	print("")


func test_dodge_block_combinations() -> void:
	print("【测试 3】各 build 闪避 + 格挡")
	print("---" .repeat(20))

	# 刺客 build
	var assassin := Stats.new()
	assassin.base_initiative = 130
	assassin.defense = 70
	print("【刺客】init=130, def=70, 皮甲(weight 8, light), 双匕+精通(base_block 21)：")
	print("    Dodge:  %.1f%%" % assassin.dodge_chance(8, "light"))
	print("    Block:  %.1f%%" % assassin.block_chance(21, "light"))

	# 重盾兵 build
	var shield := Stats.new()
	shield.base_initiative = 85
	shield.defense = 70
	print("\n【重盾兵】init=85, def=70, 板甲(weight 35, heavy), 横刀+盾(base_block=8+25=33)：")
	print("    Dodge:  %.1f%%" % shield.dodge_chance(35, "heavy"))
	print("    Block:  %.1f%%" % shield.block_chance(33, "heavy"))

	# 陌刀手 build
	var modao := Stats.new()
	modao.base_initiative = 90
	modao.defense = 50
	print("\n【陌刀手】init=90, def=50, 板甲(heavy), 陌刀(base_block 15)：")
	print("    Dodge:  %.1f%%" % modao.dodge_chance(35, "heavy"))
	print("    Block:  %.1f%%" % modao.block_chance(15, "heavy"))

	# 弓手 build
	var archer := Stats.new()
	archer.base_initiative = 100
	archer.defense = 60
	print("\n【弓手】init=100, def=60, 皮甲(light), 长弓(base_block 0，远程)：")
	print("    Dodge:  %.1f%%" % archer.dodge_chance(8, "light"))
	print("    Block:  %.1f%% （远程武器 0 格挡）" % archer.block_chance(0, "light"))

	print("")
	print("→ 各 build 防御身份清晰：刺客闪 + 双武器格 / 盾兵盾 + 中等闪 / 陌刀靠护甲 / 弓手仅闪")
	print("")
