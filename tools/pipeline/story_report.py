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
    """[(dialog/węzeł porażki, test, wyjście, czy porażka niczego nie daje)]: bez wpisu w dzienniku i bez walki."""
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
                exits = list(dict.fromkeys(c["text"] for c in fail.get("choices", []) if c.get("next") and not c.get("end")))
                # porażka, po której rozmowa idzie tam, gdzie po sukcesie (np. targowanie), niczego nie zamyka
                after_fail = {c.get("next") for c in fail.get("choices", []) if c.get("next")}
                after_win = {c.get("next") for c in nodes.get(chk.get("success"), {}).get("choices", []) if c.get("next")}
                same_way = bool(after_fail) and after_fail <= after_win
                way = journal[0] if journal else ("walka" if fight else ("; ".join(exits) if exits else "—"))
                skill = chk.get("skill", chk.get("ability", "?"))
                out.append((f"{name}/{chk['fail']}", f"{skill} ST {chk.get('dc')} ({name}/{node_id}#{i})", way, not journal and not fight and not same_way and not chk.get("gain_effects")))
    return out


def choice_text(check, key):
    """Tekst wyboru „dialog/węzeł/indeks” albo pusty napis."""
    try:
        name, node, idx = key.rsplit("/", 2)
        return check.dialogues[name]["nodes"][node]["choices"][int(idx)].get("text", "")
    except (KeyError, IndexError, ValueError):
        return ""


# Sprawy rozstrzygnięte przez autora: raport pokazuje je jako przyjęte, a nie jako decyzje do podjęcia.
ACCEPTED_EARLY_COMBAT = {"warehouse": "decisions/0007-level-one-risks.md"}
# (spotkanie, klasa, poziom trudności), w których towarzyszka może być wyraźnie gorsza niż solo.
ACCEPTED_COMPANION_DROPS = {("ambush", "wizard", "normal"): "decisions/0007-level-one-risks.md"}


def decisions(check, paths, balance_problems, lint, keys, voice):
    """[(tytuł, treść HTML, kotwica sekcji)]: sprawy, które wymagają decyzji autora."""
    out = []
    early = {}
    for r in paths or []:
        for enc, c in r["combats"].items():
            if c["min_level"] < 2 and c["min_xp"] == 0 and enc != "ambush" and enc not in ACCEPTED_EARLY_COMBAT:
                early.setdefault(enc, []).append(r["class"])
    for enc, cls in sorted(early.items()):
        out.append((f"Walka {enc} dostępna na 1. poziomie bez PD",
                    f"Klasy: {esc(', '.join(cls))}. Najkrótsza droga omija wszystkie źródła PD.", "paths"))
    bare = sorted({node for node, _, _, b in failures(check) if b})
    if bare:
        out.append((f"Porażki bez treści ({len(bare)})", "Ani wpisu w dzienniku, ani walki: gracz nie wie, co dalej "
                    "(zasada 4). " + ", ".join(f"<code>{esc(n)}</code>" for n in bare), "failures"))
    for p in balance_problems:
        out.append(("Odwrócona kolejność poziomów trudności", esc(p), "balance"))
    unseen = None
    for r in paths or []:
        u = set(r["unseen_choices"])
        unseen = u if unseen is None else unseen & u
    if unseen:
        items = "".join(f"<li><code>{esc(k)}</code> {esc(choice_text(check, k))}</li>" for k in sorted(unseen))
        out.append((f"Wybory niewidoczne w żadnym przebiegu ({len(unseen)})",
                    f"Rzadkie kombinacje warunków albo martwy tekst.<ul class=compact>{items}</ul>", "paths"))
    if lint:
        out.append((f"story lint: {len(lint)} ostrzeżeń", "Uruchom <code>pipeline.sh story lint</code>.", "status"))
    if keys:
        out.append((f"story keys: {len(keys)} uwag", "Przesunięte albo nieaktualne tłumaczenia.", "status"))
    for lang, key_missing, all_missing in voice:
        if all_missing:
            items = ", ".join(f"<code>{esc(n)}</code>" for n in all_missing)
            out.append((f"Nagrania [{esc(lang)}]: {len(all_missing)} węzłów bez głosu (kluczowe: {len(key_missing)})",
                        items, "status"))
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

    dec = decisions(check, paths, bal_problems, lint, keys, voice)
    cells = {(r["encounter"], r["class"], r["party"], r["difficulty"]): r for r in rows}
    lis_drops = []
    for (enc, cls, party, diff), r in sorted(cells.items()):
        solo = cells.get((enc, cls, "solo", diff))
        if party != "solo" and solo and story.clearly_worse(r, solo):
            lis_drops.append((enc, cls, diff))
            if (enc, cls, diff) in ACCEPTED_COMPANION_DROPS:
                continue
            dec.append(("Z towarzyszką trudniej niż solo",
                        f"{esc(enc)} · {esc(cls)} · {DIFF[diff]}: z Lis {r['wins']}/{r['n']}, solo {solo['wins']}/{solo['n']}.",
                        "balance"))
    page = render(check, paths, rows, cells, bal_problems, lis_drops, lint, keys, voice, dec)
    (out_dir / "index.html").write_text(page, encoding="utf-8")
    print(f"STORY_REPORT_OK: {out_dir / 'index.html'} (decyzje: {len(dec)})")
    return 0


