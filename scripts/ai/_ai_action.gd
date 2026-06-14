##
## _ai_action.gd — AIAction 工厂方法代理
##
## 业务代码通过此文件的静态方法创建 AIAction，
## 避免 headless 模式下的 class_name 注册问题。
##

const _AIAction = preload("res://scripts/ai/ai_action.gd")

# ── Type 常量 ──
const END_TURN: int = 0
const WAIT:     int = 1
const MOVE:     int = 2
const ATTACK:   int = 3
const ABILITY:  int = 4
const DEFEND:   int = 5

# ── 工厂方法 ──
static func end_turn(p_reason: String):
	return _AIAction.end_turn(p_reason)

static func wait(p_reason: String):
	return _AIAction.wait(p_reason)

static func move(path: Array, p_score: float = 0.0, p_reason: String = ""):
	return _AIAction.move(path, p_score, p_reason)

static func attack(target, attack_mode: String, p_score: float = 0.0, p_reason: String = ""):
	return _AIAction.attack(target, attack_mode, p_score, p_reason)

static func ability(ability_id: String, target, context: Dictionary = {}, p_score: float = 0.0, p_reason: String = ""):
	return _AIAction.ability(ability_id, target, context, p_score, p_reason)
