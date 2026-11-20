# 0004. Player-controlled companions in combat, AI as an option

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

Companion Lis fought under `AIBasic`: offensive cantrips first, then weapons. The AI never heals, positions or
uses Sleep well, so taking Lis along gave the player little control. The open-items list had a
"player-controlled companion". [ADR 0001](0001-solo-encounter-scaling.md) also keeps fights with a companion at
full strength, so a well-played Lis matters more.

## Options

1. **Always player-controlled**: full tactics, but slower fights, and some players want to play only their character.
2. **AI only**: what we had.
3. **A setting, player control by default**: genre-standard turn-based control, with AI for players who prefer it.

## Decision

Option 3. `CombatManager.control_party` (from `Audio.control_companions`, `user://settings.cfg`, default on)
makes `is_controlled(c)` true for party members, so their turn waits for input like the player's. The world acts
through `_acting()` (the creature whose turn it is) in the action bar, spellbook, clicks and hover. The action bar
prefixes the companion's name.

## Consequences

- The inventory window still shows the player's inventory. A potion during the companion's turn comes from the
  companion's own bag via the action bar.
- Tests and simulations create `CombatManager` without `control_party`, so companions there stay AI, as before.
- The setting takes effect from the next fight.
- Test: `test_player_controls_companion_turn` in `tests/unit/test_companion.gd`.
