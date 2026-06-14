extends Node
##
## AIConfigDB.gd — AI 配置单例（autoload）
##
## 启动时加载 data/ai_config.json，运行时所有 AI 模块通过此单例读取配置。
## 后续加新参数只需改 JSON，不改代码。
##

var _data: Dictionary = {}

func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var path: String = "res://data/ai_config.json"
	if not FileAccess.file_exists(path):
		push_warning("[AIConfigDB] ai_config.json not found, using defaults")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
		print("[AIConfigDB] loaded ai_config.json")


# ── 公开 getter ──

## 加权随机参数
func consider_cutoff() -> float:
	return _get_nested("weighted_pick/consider_cutoff", 0.25)

func min_pool_score() -> float:
	return _get_nested("weighted_pick/min_pool_score", 10.0)


func is_deterministic() -> bool:
	return bool(_get_nested("weighted_pick/deterministic", false))


## 单测 / 调试：强制最高分选取（不修改 JSON 文件）
func set_deterministic(enabled: bool) -> void:
	if not _data.has("weighted_pick") or not (_data["weighted_pick"] is Dictionary):
		_data["weighted_pick"] = {}
	_data["weighted_pick"]["deterministic"] = enabled


## 仿真 / 批量跑局：关闭 [AI] 决策日志（默认 JSON 可仍为 true）
func set_log_decisions(enabled: bool) -> void:
	if not _data.has("debug") or not (_data["debug"] is Dictionary):
		_data["debug"] = {}
	_data["debug"]["log_decisions"] = enabled

## 行为基础分
func behavior_baseline(behavior_id: String) -> float:
	var tbl: Dictionary = _get_nested("behavior_baseline", {})
	return float(tbl.get(behavior_id, 0.0))


func breath_stamina_threshold() -> float:
	return float(_get_nested("breath_regulation/stamina_remaining_threshold", 0.20))


func breath_recovery_utility_scale() -> float:
	return float(_get_nested("breath_regulation/recovery_utility_scale", 120.0))


func breath_min_kill_hit_chance() -> float:
	return float(_get_nested("breath_regulation/min_kill_hit_chance", 0.20))


func breath_attack_opportunity_weight() -> float:
	return float(_get_nested("breath_regulation/attack_opportunity_weight", 1.0))


func preempt_utility_per_enemy_beaten() -> float:
	return float(_get_nested("preempt/utility_per_enemy_beaten", 95.0))


func preempt_slot_gain_scale() -> float:
	return float(_get_nested("preempt/slot_gain_scale", 12.0))


func ap_hold_opportunity_weight() -> float:
	return float(_get_nested("attack_opportunity/ap_hold_weight", 1.0))


func breath_score_critical() -> float:
	return breath_recovery_utility_scale() * 2.0


func breath_threat_penalty() -> float:
	return 0.0


func breath_min_score() -> float:
	return 0.0


func attack_utility_scale() -> float:
	return float(_get_nested("attack_opportunity/utility_scale", 100.0))


func attack_opportunity_weight() -> float:
	return float(_get_nested("attack_opportunity/weight", 1.0))


func hold_stance_bonus() -> float:
	return float(_get_nested("attack_opportunity/hold_stance_bonus", 40.0))


## TargetScore 权重
func target_weight(key: String) -> float:
	var tbl: Dictionary = _get_nested("target_score/weights", {})
	return float(tbl.get(key, 0.0))

func target_mult(key: String) -> float:
	var tbl: Dictionary = _get_nested("target_score/multipliers", {})
	return float(tbl.get(key, 1.0))

## 能力优先级基础分
func ability_priority(priority: String) -> float:
	var tbl: Dictionary = _get_nested("ability_priority_baseline", {})
	return float(tbl.get(priority, 100.0))

## 动作循环
func max_actions_per_turn() -> int:
	return _get_nested("action_loop/max_actions_per_turn", 6)


# ── 内部辅助 ──

func _get_nested(key_path: String, default):
	var keys := key_path.split("/")
	var d = _data
	for k in keys:
		if d is Dictionary:
			d = d.get(k, null)
		else:
			return default
	return d if d != null else default
