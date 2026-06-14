extends Node
##
## 无头 4v4 仿真入口（I3 数值门禁）
## ./tools/run_sim.sh
## SIM_GAMES=24 SIM_MIRROR_GAMES=12 ./tools/run_sim.sh
## SIM_I3_STRICT=0  — 镜像 §十四 仅 WARN（收基线）；=1 未达标 FAIL

const GAMES_PASS_VS_AI: int = 12
const BASE_SEED: int = 20260611

const ENGAGEMENT_TARGET: float = 0.90
const MIN_ATTACKS_PER_GAME: float = 4.0
const DISPOSITION_ROUND_DELTA: float = 3.0


func _ready() -> void:
	_configure_sim_ai_debug()
	_load_ai_scripts()
	await get_tree().process_frame

	var games_demo: int = _int_env("SIM_GAMES", 12)
	var games_mirror: int = _int_env("SIM_MIRROR_GAMES", 12)
	var games_disp: int = _int_env("SIM_DISPOSITION_GAMES", 8)
	var i3_strict: bool = _bool_env("SIM_I3_STRICT", false)

	print("=== BattleSimHarness I3 (demo=%d mirror=%d disp=%d strict=%s) ===\n" % [
		games_demo, games_mirror, games_disp, i3_strict
	])

	var fails: int = 0
	var report: Dictionary = {
		"generated_at": Time.get_datetime_string_from_system(),
		"i3_strict": i3_strict,
		"suites": {},
	}

	var demo_results: Array = await _run_lineup("demo", BASE_SEED, games_demo, "")
	var demo_agg: Dictionary = _aggregate(demo_results)
	report["suites"]["demo"] = {"aggregate": demo_agg, "results": demo_results}
	_print_suite_header("demo 不对称 4v4", games_demo, demo_agg)
	fails += _check_demo_invariants(demo_results, demo_agg)

	var mirror_results: Array = await _run_lineup("mirror", BASE_SEED + 5000, games_mirror, "")
	var mirror_agg: Dictionary = _aggregate(mirror_results)
	report["suites"]["mirror"] = {"aggregate": mirror_agg, "results": mirror_results}
	_print_suite_header("mirror 镜像 4v4", games_mirror, mirror_agg)
	fails += _apply_i3_gates(mirror_agg, i3_strict, "mirror")

	var berserk_results: Array = await _run_lineup("mirror", BASE_SEED + 7000, games_disp, "berserk")
	var guard_results: Array = await _run_lineup("mirror", BASE_SEED + 8000, games_disp, "guard")
	var berserk_agg: Dictionary = _aggregate(berserk_results)
	var guard_agg: Dictionary = _aggregate(guard_results)
	report["suites"]["disposition_berserk"] = {"aggregate": berserk_agg}
	report["suites"]["disposition_guard"] = {"aggregate": guard_agg}
	var disp_check: Dictionary = _HarnessClass().check_disposition_delta(
		berserk_agg, guard_agg, DISPOSITION_ROUND_DELTA
	)
	print("\n--- 倾向 A/B (enemy berserk vs guard, %d 局/侧) ---" % games_disp)
	print("  %s" % disp_check.message)
	if not disp_check.pass:
		if i3_strict:
			fails += 1
			print("[FAIL] 倾向差异未达标")
		else:
			print("[WARN] 倾向差异未达标")

	fails += await _run_pass_vs_ai_suite()

	_write_report(report, demo_results, mirror_results, berserk_results, guard_results)

	print("\n======== 总结: %s ========" % ("FAIL" if fails > 0 else "PASS"))
	if fails > 0:
		print("  未达标见 [FAIL]；调 JSON 前请先修 AI → logs/balance_hypothesis.md")
	get_tree().quit(1 if fails > 0 else 0)


func _HarnessClass():
	return load("res://scripts/core/BattleSimHarness.gd")


