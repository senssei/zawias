# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Stabilne klucze tłumaczeń i nagrań (pipeline.sh story keys, docs/story-pipeline.md).

Klucze nakładki i18n/<lang>/data.json to ścieżki z indeksami ("dialogues/sever:nodes/x/effects/5/journal"), a klucze
nagrań okrzyków to "barks/<npc>_<indeks>". Wstawienie elementu w środek listy przesuwa indeksy i tłumaczenie
albo nagranie trafia do złego tekstu. Obok nakładki leży i18n/<lang>/data.source.json: polski tekst, z którego
powstało każde tłumaczenie. Kontrola porównuje go z bieżącymi danymi:

  ok          ten sam tekst pod tym samym kluczem;
  przesunięty tekst źródłowy stoi teraz pod innym kluczem tego samego kształtu (--fix przemianowuje klucz);
  nieaktualny polski tekst się zmienił, tłumaczenie trzeba odświeżyć (zostaje do ręcznej poprawki);
  bez źródła  tłumaczenie bez zapisanego tekstu źródłowego (--fix zapisuje bieżący polski tekst).

Nagrania okrzyków: tekst w manifeście głosów porównany z bieżącym tekstem (z nakładką); przesunięte nagrania
--fix przemianowuje razem z plikami .ogg.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NUM = re.compile(r"^\d+$")


def _flatten(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            _flatten(v, path + [str(k)], out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            _flatten(v, path + [str(i)], out)
    elif isinstance(node, str):
        out["/".join(path)] = node


class Data:
    """Polskie dane: plik -> {ścieżka: tekst} (wczytane leniwie)."""

    def __init__(self, root=ROOT):
        self.root = root
        self._files = {}

    def file(self, file_key):
        if file_key not in self._files:
            p = self.root / "data" / (file_key + ".json")
            flat = {}
            if p.exists():
                _flatten(json.loads(p.read_text(encoding="utf-8")), [], flat)
            self._files[file_key] = flat
        return self._files[file_key]

    def text(self, key):
        file_key, _, path = key.partition(":")
        return self.file(file_key).get(path)


def _shape(path):
    return tuple("#" if NUM.match(s) else s for s in path.split("/"))


def _load(p):
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def _dump(p, d):
    p.write_text(json.dumps(d, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def check_overlay(lang, root=ROOT, fix=False):
    """[(stan, klucz, szczegół)]; z fix=True poprawia nakładkę i plik źródeł."""
    over_p = root / "i18n" / lang / "data.json"
    src_p = root / "i18n" / lang / "data.source.json"
    overlay, sources = _load(over_p), _load(src_p)
    data = Data(root)
    report, renames = [], {}
    for key in overlay:
        now = data.text(key)
        src = sources.get(key)
        if src is None:
            report.append(("bez źródła", key, now or "(brak ścieżki w danych)"))
            continue
        if now == src:
            continue
        file_key, _, path = key.partition(":")
        cands = [p for p, t in data.file(file_key).items()
                 if t == src and _shape(p) == _shape(path) and p != path]
        if len(cands) == 1:
            new = f"{file_key}:{cands[0]}"
            if new in overlay and data.text(new) == sources.get(new):
                report.append(("konflikt", key, f"{new} ma już aktualne tłumaczenie"))
                continue
            renames[key] = new
            report.append(("przesunięty", key, new))
        else:
            report.append(("nieaktualny", key, f"było: {src!r} · jest: {now!r}"))
    if fix:
        out, out_src = {}, {}
        for key, val in overlay.items():
            new = renames.get(key, key)
            out[new] = val
            out_src[new] = sources.get(key) if key in renames else sources.get(key, data.text(key))
        # klucz przesunięty na miejsce innego przesuniętego: oba trafiają na nowe miejsca bez kolizji
        for key in out:
            if out_src.get(key) is None:
                out_src[key] = data.text(key)
        _dump(over_p, out)
        _dump(src_p, {k: out_src[k] for k in out})
    return report


def check_voice(lang, root=ROOT, fix=False):
    """Przesunięte nagrania okrzyków: [(stan, klucz, szczegół)]."""
    man_p = root / "assets" / "audio" / "voice" / lang / "manifest.json"
    man = _load(man_p)
    if not man:
        return []
    overlay = _load(root / "i18n" / lang / "data.json") if lang != "pl" else {}
    barks = json.loads((root / "data" / "barks.json").read_text(encoding="utf-8"))

    def bark_text(npc, i):
        return overlay.get(f"barks:{npc}/{i}/text", barks[npc][i]["text"]) if i < len(barks.get(npc, [])) else None

    report, renames = [], {}
    for key, rec in man.items():
        if not key.startswith("barks/"):
            continue
        name = key.split("/", 1)[1]
        npc, idx = name.rsplit("_", 1)
        said = " ".join(s["text"] for s in rec["segments"])
        now = bark_text(npc, int(idx))
        if now is not None and said == _clean(now):
            continue
        cands = [i for i in range(len(barks.get(npc, []))) if _clean(bark_text(npc, i)) == said and i != int(idx)]
        if len(cands) == 1:
            renames[key] = f"barks/{npc}_{cands[0]}"
            report.append(("przesunięty", key, renames[key]))
        else:
            report.append(("nieaktualny", key, f"nagranie: {said!r}"))
    if fix and renames:
        voice_dir = root / "assets" / "audio" / "voice" / lang / "barks"
        out = {}
        tmp = []
        for key, rec in man.items():
            new = renames.get(key)
            if not new:
                out.setdefault(key, rec)
                continue
            old_base, new_base = key.split("/", 1)[1], new.split("/", 1)[1]
            segs = []
            for s in rec["segments"]:
                nf = s["file"].replace(old_base + "_", new_base + "_", 1)
                src = voice_dir / s["file"]
                if src.exists():
                    t = voice_dir / (".tmp_" + nf)
                    src.rename(t)
                    tmp.append((t, voice_dir / nf))
                    imp = src.with_name(src.name + ".import")
                    if imp.exists():
                        imp.unlink()   # Godot zaimportuje plik pod nową nazwą
                segs.append(dict(s, file=nf))
            out[new] = dict(rec, segments=segs)
        for t, final in tmp:
            t.rename(final)
        _dump(man_p, dict(sorted(out.items())))
    return report


def _clean(s):
    """Jak VoiceLines.bark_text: tekst okrzyku tak, jak trafia do nagrania."""
    if s is None:
        return None
    s = s.replace("…", "...").strip()
    while s and s[0] in ".,;:—–- ":
        s = s[1:].strip()
    return s


def init_sources(lang, root=ROOT):
    """Zapisuje bieżący polski tekst jako źródło każdego tłumaczenia (jednorazowo, gdy nakładka jest aktualna)."""
    overlay = _load(root / "i18n" / lang / "data.json")
    data = Data(root)
    _dump(root / "i18n" / lang / "data.source.json", {k: data.text(k) for k in overlay})
    return len(overlay)


def run(langs, fix=False, root=ROOT):
    report = []
    for lang in langs:
        report += [(lang, "tłumaczenie") + r for r in check_overlay(lang, root, fix)]
        report += [(lang, "nagranie") + r for r in check_voice(lang, root, fix)]
    return report
