# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Sprawdza scenariusze storyboardu oraz odtwarza je w Godot."""

import argparse
import os
import re
import shutil
import subprocess
import sys
from html import escape
from pathlib import Path
from tempfile import TemporaryDirectory

from story import ROOT, StoryCheck


def check_board(id_):
    check = StoryCheck(ROOT)
    boards = check.load("data/storyboard.json")
    if id_ not in boards or id_ not in check.maps:
        raise ValueError(f"Nieznana plansza {id_!r}")
    board = boards[id_]
    map_data = check.maps[id_]
    actors = {actor["id"]: actor.get("dialogue") for group in ("npcs", "objects")
              for actor in map_data.get(group, [])}
    actors_all = set(actors) | {spawn["id"] for enc in check.encounters.values() for spawn in enc.get("spawn", [])}
    spells = check.load("data/spells.json")
    classes = check.load("data/classes.json")
    seen = set()
    for panel in board["panels"]:
        name = panel["id"]
        if not re.fullmatch("[a-z0-9-]+", name) or name in seen:
            raise ValueError(f"Niepoprawny lub powtórzony identyfikator {name!r}")
        seen.add(name)
        check.quest_pair(name, panel["expect"]["quest"], allow_empty=False)
        dialogue = None
        steps = [entry for step in panel["steps"]
                 for entry in (board[step["sequence"]] if "sequence" in step else [step])]
        for step in steps:
            if "actor" in step:
                dialogue = actors.get(step["actor"])
                check.reference(name, dialogue, check.dialogues, "dialog aktora")
            elif "node" in step:
                nodes = check.dialogues.get(dialogue, {}).get("nodes", {})
                if check.reference(name, step["node"], nodes, "węzeł"):
                    if type(step["choice"]) is not int or not 0 <= step["choice"] < len(nodes[step["node"]].get("choices", [])):
                        check.errors.append(f"{name}: brak wyboru {step}")
            elif "cast" in step:
                if step["cast"] not in spells:
                    check.errors.append(f"{name}: nieznany czar {step}")
            elif "target" in step:
                if step["target"] not in actors_all:
                    check.errors.append(f"{name}: nieznany cel {step}")
            elif step not in ({"menu": "map"}, {"menu": "spellbook"}, {"wait": "player_turn"}, {"wait": "companion"}):
                check.errors.append(f"{name}: nieznana czynność {step}")
        if panel.get("class", "rogue") not in classes:
            check.errors.append(f"{name}: nieznana klasa {panel['class']!r}")
    if not seen or check.errors:
        raise ValueError("\n".join(check.errors) or "Brak kadrów")
    return board["panels"]


def review(args, panels):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    engine = os.environ.get("GODOT") or shutil.which("godot") or "godot"
    with TemporaryDirectory(prefix=".storyboard-", dir=output) as temp, TemporaryDirectory(prefix="zawias-saves-") as saves:
        staging = Path(temp)
        env = dict(os.environ, XDG_DATA_HOME=saves, XDG_CONFIG_HOME=saves)
        command = [engine, "--path", str(ROOT), "--resolution", "960x540", "--audio-driver", "Dummy"]
        result = subprocess.run([*command, "--", "--quickstart", "--class=rogue",
                                 f"--map={args.id}", f"--lang={args.lang}",
                                 f"--storyboard={args.id}", f"--storyboard-output={staging}"], env=env)
        if result.returncode:
            return result.returncode
        sections = []
        for panel in panels:
            file = staging / (panel["id"] + ".png")
            with file.open("rb") as image:
                if image.read(8) != b"\x89PNG\r\n\x1a\n":
                    raise ValueError(f"{file.name}: niepoprawny PNG")
            title = escape(panel["title"])
            question = escape(panel["question"])
            quest, stage = panel["expect"]["quest"]
            expected = escape(f"{quest} = {stage}")
            sections.append(f'<section><h2>{title}</h2><p>{question}</p><code>{expected}</code>'
                            f'<p><a href="{file.name}"><img src="{file.name}" alt="{title}"></a></p></section>')
        report = staging / "index.html"
        report.write_text('<!doctype html><html lang="pl"><meta charset="utf-8">'
                          '<title>Storyboard Zawiasu</title>'
                          '<style>body{margin:2rem auto;max-width:960px;padding:0 1rem;'
                          'font:16px system-ui;background:#201725;color:#f8e8d0}img{width:100%}</style>'
                          f'<h1>Storyboard Zawiasu · {args.lang.upper()}</h1>{"".join(sections)}</html>', encoding="utf-8")
        for file in sorted(staging.glob("*.png")):
            file.replace(output / file.name)
        report.replace(output / report.name)
    print(f"STORYBOARD_REVIEW_OK: {output / 'index.html'}")
    return 0


def main():
    parser = argparse.ArgumentParser(prog="pipeline.sh storyboard")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check").add_argument("id")
    render = sub.add_parser("review")
    render.add_argument("id")
    render.add_argument("output", type=Path)
    render.add_argument("--lang", choices=("pl", "en"), default="pl")
    args = parser.parse_args()
    try:
        panels = check_board(args.id)
        if args.command == "review":
            return review(args, panels)
        print(f"STORYBOARD_OK: {len(panels)} kadry")
        return 0
    except (OSError, KeyError, TypeError, ValueError) as error:
        print(f"STORYBOARD_ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
