extends RefCounted
class_name AISceneExecutor
##
## AISceneExecutor.gd — 场景执行器（BattleScene 专用）
## 无类型标注，兼容 headless 模式。
##
const _AT = preload("res://scripts/ai/_ai_action.gd")


func run(action, unit, battle_scene, tm = null) -> bool:
	if unit == null or not unit.is_alive():
		return false
	match action.type:
		_AT.MOVE:
			return await _exec_move(action, unit, battle_scene)
		_AT.ATTACK:
			return await _exec_attack(action, unit, battle_scene)
		_AT.WAIT:
			return _exec_wait(unit, tm)
		_AT.ABILITY:
			return _exec_ability(action, unit)
		_: return false


func _exec_move(action, unit, scene) -> bool:
	var path: Array = action.payload.get("path", [])
	if path.is_empty():
		return true
	var typed: Array[Vector2i] = []
	for p in path:
		if p is Vector2i:
			typed.append(p)
	if typed.is_empty():
		return true
	var moved: bool = unit.move_along_path(typed)
	await scene.get_tree().create_timer(float(typed.size()) * 0.12).timeout
	# AP 不足时移动静默失败 → 不继续
	if not moved:
		return false
	return unit.is_alive()


func _exec_attack(action, unit, scene) -> bool:
	var target = action.payload.get("target", null)
	if target == null or not target.is_alive():
		return true
	var mode: String = action.payload.get("attack_mode", "")
	unit.attack_target(target, mode)
	await scene.get_tree().create_timer(0.35).timeout
	return unit.is_alive()


func _exec_wait(_unit, tm) -> bool:
	if tm != null and tm.has_method("wait_current"):
		tm.wait_current()
	return false


func _exec_ability(action, unit) -> bool:
	var ability_id: String = action.payload.get("ability_id", "")
	if ability_id == "breath_regulation" and unit.has_method("use_ability_breath_regulation"):
		if unit.use_ability_breath_regulation():
			return false
		return true
	if ability_id == "preempt" and unit.has_method("use_ability_preempt"):
		if unit.use_ability_preempt():
			return false
		return true
	const _AbilityLibrary = preload("res://scripts/core/AbilityLibrary.gd")
	const _Result = preload("res://scripts/core/abilities/AbilityResult.gd")
	var ab = _AbilityLibrary.get_by_id(ability_id)
	if ab == null:
		return true
	var target = action.payload.get("target", null)
	var ctx: Dictionary = action.payload.get("context", {})
	if unit.has_method("use_ability"):
		var r: Dictionary = unit.use_ability(ab, target, ctx)
		return bool(r.get(_Result.OK, false)) and unit.is_alive()
	return true
