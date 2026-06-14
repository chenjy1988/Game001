#!/usr/bin/env bash
# Shared Godot headless environment (running-headless-godot skill).
# Source from tools/*.sh:  source "$(dirname "$0")/godot_env.sh"

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export PROJECT_DIR

export XDG_DATA_HOME="$PROJECT_DIR/.godot-xdg/data"
export XDG_CONFIG_HOME="$PROJECT_DIR/.godot-xdg/config"
export XDG_CACHE_HOME="$PROJECT_DIR/.godot-xdg/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$PROJECT_DIR/logs"

if command -v godot >/dev/null 2>&1; then
	GODOT_BIN="godot"
elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
	GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
else
	echo "godot binary not found in PATH or /Applications/Godot.app" >&2
	exit 127
fi
export GODOT_BIN
