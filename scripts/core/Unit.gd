extends Node2D
class_name Unit
##
## Unit.gd — 战场单位
##
## 持有 Stats / WeaponData / ArmorData，处理移动、攻击、回合开始/结束。
## 通过信号与 TurnManager / BattleScene 通信。
##

signal action_completed(unit)              ## 单位本回合行动完毕（主动结束 turn）
signal unit_died(unit)                     ## 单位死亡
signal moved(unit, from_axial, to_axial)   ## 单位完成一次移动
signal attacked(unit, target, result)      ## 单位完成一次攻击
signal stats_changed(unit)                 ## 属性变化（用于 UI 刷新）

@export var stats: Stats
@export var weapon: WeaponData
@export var armor: ArmorData
var job = null       ## JobClass 实例，由 BattleScene spawn 时从 JobDB 注入

# ──── 先发制人技能相关（G2） ────
var preempt_active: bool = false            ## 先发制人是否激活
var preempt_initiative_bonus: int = 0       ## 先发制人 +Init 值（通常 +40）

# ──── 移动技能标志 ────
var ignore_oa_this_move: bool = false       ## 本次移动无视借机攻击（滑步技能激活时设为 true，移动结束后自动清除）

var axial_pos: Vector2i = Vector2i.ZERO
var hex_grid: HexGrid = null               ## 由 BattleScene 注入
var _registered_at_pos: bool = true         ## self 是否在 _occupants[axial_pos] 中（穿过友方格子时暂不注册）

const MOVE_SPEED_PX_PER_SEC: float = 220.0
const FATIGUE_PER_HEX: int = 3             ## 每移动 1 hex 消耗的疲劳
const AP_PER_HEX: int = 2                  ## 每移动 1 hex 消耗的 AP（战兄弟标准节奏）


func _ready() -> void:
	if stats:
		stats.init_runtime(armor.weight if armor else 0)
	_try_load_sprite()


# ──────────── Sprite 加载（Kenney Tiny Battle 等外部素材） ────────────
## 武器 id → sprite 文件名前缀（不含 _blue/_red.png）
## 找不到对应文件就回退到程序化绘制（_draw 内 fallback 分支）
const _SPRITE_DIR: String = "res://assets/sprites/units/"
const _WEAPON_TO_SPRITE: Dictionary = {
	"short_sword": "warrior",
	"war_hammer":  "hammerman",
	"dagger":      "rogue",
	"spear":       "spearman",
	"battle_axe":  "axeman",
}

## 武器 id → 武器小图标资源（绝对路径，res://assets/processed/）
const _WEAPON_ICON_DIR: String = "res://assets/processed/"
const _WEAPON_TO_ICON: Dictionary = {
	"short_sword": "sword.png",   # 用户决定取 sword.png 当短剑
	"sword":       "sword.png",
	"war_hammer":  "war_hammer.png",
	"dagger":      "dagger.png",
	"spear":       "spear.png",
	"battle_axe":  "battle_axe.png",
}

var _sprite_texture: Texture2D = null
var _weapon_icon_texture: Texture2D = null

func _try_load_sprite() -> void:
	if weapon == null:
		return
	var base: String = _WEAPON_TO_SPRITE.get(weapon.id, "warrior")
	var color_tag: String = "blue" if get_faction() == 0 else "red"
	var path: String = "%s%s_%s.png" % [_SPRITE_DIR, base, color_tag]
	if ResourceLoader.exists(path):
		_sprite_texture = load(path) as Texture2D
	else:
		_sprite_texture = null  # 回退到程序化绘制
	# 武器小图标（用于 sprite 模式头顶展示，取代程序化武器叠加）
	var icon_name: String = _WEAPON_TO_ICON.get(weapon.id, "")
	if icon_name != "":
		var icon_path: String = _WEAPON_ICON_DIR + icon_name
		if ResourceLoader.exists(icon_path):
			_weapon_icon_texture = load(icon_path) as Texture2D


## 提供给 UI 层（TopBar）使用：拿到当前单位的"圆形头像贴图"
## 优先使用大尺寸 sprite_texture（自带透明），UI 那边自己画圆形遮罩
func get_portrait_texture() -> Texture2D:
	return _sprite_texture


## 专门给行动条 / SidePanel 等"小头像"使用的胸像贴图。
## 优先级：
##   1) 显式手动指定的 portrait_override（暂未提供接口，预留）
##   2) 按角色类型挑选 assets/processed/portrait_*.png：
##      - 友方  → portrait_warrior.png
##      - 敌方头目（带 "头目"/"boss" 关键字 或 战斧/双手武器） → portrait_boss_orc.png
##      - 其它敌方 → portrait_bandit.png
##   3) 兜底：返回全身 sprite_texture
const _PORTRAIT_DIR: String = "res://assets/processed/"
var _portrait_cache: Dictionary = {}      ## name → Texture2D，避免重复 load

func get_action_bar_portrait() -> Texture2D:
	var key: String = _decide_portrait_key()
	if key == "":
		return _sprite_texture
	if _portrait_cache.has(key):
		return _portrait_cache[key]
	var path: String = _PORTRAIT_DIR + key + ".png"
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path) as Texture2D
		_portrait_cache[key] = t
		return t
	return _sprite_texture


func _decide_portrait_key() -> String:
	if get_faction() == 0:
		return "portrait_warrior"
	# 敌方
	var nm: String = stats.unit_name if stats else ""
	if nm.find("头目") >= 0 or nm.findn("boss") >= 0:
		return "portrait_boss_orc"
	# 战斧使用者也视为头目（视觉差异化）
	if weapon and weapon.id == "battle_axe":
		return "portrait_boss_orc"
	return "portrait_bandit"


# ──────────── 接口 ────────────
func get_faction() -> int:
	return stats.faction if stats else 0


func get_unit_name() -> String:
	return stats.unit_name if stats else "?"


