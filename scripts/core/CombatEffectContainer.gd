extends RefCounted
##
## 单位战斗效果容器 — 存储实例 + 折叠 EffectiveCombatStats

const _EffectiveCombatStats = preload("res://scripts/core/EffectiveCombatStats.gd")
const _DerivedEffects = preload("res://scripts/core/effects/DerivedEffects.gd")

var _owner = null
var _effects: Array = []
var _pending_add: Array = []
var _busy: int = 0
var _effective = null
var _dirty: bool = true


func _init(owner = null) -> void:
	_owner = owner


func add(effect) -> void:
	if effect == null:
		return
	if _busy > 0:
		_pending_add.append(effect)
		return
	_add_internal(effect)


func _add_internal(effect) -> void:
	if not effect.is_stacking:
		for e in _effects:
			if e.id == effect.id:
				e.turns_remaining = effect.turns_remaining
				e.on_refresh()
				_mark_dirty()
				return
	_effects.append(effect)
	effect.on_added(self)
	_mark_dirty()


func remove_by_id(effect_id: String) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		if _effects[i].id == effect_id:
			_effects[i].on_removed()
			_effects.remove_at(i)
			_mark_dirty()


func has_id(effect_id: String) -> bool:
	for e in _effects:
		if e.id == effect_id:
			return true
	return false


func query_ui() -> Array:
	var out: Array = []
	for e in _effects:
		if e.show_in_ui:
			out.append(e.to_ui_entry())
	return out


func get_effective():
	if _dirty or _effective == null:
		rebuild_effective()
	return _effective


func rebuild_effective() -> void:
	_busy += 1
	var base = _EffectiveCombatStats.from_stats(_owner.stats if _owner != null else null)
	_DerivedEffects.apply_to_stats(_owner, base)
	var sorted: Array = _effects.duplicate()
	sorted.sort_custom(func(a, b): return a.order < b.order)
	for e in sorted:
		e.on_update(base)
	for e in sorted:
		e.on_after_update(base)
	_effective = base
	_dirty = false
	_busy -= 1
	_flush_pending()


func _flush_pending() -> void:
	if _pending_add.is_empty():
		return
	var batch: Array = _pending_add.duplicate()
	_pending_add.clear()
	for e in batch:
		_add_internal(e)


func _mark_dirty() -> void:
	_dirty = true


func notify_combat_started() -> void:
	for e in _effects:
		e.on_combat_started()
	_mark_dirty()


func notify_combat_finished() -> void:
	for e in _effects:
		e.on_combat_finished()
	_effects.clear()
	_mark_dirty()


func notify_turn_started() -> void:
	for e in _effects:
		e.on_turn_started()
	_mark_dirty()


func notify_turn_ended() -> void:
	for e in _effects:
		e.on_turn_ended()
		if e.turns_remaining > 0:
			e.turns_remaining -= 1
	for i in range(_effects.size() - 1, -1, -1):
		if _effects[i].is_expired():
			_effects[i].on_removed()
			_effects.remove_at(i)
	_mark_dirty()
