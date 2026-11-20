#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Opakowuje napisy do tłumaczenia w Loc.t("...") (wykrywanie jak w extract.py).
Pomija: stałe (także wielowierszowe), linie `func` (argumenty domyślne muszą być stałe), komunikaty debugowe,
napisy już opakowane. Wypisuje pominięte napisy ze stałych, które trzeba tłumaczyć w miejscu użycia.
Użycie: wrap.py [--dry-run]"""
import re, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from extract import ROOT, LIT, DEBUG, wanted

dry = "--dry-run" in sys.argv
skipped = []
changed = 0
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    if path.name == "loc.gd":
        continue
    out, depth, in_const = [], 0, False
    for line in path.read_text(encoding="utf-8").splitlines(keepends=True):
        code = line.split("##")[0]
        stripped = code.lstrip()
        starts_const = stripped.startswith(("const ", "static const ", "@export", "enum "))
        no_str = LIT.sub('""', code)
        if starts_const and not in_const:
            in_const = True
            depth = 0
        if in_const:
            depth += no_str.count("[") + no_str.count("{") + no_str.count("(") - no_str.count("]") - no_str.count("}") - no_str.count(")")
            for m in LIT.finditer(code):
                if wanted(m.group(1)):
                    skipped.append(f"{path.relative_to(ROOT)}: {m.group(1)}")
            if depth <= 0:
                in_const = False
            out.append(line)
            continue
        if stripped.startswith(("func ", "static func ", "#")) or "# notr" in line or DEBUG.search(code) or stripped.startswith("match "):
            out.append(line)
            continue

        def rep(m):
            s = m.group(1)
            pre = code[:m.start()]
            if not wanted(s) or pre.endswith(("Loc.t(", "tr(")):
                return m.group(0)
            return f'Loc.t("{s}")'
        new = LIT.sub(rep, code) + line[len(code):]
        if new != line:
            changed += 1
        out.append(new)
    if not dry:
        path.write_text("".join(out), encoding="utf-8")
print(f"zmienione linie: {changed}")
print("POMINIĘTE (stałe):")
for s in skipped:
    print("  " + s)
