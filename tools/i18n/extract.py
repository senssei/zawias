#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Wyciąga napisy do tłumaczenia ze skryptów GDScript: literały z polskimi znakami albo zdania (spacja + litera).
Wypisuje JSON {plik: [napisy]}; pomija ścieżki, identyfikatory, BBCode bez tekstu i linie oznaczone `# notr`."""
import json, re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
LIT = re.compile(r'(?<![\\\w])"((?:[^"\\\n]|\\.)*)"')
PL = set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")
SKIP = {"Music", "Ambient", "Master", "SFX", "Label", "Panel", "Button", "Audio", "Sap", "Vex", "GameState", "Loc",
        "ZAWIAS", "ProgressBar", "PaintedArea", " / Language", "Graze", "Push", "Slow", "Topple", "Cleave", "Nick", "Polski", "English", "OK"}
DEBUG = re.compile(r"\b(push_error|push_warning|print|printerr|prints|assert)\(")


def wanted(s: str) -> bool:
    if not s or s.startswith(("res://", "user://", "uid://", "--", "#")):
        return False
    if "/" in re.sub(r"\[/?[a-z_]+(=[^\]]*)?\]", "", s) and " " not in s:
        return False   # ścieżka (BBCode z [/tag] nie liczy się jako ścieżka)
    if s in SKIP:
        return False
    core = re.sub(r"\[/?[a-z_]+(=[^\]]*)?\]|\[[A-Z0-9]{1,6}\]|%[-+0-9.]*[sdf%]|\{[a-z_0-9]*\}|\\n", " ", s).strip()
    if not re.search(r"[A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]{2,}", core):
        return False
    if any(c in PL for c in core):
        return True
    if re.fullmatch(r"[a-z0-9_.:]+", s) or re.fullmatch(r"[A-Z][A-Za-z0-9]+(Container|Label|Button|Edit|Box|Slider|Rect|Panel)", s):
        return False   # identyfikator albo typ węzła/motywu
    words = re.findall(r"[A-Za-z]{3,}", core)
    return bool(words) and (" " in s.strip() or bool(re.match(r"^[A-Z(]", core)))


def scan(path):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        code = line.split("##")[0]
        if "# notr" in line or code.lstrip().startswith("#") or DEBUG.search(code):
            continue
        if re.search(r'#[^"]*$', code):
            code = code[:code.rfind("#")] if code.count('"') % 2 == 0 and '"' not in code[code.rfind("#"):] else code
        for m in LIT.finditer(code):
            if wanted(m.group(1)):
                out.append(m.group(1))
    return out


if __name__ == "__main__":
    res = {}
    for p in sorted((ROOT / "scripts").rglob("*.gd")):
        s = scan(p)
        if s:
            res[str(p.relative_to(ROOT))] = s
    json.dump(res, sys.stdout, ensure_ascii=False, indent=1)