## 当前装备的武器是否不在职业武器池内（触发「手拙」debuff）
func has_unfamiliar_weapon() -> bool:
	if job == null or weapon == null:
		return false
	return not job.has_weapon(weapon.id)


func is_alive() -> bool:
	return stats and stats.is_alive()


# ──── 先发制人技能相关方法（G2） ────
func get_fatigue_ratio() -> float:
	## 返回气力百分比（0.0~1.0）
	if not stats or stats.max_stamina <= 0:
		return 0.0
	return clamp(float(stats.fatigue) / float(stats.max_stamina), 0.0, 1.0)


func is_wearing_heavy_armor() -> bool:
	## 判断是否穿重甲（用于先发制人消耗倍数 ×1.6）
	return armor and armor.armor_class == "heavy"


## 获取全身重量（武器 + 护甲 + 道具）
## 用于 effective_initiative_v2 计算
func get_total_weight() -> int:
	var total: int = 0
	if weapon:
		if weapon.has_method("get") and "weight" in weapon:
			total += int(weapon.weight)
		elif weapon is WeaponData:
			total += int(weapon.weight)
	if armor:
		if armor.has_method("get") and "weight" in armor:
			total += int(armor.weight)
		elif armor is ArmorData:
			total += int(armor.weight)
	# TODO: 加上道具重量（当实装道具系统时）
	return total


func use_ability_preempt() -> bool:
	## 技能执行：扣 1 AP + 20/32 气力，设置先发制人激活
	## 返回技能是否成功激活
	if not stats or not is_alive():
		return false

	# 检查 AP
	if stats.ap < 1:
		return false

	# 计算气力消耗
	var fatigue_cost: int = 20
	if is_wearing_heavy_armor():
		fatigue_cost = int(20 * 1.6)  # = 32

	# 检查气力是否足够（不能超过 max_stamina）
	if stats.fatigue + fatigue_cost > stats.max_stamina:
		return false

	# 执行消耗
	stats.spend_ap(1)
	stats.add_fatigue(fatigue_cost)

	# 激活先发制人加值
	preempt_active = true
	preempt_initiative_bonus = 40

	stats_changed.emit(self)
	return true


func reset_turn_effects() -> void:
	## 每回合开始时清除先发制人加值（单次技能，不跨回合）
	preempt_active = false
	preempt_initiative_bonus = 0


func place_at(axial: Vector2i, grid: HexGrid) -> void:
	hex_grid = grid
	axial_pos = axial
	position = HexCoord.axial_to_pixel(axial, HexGrid.HEX_SIZE)
	hex_grid.set_occupant(axial, self)


# ──────────── 回合 ────────────
func start_turn() -> void:
	if not is_alive():
		return
	reset_turn_effects()  # 清除上回合效果（先发制人 +Init）
	stats.reset_ap()
	# 气力不自动恢复（design.md § 三：没有自然恢复，每一点变化都来自玩家明确选择）
	stats_changed.emit(self)


func end_turn() -> void:
	action_completed.emit(self)


# ──────────── 移动 ────────────
## 沿路径异步移动；返回是否成功开始移动。
## 每走一步：本格被任意敌人 ZoC 控制 → 触发该敌人借机攻击；
## 借机攻击命中（或打死）→ 中断剩余路径；本步 AP/疲劳照扣（BB 原版"赔了夫人又折兵"规则）。
func move_along_path(path: Array[Vector2i]) -> bool:
	if path.is_empty() or not is_alive():
		return false
	var ap_needed: int = path.size() * AP_PER_HEX
	if stats.ap < ap_needed:
		return false

	# 异步动画 + 逐步 OA 检查
	_animate_path(path)
	return true


