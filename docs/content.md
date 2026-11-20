# Writing content

All content is JSON in `data/`. Polish is the source language; English lives in a translation overlay
(see [localization.md](localization.md)). After adding text, run `./run_tests.sh`: the asset and i18n tests point
out missing portraits, models, sounds and translations.

## Dialogues (`data/dialogues/<id>.json`)

The file name is the dialogue id. An NPC or object refers to it with `"dialogue": "<id>"` in the map, and its
portrait is `assets/portraits/<id>.png` (a node can override it with `"portrait"`).

```json
{
  "start": "start",
  "starts": [ {"if": {"has_item": "key_without_door"}, "next": "return"} ],
  "nodes": {
    "start": {
      "speaker": "Mirela",
      "text": "…",
      "choices": [
        {"text": "What happened?", "next": "theft"},
        {"text": "Persuade her", "once": true,
         "check": {"skill": "persuasion", "dc": 13, "success": "deal", "fail": "no_deal",
                   "success_effects": [{"gold": 50}]}},
        {"text": "Leave", "end": true}
      ],
      "effects": [{"set_flag": "met_mirela"}]
    }
  }
}
```

- `starts`: the first entry whose `if` holds picks the opening node; otherwise `start`.
- Choice keys: `text`, `next`, `end`, `if` (show only when the condition holds), `once`, `effects`, `redirect`,
  `check`: `skill` or `ability`, `dc`, `success` / `fail` (next node), `success_effects` / `fail_effects`, optional `adv_if`, and optional degree-of-success bands `boon_effects` (success by 5+), `cost_effects` (success by 0–4), `gain_effects` (failure by 1–4); see [ADR 0008](decisions/0008-degree-of-success.md). The effect `log` adds a plain line to the log. A choice may carry `"motivation": "category:option"` (see [ADR 0009](decisions/0009-motivations.md)): visible only for that motivation, grants Heroic Inspiration once; append such choices at the end of the list so translation keys keep their indices.
- Node keys: `speaker`, `text`, `choices`, `effects` (applied when the node is shown), `portrait`.

### Conditions (`if`)

All keys must hold: `flag`, `not_flag`, `flags` (all), `any_flag`, `class`, `species`, `has_item`, `not_item`,
`gold` (at least), `quest: [id, stage]`, `quest_any: [id, [stages]]`, `not_quest`, `knows_spell`, `skill_prof`,
`in_party: "<npc id>"`, `reputation_not: [faction, attitude]`, `near: [x, y, radius]` (the player stands within
`radius` cells, e.g. for companion comments).

Faction reputation uses `{"reputation": ["inscribed", "wary"]}` as a condition
and `{"set_reputation": ["inscribed", "wary"]}` as an effect. Faction IDs are in
`data/factions.json`. Attitudes are `wary`, `neutral`, and `friendly`. Each
faction defaults to neutral, including in old saves. Changes appear in the log.
Each faction in `data/factions.json` has `name`, `desc` and `effects` (one sentence per attitude), which the
journal shows next to the current attitude. Write `effects` only for consequences that exist in the data: the
sentence promises the player something.

### Effects

`set_flag`, `clear_flag`, `gold` (negative pays), `give_item`, `take_item`, `xp`, `heal`, `long_rest`,
`journal` (adds a journal entry), `quest: [id, stage]`, `join_party` / `leave_party: "<npc id>"` (companions,
see below), plus world requests `start_combat: "<encounter>"`,
`end_game: "<ending>"`, `remove_npc: "<id>"`.

## Quests

Quest names and stage descriptions are in `GameState.QUEST_NAMES` / `QUEST_STAGES`
(`scripts/game/game_state.gd`). Stages are set by `{"quest": ["key", "lead_warehouse"]}` effects.

## Companions

An NPC in the map JSON with a `companion` block (`class`, `species`, `background`, `scores`, `bonus`, as in character
creation) can join with the `join_party` effect. The companion is built at the player's level (and catches up after
every XP gain with default choices), sets the flag `<id>_joined`, follows the player along their trail (swapping
places in tight spots), shares rests and fights on the party side. By default the player controls the companion's turns; with the
setting "Control companions in combat" off, the AI does (offensive cantrips first, then weapons). After a won fight a downed companion gets up with 1 HP. Companions are stored in saves. Example: Lis
(`data/dialogues/lis.json`, nodes `join`, `companion`, `leave`).

## Market barks (`data/barks.json`)

