# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""story report (docs/story-pipeline.md): jedna strona HTML do przeglądu przed playtestem.

Zbiera: story check, story lint, story keys, pokrycie nagrań, oś fabuły i ślady w mgle, macierz konsekwencji
frakcji, porażki i ich wyjścia, story paths, story balance oraz listę decyzji wynikających z tych danych.
Użycie: pipeline.sh story report --out work/story-report [--paths-json p.json] [--balance-json b.json]
"""
import html
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def esc(s):
    return html.escape(str(s))


def table(head, rows):
    out = ["<table><tr>" + "".join(f"<th>{esc(h)}</th>" for h in head) + "</tr>"]
    for r in rows:
        out.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
    out.append("</table>")
    return "".join(out)


def faction_matrix(check):
    """[(frakcja, nastawienie, opis skutku, źródła set_reputation, warunki)]"""
    sources = {}
    for name, data in check.dialogues.items():
        for node_id, node in data.get("nodes", {}).items():
            effs = [("", node.get("effects", []))] + [(f"#{i}", c.get("effects", [])) for i, c in enumerate(node.get("choices", []))]
            for suffix, lst in effs:
                for e in lst:
                    if "set_reputation" in e:
                        sources.setdefault(tuple(e["set_reputation"]), []).append(f"{name}/{node_id}{suffix}")
    for name, enc in check.encounters.items():
        for e in enc.get("on_victory", []):
            if "set_reputation" in e:
                sources.setdefault(tuple(e["set_reputation"]), []).append(f"walka {name}")
    uses = {}
    for where, cond in check.all_conditions():
        for key in ("reputation", "reputation_not"):
            if key in cond:
                f, a = cond[key]
                label = where if key == "reputation" else f"{where} (nie)"
                uses.setdefault((f, a), []).append(label)
    rows = []
    for f, data in check.factions.items():
        for a in ("friendly", "neutral", "wary"):
            rows.append((data.get("name", f), a, data.get("effects", {}).get(a, ""), sources.get((f, a), []), uses.get((f, a), [])))
    return rows


def failures(check):
    """[(dialog/węzeł porażki, test, wyjście)]"""
    out = []
    for name, data in check.dialogues.items():
        nodes = data.get("nodes", {})
        for node_id, node in nodes.items():
            for i, ch in enumerate(node.get("choices", [])):
                chk = ch.get("check")
                if not chk or chk.get("fail") not in nodes:
                    continue
                fail = nodes[chk["fail"]]
                journal = [e["journal"] for e in fail.get("effects", []) if "journal" in e]
                fight = any("start_combat" in e for c in fail.get("choices", []) for e in c.get("effects", []))
                exits = [c["text"] for c in fail.get("choices", []) if c.get("next") and not c.get("end")]
                way = journal[0] if journal else ("walka" if fight else ("; ".join(exits) if exits else "—"))
                skill = chk.get("skill", chk.get("ability", "?"))
                out.append((f"{name}/{chk['fail']}", f"{skill} ST {chk.get('dc')} ({name}/{node_id}#{i})", way))
    return out


def decisions(paths, balance_problems, lint, keys, voice):
    early = {}
    for r in paths or []:
        for enc, c in r["combats"].items():
            if c["min_level"] < 2 and c["min_xp"] == 0 and enc != "ambush":
                early.setdefault(enc, []).append(r["class"])
    out = [f"{enc}: dostępna na 1. poziomie bez PD ({', '.join(cls)})." for enc, cls in sorted(early.items())]
    out += [f"Balans: odwrócona kolejność poziomów: {p}" for p in balance_problems]
    unseen = None
    for r in paths or []:
        u = set(r["unseen_choices"])
        unseen = u if unseen is None else unseen & u
    if unseen:
        out.append("Wybory niewidoczne w żadnym przebiegu: " + ", ".join(sorted(unseen)) + " (rzadkie kombinacje albo martwy tekst).")
    if lint:
        out.append(f"story lint: {len(lint)} ostrzeżeń.")
    if keys:
        out.append(f"story keys: {len(keys)} przesuniętych albo nieaktualnych tłumaczeń.")
    for lang, key_missing, all_missing in voice:
        if all_missing:
            out.append(f"Nagrania [{lang}]: {len(all_missing)} węzłów bez głosu, w tym kluczowe: {len(key_missing)}.")
    return out


def main(args, check):
    import story
    import story_keys
    out_dir = Path(args.out or ROOT / "work" / "story-report").resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    lint = check.lint()
    langs = sorted(p.parent.name for p in (ROOT / "i18n").glob("*/data.json"))
    keys = story_keys.run(langs)
    voice = check.voice_report()
    with tempfile.TemporaryDirectory(prefix="zawias-report-") as tmp:
        if args.paths_json:
            paths = json.loads(Path(args.paths_json).read_text(encoding="utf-8"))
        else:
            pj = Path(tmp) / "paths.json"
            code, log = story.run_godot([f"--story-paths={pj}", f"--classes={args.classes}",
                                         f"--max-states={args.max_states}", f"--walks={args.walks}"], tmp)
            paths = json.loads(pj.read_text(encoding="utf-8")) if pj.exists() else []
            if not paths:
                print(log, file=sys.stderr)
    rows = json.loads(Path(args.balance_json).read_text(encoding="utf-8")) if args.balance_json \
        else (story.balance_rows(args.classes, args.seeds) or [])
    bal_problems = story.balance_problems(rows)

    sec = []
    sec.append("<h2>Stan</h2>" + table(["Kontrola", "Wynik"], [
        ("story check", f"błędy {len(check.errors)}, ostrzeżenia {len(check.warnings)}"),
        ("story lint", f"{len(lint)} ostrzeżeń"),
        ("story keys", f"{len(keys)} uwag"),
        *[(f"nagrania [{l}]", f"bez głosu {len(a)}, kluczowe {len(k)}") for l, k, a in voice],
        ("story paths", f"{len(paths)} klas"), ("story balance", f"{len(rows)} komórek, problemy {len(bal_problems)}"),
    ]))
    dec = decisions(paths, bal_problems, lint, keys, voice)
    sec.append("<h2>Do decyzji</h2>" + ("<ul>" + "".join(f"<li>{esc(d)}</li>" for d in dec) + "</ul>" if dec else "<p>Brak.</p>"))
    arc_rows = []
    for quest, data in check.arcs.items():
        for beat in data["beats"]:
            arc_rows.append((esc(quest), esc(beat["stage"]), esc(", ".join(beat["sources"]))))
    for name, m in check.maps.items():
        for mem in m.get("memories", []):
            arc_rows.append(("ślad w mgle", esc(mem["id"]), esc(mem.get("journal", mem["text"]))))
    sec.append("<h2>Oś fabuły i ślady</h2>" + table(["Oś", "Etap", "Źródła"], arc_rows))
    sec.append("<h2>Konsekwencje frakcji</h2>" + table(["Frakcja", "Nastawienie", "Opis w dzienniku", "Skąd", "Co zmienia"],
        [(esc(f), esc(a), esc(t) or "—", esc(", ".join(s)) or "—", esc(", ".join(u)) or "—") for f, a, t, s, u in faction_matrix(check)]))
    sec.append("<h2>Porażki i wyjścia</h2>" + table(["Węzeł porażki", "Test", "Co dalej"],
        [(esc(a), esc(b), esc(c)) for a, b, c in failures(check)]))
    prow = []
    for r in paths:
        ends = "; ".join(f"{k}: {v['count']} dróg, najkrótsza {len(v['path'])}" for k, v in sorted(r["endings"].items()))
        fights = "; ".join(f"{k}: poziom {c['min_level']}–{c['max_level']}, PD {c['min_xp']}–{c['max_xp']}" for k, c in sorted(r["combats"].items()))
        prow.append((esc(r["class"]), esc(ends), esc(fights), esc(r["dead_end_count"])))
    sec.append("<h2>Przejścia (story paths)</h2>" + table(["Klasa", "Finały", "Walki", "Ślepe zaułki"], prow))
    diffs = ["story", "normal"]
    cells = {(r["encounter"], r["class"], r["party"], r["difficulty"]): r for r in rows}
    brow = []
    for key in dict.fromkeys((r["encounter"], r["level"], r["class"], r["party"]) for r in rows):
        enc, lvl, cls, party = key
        brow.append((esc(f"{enc} ({lvl})"), esc(cls), "solo" if party == "solo" else "z Lis",
                     *[esc(f"{cells[(enc, cls, party, d)]['wins']}/{cells[(enc, cls, party, d)]['n']}") if (enc, cls, party, d) in cells else "—" for d in diffs]))
    sec.append("<h2>Balans (story balance)</h2>" + table(["Spotkanie (poziom)", "Klasa", "Skład", "Opowieść", "Normalny"], brow))
    page = ('<!doctype html><html lang="pl"><meta charset="utf-8"><title>Raport fabuły Zawiasu</title>'
            '<style>body{margin:2rem auto;max-width:1100px;padding:0 1rem;font:15px system-ui;background:#201725;color:#f8e8d0}'
            'table{border-collapse:collapse;width:100%;margin:.5rem 0 1.5rem}td,th{border:1px solid #4a3a48;padding:.3rem .5rem;'
            'vertical-align:top;text-align:left}th{background:#2f2236}h2{color:#d9b36c;margin-top:2rem}</style>'
            '<h1>Raport fabuły Zawiasu</h1>' + "".join(sec) + "</html>")
    (out_dir / "index.html").write_text(page, encoding="utf-8")
    print(f"STORY_REPORT_OK: {out_dir / 'index.html'} (decyzje: {len(dec)})")
    return 0
