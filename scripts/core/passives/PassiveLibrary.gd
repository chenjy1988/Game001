extends RefCounted
class_name PassiveLibrary
##
## PassiveLibrary — 被动技能注册中心（仿 AbilityLibrary）
##
## 加载顺序：
##   1) _register_native() — 注册 .gd 子类（复杂公式/事件回调）
##   2) _load_from_json() — 加载 data/passives.json（数据驱动被动）
##

const _GenericPassive = preload("res://scripts/core/passives/GenericPassive.gd")

const PASSIVES_JSON_PATH := "res://data/passives.json"

static var _by_id: Dictionary = {}
static var _initialized: bool = false


static func get_by_id(passive_id: String):
	_ensure_loaded()
	return _by_id.get(passive_id, null)


static func ids() -> Array:
	_ensure_loaded()
	return _by_id.keys()


static func reload() -> void:
	_by_id.clear()
	_initialized = false
	_ensure_loaded()


static func all() -> Array:
	_ensure_loaded()
	return _by_id.values()


# ──── 私有 ────

static func _ensure_loaded() -> void:
	if _initialized: return
	_initialized = true
	_register_native()
	_load_from_json(PASSIVES_JSON_PATH)


static func _register_native() -> void:
	# 复杂公式/事件触发被动在此注册
	# 例：
	#   var qhhx = PassiveQiHaiHuiXuan.new()
	#   _by_id[qhhx.id] = qhhx
	pass


static func _load_from_json(path: String) -> void:
	if not FileAccess.file_exists(path): return
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary): return

	var loaded: int = 0
	for k in parsed.keys():
		if String(k).begins_with("_"): continue
		var cfg = parsed[k]
		if not (cfg is Dictionary): continue
		if not cfg.has("id"):
			cfg["id"] = String(k)
		var p = _GenericPassive.from_dict(cfg)
		if p != null:
			_by_id[p.id] = p
			loaded += 1

	if loaded > 0:
		print("[PassiveLibrary] loaded %d JSON passives from %s" % [loaded, path])
