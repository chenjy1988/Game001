#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_godot_env.sh"

run_script() {
  local script_path="$1"
  local log_name="$2"
  echo "=== running $script_path ==="
  "$GODOT" --headless --path "$PROJECT_DIR" --script "$script_path" \
    2>&1 | tee "$PROJECT_DIR/logs/$log_name"
  local code="${PIPESTATUS[0]}"
  echo "godot_exit=$code ($script_path)"
  return "$code"
}

failures=0
mode="${1:-quick}"

run_script "res://tools/tests/run_tests.gd" "run_tests.log" || failures=$((failures + 1))

if [ "$mode" = "--full" ]; then
  run_script "res://scripts/tools/test_damage_system.gd" "test_damage_system.log" || failures=$((failures + 1))
  run_script "res://scripts/tools/test_turn_scheduler.gd" "test_turn_scheduler.log" || failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "tests failed: $failures suite(s)"
  exit 1
fi

if [ "$mode" = "--full" ]; then
  echo "all tests passed (full)"
else
  echo "health checks passed (use --full for damage + turn scheduler suites)"
fi