DIFF = {"story": "Opowieść", "normal": "Normalny"}
ATTITUDE = {"friendly": "przyjazne", "neutral": "neutralne", "wary": "nieufne"}

CSS = """
:root{--bg:#1a1214;--panel:#2a1d1c;--panel2:#3b2a26;--line:#4d3830;--brass:#d9a85b;--rust:#b5532a;
--text:#eadbc8;--muted:#a89584;--good:#8fcf7a;--bad:#e0634f;--planar:#9b7fd1;color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,sans-serif}
header{padding:2rem 1rem 1rem;max-width:1180px;margin:auto}
header h1{font:600 2rem Georgia,serif;color:var(--brass);margin:0}
header p{color:var(--muted);margin:.25rem 0 0}
nav{position:sticky;top:0;z-index:2;background:color-mix(in srgb,var(--bg) 92%,transparent);backdrop-filter:blur(6px);
border-bottom:1px solid var(--line)}
nav div{max-width:1180px;margin:auto;padding:.5rem 1rem;display:flex;gap:1rem;overflow-x:auto;white-space:nowrap}
nav a{color:var(--muted);text-decoration:none;font-size:.9rem}nav a:hover{color:var(--brass)}
main{max-width:1180px;margin:auto;padding:0 1rem 4rem}
h2{font:600 1.35rem Georgia,serif;color:var(--brass);margin:2.5rem 0 .75rem;scroll-margin-top:3rem}
h3{font-size:1rem;margin:0 0 .5rem}
code{font:.85em ui-monospace,monospace;color:var(--muted)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:.75rem}
.card{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--good);border-radius:6px;padding:.6rem .8rem}
.card.warn{border-left-color:var(--bad)}.card b{display:block;font-size:1.4rem}.card span{color:var(--muted);font-size:.85rem}
.dec{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--brass);border-radius:6px;padding:.7rem 1rem;margin:.6rem 0}
.dec h3 a{color:var(--text);text-decoration:none}.dec h3 a:after{content:" ↓";color:var(--muted);font-weight:400}
.dec div{color:var(--muted)}
ul.compact{margin:.4rem 0 0;padding-left:1.1rem}ul.compact li{margin:.15rem 0}
.wrap{overflow-x:auto}
table{border-collapse:collapse;width:100%;margin:.25rem 0 1rem;font-size:.92rem}
th,td{border-bottom:1px solid var(--line);padding:.4rem .55rem;vertical-align:top;text-align:left}
th{color:var(--muted);font-weight:500;background:var(--panel)}
.chip{display:inline-block;padding:0 .45rem;border-radius:99px;font-size:.8rem;border:1px solid var(--line);white-space:nowrap}
.chip.friendly{color:var(--good);border-color:var(--good)}.chip.wary{color:var(--bad);border-color:var(--bad)}
.chip.neutral{color:var(--muted)}.chip.fight{color:var(--bad);border-color:var(--bad)}.chip.skill{color:var(--planar);border-color:var(--planar)}
.heat td.v{text-align:center;font-variant-numeric:tabular-nums;font-weight:600;color:#1a1214;
background:color-mix(in oklab,var(--good) calc(var(--p)*100%),var(--bad))}
.heat td.v.flag{outline:3px solid var(--brass);outline-offset:-3px}
.heat td.grp{color:var(--brass)}
.legend{color:var(--muted);font-size:.85rem}
.classes{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:.75rem}
.cls{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:.8rem 1rem}
.cls dl{margin:0;display:grid;grid-template-columns:auto 1fr;gap:.2rem .7rem;font-size:.9rem}
.cls dt{color:var(--muted)}.cls dd{margin:0}
.route{font-size:.8rem;color:var(--muted)}
.timeline{display:flex;flex-wrap:wrap;gap:.5rem;margin-bottom:1rem}
.beat{background:var(--panel);border:1px solid var(--line);border-top:3px solid var(--planar);border-radius:6px;padding:.5rem .7rem;flex:1 1 160px}
.beat b{display:block}.beat span{color:var(--muted);font-size:.85rem}
"""


