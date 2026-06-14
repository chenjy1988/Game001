extends RefCounted
class_name AIIntentWeights

##
## AIIntentWeights.gd — 风格权重表（5 维：attack/defend/support/reposition/retreat）
##
## 设计：见 design/ai-decision-logic.md §二
##
## 权重合成顺序：
##   1) 职业基线（jobs[job_id]）
##   2) 武器修饰（weapon_modifiers[weapon_type]）
##   3) 阵营修饰（factions[faction_preset]）
##   4) 状态修正（modifiers/hp_xxx, stamina_xxx, armor_broken）
##   5) 局面修正（modifiers/battle_xxx, ally_xxx, enemy_ranged_adv）
##
## 加权方式：连乘。最终 weights[cat] ≥ 0；所有候选 final = base_score × weights[cat]
##
## 数据来源：data/ai_intent_weights.json（启动时 AIIntentWeightsDB autoload 加载）
##

const CATEGORIES: Array[String] = ["attack", "defend", "support", "reposition", "retreat"]


# ──────────── 入口 ────────────

## 计算单位的权重表
##   unit:    Unit 实例（读 job_id / weapon / faction）
##   view:    AIWorldView（读战场局面、盟友危机、远程优势）
##   profile: AIProfile（可选；archetype/disposition 影响修饰）
##
## 返回：Dictionary { attack, defend, support, reposition, retreat }
static func compute(unit, view = null, profile = null) -> Dictionary:
	var w: Dictionary = _default_weights()
	if unit == null:
		return w

	var db = _db()
	if db == null:
		return w

	# 1) 职业基线
	var job_id: String = _job_id(unit)
	_apply(w, db.get_job_weights(job_id))

	# 2) 武器修饰
	var weapon_kind: String = _weapon_kind(unit)
	if weapon_kind != "":
		_apply(w, db.get_weapon_weights(weapon_kind))

	# 3) 阵营修饰
	var faction_preset: String = _faction_preset(unit)
	_apply(w, db.get_faction_weights(faction_preset))

	# 4) 状态修正
	_apply(w, db.get_modifier(_hp_state(unit)))
	_apply(w, db.get_modifier(_stamina_state(unit)))
	if _armor_broken(unit):
		_apply(w, db.get_modifier("armor_broken"))

	# 5) 局面修正
	if view != null:
		var scene_state: String = _battle_state(view)
		if scene_state != "":
			_apply(w, db.get_modifier(scene_state))
		var ally_state: String = _ally_crisis(view, unit)
		if ally_state != "":
			_apply(w, db.get_modifier(ally_state))
		var ranged_state: String = _ranged_balance(view)
		if ranged_state != "":
			_apply(w, db.get_modifier(ranged_state))

	# 6) AIProfile 倾向（M1 接入：archetype/disposition 已经反映在职业 + 阵营，这里只做温和增益）
	# Phase 2.5 P1 视情况扩展

	# 钳制下限，避免 0 让候选完全失声
	for k in CATEGORIES:
		w[k] = max(0.05, w[k])

	return w


# ──────────── 上下文提取 ────────────

static func _job_id(unit) -> String:
	if unit == null:
		return ""
	if "job" in unit and unit.job != null and "id" in unit.job:
		return str(unit.job.id)
	if "job_id" in unit:
		return str(unit.job_id)
	return ""


static func _weapon_kind(unit) -> String:
	# 返回 ranged_main / two_handed / shield / dagger 之一（互斥优先级）
	if unit == null or unit.weapon == null:
		return ""
	var w = unit.weapon
	# ranged_main：远程为主武器
	if "weapon_type" in w and str(w.weapon_type) == "ranged":
		return "ranged_main"
	# 持盾（副手）
	if "shield" in unit and unit.shield != null:
		return "shield"
	# dagger
	if "id" in w and "dagger" in str(w.id):
		return "dagger"
	# two_handed：可用武器 weight 启发，简化按 id 关键字
	if "id" in w:
		var wid: String = str(w.id)
		if "modao" in wid or "spear" in wid or "axe" in wid or "hammer" in wid or "mashuo" in wid:
			return "two_handed"
	return ""


