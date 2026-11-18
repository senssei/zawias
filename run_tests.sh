#!/usr/bin/env bash
# Uruchamia testy jednostkowe GUT w trybie headless.
GODOT="${GODOT:-$HOME/.local/bin/godot}"
cd "$(dirname "$0")"
"$GODOT" --headless --import >/dev/null 2>&1
ZAWIAS_LANG=pl "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit "$@"
