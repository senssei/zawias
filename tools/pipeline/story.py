# SPDX-FileCopyrightText: 2026 Rafal Warzycha
# SPDX-License-Identifier: MIT
"""Sprawdza odwołania i strukturę danych fabularnych Zawiasu."""

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
END_NODES = {"", "end"}
ATTITUDES = {"wary", "neutral", "friendly"}


CONDITION_KEYS = {"any_flag", "class", "flag", "flags", "gold", "has_item", "in_party", "knows_spell", "motivation",
                  "near", "not_flag", "not_flags", "not_item", "not_quest", "quest", "quest_any", "reputation",
                  "reputation_not", "skill_prof", "species", "word", "word_clean", "words_max", "words_min"}
WORD_STATES = {"oath": ["open", "kept", "broken"], "lie": ["hidden", "exposed"]}

class StoryCheck:
    def __init__(self, root):
        self.root = root
        self.errors = []
        self.warnings = []
        self.dialogues = self.directory("data/dialogues")
        self.maps = self.directory("data/maps")
        self.encounters = self.load("data/encounters.json")
        self.items = self.load("data/items.json")
        self.factions = self.load("data/factions.json")
        self.arcs = self.load("data/story_arcs.json")
        self.barks = self.load("data/barks.json")
        self.motivations = self.load("data/motivations.json")
        self.words = self.load("data/words.json")
        self.stages = self.quest_stages()
        self.npcs = {
            npc["id"] for map_data in self.maps.values()
            for npc in map_data.get("npcs", [])
        }

    def directory(self, location):
        paths = sorted((self.root / location).glob("*.json"))
        if not paths:
            self.errors.append(f"{location}: brak plików JSON")
        return {path.stem: self.load(path.relative_to(self.root)) for path in paths}

    def load(self, location):
        try:
            value = json.loads((self.root / location).read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise ValueError(f"{location}:{error.lineno}:{error.colno}: {error.msg}") from error
        if not isinstance(value, dict):
            raise ValueError(f"{location}: oczekiwano obiektu JSON")
        return value

    def quest_stages(self):
        location = "scripts/game/game_state.gd"
        source = (self.root / location).read_text(encoding="utf-8")
        match = re.search(r"^const QUEST_STAGES\s*:=\s*(\{.*?^\})", source, re.M | re.S)
        if not match:
            raise ValueError(f"{location}: brak deklaracji QUEST_STAGES")
        # Deklaracja zawiera słowniki literałów z przecinkami także po ostatnim wpisie.
        literal = re.sub(r',(?=\s*\})|"(?:\\.|[^"\\])*"',
                         lambda token: "" if token[0] == "," else token[0], match[1])
        try:
            return json.loads(literal)
        except json.JSONDecodeError as error:
            raise ValueError(f"{location}: nieczytelny słownik QUEST_STAGES: {error.msg}") from error

    def reference(self, location, value, entries, kind):
        if isinstance(value, str) and value in entries:
            return True
        self.errors.append(f"{location}: nieznany {kind} {value!r}")
        return False

    def quest(self, location, quest, stage, *, allow_empty=True):
        if self.reference(location, quest, self.stages, "identyfikator zadania"):
            if stage != "" or not allow_empty:
                self.reference(location, stage, self.stages[quest], f"etap zadania {quest!r}")

    def quest_pair(self, location, value, *, many=False, allow_empty=True):
        if not isinstance(value, list) or len(value) != 2:
            self.errors.append(f"{location}: oczekiwano pary [zadanie, {'lista etapów' if many else 'etap'}]")
            return
        quest, stages = value if many else (value[0], [value[1]])
        if not isinstance(stages, list) or not stages:
            self.errors.append(f"{location}: oczekiwano niepustej listy etapów")
            return
        for stage in stages:
            self.quest(location, quest, stage, allow_empty=allow_empty)

    def reputation(self, location, value):
        if not isinstance(value, list) or len(value) != 2:
            self.errors.append(f"{location}: oczekiwano pary [frakcja, nastawienie]")
            return
        self.reference(f"{location}/0", value[0], self.factions, "identyfikator frakcji")
        self.reference(f"{location}/1", value[1], ATTITUDES, "stan reputacji")

    def condition(self, location, value):
        if value is None:
            return
        for key in sorted(set(value) - CONDITION_KEYS):   # literówka w kluczu warunku = warunek zawsze spełniony
            self.errors.append(f"{location}/{key}: nieznany klucz warunku")
        for key in ("has_item", "not_item"):
            if key in value:
                self.reference(f"{location}/{key}", value[key], self.items, "przedmiot")
        for key in ("quest", "quest_any"):
            if key in value:
                self.quest_pair(f"{location}/{key}", value[key], many=key == "quest_any")
        if "not_quest" in value:
            self.reference(f"{location}/not_quest", value["not_quest"], self.stages, "identyfikator zadania")
        if "in_party" in value:
            self.reference(f"{location}/in_party", value["in_party"], self.npcs, "NPC")
        for key in ("reputation", "reputation_not"):
            if key in value:
                self.reputation(f"{location}/{key}", value[key])
        if "motivation" in value:
            self.motivation(f"{location}/motivation", value["motivation"])
        if "word" in value:
            word = value["word"]
            if not isinstance(word, list) or len(word) != 2:
                self.errors.append(f"{location}/word: oczekiwano [id, stan]")
            elif self.reference(f"{location}/word/0", word[0], self.words, "słowo z data/words.json"):
                states = WORD_STATES[self.words[word[0]].get("kind")]
                self.reference(f"{location}/word/1", word[1], states, "stan słowa")
        for key in ("words_min", "words_max"):
            if key not in value:
                continue
            pair = value[key]
            if not isinstance(pair, list) or len(pair) != 2 or not isinstance(pair[1], int):
                self.errors.append(f"{location}/{key}: oczekiwano [stan, liczba]")
            else:
                self.reference(f"{location}/{key}/0", pair[0], WORD_STATES["oath"] + WORD_STATES["lie"] + ["lie", "any"], "stan słowa")
        if "near" in value and (not isinstance(value["near"], list) or len(value["near"]) != 3):
            self.errors.append(f"{location}/near: oczekiwano [x, y, promień]")

    def word_ids(self, kind):
        """Identyfikatory rejestru słowa danego rodzaju (ADR 0010)."""
        return {key for key, word in self.words.items() if word.get("kind") == kind}

    def motivation(self, location, value):
        """„kategoria:opcja” z data/motivations.json (ADR 0009)."""
        cat, _, opt = str(value).partition(":")
        if opt not in self.motivations.get(cat, {}).get("options", {}):
            self.errors.append(f"{location}: nieznana motywacja {value}")

    def effects(self, location, values):
        for index, effect in enumerate(values or []):
            path = f"{location}/{index}"
            for key, entries, kind in (
                ("give_item", self.items, "przedmiot"), ("take_item", self.items, "przedmiot"),
                ("start_combat", self.encounters, "identyfikator spotkania"),
                ("join_party", self.npcs, "NPC"), ("leave_party", self.npcs, "NPC"),
                ("remove_npc", self.npcs, "NPC"),
                ("oath", self.word_ids("oath"), "obietnica z data/words.json"),
                ("oath_kept", self.word_ids("oath"), "obietnica z data/words.json"),
                ("oath_broken", self.word_ids("oath"), "obietnica z data/words.json"),
                ("lie", self.word_ids("lie"), "kłamstwo z data/words.json"),
                ("lie_exposed", self.word_ids("lie"), "kłamstwo z data/words.json"),
            ):
                if key in effect:
                    self.reference(f"{path}/{key}", effect[key], entries, kind)
            if "quest" in effect:
                self.quest_pair(f"{path}/quest", effect["quest"], allow_empty=False)
            if "set_reputation" in effect:
                self.reputation(f"{path}/set_reputation", effect["set_reputation"])

    def dialogue(self, name, data):
        path = f"data/dialogues/{name}.json"
        nodes = data.get("nodes")
        if not isinstance(nodes, dict) or not nodes:
            self.errors.append(f"{path}/nodes: oczekiwano niepustego obiektu")
            return
        starts = set()
        edges = {node: set() for node in nodes}
        redirects = {node: set() for node in nodes}

        def transition(location, target, destinations):
            if isinstance(target, str) and target in END_NODES:
                return
            if self.reference(location, target, nodes, "węzeł dialogu"):
                destinations.add(target)

        def alternatives(location, rows, destinations):
            for index, row in enumerate(rows):
                entry = f"{location}/{index}"
                self.condition(f"{entry}/if", row.get("if"))
                transition(f"{entry}/next", row.get("next"), destinations)

        transition(f"{path}/start", data.get("start", "start"), starts)
        alternatives(f"{path}/starts", data.get("starts", []), starts)
        for node_id, node in nodes.items():
            location = f"{path}/nodes/{node_id}"
            outgoing = edges[node_id]
            routes = redirects[node_id]
            alternatives(f"{location}/redirect", node.get("redirect", []), routes)
            outgoing.update(routes)
            self.effects(f"{location}/effects", node.get("effects"))
            for index, choice in enumerate(node.get("choices", [])):
                entry = f"{location}/choices/{index}"
                self.condition(f"{entry}/if", choice.get("if"))
                self.effects(f"{entry}/effects", choice.get("effects"))
                if "dialogue" in choice:   # przejście do innego dialogu: "next" to węzeł w nim
                    other = self.dialogues.get(choice["dialogue"])
                    if other is None:
                        self.errors.append(f"{entry}/dialogue: nieznany dialog {choice['dialogue']!r}")
                    else:
                        self.reference(f"{entry}/next", choice.get("next", other.get("start", "start")),
                                       other.get("nodes", {}), f"węzeł dialogu {choice['dialogue']!r}")
                elif "next" in choice:
                    destinations = set() if choice.get("end") or "check" in choice else outgoing
                    transition(f"{entry}/next", choice["next"], destinations)
                if "motivation" in choice:
                    self.motivation(f"{entry}/motivation", choice["motivation"])
                if "check" in choice:
                    check = choice["check"]
                    self.condition(f"{entry}/check/adv_if", check.get("adv_if"))
                    for result in ("success", "fail"):
                        transition(f"{entry}/check/{result}", check.get(result), outgoing)
                        self.effects(f"{entry}/check/{result}_effects", check.get(f"{result}_effects"))
                    for band in ("boon", "cost", "gain"):   # stopień sukcesu (docs/decisions/0008)
                        self.effects(f"{entry}/check/{band}_effects", check.get(f"{band}_effects"))
                    for key in check:
                        if key.endswith("_effects") and key.split("_")[0] not in ("success", "fail", "boon", "cost", "gain"):
                            self.errors.append(f"{entry}/check/{key}: nieznany pas testu")

        reachable = self.reachable(edges, starts)
        for node in sorted(nodes.keys() - reachable):
            self.warnings.append(f"{path}/nodes/{node}: brak ścieżki od wejścia do dialogu")
        for node, targets in redirects.items():
            if targets and node in self.reachable(redirects, targets):
                self.warnings.append(f"{path}/nodes/{node}/redirect: możliwa pętla przekierowań")

    @staticmethod
    def reachable(edges, starts):
        seen = set()
        pending = set(starts)
        while pending:
            node = pending.pop()
            seen.add(node)
            pending.update(edges[node] - seen)
        return seen

    def map_content(self, name, data):
        path = f"data/maps/{name}.json"
        actors = set()
        for group in ("npcs", "objects", "triggers"):
            for index, entry in enumerate(data.get(group, [])):
                location = f"{path}/{group}/{index}"
                if group != "triggers":
                    actors.add(entry["id"])
                if entry.get("dialogue"):
                    self.reference(f"{location}/dialogue", entry["dialogue"], self.dialogues, "dialog")
                if entry.get("encounter"):
                    self.reference(f"{location}/encounter", entry["encounter"], self.encounters, "identyfikator spotkania")
                self.condition(f"{location}/if", entry.get("if"))
                if "route" in entry:
                    self.condition(f"{location}/route/if", entry["route"].get("if"))
        for index, entry in enumerate(data.get("loot", [])):
            location = f"{path}/loot/{index}"
            if not entry.get("id") or not entry.get("name") or not isinstance(entry.get("pos"), list):
                self.errors.append(f"{location}: wymagane pola id, name i pos")
                continue
            if entry["id"] in actors:
                self.errors.append(f"{location}: identyfikator {entry['id']} już zajęty")
            actors.add(entry["id"])
            if entry.get("shape", "satchel") not in ("barrel", "crate", "satchel"):
                self.errors.append(f"{location}/shape: nieznany kształt {entry.get('shape')}")
            self.effects(f"{location}/effects", entry.get("effects"))
        for group in ("whispers", "memories"):
            for index, entry in enumerate(data.get(group, [])):
                location = f"{path}/{group}/{index}"
                self.condition(f"{location}/if", entry.get("if"))
                if not entry.get("text") or not isinstance(entry.get("cell"), list):
                    self.errors.append(f"{location}: wymagane pola cell i text")
                if group == "memories":
                    self.effects(f"{location}/effects", entry.get("effects"))
        for quest, stages in data.get("quest_markers", {}).items():
            for stage, targets in stages.items():
                location = f"{path}/quest_markers/{quest}/{stage or '(start)'}"
                self.quest(location, quest, stage)
                for index, target in enumerate(targets):
                    self.reference(f"{location}/{index}", target, actors, "cel mapy")

    def arc(self, quest, data):
        path = f"data/story_arcs.json/{quest}/beats"
        represented = set()
        for index, beat in enumerate(data["beats"]):
            stage = beat["stage"]
            location = f"{path}/{index}"
            self.quest(location, quest, stage, allow_empty=False)
            if stage in represented or not beat["sources"]:
                self.errors.append(f"{location}: powtórzony etap lub brak źródeł")
            represented.add(stage)
            for source in beat["sources"]:
                dialogue, _, node = source.partition("/")
                nodes = self.dialogues.get(dialogue, {}).get("nodes", {})
                if self.reference(location, node, nodes, f"węzeł dialogu {dialogue!r}"):
                    if not any(effect.get("quest") == [quest, stage] for effect in nodes[node].get("effects", [])):
                        self.errors.append(f"{location}: {source} nie ustawia etapu {stage!r}")
        for missing in sorted(self.stages.get(quest, {}).keys() - represented):
            self.errors.append(f"{path}: brak etapu {missing!r}")

    def key_scenes(self):
        """Węzły kluczowe dla odbioru fabuły: źródła etapów osi i węzły odwiedzane w kadrach storyboardu."""
        scenes = {source for arc in self.arcs.values() for beat in arc["beats"] for source in beat["sources"]}
        boards = self.load("data/storyboard.json") if (self.root / "data/storyboard.json").exists() else {}
        for map_id, board in boards.items():
            map_data = self.maps.get(map_id, {})
            actors = {actor["id"]: actor.get("dialogue", actor["id"]) for group in ("npcs", "objects")
                      for actor in map_data.get(group, [])}
            for panel in board.get("panels", []):
                dialogue = None
                steps = [entry for step in panel["steps"]
                         for entry in (board[step["sequence"]] if "sequence" in step else [step])]
                for step in steps:
                    if "actor" in step:
                        dialogue = actors.get(step["actor"])
                    elif "node" in step and dialogue:
                        scenes.add(f"{dialogue}/{step['node']}")
        return scenes

    def voice_report(self):
        """[(język, brak w scenach kluczowych, wszystkie węzły bez nagrania)] dla języków z manifestem głosów."""
        voiced = {}
        for path in sorted((self.root / "assets/audio/voice").glob("*/manifest.json")):
            voiced[path.parent.name] = set(self.load(path.relative_to(self.root)).keys())
        spoken = {f"{name}/{node}" for name, data in self.dialogues.items()
                  for node, entry in data.get("nodes", {}).items() if entry.get("text")}
        key = self.key_scenes() & spoken
        return [(lang, sorted(key - keys), sorted(spoken - keys)) for lang, keys in voiced.items()]

    # ------------------------------------------------------------ story lint (docs/story-pipeline.md)
    def all_conditions(self):
        """(miejsce, warunek) dla każdego warunku w dialogach, okrzykach i mapach."""
        out = []
        for name, data in self.dialogues.items():
            for index, row in enumerate(data.get("starts", [])):
                out.append((f"dialogues/{name}/starts/{index}", row.get("if")))
            for node_id, node in data.get("nodes", {}).items():
                for index, row in enumerate(node.get("redirect", [])):
                    out.append((f"dialogues/{name}/{node_id}/redirect/{index}", row.get("if")))
                for index, choice in enumerate(node.get("choices", [])):
                    out.append((f"dialogues/{name}/{node_id}/choices/{index}", choice.get("if")))
                    out.append((f"dialogues/{name}/{node_id}/choices/{index}/adv_if",
                                choice.get("check", {}).get("adv_if")))
        for npc, lines in self.barks.items():
            for index, line in enumerate(lines):
                out.append((f"barks/{npc}/{index}", line.get("if")))
        for name, data in self.maps.items():
            for group in ("npcs", "objects", "triggers", "whispers", "memories"):
                for index, entry in enumerate(data.get(group, [])):
                    out.append((f"maps/{name}/{group}/{index}", entry.get("if")))
        return [(where, cond) for where, cond in out if cond]

    def all_effects(self):
        out = []
        for data in self.dialogues.values():
            for node in data.get("nodes", {}).values():
                out.extend(node.get("effects", []))
                for choice in node.get("choices", []):
                    out.extend(choice.get("effects", []))
                    for key, value in choice.get("check", {}).items():
                        if key.endswith("_effects"):
                            out.extend(value)
        for encounter in self.encounters.values():
            out.extend(encounter.get("on_victory", []))
            out.extend(encounter.get("on_defeat", []))
        for data in self.maps.values():
            for entry in data.get("memories", []) + data.get("loot", []):
                out.extend(entry.get("effects", []))
        return out

    def lint(self):
        """Reguły pisania jako ostrzeżenia: [(reguła, miejsce, opis)]."""
        found = []
        # 1. porażka z wyjściem: węzeł porażki testu bez wpisu w dzienniku, bez walki i bez wyboru dalej
        for name, data in self.dialogues.items():
            nodes = data.get("nodes", {})
            for node_id, node in nodes.items():
                for index, choice in enumerate(node.get("choices", [])):
                    target = choice.get("check", {}).get("fail")
                    fail = nodes.get(target)
                    if not fail:
                        continue
                    journal = any("journal" in e for e in fail.get("effects", []))
                    exits = [c for c in fail.get("choices", [])
                             if (c.get("next") and not c.get("end")) or "check" in c
                             or any("start_combat" in e for e in c.get("effects", []))]
                    if not journal and not exits and not fail.get("redirect"):
                        found.append(("porażka-bez-wyjścia", f"dialogues/{name}/{target}",
                                      f"porażka testu z {node_id}/choices/{index} kończy rozmowę bez wpisu w dzienniku"))
        # 2. obietnice frakcji: osiągalne nastawienie z opisem skutku musi mieć warunek w danych (i odwrotnie)
        set_to = {tuple(e["set_reputation"]) for e in self.all_effects() if "set_reputation" in e}
        used = {}
        for where, cond in self.all_conditions():
            for key in ("reputation", "reputation_not"):
                if key in cond:
                    used.setdefault(tuple(cond[key]), []).append(where)
        for faction, data in self.factions.items():
            for attitude, text in data.get("effects", {}).items():
                if attitude == "neutral" or not text or (faction, attitude) not in set_to:
                    continue
                if (faction, attitude) not in used:
                    found.append(("obietnica-frakcji", f"data/factions.json/{faction}/effects/{attitude}",
                                  "opis skutku bez warunku reputation/reputation_not w danych"))
        for (faction, attitude), wheres in sorted(used.items()):
            if attitude != "neutral" and not self.factions.get(faction, {}).get("effects", {}).get(attitude):
                found.append(("skutek-bez-opisu", wheres[0],
                              f"warunek na {faction}={attitude}, którego dziennik nie opisuje (factions.json effects)"))
        # 3. kto mówi: cytat po frazie o własnym głosie/szepcie w węźle mówionym głosem rozmówcy
        cast = set(self.load("assets/audio/voice/voices.json").keys()) if (self.root / "assets/audio/voice/voices.json").exists() else set()
        voice_phrase = re.compile(r"(własn\w* głos\w*|swój głos|twój głos|szepcz\w*|szept\w*)[^„“\"]{0,60}[„“\"]", re.I)
        for name, data in self.dialogues.items():
            if name not in cast:
                continue
            for node_id, node in data.get("nodes", {}).items():
                if voice_phrase.search(node.get("text", "")) and "narrator_quotes" not in node:
                    found.append(("kto-mówi", f"dialogues/{name}/{node_id}",
                                  "cytat po frazie o własnym głosie lub szepcie; czy to na pewno głos rozmówcy? (narrator_quotes)"))
        # 4. okrzyk towarzysza bez warunku pada raz, w przypadkowym miejscu
        for npc, lines in self.barks.items():
            for index, line in enumerate(lines):
                if line.get("companion") and not line.get("if"):
                    found.append(("okrzyk-towarzysza", f"data/barks.json/{npc}/{index}",
                                  "komentarz towarzysza bez warunku (miejsce albo stan gry)"))
        return found

    def run(self):
        for name, data in self.dialogues.items():
            self.dialogue(name, data)
        for name, data in self.maps.items():
            self.map_content(name, data)
        for name, encounter in self.encounters.items():
            self.effects(f"data/encounters.json/{name}/on_victory", encounter.get("on_victory"))
            self.effects(f"data/encounters.json/{name}/on_defeat", encounter.get("on_defeat"))
        for npc, lines in self.barks.items():
            self.reference(f"data/barks.json/{npc}", npc, self.npcs, "NPC")
            for index, line in enumerate(lines):
                self.condition(f"data/barks.json/{npc}/{index}/if", line.get("if"))
                if line.get("companion") and not any(n.get("companion") for m in self.maps.values()
                                                     for n in m.get("npcs", []) if n["id"] == npc):
                    self.errors.append(f"data/barks.json/{npc}/{index}: okrzyk towarzysza dla NPC bez bloku companion")
        for quest, data in self.arcs.items():
            self.arc(quest, data)
        for lang, key_missing, _ in self.voice_report():
            for scene in key_missing:
                self.warnings.append(f"assets/audio/voice/{lang}: brak nagrania sceny kluczowej {scene} "
                                     f"(pipeline.sh voice --lang {lang} --only {scene.split('/')[0]} --node {scene.split('/')[1]})")


def run_godot(flag_args, tmp):
    """Uruchamia grę bez okna z argumentami narzędzia; zwraca (kod, stdout+stderr)."""
    import os
    import shutil
    import subprocess
    engine = os.environ.get("GODOT") or shutil.which("godot") or str(Path.home() / ".local/bin/godot")
    env = dict(os.environ, XDG_DATA_HOME=tmp, XDG_CONFIG_HOME=tmp)
    cmd = [engine, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--", *flag_args]
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    return result.returncode, result.stdout[-2000:] + result.stderr[-2000:]


def balance_rows(classes, seeds, out=None):
    """Macierz walk z Godota (tools/dev/story_balance.gd): lista wierszy albo None."""
    import tempfile
    with tempfile.TemporaryDirectory(prefix="zawias-balance-") as tmp:
        path = Path(out).resolve() if out else Path(tmp) / "balance.json"
        code, log = run_godot([f"--story-balance={path}", f"--classes={classes}", f"--seeds={seeds}"], tmp)
        if code or not path.exists():
            print(log, file=sys.stderr)
            return None
        return json.loads(path.read_text(encoding="utf-8"))


def clearly_worse(a, b):
    """Czy wynik a jest gorszy od b o więcej niż 2 błędy standardowe (test różnicy proporcji, wspólne p).

    Przy 16 ziarnach 14/16 kontra 16/16 to szum; dopiero przy 64 ziarnach różnice rzędu 10 punktów są istotne."""
    na, nb = max(a["n"], 1), max(b["n"], 1)
    pa, pb = a["wins"] / na, b["wins"] / nb
    p = (a["wins"] + b["wins"]) / (na + nb)
    se = (p * (1 - p) * (1 / na + 1 / nb)) ** 0.5
    return se > 0 and pb - pa > 2 * se


def balance_problems(rows):
    """Odwrócona kolejność poziomów: Opowieść wyraźnie trudniejsza od Normalnego (clearly_worse)."""
    cells = {(r["encounter"], r["class"], r["party"], r["difficulty"]): r for r in rows}
    out = []
    for (enc, cls, party, diff), r in cells.items():
        normal = cells.get((enc, cls, party, "normal"))
        if diff == "story" and normal and clearly_worse(r, normal):
            out.append(f"{enc} · {cls} · {party}: Opowieść {r['wins']}/{r['n']} < Normalny {normal['wins']}/{normal['n']}")
    return sorted(out)


def balance_table(rows):
    """Tabela Markdown: wiersz = spotkanie, klasa, skład; kolumny = poziomy trudności."""
    diffs = sorted({r["difficulty"] for r in rows}, key=lambda d: ["story", "normal"].index(d) if d in ("story", "normal") else 9)
    keys = []
    for r in rows:
        k = (r["encounter"], r["level"], r["class"], r["party"])
        if k not in keys:
            keys.append(k)
    cells = {(r["encounter"], r["class"], r["party"], r["difficulty"]): r for r in rows}
    lines = ["| Spotkanie (poziom) | Klasa | Skład | " + " | ".join(diffs) + " |",
             "|---|---|---|" + "---|" * len(diffs)]
    for enc, lvl, cls, party in keys:
        vals = [f"{cells[(enc, cls, party, d)]['wins']}/{cells[(enc, cls, party, d)]['n']}" for d in diffs
                if (enc, cls, party, d) in cells]
        lines.append(f"| {enc} ({lvl}) | {cls} | {'solo' if party == 'solo' else 'z Lis'} | " + " | ".join(vals) + " |")
    return "\n".join(lines)


def balance_command(args):
    rows = balance_rows(args.classes, args.seeds, args.json)
    if rows is None:
        print("STORY_BALANCE_ERROR: Godot nie zapisał raportu", file=sys.stderr)
        return 1
    print(balance_table(rows))
    problems = balance_problems(rows)
    for p in problems:
        print(f"STORY_BALANCE: odwrócona kolejność poziomów: {p}")
    print(f"STORY_BALANCE: {len(rows)} komórek, {args.seeds} ziaren, problemy: {len(problems)}")
    return 1 if args.strict and problems else 0


def paths_command(args, check):
    """story paths: przejścia w Godocie (tools/dev/story_paths.gd) i raport po polsku."""
    import os
    import shutil
    import subprocess
    import tempfile
    engine = os.environ.get("GODOT") or shutil.which("godot") or str(Path.home() / ".local/bin/godot")
    with tempfile.TemporaryDirectory(prefix="zawias-paths-") as tmp:
        out = Path(args.json).resolve() if args.json else Path(tmp) / "paths.json"
        env = dict(os.environ, XDG_DATA_HOME=tmp, XDG_CONFIG_HOME=tmp)
        cmd = [engine, "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--",
               f"--story-paths={out}", f"--classes={args.classes}", f"--difficulty={args.difficulty}",
               f"--max-states={args.max_states}", f"--walks={args.walks}"]
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        if result.returncode or not out.exists():
            print(result.stdout[-2000:], result.stderr[-2000:], file=sys.stderr)
            print("STORY_PATHS_ERROR: Godot nie zapisał raportu", file=sys.stderr)
            return 1
        reports = json.loads(out.read_text(encoding="utf-8"))
    endings_in_data = sorted({e["end_game"] for d in check.dialogues.values() for n in d.get("nodes", {}).values()
                              for c in [n] + n.get("choices", []) for e in c.get("effects", []) if "end_game" in e})
    problems = 0
    unseen_all = None
    for r in reports:
        print(f"\n== {r['class']} · {r['difficulty']}: {r['states']} stanów wszerz, {r['walks']} losowych przejść, "
              f"{r.get('seconds', 0):.0f} s")
        if r["walks"]:
            dist = ", ".join(f"{k} {v}" for k, v in sorted(r["walk_endings"].items()))
            print(f"  losowe przejścia: {dist or 'brak finałów'}, bez finału po limicie kroków: {r['walk_stuck']}")
        for ending in endings_in_data:
            e = r["endings"].get(ending)
            if not e:
                print(f"  finał {ending}: NIEOSIĄGNIĘTY")
                problems += 1
            else:
                print(f"  finał {ending}: {e['count']} dróg, najkrótsza {len(e['path'])} kroków "
                      f"(poziom {e['level']}, {e['xp']} PD): {' → '.join(e['path'])}")
        for enc, c in sorted(r["combats"].items()):
            print(f"  walka {enc}: poziom {c['min_level']}–{c['max_level']}, PD {c['min_xp']}–{c['max_xp']} "
                  f"(solo {c['solo']}, z drużyną {c['party']})")
            if c["min_level"] < 2 and c["min_xp"] == 0:
                print(f"    uwaga: {enc} dostępna na 1. poziomie bez żadnych PD")
        if r["dead_end_count"]:
            problems += 1
            print(f"  ślepe zaułki: {r['dead_end_count']} (zadanie bez postępu), np.:")
            for d in r["dead_ends"][:3]:
                print(f"    {d['key'] or '(nieprzyjęte)'}: {' → '.join(d['path'])}")
        unseen = set(r["unseen_choices"])
        unseen_all = unseen if unseen_all is None else unseen_all & unseen
    if unseen_all:
        print(f"\nWybory niewidoczne w żadnym przebiegu żadnej klasy ({len(unseen_all)}):")
        for k in sorted(unseen_all):
            print(f"  {k}")
    print(f"\nSTORY_PATHS: {len(reports)} klas, problemy: {problems}")
    return 1 if args.strict and problems else 0


def main():
    parser = argparse.ArgumentParser(prog="pipeline.sh story")
    parser.add_argument("command", choices=["check", "arc", "voice", "lint", "keys", "paths", "balance", "report"])
    parser.add_argument("--seeds", type=int, default=64, help="balance: ziarna na komórkę macierzy")
    parser.add_argument("--out", help="report: katalog raportu HTML")
    parser.add_argument("--paths-json", help="report: gotowy JSON z story paths (bez uruchamiania)")
    parser.add_argument("--balance-json", help="report: gotowy JSON z story balance (bez uruchamiania)")
    parser.add_argument("--classes", default="fighter,rogue,wizard,cleric", help="paths: klasy")
    parser.add_argument("--difficulty", default="normal", help="paths: poziom trudności")
    parser.add_argument("--max-states", type=int, default=300, help="paths: limit stanów przeszukiwania wszerz na klasę")
    parser.add_argument("--walks", type=int, default=200, help="paths: liczba losowych przejść na klasę")
    parser.add_argument("--json", help="paths: zapisz pełny raport JSON")
    parser.add_argument("--strict", action="store_true", help="lint, keys: kod 1 przy ostrzeżeniach")
    parser.add_argument("--fix", action="store_true", help="keys: przemianuj przesunięte klucze, zapisz brakujące źródła")
    parser.add_argument("--init", action="store_true", help="keys: zapisz bieżący polski tekst jako źródła tłumaczeń")
    parser.add_argument("arc_id", nargs="?")
    args = parser.parse_args()
    if (args.command == "arc") != (args.arc_id is not None):
        parser.error("podaj identyfikator osi tylko dla polecenia arc")
    try:
        check = StoryCheck(ROOT)
        check.run()
        if args.arc_id is not None:
            check.reference("data/story_arcs.json", args.arc_id, check.arcs, "identyfikator osi")
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"STORY_ERROR: {error}", file=sys.stderr)
        return 1
    for warning in check.warnings if args.command not in ("voice", "lint") else []:
        print(f"STORY_WARNING: {warning}", file=sys.stderr)
    for error in check.errors:
        print(f"STORY_ERROR: {error}", file=sys.stderr)
    if check.errors:
        return 1
    if args.command == "paths":
        return paths_command(args, check)
    if args.command == "balance":
        return balance_command(args)
    if args.command == "report":
        import story_report
        return story_report.main(args, check)
    if args.command == "keys":
        import story_keys
        langs = sorted(p.parent.name for p in (ROOT / "i18n").glob("*/data.json"))
        if args.init:
            for lang in langs:
                print(f"STORY_KEYS: {lang}: zapisano źródła {story_keys.init_sources(lang)} tłumaczeń")
            return 0
        rows = story_keys.run(langs, fix=args.fix)
        for lang, kind, state, key, detail in rows:
            print(f"STORY_KEYS [{lang} {kind}] {state}: {key} → {detail}")
        fixed = args.fix and any(state in ("przesunięty", "bez źródła") for _, _, state, _, _ in rows)
        print(f"STORY_KEYS: {len(rows)} uwag" + (" (poprawione: przesunięte i bez źródła)" if fixed else ""))
        stale = [r for r in rows if not (args.fix and r[2] in ("przesunięty", "bez źródła"))]
        return 1 if args.strict and stale else 0
    if args.command == "lint":
        found = check.lint()
        for rule, where, text in found:
            print(f"STORY_LINT [{rule}] {where}: {text}")
        print(f"STORY_LINT: {len(found)} ostrzeżeń")
        return 1 if args.strict and found else 0
    if args.command == "voice":
        for lang, key_missing, all_missing in check.voice_report():
            print(f"[{lang}] bez nagrania: {len(all_missing)} węzłów, w tym kluczowe: {len(key_missing)}")
            for scene in all_missing:
                print(f"  {'*' if scene in key_missing else ' '} {scene}")
        return 0
    if args.arc_id is not None:
        print(f"Oś fabularna: {args.arc_id}")
        for beat in check.arcs[args.arc_id]["beats"]:
            print(f"  {beat['stage']}: {', '.join(beat['sources'])}")
        return 0
    print(f"STORY_OK: {len(check.dialogues)} dialogów, {len(check.maps)} map, "
          f"{len(check.encounters)} spotkań, ostrzeżenia: {len(check.warnings)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
