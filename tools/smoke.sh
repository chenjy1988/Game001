#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_godot_env.sh"

"$GODOT" --headless --path "$PROJECT_DIR" --quit-after 60 \
  2>&1 | tee "$PROJECT_DIR/logs/smoke.log"
echo "godot_exit=${PIPESTATUS[0]}"
