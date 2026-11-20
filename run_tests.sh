#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
# Uruchamia testy jednostkowe GUT w trybie headless (najpierw kontrola licencji SPDX i danych fabuły).
GODOT="${GODOT:-$HOME/.local/bin/godot}"
cd "$(dirname "$0")"
python3 tools/dev/spdx_check.py | tail -1 | grep -q SPDX_OK || { python3 tools/dev/spdx_check.py; echo "Brak licencji SPDX: dopisz nagłówek albo wpis w REUSE.toml"; exit 1; }
# dane fabuły: odwołania i przejścia (story check), reguły pisania (story lint, docs/story-pipeline.md)
python3 tools/pipeline/story.py check >/dev/null || { python3 tools/pipeline/story.py check; exit 1; }
python3 tools/pipeline/story.py lint --strict >/dev/null || { python3 tools/pipeline/story.py lint; echo "Popraw ostrzeżenia story lint"; exit 1; }
# klucze tłumaczeń i nagrań okrzyków zgodne z polskim tekstem (story keys, docs/localization.md)
python3 tools/pipeline/test_story_keys.py >/dev/null 2>&1 || { python3 tools/pipeline/test_story_keys.py; exit 1; }
python3 tools/pipeline/story.py keys --strict >/dev/null || { python3 tools/pipeline/story.py keys; echo "Przesunięte albo nieaktualne tłumaczenia: tools/pipeline/pipeline.sh story keys --fix"; exit 1; }
"$GODOT" --headless --import >/dev/null 2>&1
ZAWIAS_LANG=pl "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gpost_run_script=res://tests/stop_audio.gd -gexit "$@"
