#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_godot_env.sh"

echo "=== Game001 init ==="
echo "Project: $PROJECT_DIR"
echo "Godot: $($GODOT --version)"

echo "=== importing assets & rebuilding script cache ==="
"$GODOT" --headless --path "$PROJECT_DIR" --import \
  2>&1 | tee "$PROJECT_DIR/logs/import.log"

echo "=== smoke test ==="
bash "$PROJECT_DIR/tools/smoke.sh"

echo "=== health checks ==="
bash "$PROJECT_DIR/tools/run_tests.sh"

echo ""
echo "Init complete."
echo "  Editor:  godot --path \"$PROJECT_DIR\" --editor"
echo "  Run:     godot --path \"$PROJECT_DIR\""
echo "  Tests:   bash tools/run_tests.sh"
