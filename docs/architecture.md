# Architecture

About 6,700 lines of GDScript in four layers. The lower layers know nothing about the upper ones, so the rules
and combat run headless in tests.

```
scripts/rules/      SRD 5.2 rules: pure functions and data, no scenes          (tested: test_rules, test_combat)
scripts/combat/     grid, turn manager, enemy AI                                (tested: test_combat, test_slice)
scripts/dialogue/   dialogue runner: nodes, conditions, checks, effects         (tested: test_quest, test_slice)
scripts/game/       autoloads: GameState, Audio, Loc
scripts/world/      2.5D presentation: World, Actor, IsoCamera
scripts/ui/         main menu, character creation, HUD, shared widgets
data/               all content as JSON (classes, spells, monsters, maps, dialogues, encounters)
i18n/               translation overlays (see localization.md)
```

## Rules (`scripts/rules`)

- `DB` loads `data/<table>.json` once and caches it (numbers from JSON are floats: cast to `int`).
  The active translation overlay is applied at load time.
- `Creature` is a character or monster: scores, HP, conditions, resources, spells, inventory, grid position.
- `CharacterBuilder` builds player characters from creation options (species, background bonuses and origin feat,
  class choices) and monsters from `monsters.json`. Monster HP goes through `Difficulty.monster_hp`.
- `Abilities`, `Checks`, `Attack`, `Spellcasting`, `Rest`, `Leveling`, `Dice`: the SRD mechanics. Every function
  that rolls returns a structured result plus the log lines, so the UI never re-derives math.
- `Dice` has a seeded RNG and a queue of forced rolls (`Dice.force([15, 3])`), used by tests and debug flags.
- `Difficulty`: presets `story` (enemies at half HP, −3 to hit; the game default) and `normal` (plain SRD).

## Combat (`scripts/combat`)

- `CombatGrid` is built from the map rows: walls, difficult terrain, dynamic blocks (props, painted buildings),
  A* paths, Chebyshev distance, line of sight.
- `CombatManager` owns initiative and the turn economy (action, bonus action, reaction, movement), opportunity
  attacks, conditions with durations, concentration, death saves and victory/defeat. It emits `event` signals
  (`log`, `turn`, `attack`, `move`, ...) that the world turns into animations and sounds.
- `AIBasic` picks targets and moves/attacks for enemies. The test suite also uses it to play the player side.

## Dialogue and quest state

- `DialogueRunner` walks a dialogue JSON: picks the start node from `starts` conditions, filters choices by `if`,
  rolls skill checks (with Heroic Inspiration rerolls), applies `effects` / `success_effects` / `fail_effects`
  and emits `node_shown`, `check_rolled`, `finished`.
- `GameState` (autoload) holds the player, flags, quest stages, removed NPCs, the log and the current map, evaluates
  conditions (`check()`), applies effects (`apply_effects()`) and saves/loads JSON under `user://saves`
  (`version` field, autosave before fights). World-level effects (`start_combat`, `end_game`, `remove_npc`) are
  forwarded to the world through the `world_request` signal.

## World (`scripts/world`)

- `World` builds the map from `data/maps/<id>.json`: blockout geometry, props, NPCs and objects, triggers, the
  painted area when its files exist (see [painted-area.md](painted-area.md)), exploration (click-to-move) and
  combat mode (targeting, previews, hit chances), dialogue opening and the endings.
- `Actor` is a character or object on the grid: loads its GLB model (falls back to a placeholder figure and reports
  an error if a model exists but fails to load), plays animations, moves along paths with footsteps synced to the
  walk cycle, and carries the x-ray silhouette material.
- `IsoCamera`: orthographic isometric camera (yaw 45°, pitch −35.26°), pan/zoom, clamped to the painting.

## UI (`scripts/ui`)

`UI` holds shared widgets, colors and the settings panel (volumes, difficulty, language, fullscreen).
`HUD` draws the portrait panel, log, combat bar, dialogue window and the character / inventory / journal /
level-up windows. `MainMenu` and `CharacterCreation` are standalone screens. All visible strings go through `Loc.t()`.

## Autoloads

| Name | Script | Role |
|---|---|---|
| `Loc` | `scripts/game/loc.gd` | current language, `Loc.t()` for code strings, data overlays |
| `GameState` | `scripts/game/game_state.gd` | game state, conditions, effects, save/load |
| `Audio` | `scripts/game/audio.gd` | music crossfades, ambience loops, SFX pool, bus volumes, settings |

## Tests

46 GUT tests in `tests/unit`, run headless by `./run_tests.sh` (forces Polish via `ZAWIAS_LANG=pl`, because the
quest tests pick dialogue choices by their Polish text):

- `test_rules`, `test_combat`: SRD mechanics and combat edge cases.
- `test_quest`, `test_slice`: every class walks all three quest routes (diplomacy, stealth, combat with save/load
  in the middle); fights are played by the AI on both sides with seeded dice.
- `test_assets`: every model, prop, portrait and sound referenced by data or code exists and loads.
- `test_i18n`: every code string is translated, placeholders and BBCode match, data overlay paths exist.
- `test_scene_smoke`: the world scene builds with actors.
