# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Walidacja profili i podgląd animacji czarów na mapie gry."""

import argparse
from html import escape
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parents[2]
KINDS = {"aura", "beam", "bolt", "burst", "cone", "pillar", "volley"}
PHASES = (18, 50, 83)


def validate():
    spells = json.loads((ROOT / "data/spells.json").read_text(encoding="utf-8"))
    profiles = json.loads((ROOT / "data/spell_fx.json").read_text(encoding="utf-8"))
    if not isinstance(profiles, dict):
        raise ValueError("data/spell_fx.json: oczekiwano słownika profili")
    errors = [f"{id_}: brak profilu" for id_ in sorted(spells.keys() - profiles.keys())]
    errors.extend(f"{id_}: nieznany czar" for id_ in sorted(profiles.keys() - spells.keys()))
    for id_ in sorted(profiles.keys() & spells.keys()):
        profile = profiles[id_]
        if not isinstance(profile, dict) or profile.keys() != {"kind", "color", "seconds"}:
            errors.append(f"{id_}: oczekiwane pola kind, color i seconds")
            continue
        kind, color, seconds = (profile[key] for key in ("kind", "color", "seconds"))
        if not isinstance(kind, str) or kind not in KINDS:
            errors.append(f"{id_}: nieznany rodzaj efektu {kind!r}")
        if not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
            errors.append(f"{id_}: kolor musi mieć format #RRGGBB")
        if type(seconds) not in (int, float) or not 0.15 <= seconds <= 2.0:
            errors.append(f"{id_}: czas musi mieścić się w zakresie 0.15–2.0 s")
        shape = spells[id_].get("area", {}).get("shape")
        if (kind == "cone") != (shape == "cone"):
            errors.append(f"{id_}: profil cone musi odpowiadać stożkowi w zasadach czaru")
        if kind == "volley" and not spells[id_].get("darts"):
            errors.append(f"{id_}: profil volley wymaga liczby pocisków w zasadach czaru")
    return spells, errors


def write_review(staging, output, ids, spells):
    rows = []
    frames = []
    for id_ in ids:
        name = escape(spells[id_]["name"])
        cells = []
        for phase in PHASES:
            filename = f"{id_}-{phase:02d}.png"
            frame = staging / filename
            with frame.open("rb") as image:
                if image.read(8) != b"\x89PNG\r\n\x1a\n":
                    raise ValueError(f"{filename}: niepoprawna klatka PNG")
            frames.append(frame)
            src = escape(filename, quote=True)
            cells.append(f'<td><a href="{src}"><img src="{src}" alt="{name}, {phase}%"></a></td>')
        rows.append(f'<tr><th scope="row">{name}<small>{escape(id_)}</small></th>{"".join(cells)}</tr>')
    headings = "".join(f'<th scope="col">{phase}%</th>' for phase in PHASES)
    report = staging / "index.html"
    report.write_text(f"""<!doctype html>
<html lang="pl">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Przegląd animacji czarów</title>
<style>
body {{ margin: 1.5rem; font: 16px system-ui; color: #f4e4cf; background: #1b1420; }}
table {{ width: 100%; border-collapse: collapse; table-layout: fixed; }}
th, td {{ text-align: left; padding: .35rem; vertical-align: top; }}
th:first-child {{ width: 11rem; overflow-wrap: anywhere; }}
small {{ display: block; margin-top: .3rem; color: #c5ad94; }}
img {{ display: block; width: 100%; height: auto; }}
</style>
<h1>Przegląd animacji czarów</h1>
<table><thead><tr><th scope="col">Czar</th>{headings}</tr></thead>
<tbody>{"".join(rows)}</tbody></table>
</html>
""", encoding="utf-8")
    for frame in frames:
        frame.replace(output / frame.name)
    report.replace(output / report.name)
    print(f"SPELLFX_REVIEW_OK: {output / report.name} ({len(ids)} czarów)")


def main():
    cli = argparse.ArgumentParser(prog="pipeline.sh spellfx")
    commands = cli.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    preview = commands.add_parser("preview")
    preview.add_argument("id")
    preview.add_argument("--once", action="store_true", help="zakończ po jednym odtworzeniu")
    preview.add_argument("--headless", action="store_true", help="odtwórz raz bez okna")
    capture = commands.add_parser("capture")
    capture.add_argument("id")
    capture.add_argument("output", type=Path)
    review = commands.add_parser("review")
    review.add_argument("output", type=Path)
    review.add_argument("--only", metavar="ID,...", help="lista czarów rozdzielona przecinkami")
    for command in (preview, capture, review):
        command.add_argument("--godot", default=os.environ.get("GODOT") or shutil.which("godot") or "godot")
    args = cli.parse_args()
    try:
        spells, errors = validate()
        if args.command == "review":
            ids = list(spells) if args.only is None else list(dict.fromkeys(
                id_.strip() for id_ in args.only.split(",")))
        else:
            ids = [] if args.command == "check" else [args.id]
        errors.extend(f"{id_!r}: nieznany czar" for id_ in ids if id_ not in spells)
        if errors:
            for error in errors:
                print(f"SPELLFX_ERROR: {error}", file=sys.stderr)
            return 1
        if args.command == "check":
            print(f"SPELLFX_OK: {len(spells)} profili")
            return 0
        engine = [args.godot, "--path", str(ROOT)]
        if args.command in ("capture", "review"):
            output = args.output.resolve()
            output.mkdir(parents=True, exist_ok=True)
            engine.extend(["--fixed-fps", "60", "--resolution", "960x540", "--audio-driver", "Dummy"])
        elif args.headless:
            engine.append("--headless")
        engine.extend(["--", "--quickstart", "--class=wizard", "--goto=11,8",
                       "--camat=12,8", "--zoom=10", "--showcase", f"--spellfx={','.join(ids)}"])
        if args.command == "review":
            with TemporaryDirectory(prefix=".spellfx-", dir=output) as directory:
                staging = Path(directory)
                result = subprocess.run([*engine, f"--spellfx-capture={staging}"], check=False)
                if result.returncode:
                    return result.returncode
                write_review(staging, output, ids, spells)
                return 0
        if args.command == "capture":
            engine.append(f"--spellfx-capture={output}")
        elif args.once or args.headless:
            engine.append("--spellfx-once")
        return subprocess.run(engine, check=False).returncode
    except (OSError, ValueError) as error:
        print(f"SPELLFX_ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
