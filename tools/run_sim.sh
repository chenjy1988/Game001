#!/usr/bin/env bash
# Headless 4v4 battle simulation (evaluating-gameplay-balance harness).
# Env: SIM_GAMES SIM_MIRROR_GAMES SIM_DISPOSITION_GAMES SIM_I3_STRICT(0|1)
#       SIM_AI_LOG_DECISIONS(0|1) — 默认 0，关闭 [AI] 决策日志
set -euo pipefail || true
source "$(dirname "$0")/godot_env.sh"

export SIM_AI_LOG_DECISIONS="${SIM_AI_LOG_DECISIONS:-0}"

echo "== sim: battle_sim_runner (AI log=${SIM_AI_LOG_DECISIONS}) =="
"$GODOT_BIN" --path "$PROJECT_DIR" \
	--scene res://scenes/tools/BattleSim.tscn \
	2>&1 | tee "$PROJECT_DIR/logs/battle_sim.log"
code="${PIPESTATUS[0]}"
echo "godot_exit=$code log=$PROJECT_DIR/logs/battle_sim.log"
if [ "$code" -ne 0 ]; then
	echo "run_sim: FAILED" >&2
	exit 1
fi
if grep -E '^(ERROR|SCRIPT ERROR|Parse Error)' "$PROJECT_DIR/logs/battle_sim.log" >/dev/null 2>&1; then
	echo "run_sim: errors in log" >&2
	exit 1
fi
echo "run_sim: ok"
