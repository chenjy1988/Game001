extends Node
##
## JobDB.gd — 职业数据库 Autoload
##

const _JOBS_PATH: String = "res://data/jobs.json"
const JobClassScript = preload("res://scripts/core/JobClass.gd")

var _jobs: Dictionary = {}   ## id -> JobClass


func _ready() -> void:
	_load_jobs()
	print("[JobDB] loaded %d jobs" % _jobs.size())


func _load_jobs() -> void:
	if not FileAccess.file_exists(_JOBS_PATH):
		push_error("[JobDB] jobs.json not found: %s" % _JOBS_PATH)
		return
	var file := FileAccess.open(_JOBS_PATH, FileAccess.READ)
	if file == null:
		push_error("[JobDB] cannot open jobs.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[JobDB] JSON parse error: %s" % json.get_error_message())
		return
	var arr = json.data
	if not arr is Array:
		push_error("[JobDB] jobs.json root must be Array")
		return
	for obj in arr:
		var j = JobClassScript.new()
		j.id           = obj.get("id", "")
		j.display_name = obj.get("name", "")
		j.description  = obj.get("description", "")
		j.tier         = obj.get("tier", 1)
		var hp    = obj.get("hp_range",      [70, 90])
		var init  = obj.get("init_range",    [60, 80])
		var melee = obj.get("melee_range",   [60, 80])
		var def   = obj.get("defense_range", [30, 45])
		var res   = obj.get("resolve_range", [35, 50])
		var wis   = obj.get("wisdom_range",  [25, 40])
		j.hp_min       = hp[0];    j.hp_max       = hp[1]
		j.init_min     = init[0];  j.init_max     = init[1]
		j.melee_min    = melee[0]; j.melee_max    = melee[1]
		j.defense_min  = def[0];   j.defense_max  = def[1]
		j.resolve_min  = res[0];   j.resolve_max  = res[1]
		j.wisdom_min   = wis[0];   j.wisdom_max   = wis[1]
		j.max_ap       = obj.get("max_ap",    9)
		j.move_range   = obj.get("move_range", 4)
		var pool = obj.get("weapon_pool", [])
		j.weapon_pool.clear()
		for w in pool:
			j.weapon_pool.append(str(w))
		var ab_list = obj.get("abilities", [])
		for ab_id in ab_list:
			j.abilities.append(str(ab_id))
		_jobs[j.id] = j


## 获取职业（找不到返回 null）
func get_job(id: String):
	return _jobs.get(id, null)


## 获取所有职业（按 tier 排序）
func get_all_jobs() -> Array:
	var arr: Array = []
	for j in _jobs.values():
		arr.append(j)
	arr.sort_custom(func(a, b): return a.tier < b.tier)
	return arr


## 获取指定 tier 的职业列表
func get_jobs_by_tier(tier: int) -> Array:
	var arr: Array = []
	for j in _jobs.values():
		if j.tier == tier:
			arr.append(j)
	return arr