static func _faction_preset(unit) -> String:
	# 阵营预设来自 AIDispositionDB 或 unit.ai_faction_preset；缺省为 _default
	if unit == null:
		return "_default"
	if "ai_faction_preset" in unit:
		var p: String = str(unit.ai_faction_preset)
		if p != "":
			return p
	return "_default"


static func _hp_state(unit) -> String:
	if unit == null or unit.stats == null:
		return "hp_full"
	var max_hp: float = float(max(1, unit.stats.max_hp))
	var ratio: float = float(unit.stats.hp) / max_hp
	if ratio < 0.30:
		return "hp_critical"
	if ratio < 0.70:
		return "hp_wounded"
	return "hp_full"


static func _stamina_state(unit) -> String:
	if unit == null or unit.stats == null:
		return ""
	if not "max_stamina" in unit.stats:
		return ""
	var max_s: float = float(max(1, unit.stats.max_stamina))
	var remain_stamina: float = float(unit.stats.stamina)
	var remain: float = remain_stamina / max_s
	if remain < 0.10:
		return "stamina_fatigued"
	if remain < 0.30:
		return "stamina_wavering"
	return ""


static func _armor_broken(unit) -> bool:
	if unit == null or unit.stats == null:
		return false
	if not "max_body_armor" in unit.stats:
		return false
	if unit.stats.max_body_armor <= 0:
		return false
	return unit.stats.body_armor <= 0


static func _battle_state(view) -> String:
	if view == null:
		return ""
	# 优先 FactionBrain 暴露的 battle_state；退化为根据 alive 比例估算
	if view.faction_brain is Dictionary:
		var s: String = str(view.faction_brain.get("battle_state", ""))
		if s != "":
			return "battle_" + s
	# 退化估算
	var allies: int = view.alive_allies.size() if "alive_allies" in view else 0
	var enemies: int = view.alive_enemies.size() if "alive_enemies" in view else 0
	if allies == 0:
		return "battle_collapsing"
	if enemies == 0:
		return "battle_dominant"
	var ratio: float = float(allies) / float(allies + enemies)
	if ratio < 0.30:
		return "battle_collapsing"
	if ratio < 0.45:
		return "battle_pressured"
	if ratio > 0.65:
		return "battle_dominant"
	return ""


static func _ally_crisis(view, self_unit) -> String:
	if view == null or not "alive_allies" in view:
		return ""
	for ally in view.alive_allies:
		if ally == self_unit or not ally.is_alive():
			continue
		# dying：HP < 30%
		if ally.stats != null and ally.stats.max_hp > 0:
			var ratio: float = float(ally.stats.hp) / float(ally.stats.max_hp)
			if ratio < 0.30:
				return "ally_dying"
	# surrounded：任意盟友周围 ≥2 敌人
	if view.unit != null and view.unit.hex_grid != null:
		var grid = view.unit.hex_grid
		var HC = preload("res://scripts/core/HexCoord.gd")
		for ally in view.alive_allies:
			if ally == self_unit:
				continue
			var enemy_count: int = 0
			for d in range(6):
				var nb: Vector2i = HC.neighbor(ally.axial_pos, d)
				var occ = grid.get_occupant(nb)
				if occ != null and occ.is_alive() and occ.get_faction() != ally.get_faction():
					enemy_count += 1
			if enemy_count >= 2:
				return "ally_surrounded"
	return ""


static func _ranged_balance(view) -> String:
	if view == null or not view.has_method("ranged_balance"):
		return ""
	# WorldView.ranged_balance(): 1=ENEMY_ADV, 2=ALLY_ADV
	var bal: int = view.ranged_balance()
	if bal == 1:
		return "enemy_ranged_adv"
	if bal == 2:
		return "ally_ranged_adv"
	return ""


# ──────────── 基础工具 ────────────

static func _default_weights() -> Dictionary:
	return { "attack": 1.0, "defend": 1.0, "support": 1.0, "reposition": 1.0, "retreat": 1.0 }


static func _apply(w: Dictionary, mult_dict) -> void:
	if mult_dict == null or not (mult_dict is Dictionary) or mult_dict.is_empty():
		return
	for k in CATEGORIES:
		if mult_dict.has(k):
			w[k] = float(w[k]) * float(mult_dict[k])


static func _db():
	var tree = Engine.get_main_loop()
	if tree == null:
		return null
	if tree.root == null:
		return null
	return tree.root.get_node_or_null("AIIntentWeightsDB")
