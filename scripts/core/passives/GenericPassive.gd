extends "res://scripts/core/passives/PassiveEffect.gd"
class_name GenericPassive
##
## GenericPassive — 数据驱动通用被动（仿 GenericAbility）
##
## 从 JSON 构造永久被动。复杂触发逻辑请写 .gd 子类。
##

static func from_dict(cfg: Dictionary):
	var script := load("res://scripts/core/passives/GenericPassive.gd")
	var p = script.new()
	p._load_config(cfg)
	return p


func _load_config(cfg: Dictionary) -> void:
	id               = String(cfg.get("id", ""))
	display_name     = String(cfg.get("display_name", id))
	kind             = String(cfg.get("kind", "permanent"))
	condition_expr   = String(cfg.get("trigger_when", ""))
	trigger_event    = String(cfg.get("trigger_event", ""))
	trigger_phase    = String(cfg.get("trigger_phase", ""))
	stamina_cost_per_trigger = int(cfg.get("stamina_cost_per_trigger", 0))
	mutex_with       = cfg.get("mutex_with", [])
	hooks            = cfg.get("hooks", [])
	ai_hint          = cfg.get("ai_hint", {})
	source           = String(cfg.get("source", ""))

	var mods: Dictionary = cfg.get("modifiers", {}) if cfg.get("modifiers") is Dictionary else {}
	if mods.has("hit_pct"):             hit_pct            = float(mods["hit_pct"])
	if mods.has("defense_flat"):        defense_flat       = float(mods["defense_flat"])
	if mods.has("defense_pct"):         defense_pct        = float(mods["defense_pct"])
	if mods.has("damage_mult"):         damage_mult_min    = float(mods["damage_mult"]); damage_mult_max = damage_mult_min
	if mods.has("damage_mult_min"):     damage_mult_min    = float(mods["damage_mult_min"])
	if mods.has("damage_mult_max"):     damage_mult_max    = float(mods["damage_mult_max"])
	if mods.has("stamina_cost_mult"):   stamina_cost_mult  = float(mods["stamina_cost_mult"])
	if mods.has("armor_damage_mult"):   armor_damage_mult  = float(mods["armor_damage_mult"])
	if mods.has("damage_taken_mult"):   damage_taken_mult  = float(mods["damage_taken_mult"])
	if mods.has("hp_max_pct"):          hp_max_pct         = float(mods["hp_max_pct"])
	if mods.has("wound_threshold_pct"): wound_threshold_pct = float(mods["wound_threshold_pct"])
