# 0001. Solo encounter scaling, per encounter and preset

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

The vertical slice is usually played solo (companion Lis is optional). The encounters were built for SRD budgets
that assume a party. Measurements with the slice test player (`tests/unit/test_slice.gd`, `_player_turn`), solo,
16 seeds per class (900 + 53k):

| Setup | Wizard | Cleric | Rogue | Fighter |
|---|---|---|---|---|
| Normal, full ambush (2 bandits), level 1 | 6 | 7 | 6 | 14 |
| Normal, ambush with 1 bandit | 13 | 13 | 14 | 16 |
| Story, full ambush | 9 | 10 | 12 | 14 |
| Normal, warehouse without mephit, level 2 | 10 | 14 | 13 | 16 |
| Story, full warehouse, level 2 | 10 | 14 | 15 | 15 |

Two more facts:

- The combat route reached the warehouse at level 1 (175 of 300 XP), where the wizard won 4 of 12.
- The first measurements were wrong. The test player cast ranged spell attacks while adjacent (disadvantage)
  and never drank potions, and it set XP directly, which skips leveling. The tactic was fixed before the
  numbers above.

## Options

1. **Scale on every preset**: simple, but Story already halves enemy HP; the user flagged it as too easy.
2. **Scale on Normal only**: Story's ambush (2 bandits) ended up harder than Normal's (1 bandit), an inverted
   difficulty order.
3. **Per-encounter presets**: an encounter lists the presets where it scales. The ambush scales on both, the
   warehouse only on Normal.
4. **Steer the player to Lis instead**: no data changes, but solo stays punishing.

## Decision

Option 3, plus more XP for the ambush (100 → 250) so the combat route enters the warehouse at level 2.
`"solo": {"skip": [...], "difficulty": [...]}` in `data/encounters.json`; without `difficulty` the preset's
`solo_scaling` decides (Normal: on, Story: off). Logic: `Difficulty.solo_skip`.

## Consequences

- Story stays easier than Normal for every class in both fights.
- With a companion, fights are always full; Lis adds challenge rather than removing it.
- Solo players get less monster XP (skipped enemies give none); the ambush reward compensates.
- Regression guard: `test_wizard_solo_normal_combat_rate` (wizard solo, Normal: ambush ≥ 9/12, warehouse ≥ 6/12,
  level 2 at the warehouse). At acceptance it measured 10/12 and 9/12.
- To re-measure, temporarily loop `_fight` over classes and seeds as described above; the test player is weaker
  than a human, so treat results as a lower bound and confirm in playtests.
