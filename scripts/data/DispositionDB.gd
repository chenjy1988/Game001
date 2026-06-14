extends Node
##
## DispositionDB.gd — 战法倾向（ai-system §七）
##

var _by_id: Dictionary = {}


func _ready() -> void:
	_load()


func _load() -> void:
	_by_id.clear()
	var path: String = "res://data/enemy_dispositions.json"
	if not FileAccess.file_exists(path):
		push_warning("[DispositionDB] enemy_dispositions.json not found")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for entry in parsed.get("dispositions", []):
			if entry is Dictionary and entry.has("id"):
				_by_id[entry["id"]] = entry
	if _by_id.is_empty():
		_by_id["default"] = {"id": "default", "behavior_mult": {}, "target_mult": 1.0}
	else:
		print("[DispositionDB] loaded %d dispositions" % _by_id.size())


func get_disposition(disposition_id: String) -> Dictionary:
	if _by_id.has(disposition_id):
		return _by_id[disposition_id]
	return _by_id.get("default", {"id": "default", "behavior_mult": {}, "target_mult": 1.0})


func behavior_mult(disposition_id: String, behavior_id: String) -> float:
	var d: Dictionary = get_disposition(disposition_id)
	var tbl: Dictionary = d.get("behavior_mult", {})
	return float(tbl.get(behavior_id, 1.0))


func target_mult(disposition_id: String) -> float:
	var d: Dictionary = get_disposition(disposition_id)
	return float(d.get("target_mult", 1.0))
