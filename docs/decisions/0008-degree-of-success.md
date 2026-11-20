# 0008. Degree of success: boon, cost and gain on dialogue checks

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

Dialogue checks are binary: `success` → one node, `fail` → another. Writing rule 4 ("failure as story") and the
first narrative-mechanics idea in `docs/todo.md` ask for more shades: a strong success that gives a little extra,
a narrow success that costs something, a near miss that still teaches something. The idea comes from Genesys,
whose names, dice and symbols we do not use. A d20 with a DC can express the same thing through the margin
(total − DC).

## Options

1. **Two bands, as first written in todo.md**: success by 5+ gives a boon; failure by 5+ gives a complication
   plus something in return. Rolling very low gets rewarded, though, and the fail branch already is the
   complication.
2. **Four bands by margin, all optional** (chosen):
   - **boon**: success by 5 or more;
   - **cost**: success by 0–4 ("you manage, but…");
   - **gain**: failure by 1–4 ("you didn't make it, but…");
   - **plain failure**: failure by 5 or more, which takes only the fail branch.
3. **New nodes per band** (`boon: "node_id"`): this gives full control, but it doubles the dialogue graph and the voice lines.

## Decision

Option 2, as extra effects on the check, next to `success_effects` and `fail_effects`: `boon_effects`,
`cost_effects` and `gain_effects`. A band without effects does nothing, so every existing check keeps working.
The player sees the band only when it does something. The toast then reads "SUKCES Z NADDATKIEM" (success with
something extra), "SUKCES, ALE…" (success, but…) or "PORAŻKA, ALE…" (failure, but…), and the effects usually add a
`log` line (a new effect: a plain line in the log) or a journal entry. With a Heroic Inspiration reroll, the band
comes from the final roll. Natural 20 and 1 have no special meaning, as in SRD 5.2 ability checks.

The first uses in the Rusty Market are:

| Check | Band | Effect |
|---|---|---|
| Doorkeeper, persuasion DC 13 | cost | he lets you in but studies your face: Unravelers `wary` |
| Doorkeeper, persuasion DC 13 | boon | he lets slip that Sever fears the key: Heroic Inspiration |
| Back door lock, Sleight of Hand DC 13 | gain | you overhear the guard change: advantage on the stealth check inside |
| Kwit, persuasion DC 13 | cost | he talks, but adds a "handling fee" of 5 gp |
| Arch runes, Arcana DC 10 | gain | one word stays readable ("believe"): a journal clue |

## Consequences

- `DialogueRunner.check_band(res)` decides the band, and `check_rolled` carries it as a fourth argument.
- `story paths` also tries a narrow success and a narrow failure on checks that have `cost_effects` or
  `gain_effects`. It used to try only natural 20 and 1.
- `story report` counts a failure with `gain_effects` as one that has content.
- Balance: the effects are small (one inspiration, 5 gp, one advantage). The combat simulations do not go
  through dialogue, so the numbers do not change.
- To write: put the band's consequence into a `log` line or a journal entry, so the player sees why.