func _animate_path(path: Array[Vector2i]) -> void:
	var from: Vector2i = axial_pos
	_registered_at_pos = true  ## 移动开始时，self 在 _occupants 中

	# ── 跳跃检测：中间格子（不含目的地）存在存活友方单位 ──
	var has_ally_in_path: bool = false
	for i in range(0, path.size() - 1):
		var mid_occ = hex_grid.get_occupant(path[i])
		if mid_occ != null and mid_occ != self \
				and mid_occ.has_method("is_alive") and mid_occ.is_alive() \
				and mid_occ.has_method("get_faction") \
				and mid_occ.get_faction() == get_faction():
			has_ally_in_path = true
			break
	if has_ally_in_path:
		await _jump_along_path(path, from)
		return

	for step in path:
		# 1) 触发借机攻击的判定（六边形版改良规则）：
		#    敌人 X 之前与你相邻（你在 X 的 ZoC 内）→ 本步无论你怎么动都触发：
		#      • 在同一 X 的 ZoC 内绕侧（保持距离 1） → 触发（"在剑尖滑过"被劈）
		#      • 脱离 X 的 ZoC（拉开距离 ≥2）           → 触发（背身撤退）
		#    敌人 X 之前不与你相邻（你不在 ZoC 内）→ 不触发：
		#      • 进入 X 的 ZoC（本步开始相邻） → 不触发（拉近距离时敌人无机会）
		#    BB 原版只在"脱离"时触发，但在六边形+ZoC=1邻 的地图上"脱离"罕见，
		#    会让玩家觉得"敌人剑尖滑过却不打我"反直觉。这条改良规则配合夹击使用。
		var leaving_ctrls: Array = []
		if not ignore_oa_this_move:
			leaving_ctrls = hex_grid.get_zoc_controllers(axial_pos, get_faction())

		# 2) 预扣本步 AP / 疲劳
		#    BB 原版规则：被借机攻击命中后，AP/疲劳"照扣"，不退还。
		#    意义：闯 ZoC 是真实付出代价的博弈，不是免费试探。
		stats.spend_ap(AP_PER_HEX)
		stats.add_fatigue(FATIGUE_PER_HEX)

		# 3) 借机攻击：命中即停，不再执行后续攻击者
		var hit_blocked: bool = false
		for ctrl in leaving_ctrls:
			if not is_alive():
				break
			var oa_result: Dictionary = DamageSystem.execute_attack(ctrl, self)
			oa_result["is_opportunity_attack"] = true
			var def_fat: int = DamageSystem.calculate_defend_fatigue(self)
			if def_fat > 0:
				stats.add_fatigue(def_fat)
				oa_result["defend_fatigue"] = def_fat
			_apply_attack_result(ctrl, self, oa_result)
			ctrl.attacked.emit(ctrl, self, oa_result)
			if oa_result.get("hit", false) or not is_alive():
				hit_blocked = true
				break  # 命中即停，跳过后续借机攻击者

		# 被打死或被命中阻挡 → 停在原地，不进入新格
		# AP/疲劳已在第 2 步扣掉，不退还（"赔了夫人又折兵"）
		if hit_blocked or not is_alive():
			if not _registered_at_pos:
				hex_grid.set_occupant(axial_pos, self)
				_registered_at_pos = true
			ignore_oa_this_move = false
			stats_changed.emit(self)
			return

		# 4) tween 到下一格
		var target_pos: Vector2 = HexCoord.axial_to_pixel(step, HexGrid.HEX_SIZE)
		var distance: float = position.distance_to(target_pos)
		var duration: float = max(0.05, distance / MOVE_SPEED_PX_PER_SEC)
		var tween := create_tween()
		tween.tween_property(self, "position", target_pos, duration)
		await tween.finished

		# 5) 更新占用（穿过友方格子时不覆盖友方）
		var step_occ = hex_grid.get_occupant(step)

		# ── 硬性保险：如果这一步是敌方存活单位所在格，立刻停在上一格 ──
		var step_has_enemy: bool = step_occ != null and step_occ != self \
			and step_occ.has_method("get_faction") and step_occ.get_faction() != get_faction() \
			and step_occ.has_method("is_alive") and step_occ.is_alive()
		if step_has_enemy:
			if not _registered_at_pos:
				hex_grid.set_occupant(axial_pos, self)
				_registered_at_pos = true
			ignore_oa_this_move = false
			stats_changed.emit(self)
			return

		var step_has_friendly: bool = step_occ != null and step_occ != self \
			and step_occ.has_method("is_alive") and step_occ.is_alive() \
			and step_occ.has_method("get_faction") and step_occ.get_faction() == get_faction()
		if step_has_friendly:
			# 穿过友方格子：从旧位置移除 self，不覆盖友方占用
			if _registered_at_pos:
				hex_grid.set_occupant(axial_pos, null)
			_registered_at_pos = false
		else:
			if _registered_at_pos:
				hex_grid.move_occupant(axial_pos, step, self)
			else:
				hex_grid.set_occupant(step, self)
			_registered_at_pos = true
		axial_pos = step
		moved.emit(self, from, step)
		from = step
	# 临时调试：移动结束后核对 axial 与 sprite 像素位置是否一致
	var expected_px: Vector2 = HexCoord.axial_to_pixel(axial_pos, HexGrid.HEX_SIZE)
	if (position - expected_px).length() > 1.0:
		push_warning("[MOVE END] %s axial=%s pos=%s expected=%s diff=%s" % [
			get_unit_name(), axial_pos, position, expected_px, str(position - expected_px)
		])
	ignore_oa_this_move = false  # 移动结束，清除滑步标志
	stats_changed.emit(self)


## 跳跃移动：路径中含友方单位时触发，直接落到目的地（跳过中间格 OA）。
## 绝对准则仍生效：出发格若在敌人 ZoC 内，仍触发借机攻击（命中则中断跳跃）。
## AP / 疲劳按真实路径长度照扣（和走路一样）。
func _jump_along_path(path: Array[Vector2i], from: Vector2i) -> void:
	var steps: int = path.size()
	var dest_axial: Vector2i = path[-1]

	# ── 出发格 OA 判定（绝对准则：在敌人周身 1 格内就触发）──
	var leaving_ctrls: Array = hex_grid.get_zoc_controllers(axial_pos, get_faction())
	# 扣除第一步 AP/疲劳（无论是否被命中都扣，BB 赔了夫人又折兵规则）
	stats.spend_ap(AP_PER_HEX)
	stats.add_fatigue(FATIGUE_PER_HEX)
	for ctrl in leaving_ctrls:
		if not is_alive():
			break
		var oa_result: Dictionary = DamageSystem.execute_attack(ctrl, self)
		oa_result["is_opportunity_attack"] = true
		var def_fat: int = DamageSystem.calculate_defend_fatigue(self)
		if def_fat > 0:
			stats.add_fatigue(def_fat)
			oa_result["defend_fatigue"] = def_fat
		_apply_attack_result(ctrl, self, oa_result)
		ctrl.attacked.emit(ctrl, self, oa_result)
		if oa_result.get("hit", false) or not is_alive():
			# 命中/死亡 → 中断跳跃，留在原地
			if not _registered_at_pos:
				hex_grid.set_occupant(axial_pos, self)
				_registered_at_pos = true
			stats_changed.emit(self)
			return

	# 扣除剩余路径的 AP/疲劳
	if steps > 1:
		stats.spend_ap(AP_PER_HEX * (steps - 1))
		stats.add_fatigue(FATIGUE_PER_HEX * (steps - 1))

	# ── 抛物线动画：跳过中间格，不触发中间 OA ──
	var start_px: Vector2 = position
	var end_px: Vector2 = HexCoord.axial_to_pixel(dest_axial, HexGrid.HEX_SIZE)
	var arc_height: float = clamp(steps * 8.0, 30.0, 80.0)
	var duration: float = clamp(steps * 0.07, 0.18, 0.55)
	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			var lerp_pos: Vector2 = start_px.lerp(end_px, t)
			var arc: float = arc_height * 4.0 * t * (1.0 - t)
			position = lerp_pos + Vector2(0.0, -arc),
		0.0, 1.0, duration
	)
	await tween.finished
	position = end_px

	# 更新占用注册
	if _registered_at_pos:
		hex_grid.set_occupant(axial_pos, null)
	hex_grid.set_occupant(dest_axial, self)
	_registered_at_pos = true
	axial_pos = dest_axial

	moved.emit(self, from, dest_axial)
	stats_changed.emit(self)