func _run_lineup(lineup: String, base_seed: int, count: int, enemy_disposition: String) -> Array:
	var Harness = _HarnessClass()
	var results: Array = []
	for i in count:
		var r: Dictionary = Harness.new().run(
			get_tree(), base_seed + i, "ai", "ai", lineup, enemy_disposition
		)
		results.append(r)
		_print_one(lineup, r)
		if r.reason != "complete" or r.winner < 0:
			print("  [WARN] incomplete: %s winner=%s" % [r.reason, r.winner])
		await get_tree().process_frame
	return results


func _aggregate(results: Array) -> Dictionary:
	return _HarnessClass().aggregate(results)


func _check_demo_invariants(results: Array, agg: Dictionary) -> int:
	var fails: int = 0
	for r in results:
		if r.reason != "complete" or r.winner < 0:
			fails += 1
			print("[FAIL] demo 未完成: %s" % r.get("reason", "?"))
	if agg.avg_attacks < MIN_ATTACKS_PER_GAME:
		fails += 1
		print("[FAIL] demo 交火过少（<%.0f 次攻击/局）" % MIN_ATTACKS_PER_GAME)
	else:
		print("[PASS] demo 有足够交火")
	if agg.avg_engagement_rate < ENGAGEMENT_TARGET:
		print("[WARN] demo 交火率 %.1f%% < 90%%（不对称局，不计 I3 FAIL）" % (
			agg.avg_engagement_rate * 100.0
		))
	return fails


func _apply_i3_gates(agg: Dictionary, strict: bool, tag: String) -> int:
	var check: Dictionary = _HarnessClass().check_i3_gates(agg, strict)
	var fails: int = 0
	for msg in check.failures:
		if strict:
			fails += 1
			print("[FAIL] %s %s" % [tag, msg])
		else:
			print("[WARN] %s %s" % [tag, msg])
	if check.pass:
		print("[PASS] %s §十四 门禁全部达标" % tag)
	return fails


func _run_pass_vs_ai_suite() -> int:
	var fails: int = 0
	var pass_wins: int = 0
	for i in GAMES_PASS_VS_AI:
		var Harness = _HarnessClass()
		var r: Dictionary = Harness.new().run(get_tree(), BASE_SEED + 1000 + i, "pass", "ai")
		if r.winner == 0:
			pass_wins += 1
			fails += 1
			var surv: Dictionary = r.survivors
			print("  [WARN] pass_vs_ai seed=%d winner=%d surv=%s/%s" % [
				r.seed, r.winner, surv.ally, surv.enemy
			])
		await get_tree().process_frame
	var rate: float = float(pass_wins) / float(GAMES_PASS_VS_AI)
	print("\n--- pass_vs_ai 友方胜率: %.1f%% (%d/%d) ---" % [rate * 100.0, pass_wins, GAMES_PASS_VS_AI])
	if rate > 0.15:
		fails += 1
		print("[FAIL] pass 策略胜率过高")
	else:
		print("[PASS] pass 明显弱于 ai")
	return fails


func _int_env(key: String, default_val: int) -> int:
	var env: String = OS.get_environment(key)
	if env.is_empty():
		return default_val
	return maxi(1, int(env))


func _bool_env(key: String, default_val: bool) -> bool:
	var env: String = OS.get_environment(key)
	if env.is_empty():
		return default_val
	return env != "0" and env.to_lower() != "false"


func _configure_sim_ai_debug() -> void:
	## 批量仿真默认关决策日志；调试时可 SIM_AI_LOG_DECISIONS=1
	var log_decisions: bool = _bool_env("SIM_AI_LOG_DECISIONS", false)
	var db = get_tree().root.get_node_or_null("AIConfigDB")
	if db and db.has_method("set_log_decisions"):
		db.set_log_decisions(log_decisions)
		if not log_decisions:
			print("[BattleSim] AI decision log OFF (SIM_AI_LOG_DECISIONS=0)")