def render(check, paths, rows, cells, bal_problems, lis_drops, lint, keys, voice, dec):
    import datetime
    import story
    import subprocess
    try:
        rev = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"], capture_output=True, text=True).stdout.strip()
    except OSError:
        rev, dirty = "", ""
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    dead = sum(r["dead_end_count"] for r in paths)
    stuck = sum(r.get("walk_stuck", 0) for r in paths)
    walks = sum(r.get("walks", 0) for r in paths)

    def card(label, value, ok):
        return f'<div class="card{"" if ok else " warn"}"><b>{esc(value)}</b><span>{esc(label)}</span></div>'
    cards = [card("decyzji do podjęcia", len(dec), not dec),
             card("błędy story check", len(check.errors), not check.errors),
             card("ostrzeżenia story lint", len(lint), not lint),
             card("uwagi story keys", len(keys), not keys)]
    cards += [card(f"węzłów bez głosu [{l}]", len(a), not k) for l, k, a in voice]
    cards += [card(f"ślepe zaułki ({len(paths)} klasy)", dead, dead == 0),
              card(f"odwrócenia trudności ({len(rows)} komórek)", len(bal_problems), not bal_problems)]

    sec = [("status", "Stan", '<div class="cards">' + "".join(cards) + "</div>")]
    body = "".join(f'<div class="dec"><h3><a href="#{a}">{esc(t)}</a></h3><div>{b}</div></div>' for t, b, a in dec)
    sec.append(("decisions", "Do decyzji", body or "<p>Brak.</p>"))

    # balans: mapa cieplna
    groups = list(dict.fromkeys((r["encounter"], r["level"]) for r in rows))
    classes = list(dict.fromkeys(r["class"] for r in rows))
    parties = sorted({r["party"] for r in rows}, key=lambda p: (p != "solo", p))
    cols = [(d, p) for d in ("story", "normal") for p in parties]
    inverted = {(e, c, p) for (e, c, p, d), r in cells.items() if d == "story" and (e, c, p, "normal") in cells
                and story.clearly_worse(r, cells[(e, c, p, "normal")])}
    head = "<tr><th>Spotkanie</th><th>Klasa</th>" + "".join(
        f"<th>{DIFF[d]}<br><span class=legend>{'solo' if p == 'solo' else 'z ' + p.title()}</span></th>" for d, p in cols) + "</tr>"
    trs = []
    for enc, lvl in groups:
        for i, cls in enumerate(classes):
            tds = []
            for d, p in cols:
                r = cells.get((enc, cls, p, d))
                if not r:
                    tds.append("<td>—</td>")
                    continue
                flag = (enc, cls, p) in inverted or (enc, cls, d) in lis_drops and p != "solo"
                tds.append(f'<td class="v{" flag" if flag else ""}" style="--p:{min(1, max(0, 2 * r["wins"] / max(r["n"], 1) - 1)):.2f}">{r["wins"]}/{r["n"]}</td>')
            grp = f'<td class=grp rowspan={len(classes)}>{esc(enc)}<br><span class=legend>poziom {lvl}</span></td>' if i == 0 else ""
            trs.append(f"<tr>{grp}<td>{esc(cls)}</td>{''.join(tds)}</tr>")
    seeds = rows[0]["n"] if rows else 0
    sec.append(("balance", "Balans walk", f'<div class="wrap"><table class=heat>{head}{"".join(trs)}</table></div>'
                f'<p class=legend>Wygrane na {seeds} ziaren, AI po obu stronach. Kolor: od czerwieni (połowa lub mniej) do zieleni (komplet). Ramka: odwrócona kolejność trudności '
                f'albo wynik z towarzyszką gorszy niż solo, o ponad 2 błędy standardowe.</p>'))

    # przejścia
    cl = []
    for r in paths:
        ends = "".join(f'<dt>{esc(k)}</dt><dd>{v["count"]} dróg, najkrótsza {len(v["path"])} kroków'
                       f'<div class=route>{esc(" → ".join(v["path"]))}</div></dd>' for k, v in sorted(r["endings"].items()))
        fights = "".join(f'<dt>{esc(k)}</dt><dd>poziom {c["min_level"]}–{c["max_level"]}, PD {c["min_xp"]}–{c["max_xp"]}</dd>'
                         for k, c in sorted(r["combats"].items()))
        walk = ", ".join(f"{k} {v}" for k, v in sorted(r.get("walk_endings", {}).items()))
        cl.append(f'<div class=cls><h3>{esc(r["class"])}</h3><dl>{ends}{fights}'
                  f'<dt>losowo</dt><dd>{esc(walk)}; bez finału {r.get("walk_stuck", 0)}/{r.get("walks", 0)}</dd>'
                  f'<dt>ślepe</dt><dd>{r["dead_end_count"]}</dd></dl></div>')
    accepted = "".join(f'<p class=legend>Przyjęte: walka {esc(e)} dostępna na 1. poziomie bez PD '
                       f'(<code>docs/{esc(adr)}</code>).</p>' for e, adr in ACCEPTED_EARLY_COMBAT.items()
                       if any(r["combats"].get(e, {}).get("min_xp", 1) == 0 for r in paths))
    sec.append(("paths", "Przejścia", accepted + f'<div class=classes>{"".join(cl)}</div><p class=legend>Przeszukiwanie wszerz '
                f'plus {walks} losowych przejść (bez finału po limicie kroków: {stuck}). Poziom trudności: '
                f'{esc(DIFF.get(paths[0]["difficulty"], paths[0]["difficulty"]) if paths else "—")}.</p>'))

    # oś fabuły
    arcs = []
    for quest, data in check.arcs.items():
        beats = "".join(f'<div class=beat><b>{esc(b["stage"])}</b><span>{esc(", ".join(b["sources"]))}</span></div>' for b in data["beats"])
        arcs.append(f"<h3>{esc(quest)}</h3><div class=timeline>{beats}</div>")
    mems = [(esc(m["id"]), esc(m.get("journal", m["text"]))) for mm in check.maps.values() for m in mm.get("memories", [])]
    if mems:
        arcs.append("<h3>Ślady w mgle</h3>" + table(["Ślad", "Wpis w dzienniku"], mems))
    sec.append(("arc", "Oś fabuły", "".join(arcs)))

    frows = [(f"<b>{esc(f)}</b>", f'<span class="chip {a}">{ATTITUDE.get(a, a)}</span>', esc(t) or "—",
              esc(", ".join(s)) or "—", "<br>".join(f"<code>{esc(x)}</code>" for x in u) or "—")
             for f, a, t, s, u in faction_matrix(check)]
    sec.append(("factions", "Konsekwencje frakcji", '<div class="wrap">' +
                table(["Frakcja", "Nastawienie", "Opis w dzienniku", "Skąd", "Co zmienia"], frows) + "</div>"))

    fails = []
    for node, test, way, bare in failures(check):
        skill, _, where = test.partition(" (")
        way_html = '<span class="chip fight">walka</span>' if way == "walka" else esc(way)
        if bare:
            way_html = '<span class="chip wary">bez wskazówki</span> ' + way_html
        fails.append((f"<code>{esc(node)}</code>", f'<span class="chip skill">{esc(skill)}</span><br><code>{esc(where.rstrip(")"))}</code>', way_html))
    sec.append(("failures", "Porażki i wyjścia", '<div class="wrap">' + table(["Węzeł porażki", "Test", "Co dalej"], fails) + "</div>"))

    nav = "".join(f'<a href="#{a}">{esc(t)}</a>' for a, t, _ in sec)
    main_html = "".join(f'<h2 id="{a}">{esc(t)}</h2>{b}' for a, t, b in sec)
    meta = f"{stamp} · commit {esc(rev or '?')}{' + zmiany' if dirty else ''}"
    return ('<!doctype html><html lang="pl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>Raport fabuły Zawiasu</title><style>{CSS}</style><header><h1>Raport fabuły Zawiasu</h1>'
            f'<p>{meta}</p></header><nav><div>{nav}</div></nav><main>{main_html}</main></html>')