## 把一次攻击结果应用到 target 上（用于借机攻击和正规攻击共用）
static func _apply_attack_result(_attacker: Unit, target: Unit, result: Dictionary) -> void:
	if not result.get("hit", false):
		return
	var loc: String = result.get("hit_location", "body")
	var armor_dmg: int = result.get("armor_damage", 0)
	var hp_dmg: int = result.get("hp_damage", 0)
	if loc == "head":
		target.stats.take_head_armor_damage(armor_dmg)
	else:
		target.stats.take_body_armor_damage(armor_dmg)
	target.stats.take_hp_damage(hp_dmg)
	target.stats_changed.emit(target)
	if not target.is_alive():
		target.unit_died.emit(target)


# ──────────── 攻击 ────────────
## 对目标执行一次攻击（含命中、伤害管线计算）
## 返回 DamageResult 字典
func attack_target(target: Unit, attack_mode: String = "") -> Dictionary:
	if not is_alive() or not target.is_alive() or weapon == null:
		return {}
	if stats.ap < weapon.ap_cost:
		return {"reason": "not_enough_ap"}
	var dist: int = HexCoord.distance(axial_pos, target.axial_pos)
	if dist > weapon.attack_range:
		return {"reason": "out_of_range"}
	# 临时调试日志：定位"角色与敌人重合"bug
	print("[ATTACK] %s@%s -> %s@%s  range=%d  pos.diff=%s" % [
		get_unit_name(), axial_pos, target.get_unit_name(), target.axial_pos,
		dist, str((target.position - position).round())
	])

	stats.spend_ap(weapon.ap_cost)
	stats.add_fatigue(weapon.fatigue_cost)

	# 如果没指定攻击模式，默认用第一个
	var mode: String = attack_mode if not attack_mode.is_empty() else (weapon.attack_modes[0] if not weapon.attack_modes.is_empty() else weapon.damage_type)
	var options: Dictionary = {"mode": mode} if not mode.is_empty() else {}
	# 武器专精：在职业武器池内 1.0，否则 0.9（手拙）
	options["mastery_dmg"] = 0.9 if has_unfamiliar_weapon() else 1.0
	var result: Dictionary = DamageSystem.execute_attack(self, target, options)

	# 防守方被攻击气力消耗（design.md § 三：命中/闪避/格挡均触发）
	var defend_fat: int = DamageSystem.calculate_defend_fatigue(target)
	if defend_fat > 0:
		target.stats.add_fatigue(defend_fat)
		result["defend_fatigue"] = defend_fat

	_apply_attack_result(self, target, result)

	stats_changed.emit(self)
	attacked.emit(self, target, result)

	# ──────── 夹击 (Pincer Attack) ────────
	# 攻击命中且目标仍存活时，检查目标对侧是否有友军近战兵 → 触发追加打击
	# 借机攻击不连锁触发（避免无限循环 / 套娃）
	if result.get("hit", false) and target.is_alive() and not result.get("is_opportunity_attack", false):
		_try_pincer_attack(target)

	return result


# ──────────── 夹击 ────────────
## 检查并触发夹击：主攻击者对 target 的反方向（对侧）若有同阵营、活着、近战、装备齐的友军
## → 该友军立刻发动一次"夹击补刀"，伤害 50%，不消耗 AP/Fatigue。
## 不触发再级联：is_pincer_attack=true 的 result 不会再次检查 pincer。
##
## 限制：
## ① 主攻击者 A 必须在 target 的近战 / 长矛攻击范围内（距离 ≤ 2）
##    → 远程武器（弓 / 弩 距离 ≥ 3）不触发夹击（"我射箭对侧友军怎么夹"）
## ② B 必须站在 target 的对侧（即 target 背对 B）—— 用 A 反推 T 的"朝向"
##    无朝向系统下，"T 永远面向刚攻击它的 A" 是合理简化
## ③ 借机攻击命中（is_opportunity_attack）不触发夹击 —— 在 attack_target 处已过滤
const PINCER_DAMAGE_MULT: float = 0.5   ## 夹击补刀伤害系数（主攻击的 50%）

func _try_pincer_attack(target: Unit) -> void:
	if hex_grid == null or target == null or not target.is_alive():
		return
	# 限制 ①：A 必须在近战 / 长矛范围内（距离 ≤ 2）才能触发夹击
	# 远程武器射击对侧友军没有"夹击"物理意义
	if HexCoord.distance(axial_pos, target.axial_pos) > 2:
		return
	# 取对侧格（A 反推 T 的朝向 → T 背对的格子）
	var opp_cell: Vector2i = HexCoord.opposite_across(axial_pos, target.axial_pos)
	var ally: Unit = hex_grid.get_occupant(opp_cell)
	if ally == null or ally == self or not ally.is_alive():
		return
	if ally.get_faction() != get_faction():
		return
	if ally.weapon == null or ally.weapon.weapon_type != "melee":
		return
	# 触发夹击：用 ally 的武器执行一次衰减伤害的攻击
	var pincer_result: Dictionary = DamageSystem.execute_attack(ally, target)
	pincer_result["is_pincer_attack"] = true
	# 伤害衰减
	pincer_result["hp_damage"] = int(round(float(pincer_result.get("hp_damage", 0)) * PINCER_DAMAGE_MULT))
	pincer_result["armor_damage"] = int(round(float(pincer_result.get("armor_damage", 0)) * PINCER_DAMAGE_MULT))
	# 防守方被攻击气力消耗（命中/闪避/格挡均触发）
	var pincer_def_fat: int = DamageSystem.calculate_defend_fatigue(target)
	if pincer_def_fat > 0:
		target.stats.add_fatigue(pincer_def_fat)
		pincer_result["defend_fatigue"] = pincer_def_fat
	_apply_attack_result(ally, target, pincer_result)
	ally.attacked.emit(ally, target, pincer_result)
	# 注意：被击中通常会触发 unit_died，由 DamageSystem 流程处理


