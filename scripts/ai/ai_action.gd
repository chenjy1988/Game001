extends RefCounted
class_name AIAction

enum Type { END_TURN, WAIT, MOVE, ATTACK, ABILITY, DEFEND }
var type: int = Type.END_TURN
var payload: Dictionary = {}
var score: float = 0.0
var reason: String = ""

static func end_turn(p_reason: String = ""):
	var a = new(); a.type = Type.END_TURN; a.reason = p_reason; return a
static func wait(p_reason: String = ""):
	var a = new(); a.type = Type.WAIT; a.reason = p_reason; return a
static func move(path: Array, p_score: float = 0.0, p_reason: String = ""):
	var a = new(); a.type = Type.MOVE; a.payload = {"path": path}; a.score = p_score; a.reason = p_reason; return a
static func attack(target, attack_mode: String, p_score: float = 0.0, p_reason: String = ""):
	var a = new(); a.type = Type.ATTACK; a.payload = {"target": target, "attack_mode": attack_mode}; a.score = p_score; a.reason = p_reason; return a
static func ability(ability_id: String, target, context: Dictionary = {}, p_score: float = 0.0, p_reason: String = ""):
	var a = new(); a.type = Type.ABILITY; a.payload = {"ability_id": ability_id, "target": target, "context": context}; a.score = p_score; a.reason = p_reason; return a