func _load_ai_scripts() -> void:
	var core: Array[String] = [
		"res://scripts/core/HexCoord.gd",
		"res://scripts/core/CombatModifier.gd",
		"res://scripts/core/WeaponData.gd",
		"res://scripts/core/ArmorData.gd",
		"res://scripts/core/ShieldData.gd",
		"res://scripts/core/Stats.gd",
		"res://scripts/core/HexGrid.gd",
		"res://scripts/core/Unit.gd",
		"res://scripts/core/DamageSystem.gd",
		"res://scripts/core/TurnManager.gd",
		"res://scripts/core/abilities/AbilityEnums.gd",
		"res://scripts/core/abilities/AbilityResult.gd",
		"res://scripts/core/abilities/AbilityEffectSpec.gd",
		"res://scripts/core/abilities/Ability.gd",
		"res://scripts/core/abilities/BasicAttack.gd",
		"res://scripts/core/AbilityLibrary.gd",
	]
	for path in core:
		load(path)
	load("res://scripts/ai/ai_action.gd")
	load("res://scripts/ai/world_view.gd")
	load("res://scripts/ai/behaviors/behavior_base.gd")
	load("res://scripts/ai/scoring/target_scorer.gd")
	load("res://scripts/ai/scoring/engage_scorer.gd")
	load("res://scripts/ai/scoring/attack_opportunity.gd")
	load("res://scripts/ai/behaviors/behavior_wait.gd")
	load("res://scripts/ai/behaviors/behavior_retreat.gd")
	load("res://scripts/ai/behaviors/behavior_advance.gd")
	load("res://scripts/ai/behaviors/behavior_disengage.gd")
	load("res://scripts/ai/behaviors/behavior_defend.gd")
	load("res://scripts/ai/behaviors/behavior_engage.gd")
	load("res://scripts/ai/behaviors/behavior_attack.gd")
	load("res://scripts/ai/behaviors/behavior_breath.gd")
	load("res://scripts/ai/behaviors/behavior_preempt.gd")
	load("res://scripts/ai/ai_profile.gd")
	load("res://scripts/ai/faction_brain.gd")
	load("res://scripts/ai/ai_agent.gd")
	load("res://scripts/ai/sim_executor.gd")


func _print_one(tag: String, r: Dictionary) -> void:
	var t: Dictionary = r.telemetry
	var surv: Dictionary = r.survivors
	var disp: String = r.get("enemy_disposition", "")
	var disp_s: String = (" disp=%s" % disp) if not disp.is_empty() else ""
	print("[%s%s] seed=%d winner=%d (%s) rounds=%d eng=%.0f%% stall=%.1f%% ap=%.0f%% surv=%s/%s" % [
		tag, disp_s, r.seed, r.winner, r.reason,
		t.get("rounds", 0),
		float(t.get("engagement_rate", 0.0)) * 100.0,
		float(t.get("stall_rate", 0.0)) * 100.0,
		float(t.get("ap_utilization", 0.0)) * 100.0,
		surv.ally, surv.enemy,
	])


func _print_suite_header(name: String, games: int, agg: Dictionary) -> void:
	print("\n--- %s (%d 局) ---" % [name, games])
	print("  友方胜: %d  敌方胜: %d  平局: %d  友胜率: %.1f%%" % [
		agg.ally_wins, agg.enemy_wins, agg.draws, agg.ally_win_rate * 100.0
	])
	print("  中位回合: %.1f  均回合: %.1f  均攻击: %.1f  交火率: %.1f%%  站桩率: %.2f%%  AP利用: %.1f%%" % [
		agg.get("median_rounds", agg.avg_rounds), agg.avg_rounds, agg.avg_attacks,
		agg.avg_engagement_rate * 100.0, agg.avg_stall_rate * 100.0,
		agg.avg_ap_utilization * 100.0,
	])
	var pc: Dictionary = agg.get("post_contact", {})
	if not pc.is_empty() and int(pc.get("ai_unit_turns", 0)) > 0:
		var bc: Dictionary = pc.get("behavior_counts", {})
		print("  接敌后: 中位接敌回合=%.0f  AP=%.1f%%  站桩=%.1f%%  AP空转=%.1f%%  Defend轮=%.1f%%  hold轮=%.1f%%" % [
			float(pc.get("median_contact_round", 0)),
			float(pc.get("ap_utilization", 0)) * 100.0,
			float(pc.get("stall_rate", 0)) * 100.0,
			float(pc.get("ap_unused_rate", 0)) * 100.0,
			float(pc.get("defend_turn_rate", 0)) * 100.0,
			float(pc.get("hold_stance_turn_rate", 0)) * 100.0,
		])
		print("  接敌后 behavior: move=%d attack=%d wait=%d defend=%d end_turn=%d ability=%d" % [
			bc.get("move", 0), bc.get("attack", 0), bc.get("wait", 0),
			bc.get("defend", 0), bc.get("end_turn", 0), bc.get("ability", 0),
		])


