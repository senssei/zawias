# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Uruchamia kilka skryptów pipeline'u w jednym procesie Blendera (oszczędza czas startu).

Użycie: blender -b --python run_steps.py -- <kroki.json>
kroki.json: [{"script": "prep_for_rig.py", "args": [...]}, ...]  (ścieżki w formacie Blendera)
"""
import json
import os
import runpy
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
steps = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
failed = False
for st in steps:
    sys.argv = [sys.argv[0], "--", *st["args"]]
    try:
        runpy.run_path(os.path.join(HERE, st["script"]), run_name="__main__")
    except SystemExit as ex:
        if ex.code not in (None, 0):
            print("STEP_FAILED %s: %s" % (st["script"], ex.code))
            failed = True
            break
    except Exception:
        traceback.print_exc()
        print("STEP_FAILED %s" % st["script"])
        failed = True
        break
print("STEPS_DONE" if not failed else "STEPS_ABORTED")
