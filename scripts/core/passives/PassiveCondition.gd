extends RefCounted
class_name PassiveCondition
##
## PassiveCondition — 被动触发条件极简求值器
##
## 支持有限的关键字白名单。复杂条件请退化为 .gd 子类。
## 支持表达式：
##   self.hp_ratio < 0.30 / >= 0.50
##   self.total_armor_weight >= 30 / < 20
##   self.total_weight < N
##   self.weapon_kind == "short_spear"
##   context.overwhelm_count >= N
##   context.is_charge / context.is_critical / context.is_first_attack
##

const _HexCoord = preload("res://scripts/core/HexCoord.gd")


static func eval(expr: String, unit, context: Dictionary) -> bool:
	var s: String = expr.strip_edges()
	if s.is_empty():
		return true

	if "self.hp_ratio" in s:
		if unit == null or unit.stats == null: return false
		var ratio: float = float(unit.stats.hp) / float(max(1, unit.stats.max_hp))
		return _eval_compare(_strip_prefix(s, "self.hp_ratio"), ratio)

	if "self.total_armor_weight" in s:
		var w: float = float(_calc_armor_weight(unit))
		return _eval_compare(_strip_prefix(s, "self.total_armor_weight"), w)

	if "self.total_weight" in s:
		var w: float = float(_calc_total_weight(unit))
		return _eval_compare(_strip_prefix(s, "self.total_weight"), w)

	if "context.overwhelm_count" in s:
		var n: float = float(context.get("overwhelm_count", 0))
		return _eval_compare(_strip_prefix(s, "context.overwhelm_count"), n)

	if "self.weapon_kind" in s:
		var want: String = _extract_string_literal(s)
		if unit == null or unit.weapon == null: return false
		return String(unit.weapon.get("kind") if "kind" in unit.weapon else "") == want

	# 布尔事件
	if s == "context.is_charge":  return bool(context.get("is_charge", false))
	if s == "context.is_critical": return bool(context.get("is_critical", false))
	if s == "context.is_first_attack": return bool(context.get("is_first_attack", false))

	push_warning("[PassiveCondition] unknown expr: %s" % s)
	return false


static func _eval_compare(rest_expr: String, value: float) -> bool:
	var s: String = rest_expr.strip_edges()
	for op in [">=", "<=", "==", "!=", ">", "<"]:
		if s.begins_with(op):
			var num_str: String = s.substr(op.length()).strip_edges()
			var threshold: float = num_str.to_float()
			match op:
				">=": return value >= threshold
				"<=": return value <= threshold
				">":  return value > threshold
				"<":  return value < threshold
				"==": return abs(value - threshold) < 0.001
				"!=": return abs(value - threshold) >= 0.001
	return false


static func _strip_prefix(expr: String, key: String) -> String:
	return expr.replace(key, "")


static func _calc_armor_weight(unit) -> int:
	var w: int = 0
	if unit == null: return 0
	if unit.armor != null and "weight" in unit.armor:
		w += int(unit.armor.weight)
	if unit.shield != null and "weight" in unit.shield:
		w += int(unit.shield.weight)
	return w


static func _calc_total_weight(unit) -> int:
	if unit == null: return 0
	if unit.has_method("get_total_weight"):
		return unit.get_total_weight()
	return 0


static func _extract_string_literal(expr: String) -> String:
	var idx: int = expr.find("\"")
	if idx < 0: return ""
	var rest: String = expr.substr(idx + 1)
	var end: int = rest.find("\"")
	if end < 0: return ""
	return rest.substr(0, end)