# ──────────── 渲染 ────────────
const UNIT_RADIUS: float = 16.0

## 当前回合标记（由 BattleScene 设置），决定要不要画顶部箭头
var is_active_turn: bool = false


func set_active_turn(active: bool) -> void:
	if is_active_turn == active:
		return
	is_active_turn = active
	queue_redraw()


# ──────────── 攻击/受击反馈动画 ────────────
## 视觉 offset（独立于 position，由抖动/lunge tween 控制，_draw 时叠加到所有绘制偏移）
var _visual_offset: Vector2 = Vector2.ZERO :
	set(value):
		_visual_offset = value
		queue_redraw()


## 受击：左右抖动 + modulate 闪红/闪灰
func play_hit_reaction(hit_strength: float = 0.6, was_hit: bool = true) -> void:
	if not is_alive():
		return
	# 受击染色
	var flash_color: Color
	if was_hit:
		flash_color = Color(2.0, 0.5, 0.5)  # 强烈偏红
	else:
		flash_color = Color(1.4, 1.4, 1.4)
	var color_tween := create_tween()
	color_tween.tween_property(self, "modulate", flash_color, 0.05)
	color_tween.tween_property(self, "modulate", Color(1, 1, 1), 0.20)

	# 抖动 _visual_offset 而不是 position，避免和 _animate_path 冲突
	var amp: float = lerp(4.0, 10.0, clamp(hit_strength, 0.0, 1.0))
	var shake_tween := create_tween()
	shake_tween.tween_property(self, "_visual_offset", Vector2(-amp, 0), 0.04)
	shake_tween.tween_property(self, "_visual_offset", Vector2( amp, 0), 0.05)
	shake_tween.tween_property(self, "_visual_offset", Vector2(-amp * 0.5, 0), 0.05)
	shake_tween.tween_property(self, "_visual_offset", Vector2.ZERO, 0.06)