func _write_report(report: Dictionary, demo: Array, mirror: Array, berserk: Array, guard: Array) -> void:
	report["hypothesis"] = _build_hypothesis(report)
	var payload := report.duplicate(true)
	payload["demo_results"] = demo
	payload["mirror_results"] = mirror
	payload["disposition_berserk_results"] = berserk
	payload["disposition_guard_results"] = guard

	var json_path: String = "res://logs/battle_sim_telemetry.json"
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		print("\n  遥测: logs/battle_sim_telemetry.json")

	var hyp: String = report.get("hypothesis", "")
	if not hyp.is_empty():
		var hf := FileAccess.open("res://logs/balance_hypothesis.md", FileAccess.WRITE)
		if hf:
			hf.store_string(hyp)
			hf.close()
			print("  假设记录: logs/balance_hypothesis.md")


func _build_hypothesis(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Balance Hypothesis（I3 自动生成 %s）\n" % Time.get_datetime_string_from_system())
	lines.append("> 门禁未通过前 **禁止** 手调 `jobs.json` / `weapons.json`。\n")

	var mirror: Dictionary = report.get("suites", {}).get("mirror", {}).get("aggregate", {})
	var check: Dictionary = _HarnessClass().check_i3_gates(mirror, true)
	if not check.pass:
		lines.append("## 镜像 §十四 未达标\n")
		for msg in check.failures:
			lines.append("- [ ] %s → 先查 AI，再查 JSON\n" % msg)
		var pc: Dictionary = mirror.get("post_contact", {})
		if not pc.is_empty() and int(pc.get("ai_unit_turns", 0)) > 0:
			lines.append("## 接敌后诊断（mirror 汇总）\n")
			lines.append("- 接敌回合中位: %.0f\n" % float(pc.get("median_contact_round", 0)))
			lines.append("- AP 利用: %.1f%%（全场 %.1f%%）\n" % [
				float(pc.get("ap_utilization", 0)) * 100.0,
				float(mirror.get("avg_ap_utilization", 0)) * 100.0,
			])
			lines.append("- 站桩率: %.1f%% | AP 空转轮: %.1f%%\n" % [
				float(pc.get("stall_rate", 0)) * 100.0,
				float(pc.get("ap_unused_rate", 0)) * 100.0,
			])
			lines.append("- Defend 单位轮占比: %.1f%% | hold stance 轮占比: %.1f%%\n" % [
				float(pc.get("defend_turn_rate", 0)) * 100.0,
				float(pc.get("hold_stance_turn_rate", 0)) * 100.0,
			])
			var pbc: Dictionary = pc.get("behavior_counts", {})
			lines.append("- 接敌后 decisions: move=%d attack=%d wait=%d defend=%d end_turn=%d ability=%d\n" % [
				pbc.get("move", 0), pbc.get("attack", 0), pbc.get("wait", 0),
				pbc.get("defend", 0), pbc.get("end_turn", 0), pbc.get("ability", 0),
			])

	var demo: Dictionary = report.get("suites", {}).get("demo", {}).get("aggregate", {})
	if demo.get("ally_win_rate", 0.0) > 0.7:
		lines.append("## demo 友方胜率畸高 (%.0f%%)\n" % (demo.ally_win_rate * 100.0))
		lines.append("- [ ] 敌方手写数值偏低 → 通过后调 spawn / JSON\n")

	lines.append("\n## 验收清单（待 sim 断言）\n")
	lines.append("- [ ] 跳荡承伤命中率分布\n")
	lines.append("- [ ] 枪手对甲穿透曲线\n")
	lines.append("- [ ] 奇兵夹击触发率\n")
	lines.append("- [ ] 斥候 vs 枪手暴击率差\n")
	return "\n".join(lines)
