#!/usr/bin/env bash
# 跑 BattleSim 并将结果追加到 design/ai-experiments.md
#
# 用法:
#   ./tools/run_ai_experiment.sh "改动说明"
#   AI_EXP_CHANGE="调 wait baseline" SIM_MIRROR_GAMES=12 ./tools/run_ai_experiment.sh
#
# 环境变量（透传给 run_sim.sh）:
#   SIM_GAMES SIM_MIRROR_GAMES SIM_DISPOSITION_GAMES SIM_I3_STRICT

set -euo pipefail
source "$(dirname "$0")/godot_env.sh"

CHANGE="${1:-${AI_EXP_CHANGE:-（未填写改动说明）}}"
SIM_GAMES="${SIM_GAMES:-12}"
SIM_MIRROR_GAMES="${SIM_MIRROR_GAMES:-12}"
SIM_DISPOSITION_GAMES="${SIM_DISPOSITION_GAMES:-8}"
SIM_I3_STRICT="${SIM_I3_STRICT:-0}"

EXP_LOG="$PROJECT_DIR/design/ai-experiments.md"
EXP_DIR="$PROJECT_DIR/logs/ai_experiments"
mkdir -p "$EXP_DIR"

TS="$(date '+%Y-%m-%d %H:%M:%S')"
TS_ID="$(date '+%Y%m%d_%H%M%S')"
TELEMETRY="$PROJECT_DIR/logs/battle_sim_telemetry.json"

echo "== ai experiment: $CHANGE =="
echo "   SIM_GAMES=$SIM_GAMES MIRROR=$SIM_MIRROR_GAMES DISP=$SIM_DISPOSITION_GAMES STRICT=$SIM_I3_STRICT"

export SIM_GAMES SIM_MIRROR_GAMES SIM_DISPOSITION_GAMES SIM_I3_STRICT
set +e
"$PROJECT_DIR/tools/run_sim.sh"
SIM_EXIT=$?
set -e

if [ ! -f "$TELEMETRY" ]; then
	echo "run_ai_experiment: no telemetry at $TELEMETRY (sim exit=$SIM_EXIT)" >&2
	exit 1
fi

SNAPSHOT="$EXP_DIR/${TS_ID}.json"
cp "$TELEMETRY" "$SNAPSHOT"
echo "   snapshot: logs/ai_experiments/${TS_ID}.json"

EXP_TAG="$(python3 "$PROJECT_DIR/tools/append_ai_experiment.py" \
	"$EXP_LOG" "$TS" "$CHANGE" "$SNAPSHOT" \
	"$SIM_GAMES" "$SIM_MIRROR_GAMES" "$SIM_DISPOSITION_GAMES" "$SIM_I3_STRICT" "$TELEMETRY" \
	| tail -1)"

echo "== ai experiment done: $EXP_TAG (sim_exit=$SIM_EXIT) =="
exit "$SIM_EXIT"
