#!/usr/bin/env python3
"""Opis po polsku → linie pliku obsady (`id: opis` / `id [wysokość glow]: opis`) przez lokalny LLM (Ollama).

  cast_llm.py "<opis po polsku>" cast/<plik>.txt [--kind character|prop] [--count N]
              [--context data/maps/rusty_market.json data/dialogues/mirela.json ...] [--dry-run]

LLM dostaje: brief, istniejące linie obsady (styl i zajęte id) i przycięte pliki lore.
Odpowiedź jest walidowana (id snake_case i wolne, opis po angielsku, zakazy szablonu konceptu,
bez nazw cudzych settingów); odrzucone pozycje wracają do modelu raz z listą błędów.
Linie są dopisywane na końcu pliku, istniejące zostają bez zmian.

Model: CAST_MODEL (domyślnie qwen3:14b), serwer: OLLAMA_URL.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

OLLAMA = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
MODEL = os.environ.get("CAST_MODEL", "qwen3:14b")

# Szablon konceptu wymusza T-pose z pustymi dłońmi: te słowa psują koncept albo auto-rig.
FORBIDDEN_CHAR = ["cape", "cloak", "holding", "holds", "wielding", "wields", "in hand", "in her hand", "in his hand",
                  "sword", "staff", "spear", "shield", "bow ", "weapon", "lantern in", "carrying", "carries", "wings",
                  "cane", "walking stick", "crutch", "torch", "umbrella", "basket", "book in", "scroll in",
                  "backpack", "on the back", "on his back", "on her back", "satchel", "sack", "quiver"]
# Nazwy cudzych settingów i postaci (README: „Nie używaj nazw cudzych settingów”).
FORBIDDEN_IP = ["planescape", "sigil", "lady of pain", "torment", "nameless one", "dabus", "dungeons & dragons",
                "forgotten realms", "baldur", "greyhawk", "harmonium", "mercykillers", "dustmen", "athar",
                "xaositect", "modron", "githzerai", "tiefling", "beholder", "mind flayer", "illithid"]
POLISH = re.compile(r"[ąćęłńóśźżĄĆĘŁŃÓŚŹŻ]")
ID_RE = re.compile(r"^[a-z][a-z0-9_]{1,30}$")

SCHEMA = {
    "type": "object",
    "properties": {"entries": {"type": "array", "items": {"type": "object", "properties": {
        "id": {"type": "string"},
        "height": {"type": "number"},
        "glow": {"type": "boolean"},
        "desc": {"type": "string"},
    }, "required": ["id", "desc"]}}},
    "required": ["entries"],
}

SYSTEM = """You write cast lines for a local 3D asset pipeline of an original planar-fantasy RPG
(rust, brass and deep violet palette, art nouveau ornament, gritty market city between worlds).
Each entry becomes a FLUX image prompt that is wrapped in a template, then turned into a 3D model.
Rules for every entry:
- id: short lowercase snake_case English or Polish-without-diacritics name, unique.
- desc: ONE English sentence-list, 25-60 words, concrete visual details only: build, age, face, hair,
  clothing layers, materials, colors, distinctive accessories worn on the body.
- Keep species, gender, age and role from the Polish brief EXACTLY. Polish species words:
  krasnolud = dwarf (short, stocky, bearded), elf/elfka = elf, półelf/półelfka = half-elf, niziołek = halfling,
  gnom = gnome, człowiek = human, ork = orc, goblin = goblin, tiefling-like infernal heritage = "horned planetouched".
  Never change a dwarf into a goblin or any other species.
