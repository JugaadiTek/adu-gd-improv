#!/usr/bin/env bash
# Runs the automated test suite headlessly and exits with its exit code.
# Usage: ./tools/run_tests.sh
# Set GODOT_BIN to override the Godot executable path.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
	for candidate in \
		"X:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe" \
		"D:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe"; do
		if [ -f "$candidate" ]; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [ -z "$GODOT" ] && command -v godot >/dev/null 2>&1; then
	GODOT="$(command -v godot)"
fi
if [ -z "$GODOT" ]; then
	echo "Could not find a Godot 4.7 executable. Set GODOT_BIN to its path." >&2
	exit 1
fi

echo "Using Godot: $GODOT"
"$GODOT" --headless --path "$PROJECT_ROOT" --import
"$GODOT" --headless --path "$PROJECT_ROOT" "res://scenes/tests/TestRunner.tscn"
