extends Node
##
## ArchetypeDB.gd — 兵种 AI 模板（ai-system §七）
##

const JOB_TO_ARCHETYPE: Dictionary = {
	"tiaodang": "skirmisher",
	"qiangbing": "infantry",
	"qibing": "skirmisher",
	"chihou": "scout",
}

var _by_id: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	_by_id.clear()
	var path: String = "res://data/ai_archetypes.json"
	if not FileAccess.file_exists(path):
		push_warning("[ArchetypeDB] ai_archetypes.json not found")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for entry in parsed.get("archetypes", []):
			if entry is Dictionary and entry.has("id"):
				_by_id[entry["id"]] = entry
	if _by_id.is_empty():
		_by_id["infantry"] = _fallback_infantry()
	else:
		print("[ArchetypeDB] loaded %d archetypes" % _by_id.size())


func _fallback_infantry() -> Dictionary:
	return {
		"id": "infantry",
		"behavior_mult": {},
		"flank_mult": 1.0,
		"threat_sensitivity": 0.5,
		"oa_sensitivity": 0.5,
	}


func get_archetype(archetype_id: String) -> Dictionary:
	if _by_id.has(archetype_id):
		return _by_id[archetype_id]
	return _by_id.get("infantry", _fallback_infantry())


func archetype_for_job(job_id: String) -> String:
	return String(JOB_TO_ARCHETYPE.get(job_id, "infantry"))


func behavior_mult(archetype_id: String, behavior_id: String) -> float:
	var a: Dictionary = get_archetype(archetype_id)
	var tbl: Dictionary = a.get("behavior_mult", {})
	return float(tbl.get(behavior_id, 1.0))
