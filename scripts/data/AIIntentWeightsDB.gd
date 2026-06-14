extends Node
##
## AIIntentWeightsDB.gd — 意图权重数据库（autoload）
##
## 启动加载 data/ai_intent_weights.json，AIIntentWeights 通过此节点查询。
##

const _PATH: String = "res://data/ai_intent_weights.json"

var _data: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	if not FileAccess.file_exists(_PATH):
		push_warning("[AIIntentWeightsDB] %s not found, using defaults" % _PATH)
		return
	var f := FileAccess.open(_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
		print("[AIIntentWeightsDB] loaded ai_intent_weights.json")


# ── 查询接口 ──

func get_job_weights(job_id: String) -> Dictionary:
	var jobs: Dictionary = _data.get("jobs", {})
	if job_id != "" and jobs.has(job_id):
		return jobs[job_id]
	return jobs.get("_default", {})


func get_weapon_weights(kind: String) -> Dictionary:
	if kind == "":
		return {}
	var tbl: Dictionary = _data.get("weapon_modifiers", {})
	return tbl.get(kind, {})


func get_faction_weights(preset: String) -> Dictionary:
	var tbl: Dictionary = _data.get("factions", {})
	if preset != "" and tbl.has(preset):
		return tbl[preset]
	return tbl.get("_default", {})


func get_modifier(key: String) -> Dictionary:
	if key == "":
		return {}
	var tbl: Dictionary = _data.get("modifiers", {})
	return tbl.get(key, {})


## 调试 / 单测 hook：直接覆盖某段配置
func override_section(section: String, value: Dictionary) -> void:
	_data[section] = value
