extends Node
##
## 无头 4v4 仿真入口（--scene 模式，autoload 已就绪）
## ./tools/run_sim.sh

const _Harness = preload("res://scripts/core/BattleSimHarness.gd")

const GAMES_AI_VS_AI: int = 12
const GAMES_PASS_VS_AI: int = 12
const BASE_SEED: int = 20260611


func _ready() -> void:
	# 等 SceneTree 完成首帧挂载，避免 root busy 时 add_child 失败
	await get_tree().process_frame
	print("=== BattleSimHarness ===\n")
	var fails: int = 0

	var ai_results: Array = []
	for i in GAMES_AI_VS_AI:
		var r: Dictionary = _Harness.new().run(get_tree(), BASE_SEED + i, "ai", "ai")
		ai_results.append(r)
		_print_one("ai_vs_ai", r)
		if r.reason != "complete" or r.winner < 0:
			fails += 1
			print("  [WARN] incomplete: %s winner=%s" % [r.reason, r.winner])
		await get_tree().process_frame

	var pass_wins: int = 0
	for i in GAMES_PASS_VS_AI:
		var r: Dictionary = _Harness.new().run(get_tree(), BASE_SEED + 1000 + i, "pass", "ai")
		if r.winner == 0:
			pass_wins += 1
		var surv: Dictionary = r.survivors
		# pass invariant：友方不能比敌方更占优（胜/存活数）
		if r.winner == 0 or surv.ally > surv.enemy:
			fails += 1
			print("  [WARN] pass_vs_ai seed=%d winner=%d surv=%s/%s" % [
				r.seed, r.winner, surv.ally, surv.enemy
			])
		await get_tree().process_frame

	var pass_win_rate: float = float(pass_wins) / float(GAMES_PASS_VS_AI)
	print("\n--- pass_vs_ai 友方胜率: %.1f%% (%d/%d) ---" % [
		pass_win_rate * 100.0, pass_wins, GAMES_PASS_VS_AI
	])
	if pass_win_rate > 0.15:
		fails += 1
		print("[FAIL] pass 策略胜率过高，AI 优势不明显")
	else:
		print("[PASS] pass 策略明显弱于 ai（invariant）")

	var ai_agg := _aggregate(ai_results)
	print("\n--- ai_vs_ai 聚合 (%d 局) ---" % GAMES_AI_VS_AI)
	print("  友方胜: %d  敌方胜: %d  平局: %d" % [
		ai_agg.ally_wins, ai_agg.enemy_wins, ai_agg.draws
	])
	print("  均回合: %.1f  均攻击: %.1f  均命中: %.1f  均夹击: %.2f" % [
		ai_agg.avg_rounds, ai_agg.avg_attacks, ai_agg.avg_hits, ai_agg.avg_pincers
	])

	if ai_agg.avg_attacks < 4.0:
		fails += 1
		print("[FAIL] ai_vs_ai 交火过少（<4 次攻击/局）")
	else:
		print("[PASS] 局内有足够交火")

	print("\n======== 总结: %s ========" % ("FAIL" if fails > 0 else "PASS"))
	get_tree().quit(1 if fails > 0 else 0)


func _print_one(tag: String, r: Dictionary) -> void:
	var t: Dictionary = r.telemetry
	var surv: Dictionary = r.survivors
	print("[%s] seed=%d winner=%d (%s) rounds=%d atk=%d hit=%d pincer=%d surv=%s/%s" % [
		tag, r.seed, r.winner, r.reason,
		t.rounds, t.attacks, t.hits, t.pincers,
		surv.ally, surv.enemy,
	])


func _aggregate(results: Array) -> Dictionary:
	var ally_w: int = 0
	var enemy_w: int = 0
	var draws: int = 0
	var sum_r: float = 0.0
	var sum_a: float = 0.0
	var sum_h: float = 0.0
	var sum_p: float = 0.0
	for r in results:
		match r.winner:
			0: ally_w += 1
			1: enemy_w += 1
			_: draws += 1
		var t: Dictionary = r.telemetry
		sum_r += float(t.rounds)
		sum_a += float(t.attacks)
		sum_h += float(t.hits)
		sum_p += float(t.pincers)
	var n: float = maxf(1.0, float(results.size()))
	return {
		"ally_wins": ally_w,
		"enemy_wins": enemy_w,
		"draws": draws,
		"avg_rounds": sum_r / n,
		"avg_attacks": sum_a / n,
		"avg_hits": sum_h / n,
		"avg_pincers": sum_p / n,
	}