- Never mention lore names of existing published settings or games. The world is original.
{kind_rules}
Return JSON {{"entries": [...]}} only."""
CHAR_RULES = """- Characters: humanoid, standing. NO capes or cloaks, NOTHING held in hands, no weapons, no wings,
  no animals, no backpacks or bags on the back or shoulder (they merge with the body in 3D). Gear must be worn (belts, pouches, armor, jewelry). Start desc with the name and role,
  e.g. "Mirela, a stern middle-aged human locksmith woman, ...". No height or glow fields."""
PROP_RULES = """- Props: one isolated object, no people. Give "height" in meters (real-world size).
  Set "glow": true only when part of the object emits light (lantern, glowing runes, embers)."""


def ollama(messages):
    body = {"model": MODEL, "messages": messages, "format": SCHEMA, "stream": False, "think": False,
            "options": {"temperature": 0.7}, "keep_alive": 0}
    r = urllib.request.Request(OLLAMA + "/api/chat", data=json.dumps(body).encode(),
                               headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=600) as resp:
        return json.loads(json.loads(resp.read())["message"]["content"]).get("entries", [])


def existing_ids(cast_dir):
    ids = set()
    for name in os.listdir(cast_dir):
        if not name.endswith(".txt"):
            continue
        for line in open(os.path.join(cast_dir, name), encoding="utf-8"):
            line = line.strip()
            if line and not line.startswith("#") and ":" in line:
                ids.add(line.split(":", 1)[0].split("[")[0].strip())
    return ids


def shorten(e, max_words=60):
    """Za długi opis przycina na ostatnim przecinku przed limitem słów (lista cech zostaje spójna)."""
    words = str(e.get("desc", "")).split()
    if len(words) <= max_words:
        return e
    cut = " ".join(words[:max_words])
    if "," in cut[len(cut) // 2:]:
        cut = cut[:cut.rindex(",")]
    e = dict(e)
    e["desc"] = cut.rstrip(" ,;.")
    return e


def problems(e, kind, taken):
    out = []
    cid, desc = str(e.get("id", "")).strip(), str(e.get("desc", "")).strip()
    low = " " + desc.lower() + " "
    if not ID_RE.match(cid):
        out.append(f"id '{cid}' must be lowercase snake_case")
    if cid in taken:
        out.append(f"id '{cid}' already exists")
    if POLISH.search(desc):
        out.append("desc must be English")
    words = len(desc.split())
    if words < 12 or words > 90:
        out.append(f"desc has {words} words (need 25-60)")
    bad = [w.strip() for w in (FORBIDDEN_CHAR if kind == "character" else []) + FORBIDDEN_IP if w in low]
    if bad:
        out.append("forbidden words: " + ", ".join(bad))
    if kind == "prop":
        h = e.get("height")
        if not isinstance(h, (int, float)) or not 0.1 <= h <= 8:
            out.append("height must be a number of meters 0.1-8")
    return out


def line_of(e, kind):
    if kind == "prop":
        spec = f"{float(e['height']):g}" + (" glow" if e.get("glow") else "")
        return f"{e['id']} [{spec}]: {e['desc'].strip()}"
    return f"{e['id']}: {e['desc'].strip()}"


def read_context(paths, limit=6000):
    chunks = []
    for p in paths:
        try:
            txt = open(p, encoding="utf-8").read()
        except OSError as ex:
            print(f"pomijam kontekst {p}: {ex}", file=sys.stderr)
            continue
        chunks.append(f"--- {os.path.basename(p)} ---\n{txt[:limit // max(1, len(paths))]}")
    return "\n".join(chunks)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("brief", help="opis po polsku: kogo/czego potrzeba")
    p.add_argument("out", help="plik obsady (dopisywanie)")
    p.add_argument("--kind", choices=["character", "prop"], default="character")
    p.add_argument("--count", type=int, default=0, help="ile pozycji (0 = ile wynika z opisu)")
    p.add_argument("--context", nargs="*", default=[], help="pliki lore (mapy, dialogi)")
    p.add_argument("--dry-run", action="store_true", help="tylko wypisz linie")
    a = p.parse_args()

    out_dir = os.path.dirname(os.path.abspath(a.out)) or "."
    dirs = list(dict.fromkeys([out_dir, os.path.join(os.path.dirname(os.path.abspath(__file__)), "cast")]))
    taken, examples = set(), []
    for cast_dir in dirs:
        if not os.path.isdir(cast_dir):
            continue
        taken |= existing_ids(cast_dir)
        for name in sorted(os.listdir(cast_dir)):
            if name.endswith(".txt") and (("props" in name) == (a.kind == "prop")) and "audio" not in name:
                examples += [l.strip() for l in open(os.path.join(cast_dir, name), encoding="utf-8")
                             if l.strip() and not l.startswith("#") and ":" in l][:3]
    user = (f"Brief (Polish): {a.brief}\n"
            + (f"Number of entries: {a.count}\n" if a.count else "")
            + f"Taken ids (do not reuse): {', '.join(sorted(taken))}\n"
            + "Style examples:\n" + "\n".join(examples[:5]) + "\n"
            + (("Lore context:\n" + read_context(a.context)) if a.context else ""))
    messages = [{"role": "system", "content": SYSTEM.format(kind_rules=CHAR_RULES if a.kind == "character" else PROP_RULES)},
                {"role": "user", "content": user}]
    try:
        entries = ollama(messages)
    except Exception as ex:  # noqa: BLE001
        sys.exit(f"Ollama ({OLLAMA}, {MODEL}) nie odpowiada: {ex}")

    good, bad = [], []
    for e in map(shorten, entries):
        errs = problems(e, a.kind, taken | {g["id"] for g in good})
        (bad if errs else good).append((e, errs) if errs else e)
    if bad:
        print(f"CASTGEN_RETRY {len(bad)} pozycji do poprawy", flush=True)
        fix = "Fix these entries and return only the corrected ones:\n" + "\n".join(
            f"{json.dumps(e, ensure_ascii=False)} -> problems: {'; '.join(errs)}" for e, errs in bad)
        messages += [{"role": "assistant", "content": json.dumps({"entries": entries}, ensure_ascii=False)},
                     {"role": "user", "content": fix}]
        try:
            for e in map(shorten, ollama(messages)):
                errs = problems(e, a.kind, taken | {g["id"] for g in good})
                if errs:
                    print(f"CASTGEN_REJECT {e.get('id')}: {'; '.join(errs)}")
                else:
                    good.append(e)
        except Exception as ex:  # noqa: BLE001
            print(f"CASTGEN_REJECT poprawka nieudana: {ex}")
    if not good:
        sys.exit("CASTGEN_FAIL brak poprawnych pozycji")
    lines = [line_of(e, a.kind) for e in good]
    for l in lines:
        print(l)
    if not a.dry_run:
        new = not os.path.exists(a.out)
        with open(a.out, "a", encoding="utf-8") as f:
            if new:
                f.write(f"# Wygenerowane przez cast_llm.py ({MODEL}). Format: "
                        + ("id [wysokość glow]: opis\n" if a.kind == "prop" else "id: opis\n"))
            elif not open(a.out, encoding="utf-8").read().endswith("\n"):
                f.write("\n")
            f.write("\n".join(lines) + "\n")
    print(f"CASTGEN_OK {len(lines)} → {a.out}" + (" (dry-run)" if a.dry_run else ""))


if __name__ == "__main__":
    main()
