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
  `check`: `skill` or `ability`, `dc`, `success` / `fail` (next node), `success_effects` / `fail_effects`, optional `adv_if`.
- Node keys: `speaker`, `text`, `choices`, `effects` (applied when the node is shown), `portrait`.

### Conditions (`if`)

All keys must hold: `flag`, `not_flag`, `flags` (all), `any_flag`, `class`, `species`, `has_item`, `not_item`,
`gold` (at least), `quest: [id, stage]`, `quest_any: [id, [stages]]`, `not_quest`, `knows_spell`, `skill_prof`.

### Effects

`set_flag`, `clear_flag`, `gold` (negative pays), `give_item`, `take_item`, `xp`, `heal`, `long_rest`,
`journal` (adds a journal entry), `quest: [id, stage]`, plus world requests `start_combat: "<encounter>"`,
`end_game: "<ending>"`, `remove_npc: "<id>"`.

## Quests

Quest names and stage descriptions are in `GameState.QUEST_NAMES` / `QUEST_STAGES`
(`scripts/game/game_state.gd`). Stages are set by `{"quest": ["key", "lead_warehouse"]}` effects.

## Encounters (`data/encounters.json`)

```json
"ambush": {
  "name": "…",
  "spawn": [{"monster": "bandit", "id": "bandit1", "name": "…", "pos": [35, 6]}],
  "surprise_unless_flag": "ambush_warned",
  "unlock": ["…"],
  "intro": "…",
  "on_victory": [{"xp": 100}, {"give_item": "rust_token"}, {"quest": ["key", "lead_warehouse"]}]
}
```

NPCs on the map with `"encounter": "<id>"` and a `"monster"` join the fight (`"flees": true` makes them escape).
A trigger cell with `"encounter"` starts the fight when the player steps on it.

## Maps (`data/maps/<id>.json`)

`rows` is an ASCII grid; `legend` maps characters to tile types (walls, buildings, water, difficult terrain) and
optional `label`, `paint_height`, `paint_kind`. Other keys: `player_start`, `npcs` (id, name, pos, dialogue,
model, monster, encounter, title, color), `objects` (arch, chest, door: id, name, pos, dialogue, shape), `locks`,
`triggers`, `decor` (barrels and crates from `assets/props`). Changing buildings or props means re-painting the
map (see [painted-area.md](painted-area.md)).

## Rules data

`classes`, `subclasses`, `species`, `backgrounds`, `features`, `spells`, `weapons`, `armor`, `items`,
`monsters`, `conditions`: one entry per id, following SRD 5.2. Spells declare their mechanics
(`type`: attack / save / auto / heal / buff / reaction / utility, `damage`, `save`, `area`, `concentration`, ...).