## 攻击者前冲：朝目标方向 lunge ~35% 距离再回来；也用 _visual_offset
func play_attack_lunge(target_axial: Vector2i) -> void:
	if not is_alive():
		return
	var dir: Vector2 = (HexCoord.axial_to_pixel(target_axial, HexGrid.HEX_SIZE)
		- HexCoord.axial_to_pixel(axial_pos, HexGrid.HEX_SIZE)).normalized()
	var lunge_off: Vector2 = dir * (HexGrid.HEX_SIZE * 0.45)
	var tween := create_tween()
	tween.tween_property(self, "_visual_offset", lunge_off, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_visual_offset", Vector2.ZERO, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _process(_delta: float) -> void:
	# 当前回合单位有箭头呼吸动画，需要持续重绘
	if is_active_turn and is_alive():
		queue_redraw()


func _draw() -> void:
	if not is_alive():
		return
	# 应用视觉 offset（受击抖动、出击 lunge）
	if _visual_offset != Vector2.ZERO:
		draw_set_transform(_visual_offset, 0.0, Vector2.ONE)

	# 有外部 sprite → 走 sprite 渲染路径（带阴影/光环/HP/箭头/武器叠加），并提前返回
	if _sprite_texture != null:
		_draw_sprite_mode()
		return

	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)

	# 阵营色板
	var tunic_color: Color
	var tunic_dark: Color
	var trim_color: Color
	var glow_color: Color
	if get_faction() == 0:
		tunic_color = Color(0.30, 0.52, 0.82)
		tunic_dark  = Color(0.18, 0.32, 0.55)
		trim_color  = Color(0.83, 0.70, 0.30)
		glow_color  = Color(0.45, 0.75, 1.0)
	else:
		tunic_color = Color(0.72, 0.24, 0.24)
		tunic_dark  = Color(0.45, 0.13, 0.13)
		trim_color  = Color(0.20, 0.18, 0.14)
		glow_color  = Color(1.0, 0.45, 0.40)

	var skin_color := Color(0.92, 0.78, 0.62)
	var skin_dark  := Color(0.70, 0.55, 0.42)
	var helmet_color: Color
	var helmet_visible: bool = true
	var w: int = armor.weight if armor else 0
	if w <= 0:
		helmet_visible = false
		helmet_color = Color(0.6, 0.5, 0.4)
	elif w <= 6:
		helmet_color = Color(0.40, 0.28, 0.18)
	elif w <= 14:
		helmet_color = Color(0.55, 0.55, 0.60)
	else:
		helmet_color = Color(0.75, 0.76, 0.80)

	# 1) 投影
	var shadow_y: float = 18.0
	draw_circle(Vector2(1, shadow_y), 14.0, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(0, shadow_y + 1), 10.0, Color(0, 0, 0, 0.40))

	# 2) 当前回合：脚下扇形柔光
	if is_active_turn:
		var glow_r: float = 18.0 + breath * 3.0
		draw_circle(Vector2(0, shadow_y), glow_r,
			Color(glow_color.r, glow_color.g, glow_color.b, 0.20 + 0.10 * breath))

	# 3) 腿
	var pants_color := Color(0.22, 0.18, 0.14)
	var pants_hl    := Color(0.32, 0.27, 0.22)
	draw_rect(Rect2(Vector2(-5, 6), Vector2(4, 12)), pants_color, true)
	draw_rect(Rect2(Vector2( 1, 6), Vector2(4, 12)), pants_color, true)
	draw_line(Vector2(-5, 6), Vector2(-5, 17), pants_hl, 1.0)
	draw_line(Vector2( 1, 6), Vector2( 1, 17), pants_hl, 1.0)
	draw_rect(Rect2(Vector2(-6, 16), Vector2(5, 3)), Color(0.10, 0.08, 0.06), true)
	draw_rect(Rect2(Vector2( 1, 16), Vector2(5, 3)), Color(0.10, 0.08, 0.06), true)

	# 4) 躯干（梯形）
	var torso_pts := PackedVector2Array([
		Vector2(-6, -6), Vector2( 6, -6),
		Vector2( 8,  6), Vector2(-8,  6),
	])
	draw_colored_polygon(torso_pts, tunic_color)
	var torso_shadow_pts := PackedVector2Array([
		Vector2( 2, -6), Vector2( 6, -6),
		Vector2( 8,  6), Vector2( 4,  6),
	])
	draw_colored_polygon(torso_shadow_pts, tunic_dark)
	draw_rect(Rect2(Vector2(-8, 4), Vector2(16, 2.5)), trim_color, true)
	if w > 8:
		var plate_pts := PackedVector2Array([
			Vector2(-4, -4), Vector2( 4, -4),
			Vector2( 5,  3), Vector2(-5,  3),
		])
		draw_colored_polygon(plate_pts,
			Color(helmet_color.r, helmet_color.g, helmet_color.b, 0.55))
		draw_line(Vector2(-3, -3), Vector2(0, 2), Color(0, 0, 0, 0.4), 1.0)
		draw_line(Vector2( 3, -3), Vector2(0, 2), Color(0, 0, 0, 0.4), 1.0)

	# 5) 头 + 脖子
	draw_rect(Rect2(Vector2(-2, -8), Vector2(4, 2)), skin_dark, true)
	draw_circle(Vector2(0, -12), 5.0, skin_color)
	draw_rect(Rect2(Vector2(-2.5, -13), Vector2(1, 1)), Color(0.1, 0.05, 0.0), true)
	draw_rect(Rect2(Vector2( 1.5, -13), Vector2(1, 1)), Color(0.1, 0.05, 0.0), true)

	# 6) 头盔
	if helmet_visible:
		draw_circle(Vector2(0, -13), 5.5, helmet_color)
		draw_rect(Rect2(Vector2(-6, -11), Vector2(12, 1.5)),
			Color(helmet_color.r * 0.7, helmet_color.g * 0.7, helmet_color.b * 0.7), true)
		if w > 14:
			draw_line(Vector2(0, -13), Vector2(0, -9),
				Color(helmet_color.r * 0.5, helmet_color.g * 0.5, helmet_color.b * 0.5), 1.5)

	# 7) 武器
	_draw_weapon()

	# 8) HP 微条
	var hp_ratio: float = clamp(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
	var bar_w: float = 30.0
	var bar_h: float = 4.0
	var bar_origin := Vector2(-bar_w * 0.5, 22.0)
	draw_rect(Rect2(bar_origin - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)),
		Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(bar_origin, Vector2(bar_w, bar_h)),
		Color(0.18, 0.10, 0.10, 1.0), true)
	var fill_color: Color = Color(0.85, 0.22, 0.22)
	if hp_ratio < 0.3:
		fill_color = Color(0.65, 0.15, 0.15)
	elif hp_ratio < 0.6:
		fill_color = Color(0.95, 0.45, 0.20)
	draw_rect(Rect2(bar_origin, Vector2(bar_w * hp_ratio, bar_h)), fill_color, true)

	# 9) 当前回合：头顶箭头
	if is_active_turn:
		var arrow_y: float = -22.0 - breath * 3.0
		var arrow_pts := PackedVector2Array([
			Vector2(-6, arrow_y), Vector2( 6, arrow_y), Vector2( 0, arrow_y + 8),
		])
		var shadow_pts := PackedVector2Array([
			arrow_pts[0] + Vector2(1, 1),
			arrow_pts[1] + Vector2(1, 1),
			arrow_pts[2] + Vector2(1, 1),
		])
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.55))
		draw_colored_polygon(arrow_pts, Color(0.95, 0.82, 0.35, 0.95))
		var arrow_outline := arrow_pts.duplicate()
		arrow_outline.append(arrow_pts[0])
		draw_polyline(arrow_outline, Color(0.55, 0.40, 0.10, 0.9), 1.2, true)


# ──────────── 武器图标小章（sprite 模式专用） ────────────
## 战兄弟风格：HP 条左端贴一个小圆武器章作为"装备"指示
## 用矢量符号绘制（在 8px 圆内清晰可辨），不再依赖 PNG 武器静物图
func _draw_weapon_badge_at(center: Vector2) -> void:
	if weapon == null:
		return
	var radius: float = 7.0
	# 阴影
	draw_circle(center + Vector2(0.4, 0.8), radius + 0.8, Color(0, 0, 0, 0.65))
	# 章底（金属暗灰 → 略微立体）
	draw_circle(center, radius, Color(0.18, 0.16, 0.13, 0.98))
	draw_circle(center + Vector2(0, -0.7), radius - 1.0, Color(0.26, 0.23, 0.18, 0.95))
	# 金属外圈
	var ring_color: Color = (Color(0.78, 0.42, 0.32)
		if get_faction() == 1
		else Color(0.65, 0.78, 0.95))
	draw_arc(center, radius, 0.0, TAU, 24, ring_color, 1.2, true)
	# 武器符号（亮金属色，对比明显）
	var sym_color := Color(0.92, 0.90, 0.78)
	_draw_weapon_symbol(center, radius - 1.5, sym_color, weapon.id)


