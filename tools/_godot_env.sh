#!/usr/bin/env bash
# Shared Godot CLI environment for Game001 (project-local XDG).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export XDG_DATA_HOME="$PROJECT_DIR/.godot-xdg/data"
export XDG_CONFIG_HOME="$PROJECT_DIR/.godot-xdg/config"
export XDG_CACHE_HOME="$PROJECT_DIR/.godot-xdg/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$PROJECT_DIR/logs"

GODOT="${GODOT:-godot}"
