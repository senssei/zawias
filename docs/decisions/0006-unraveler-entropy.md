# 0006. Unraveler entropy in the warehouse fight

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

The Unravelers preach decay, but their warehouse fight played like any other. The user proposed that something
"falls apart" every round: cover disappears, rust slows movement, a weapon jams. The fight's balance was tuned
in [ADR 0001](0001-solo-encounter-scaling.md), so the effect must not shift win rates noticeably.

## Options

1. **Hazards only for the player's side**: thematic (the cult is used to decay) but makes a tuned fight harder.
2. **Symmetric random decay**: every round from round 2, d6. On 1–2 a random conscious combatant is slowed until
   the end of their turn (rust). On 3–4 a random combatant's next weapon attack has disadvantage (jammed). On 5–6
   nothing happens.
3. **Disappearing cover**: the most visual, but the combat grid has no cover system yet.

## Decision

Option 2, switched on per encounter (`"entropy": true` in `data/encounters.json`, `CombatManager.entropy`).
Effects reuse `slowed` and a new one-shot `jammed` effect (`Attack.compute_mode`; spells are not affected). The log
explains each tick, and the affected actor shows a floating word.

Measured on 16 seeds, solo, level 2, warehouse, test player from `test_slice.gd`:

| Preset | Wizard | Cleric | Rogue | Fighter |
|---|---|---|---|---|
| Story, without / with entropy | 14 / 14 | 15 / 14 | 15 / 14 | 16 / 16 |
| Normal, without / with entropy | 9 / 11 | 15 / 15 | 16 / 16 | 16 / 16 |

## Consequences

- No measurable balance shift; the fight reads as the Unravelers' place.
- `test_slice.gd` sets `mgr.entropy` from the encounter, so the regression thresholds include it.
- Disappearing cover waits for a cover system. Unravelers immune to their own decay remains an option for a
  harder variant.
