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

run_scene() {
  local scene_path="$1"
  local log_name="$2"
  echo "=== running $scene_path ==="
  "$GODOT" --headless --path "$PROJECT_DIR" --scene "$scene_path" \
    2>&1 | tee "$PROJECT_DIR/logs/$log_name"
  local code="${PIPESTATUS[0]}"
  echo "godot_exit=$code ($scene_path)"
  return "$code"
}

failures=0
mode="${1:-quick}"

run_script "res://tools/tests/run_tests.gd" "run_tests.log" || failures=$((failures + 1))

if [ "$mode" = "--full" ]; then
  run_script "res://scripts/tools/test_ability_framework.gd" "test_ability_framework.log" || failures=$((failures + 1))
  run_script "res://scripts/tools/test_combat_effects.gd" "test_combat_effects.log" || failures=$((failures + 1))
  run_script "res://scripts/tools/test_damage_system.gd" "test_damage_system.log" || failures=$((failures + 1))
  run_script "res://scripts/tools/test_turn_scheduler.gd" "test_turn_scheduler.log" || failures=$((failures + 1))
  run_scene "res://scenes/tools/TestPassiveEffects.tscn" "test_passive_effects.log" || failures=$((failures + 1))
  run_scene "res://scenes/tools/TestMovementIntent.tscn" "test_movement_intent.log" || failures=$((failures + 1))
  run_scene "res://scenes/tools/TestAIM0.tscn" "test_ai_m0.log" || failures=$((failures + 1))
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
