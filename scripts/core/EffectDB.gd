extends RefCounted
class_name EffectDB

const _StatCombatEffect = preload("res://scripts/core/effects/StatCombatEffect.gd")
const _AbilityEffectSpec = preload("res://scripts/core/abilities/AbilityEffectSpec.gd")

const EFFECTS_PATH := "res://data/effects.json"

static var _templates: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(EFFECTS_PATH):
		push_warning("[EffectDB] missing %s" % EFFECTS_PATH)
		return
	var f := FileAccess.open(EFFECTS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	for k in parsed.keys():
		if String(k).begins_with("_"):
			continue
		var tmpl = parsed[k]
		if tmpl is Dictionary:
			var copy: Dictionary = tmpl.duplicate(true)
			copy["id"] = String(k)
			_templates[String(k)] = copy


static func get_template(effect_id: String) -> Dictionary:
	_ensure_loaded()
	return _templates.get(effect_id, {})


static func create_from_spec(spec):
	if spec == null or not spec is _AbilityEffectSpec:
		return null
	_ensure_loaded()
	var tmpl: Dictionary = _templates.get(spec.effect_id, {})
	if tmpl.is_empty():
		tmpl = {
			"id": spec.effect_id,
			"display_name": spec.display_name if spec.display_name != "" else spec.effect_id,
			"order": 50,
		}
	else:
		tmpl = tmpl.duplicate(true)
	var turns: int = spec.turns
	if turns == 0:
		turns = int(tmpl.get("turns", 1))
	return _StatCombatEffect.from_template(tmpl, turns, spec.source)


static func reload() -> void:
	_templates.clear()
	_loaded = false
	_ensure_loaded()