`{"<npc id>": [{"text": "...", "if": {...}}]}`: short lines an NPC calls out when the player walks by (within 4.5
cells, in line of sight), shown in a bubble and voiced (`pipeline.sh voice`, manifest keys `barks/<npc>_<n>`).
State-dependent lines (`if`) come first, then lines not heard yet; each NPC waits 45 s, and barks never overlap.
NPCs hidden in the fog of war stay silent. Append new lines at the end of a list, because the index is part of the
recording key. `"companion": true` marks a comment the NPC says only while in the party (once per game, usually
with `near` or a quest condition); on their map spot they say only the other lines.

## Whispers and memories (map JSON)

`"whispers": [{"id", "cell", "text", "radius"?, "if"?}]`: while `cell` is still unexplored and the player is
within `radius` cells (default 6), a whisper from the fog appears over the cell (at most every 90 s, only when no
NPC is calling out). `"memories": [{"id", "cell", "text", "journal"?, "effects"?, "if"?}]`: the first time
`cell` is revealed, `text` appears over it, `journal` is added and flag `memory_<id>` is set. Use them for traces
of the story arc (the Wanderer's sign) placed where exploring pays off.

## Encounters (`data/encounters.json`)

```json
"ambush": {
  "name": "…",
  "spawn": [{"monster": "bandit", "id": "bandit1", "name": "…", "pos": [35, 6]}],
  "surprise_unless_flag": "ambush_warned",
  "solo": {"skip": ["bandit2"], "difficulty": ["story", "normal"]},
  "unlock": ["…"],
  "intro": "…",
  "on_victory": [{"xp": 250}, {"give_item": "rust_token"}, {"quest": ["key", "lead_warehouse"]}]
}
```

NPCs on the map with `"encounter": "<id>"` and a `"monster"` join the fight (`"flees": true` makes them escape).
`"entropy": true` turns on Unraveler decay each round ([mechanics.md](mechanics.md)).
`solo.skip` lists enemies (spawn or map NPC ids) that sit the fight out when the player has no companion. Without
`solo.difficulty` this applies only on presets with `solo_scaling` (Normal); with it, on the listed presets.
A trigger cell with `"encounter"` starts the fight when the player steps on it.

## Maps (`data/maps/<id>.json`)

`rows` is an ASCII grid; `legend` maps characters to tile types (walls, buildings, water, difficult terrain) and
optional `label`, `paint_height`, `paint_kind`. Other keys: `player_start`, `npcs` (id, name, pos, dialogue,
model, monster, encounter, title, color), `objects` (arch, chest, door: id, name, pos, dialogue, shape), `locks`,
`triggers`, `decor` (barrels and crates from `assets/props`). Changing buildings or props means re-painting the
map (see [painted-area.md](painted-area.md)).

`loot` lists searchable containers and items on the ground:
`{"id", "name", "pos", "shape": "barrel"|"crate"|"satchel", "text", "effects"}`. Clicking one logs `text`, applies
`effects` (as in dialogue: `gold`, `give_item`, `journal`...) once and sets the flag `looted_<id>`. Barrels and
crates use the prop models and stay empty; a satchel (procedural sack) disappears. A loot spot on a former `decor`
cell needs no re-painting, because props are 3D anyway. `story check` validates ids, shapes and effects.

`quest_markers` shows quest targets on the map: `{"<quest>": {"<stage>": ["<npc or object id>", ...]}}`, where
the stage `""` means the quest has not started yet. Legend entries with a `label` are named on the map, and the
whole building is revealed as soon as any of its walls is in sight.

### NPC routes

An NPC with a `route` walks the market in exploration mode:
`"route": {"points": [[x, y], ...], "wait": [min_s, max_s], "mode": "loop" | "pingpong", "if": {condition}}`.
The NPC starts at `pos`, walks at strolling pace to each point in turn and waits there for a random time in `wait`
(default 3–8 s). `loop` returns from the last point to the start; `pingpong` walks back the same way. `if` (a
dialogue condition) enables the route only in that game state. The NPC stops while the player is walking over to
talk, while it calls a bark and outside exploration (dialogue, combat); positions are not saved, so after loading
it starts from `pos` again. Routes are for NPCs outside encounters, and stops must be open cells that are not on a
lamp post, object or another NPC's spot (checked by `tests/unit/test_routes.gd`). Keep stops where the painting
does not hide them: `paint_map` warns about hidden route stops as well. Example: Pchła loops around the market,
Hask, Kwit and Dorn pace in front of their buildings.

## Rules data

`classes`, `subclasses`, `species`, `backgrounds`, `features`, `spells`, `weapons`, `armor`, `items`,
`monsters`, `conditions`: one entry per id, following SRD 5.2. Spells declare their mechanics
(`type`: attack / save / auto / heal / buff / reaction / utility, `damage`, `save`, `area`, `concentration`, ...).
