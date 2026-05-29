extends Node
##
## WeaponArmorDB.gd — 武器/护甲数据库（autoload 单例）
##
## 启动时从 data/*.json 加载所有配置，提供查询接口。
##

const WEAPONS_PATH := "res://data/weapons.json"
const ARMORS_PATH := "res://data/armors.json"

var _weapons: Dictionary = {}  ## id -> WeaponData
var _armors: Dictionary = {}   ## id -> ArmorData


func _ready() -> void:
	_load_weapons()
	_load_armors()
	print("[WeaponArmorDB] loaded %d weapons, %d armors" % [_weapons.size(), _armors.size()])


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
		var w := WeaponData.new()
		w.id = entry.get("id", "")
		w.display_name = entry.get("display_name", "")
		w.damage_min = int(entry.get("damage_min", 30))
		w.damage_max = int(entry.get("damage_max", 45))
		w.armor_effectiveness = float(entry.get("armor_effectiveness", 1.0))
		w.armor_penetration = float(entry.get("armor_penetration", 0.0))
		w.ap_cost = int(entry.get("ap_cost", 4))
		w.fatigue_cost = int(entry.get("fatigue_cost", 6))
		w.attack_range = int(entry.get("range", 1))
		w.head_damage_mult = float(entry.get("head_damage_mult", 1.5))
		w.weapon_type = entry.get("weapon_type", "melee")
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
		var a := ArmorData.new()
		a.id = entry.get("id", "")
		a.display_name = entry.get("display_name", "")
		a.head_armor = int(entry.get("head_armor", 0))
		a.body_armor = int(entry.get("body_armor", 0))
		a.weight = int(entry.get("weight", 0))
		a.combat_style = entry.get("combat_style", "none")
		_armors[a.id] = a


func get_weapon(id: String) -> WeaponData:
	return _weapons.get(id, null)


func get_armor(id: String) -> ArmorData:
	return _armors.get(id, null)


func list_weapon_ids() -> Array:
	return _weapons.keys()


func list_armor_ids() -> Array:
	return _armors.keys()
