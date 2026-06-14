extends Node

const _WeaponData = preload("res://scripts/core/WeaponData.gd")
const _ArmorData = preload("res://scripts/core/ArmorData.gd")
const _ShieldData = preload("res://scripts/core/ShieldData.gd")
##
## WeaponArmorDB.gd — 武器/护甲数据库（autoload 单例）
##
## 启动时从 data/*.json 加载所有配置，提供查询接口。
##

const WEAPONS_PATH := "res://data/weapons.json"
const ARMORS_PATH := "res://data/armors.json"
const SHIELDS_PATH := "res://data/shields.json"

var _weapons: Dictionary = {}  ## id -> WeaponData
var _armors: Dictionary = {}   ## id -> ArmorData
var _shields: Dictionary = {}  ## id -> ShieldData


func _ready() -> void:
	_load_weapons()
	_load_armors()
	_load_shields()
	print("[WeaponArmorDB] loaded %d weapons, %d armors, %d shields" % [
		_weapons.size(), _armors.size(), _shields.size()
	])


func _load_weapons() -> void:
	var file := FileAccess.open(WEAPONS_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开武器配置: " + WEAPONS_PATH)
		return
	var text: String = file.get_as_text()
	var data: Variant = JSON.parse_string(text)
	if data == null or not data.has("weapons"):
		push_error("武器 JSON 解析失败")
		return
	for entry in data["weapons"]:
		var w := _WeaponData.new()
		w.id = entry.get("id", "")
		w.display_name = entry.get("display_name", "")

		# ── v3.1 schema 新字段 ──
		var modes_raw: Array = entry.get("attack_modes", [])
		var modes_typed: Array[String] = []
		for m in modes_raw:
			modes_typed.append(String(m))
		w.attack_modes = modes_typed
		w.damage_base = int(entry.get("damage_base", 0))
		w.weight = int(entry.get("weight", 0))
		w.head_chance = int(entry.get("head_chance", 25))
		w.two_handed = bool(entry.get("two_handed", false))
		w.great_swing = bool(entry.get("great_swing", false))
		w.reload_ap = int(entry.get("reload_ap", 0))
		w.block_value = int(entry.get("block_value", 0))
		w.hit_modifier = int(entry.get("hit_modifier", 0))
		w.aim_head_penalty = int(entry.get("aim_head_penalty", -20))
		if entry.has("hit_modifier_by_mode"):
			w.hit_modifier_by_mode = entry["hit_modifier_by_mode"] as Dictionary
		if entry.has("aim_head_penalty_by_mode"):
			w.aim_head_penalty_by_mode = entry["aim_head_penalty_by_mode"] as Dictionary

		# range：可能是 [min, max] 数组（新）或 int（旧）
		var range_val: Variant = entry.get("range", 1)
		if range_val is Array and (range_val as Array).size() >= 2:
			w.range_min = int((range_val as Array)[0])
			w.range_max = int((range_val as Array)[1])
		else:
			w.range_min = int(range_val)
			w.range_max = int(range_val)
		w.attack_range = w.range_max  # 兼容旧字段

		w.ap_cost = int(entry.get("ap_cost", 4))
		w.weapon_type = entry.get("weapon_type", "melee")
		w.sprite = entry.get("sprite", "")

		# ── v3.1 之前的旧字段（DEPRECATED，可能 JSON 已删；为兼容旧 DamageSystem 仍读取）──
		w.damage_min = int(entry.get("damage_min", w.damage_base))
		w.damage_max = int(entry.get("damage_max", w.damage_base))
		w.armor_effectiveness = float(entry.get("armor_effectiveness", 1.0))
		w.armor_penetration = float(entry.get("armor_penetration", 0.0))
		w.stamina_cost = int(entry.get("stamina_cost", entry.get("fatigue_cost", 6)))
		w.head_damage_mult = float(entry.get("head_damage_mult", 1.5))
		w.crit_mult = float(entry.get("crit_mult", 1.5))
		w.bonus_crit_chance = float(entry.get("bonus_crit_chance", 0.0))
		w.damage_type = entry.get("damage_type", w.primary_mode())
		w.base_block = int(entry.get("base_block", w.block_value))

		_weapons[w.id] = w


func _load_armors() -> void:
	var file := FileAccess.open(ARMORS_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开护甲配置: " + ARMORS_PATH)
		return
	var text: String = file.get_as_text()
	var data: Variant = JSON.parse_string(text)
	if data == null or not data.has("armors"):
		push_error("护甲 JSON 解析失败")
		return
	for entry in data["armors"]:
		var a := _ArmorData.new()
		a.id = entry.get("id", "")
		a.display_name = entry.get("display_name", "")
		a.head_armor = int(entry.get("head_armor", 0))
		a.body_armor = int(entry.get("body_armor", 0))
		a.weight = int(entry.get("weight", 0))
		a.combat_style = entry.get("combat_style", "none")
		# 战斗模型 v3 新增字段
		a.material = entry.get("material", "leather")
		a.armor_class = entry.get("armor_class", "light")
		a.move_penalty = int(entry.get("move_penalty", 0))
		a.overlay_sprite = entry.get("overlay_sprite", "")
		_armors[a.id] = a


func get_weapon(id: String) -> _WeaponData:
	return _weapons.get(id, null)


func get_armor(id: String) -> _ArmorData:
	return _armors.get(id, null)


func _load_shields() -> void:
	var file := FileAccess.open(SHIELDS_PATH, FileAccess.READ)
	if file == null:
		push_error("无法打开盾牌配置: " + SHIELDS_PATH)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data == null or not data.has("shields"):
		push_error("盾牌 JSON 解析失败")
		return
	for entry in data["shields"]:
		var s = _ShieldData.new()
		s.id = entry.get("id", "")
		s.display_name = entry.get("display_name", "")
		s.block_value = int(entry.get("block_value", 25))
		_shields[s.id] = s


func get_shield(id: String):
	return _shields.get(id, null)


func list_weapon_ids() -> Array:
	return _weapons.keys()


func list_armor_ids() -> Array:
	return _armors.keys()
