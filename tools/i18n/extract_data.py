#!/usr/bin/env python3
"""Teksty do tłumaczenia z data/**/*.json jako płaska mapa {"plik:ścieżka": "tekst"} (format i18n/<lang>/data.json).
Pomija pola z identyfikatorami i wyrażeniami (ID_KEYS) oraz napisy bez liter. --missing i18n/en/data.json: tylko brakujące."""
import json, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from extract import ROOT

ID_KEYS = {"id", "next", "if", "flag", "set_flag", "clear_flag", "flags", "monster", "shape", "dialogue", "school",
           "cast", "type", "target", "damage", "damage_type", "save", "ability", "skill", "condition", "item", "items",
           "quest", "stage", "encounter", "model", "portrait", "color", "start", "on_hit", "effect", "heal", "upcast",
           "rows", "legend_char", "unlock", "requires", "remove_item", "give_item", "has_item", "quest_any", "spell",
           "spells", "cantrips", "weapon", "weapons", "armor", "mastery", "properties", "hit_die", "primary", "saves",
           "skills", "category", "kind", "size", "speed_type", "die", "dc", "surprise_unless_flag", "paint_kind",
           "subclass", "class", "species", "background", "feat", "origin_feat", "tool", "tools", "language", "tags",
           "range_type", "versatile", "end_game", "set_quest", "recharge", "attacks", "uses", "resource", "equipment"}


def walk(node, path, out, key=""):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ID_KEYS and not isinstance(v, dict) and not (isinstance(v, list) and v and isinstance(v[0], dict)):
                continue   # identyfikator; ta sama nazwa jako klucz węzła/wpisu (np. "start", "versatile") jest przeglądana
            walk(v, path + [k], out, k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, path + [str(i)], out, key)
    elif isinstance(node, str):
        if any(c.isalpha() for c in node) and (" " in node or not node.islower()) and not node.startswith("res://"):
            out["/".join(path)] = node


def collect():
    out = {}
    for p in sorted((ROOT / "data").rglob("*.json")):
        key = str(p.relative_to(ROOT / "data"))[:-5]
        flat = {}
        walk(json.loads(p.read_text(encoding="utf-8")), [], flat)
        for k, v in flat.items():
            out[f"{key}:{k}"] = v
    return out


if __name__ == "__main__":
    d = collect()
    if "--missing" in sys.argv:
        have = json.loads(pathlib.Path(sys.argv[sys.argv.index("--missing") + 1]).read_text(encoding="utf-8"))
        d = {k: v for k, v in d.items() if k not in have}
    json.dump(d, sys.stdout, ensure_ascii=False, indent=1)