## 在 (center, r) 范围内画武器符号
func _draw_weapon_symbol(c: Vector2, r: float, col: Color, wid: String) -> void:
	match wid:
		"short_sword", "sword":
			# 直立长剑：刃 + 十字护手 + 圆球柄
			draw_line(c + Vector2(0, -r), c + Vector2(0, r * 0.35), col, 1.6)
			draw_line(c + Vector2(-r * 0.55, r * 0.35), c + Vector2(r * 0.55, r * 0.35), col, 1.4)
			draw_circle(c + Vector2(0, r * 0.65), 1.4, col)
		"war_hammer":
			# 战锤：粗头部 + 短柄
			draw_line(c + Vector2(0, -r * 0.2), c + Vector2(0, r), Color(0.55, 0.42, 0.30), 1.4)
			draw_rect(Rect2(c + Vector2(-r * 0.85, -r * 0.55), Vector2(r * 1.7, r * 0.55)), col, true)
			# 一道高光让锤头更亮
			draw_rect(Rect2(c + Vector2(-r * 0.85, -r * 0.55), Vector2(r * 1.7, 1.2)),
				Color(1.0, 0.95, 0.78), true)
		"dagger":
			# 匕首：短刃 + 大圆盘柄（rondel）
			draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.1), col, 1.5)
			draw_line(c + Vector2(-r * 0.45, r * 0.1), c + Vector2(r * 0.45, r * 0.1), col, 1.0)
			draw_circle(c + Vector2(0, r * 0.55), 2.0, col)
		"spear":
			# 长矛：垂直长杆 + 三角矛头
			draw_line(c + Vector2(0, -r * 0.55), c + Vector2(0, r), Color(0.55, 0.42, 0.30), 1.4)
			var tip_pts := PackedVector2Array([
				c + Vector2(0, -r),
				c + Vector2(-r * 0.45, -r * 0.55),
				c + Vector2( r * 0.45, -r * 0.55),
			])
			draw_colored_polygon(tip_pts, col)
		"battle_axe":
			# 战斧：长杆 + 单边大斧刃
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0.55, 0.42, 0.30), 1.4)
			var blade_pts := PackedVector2Array([
				c + Vector2(0.3, -r * 0.85),
				c + Vector2(r * 0.95, -r * 0.55),
				c + Vector2(r * 0.95, r * 0.05),
				c + Vector2(0.3, -r * 0.05),
			])
			draw_colored_polygon(blade_pts, col)
		_:
			# 默认：圆点
			draw_circle(c, r * 0.5, col)


# ──────────── 武器绘制（区分类型） ────────────
func _draw_weapon() -> void:
	if weapon == null:
		return
	var hand: Vector2 = Vector2(8, -2)
	var wid: String = weapon.id
	match wid:
		"short_sword":
			_draw_sword(hand, 14.0, 2.4, 8.0, Color(0.78, 0.80, 0.85))
		"war_hammer":
			_draw_hammer(hand, 14.0, Color(0.45, 0.42, 0.38))
		"dagger":
			_draw_sword(hand, 8.0, 2.0, 5.0, Color(0.85, 0.86, 0.90))
		"spear":
			_draw_spear(hand, 20.0)
		"battle_axe":
			_draw_axe(hand, 14.0)
		_:
			_draw_sword(hand, 12.0, 2.0, 6.0, Color(0.75, 0.78, 0.82))


func _draw_sword(hand: Vector2, length: float, blade_w: float, guard_w: float, blade_color: Color) -> void:
	draw_rect(Rect2(hand + Vector2(-1, -1), Vector2(2.5, 5)), Color(0.30, 0.20, 0.10), true)
	draw_rect(Rect2(hand + Vector2(-guard_w * 0.5, -2), Vector2(guard_w, 1.5)),
		Color(0.50, 0.40, 0.20), true)
	var blade_top: Vector2 = hand + Vector2(0.25, -2 - length)
	var blade_rect := Rect2(hand + Vector2(-blade_w * 0.5 + 0.25, -2 - length), Vector2(blade_w, length))
	draw_rect(blade_rect, blade_color, true)
	draw_line(blade_top, blade_top + Vector2(blade_w * 0.5, 2),
		Color(blade_color.r * 0.6, blade_color.g * 0.6, blade_color.b * 0.6), 1.0)
	draw_line(blade_top + Vector2(-blade_w * 0.5, 1),
		blade_top + Vector2(-blade_w * 0.5, length - 1),
		Color(1, 1, 1, 0.6), 1.0)


func _draw_hammer(hand: Vector2, shaft_len: float, head_color: Color) -> void:
	draw_line(hand, hand + Vector2(0, -shaft_len), Color(0.40, 0.28, 0.18), 2.0)
	var head_y: float = hand.y - shaft_len
	draw_rect(Rect2(Vector2(hand.x - 5, head_y - 3), Vector2(10, 6)), head_color, true)
	draw_rect(Rect2(Vector2(hand.x - 5, head_y - 3), Vector2(10, 1.5)),
		Color(head_color.r * 1.3, head_color.g * 1.3, head_color.b * 1.3), true)


func _draw_spear(hand: Vector2, shaft_len: float) -> void:
	draw_line(hand + Vector2(0, 2), hand + Vector2(0, -shaft_len),
		Color(0.40, 0.28, 0.18), 1.6)
	var tip: Vector2 = hand + Vector2(0, -shaft_len - 5)
	var head_pts := PackedVector2Array([
		tip,
		hand + Vector2(-2.5, -shaft_len),
		hand + Vector2( 2.5, -shaft_len),
	])
	draw_colored_polygon(head_pts, Color(0.80, 0.82, 0.86))
	var head_outline := head_pts.duplicate()
	head_outline.append(head_pts[0])
	draw_polyline(head_outline, Color(0.40, 0.42, 0.46), 1.0, true)


func _draw_axe(hand: Vector2, shaft_len: float) -> void:
	draw_line(hand, hand + Vector2(0, -shaft_len), Color(0.40, 0.28, 0.18), 2.0)
	var head_y: float = hand.y - shaft_len + 2
	var head_pts := PackedVector2Array([
		Vector2(hand.x + 1, head_y),
		Vector2(hand.x + 9, head_y - 3),
		Vector2(hand.x + 10, head_y + 1),
		Vector2(hand.x + 9, head_y + 5),
		Vector2(hand.x + 1, head_y + 4),
	])
	draw_colored_polygon(head_pts, Color(0.55, 0.55, 0.58))
	var head_outline := head_pts.duplicate()
	head_outline.append(head_pts[0])
	draw_polyline(head_outline, Color(0.30, 0.30, 0.32), 1.0, true)
	draw_line(Vector2(hand.x + 9, head_y - 2), Vector2(hand.x + 9, head_y + 4),
		Color(1, 1, 1, 0.6), 1.0)


