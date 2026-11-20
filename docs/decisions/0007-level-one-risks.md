# 0007. Level-one risks stay: the warehouse threat shortcut and full fights with Lis

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

`story paths` and `story balance` raised three questions about the first level.

1. **The warehouse at level 1 with 0 XP.** The Doorkeeper's threat ("Get out of my way...") has no condition,
   so every class can start the warehouse fight right away. The fight is tuned for level 2
   ([ADR 0001](0001-solo-encounter-scaling.md)). For comparison, the wizard solo on Normal wins 11/16 even at level 2.
2. **Lis makes the level-1 ambush harder.** When she joins, solo scaling switches off and the fight is full,
   but at level 1 she has few HP. Wins out of 64 (`story balance`, 2026-11-20; a 16-seed run first showed
   wizard Normal 10/16 with Lis vs 13/16 solo):

   | ambush, level 1 | Story solo | Story with Lis | Normal solo | Normal with Lis |
   |---|---|---|---|---|
   | wizard | 60 | 58 | 55 | 42 |
   | rogue | 61 | 61 | 58 | 57 |
   | cleric | 57 | 61 | 47 | 56 |
   | fighter | 64 | 64 | 64 | 63 |

   Only the wizard on Normal is clearly worse with Lis (66% vs 86%, about 2.7 standard errors).

3. **Rogue and cleric seemed to find the warehouse easier on Normal than on Story.** On Story the rust mephit
   also fights. With 16 seeds this looked like an inverted order: rogue 14 vs 16, cleric 14 vs 15.
   With 64 seeds (`story balance --classes rogue,cleric --seeds 64`):

   | warehouse, level 2, solo | Story | Normal |
   |---|---|---|
   | rogue | 59/64 | 49/64 |
   | cleric | 58/64 | 62/64 |

   The rogue's inversion was noise. The cleric's gap is 6 points, about 1.4 standard errors, and both
   results are above 90%.

## Options

1. **Gate the threat** behind a quest stage or level 2. This is safer, but it removes a choice.
2. **Keep the shortcut and make it readable.** The threat no longer starts the fight immediately. A scene
   shows what waits behind the door, and backing off has a price.
3. **Scale the warehouse to level 1.** This needs another data path and more measurements.
4. For Lis: **partial scaling** for a party of two, or **more HP** for her at level 1.
5. For the mephit: **weaken it or remove it on Story**.

## Decision

- **Warehouse:** option 2, chosen by the user ("keep it as a shortcut"). The threat (and "I'll come in uninvited"
  after a refusal) leads to the new node `odzwierny/threat`. The Doorkeeper whistles and footsteps gather behind
  the door. The player can then fight or back off. Backing off sets the Unravelers to `wary`, so the Doorkeeper
  stops listening to persuasion, and it adds a journal entry that points to the back door. A failed bluff still
  goes straight to the fight, because the player did not choose violence.
- **Lis:** no change, chosen by the user, and confirmed after the 64-seed run. A companion is a choice with a
  cost. Only the wizard on Normal loses (two casters, no front line); the other classes gain or stay even with Lis.
  The report lists this cell as accepted (`ACCEPTED_COMPANION_DROPS`).
- **Mephit:** no change, chosen by the user after the 64-seed run. Instead, the balance report stops flagging
  noise. `story.clearly_worse` reports a gap only when it exceeds 2 standard errors (a two-proportion test).
  The old fixed rule was "more than 1 win".

## Consequences

- The `story report` lists the early warehouse as accepted (`ACCEPTED_EARLY_COMBAT` in
  `tools/pipeline/story_report.py`) instead of as an open decision.
- Threatening and then retreating closes the persuasion route, so the remaining routes are deception, the back door or force.
- The new node needs a voice line: run `pipeline.sh voice` with ComfyUI running.
- `story balance` runs 64 seeds per cell by default since 2026-11-20 (user's choice). Runs with `--seeds 16` only flag large gaps.
- Watch in playtests: do players read the whistle as a warning, and does anyone take the level-1 fight on purpose?