# ──────────── Sprite 渲染模式（外部素材路径） ────────────
## sprite 目标显示尺寸（直径方向），独立于源图分辨率，所有素材都会缩放到这个大小
##
## 取值：64 px。HEX_SIZE=36 → hex 高度 ≈ 72 px → sprite 占 hex ~89% 高度，
## 角色头部接近 hex 顶角、脚部落在 hex 下半 → 战兄弟标准的"角色填满格子"视觉。
## 早期 52 偏小（占 ~72%），相比 hex 显得"小人站大格子里"，所以拉到 64。
const SPRITE_DISPLAY_SIZE: float = 64.0   ## 让人物明显占满 hex（战兄弟风格）

## 心跳曲线：仅"当前回合且己方"时启用，让角色 sprite 上下跳
##   双拍 1.4s 周期：第一拍 0.40s 重击（4px），第二拍 0.40s 轻拍（2px），
##   每次跳动过程更"绵柔"（慢上慢下），后段静息约 0.5s
func _heartbeat_offset_y() -> float:
	if not is_active_turn:
		return 0.0
	if get_faction() != 0:
		return 0.0   # 只对玩家己方触发心跳；敌方不跳
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var phase: float = fmod(t, 1.4)
	if phase < 0.40:
		return -sin(phase / 0.40 * PI) * 4.0          # 第一拍重击 4px（慢起慢落）
	elif phase < 0.50:
		return 0.0
	elif phase < 0.90:
		return -sin((phase - 0.50) / 0.40 * PI) * 2.0 # 第二拍轻拍 2px（慢起慢落）
	else:
		return 0.0


func _draw_sprite_mode() -> void:
	var t_ms: float = float(Time.get_ticks_msec())
	var breath: float = 0.5 + 0.5 * sin(t_ms / 380.0)

	var glow_color: Color = (Color(0.45, 0.75, 1.0) if get_faction() == 0
		else Color(1.0, 0.45, 0.40))
	var shadow_y: float = 16.0

	# 心跳上跳偏移（仅当前回合且己方）
	var heartbeat_dy: float = _heartbeat_offset_y()

	# 1) 投影（脚下椭圆，给立体感）—— 不跟随心跳，留在地面
	draw_circle(Vector2(1, shadow_y), 14.0, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(0, shadow_y + 1), 10.0, Color(0, 0, 0, 0.40))

	# 2) 当前回合：脚下柔光（取代旧的头顶箭头）—— 不跟随心跳
	if is_active_turn:
		var glow_r: float = 19.0 + breath * 3.0
		draw_circle(Vector2(0, shadow_y), glow_r,
			Color(glow_color.r, glow_color.g, glow_color.b, 0.25 + 0.12 * breath))

	# 3) sprite 本体（按比例缩放到 SPRITE_DISPLAY_SIZE，脚部对齐 shadow_y）
	#    心跳：整个 sprite + HP 条 + 武器章 + 金点 一起向上跳
	#    朝向：红方面向左（敌方面对蓝方）→ 用 draw_set_transform 做 X 镜像
	var tex_size: Vector2 = _sprite_texture.get_size()
	var scale_f: float = SPRITE_DISPLAY_SIZE / max(tex_size.x, tex_size.y)
	var draw_size: Vector2 = tex_size * scale_f
	var sprite_top: float = (shadow_y - 2.0) - draw_size.y + heartbeat_dy
	var sprite_rect := Rect2(
		Vector2(-draw_size.x * 0.5, sprite_top),
		draw_size,
	)
	if get_faction() == 1:
		# 红方：在画 sprite 之前临时翻转 X，画完立刻恢复
		# 注意要把外层 _visual_offset 一起带上，否则会回到 (0,0)
		draw_set_transform(_visual_offset, 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(_sprite_texture, sprite_rect, false)
		draw_set_transform(_visual_offset, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(_sprite_texture, sprite_rect, false)

	# 4) HP 条（在角色"头顶上方"，战兄弟风格的横条）— 跟随心跳
	var hp_ratio: float = clamp(float(stats.hp) / float(stats.max_hp), 0.0, 1.0)
	var bar_w: float = 32.0
	var bar_h: float = 4.0
	var bar_y: float = sprite_top - 8.0
	var bar_origin := Vector2(-bar_w * 0.5, bar_y)
	# 黑色阴影框
	draw_rect(Rect2(bar_origin - Vector2(1, 1), Vector2(bar_w + 2, bar_h + 2)),
		Color(0, 0, 0, 0.85), true)
	# 暗红底
	draw_rect(Rect2(bar_origin, Vector2(bar_w, bar_h)),
		Color(0.18, 0.10, 0.10, 1.0), true)
	# 当前 HP 填充
	var fill_color: Color = Color(0.85, 0.22, 0.22)
	if hp_ratio < 0.3:
		fill_color = Color(0.65, 0.15, 0.15)
	elif hp_ratio < 0.6:
		fill_color = Color(0.95, 0.45, 0.20)
	draw_rect(Rect2(bar_origin, Vector2(bar_w * hp_ratio, bar_h)), fill_color, true)

	# 5) 武器小章：贴在 HP 条左端
	var badge_center := Vector2(bar_origin.x - 6.0, bar_y + bar_h * 0.5)
	_draw_weapon_badge_at(badge_center)

	# 6) 当前回合：HP 条右端再加一颗小金标
	if is_active_turn:
		var dot_center := Vector2(bar_origin.x + bar_w + 6.0, bar_y + bar_h * 0.5)
		var dot_r: float = 3.0 + breath * 0.6
		draw_circle(dot_center + Vector2(0.4, 0.6), dot_r + 0.6, Color(0, 0, 0, 0.6))
		draw_circle(dot_center, dot_r, Color(0.98, 0.82, 0.30, 0.95))
