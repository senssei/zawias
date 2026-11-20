# 0012. Defeat into the fog: losing a fight continues the story

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

Writing rule 4 says failure and death are part of the story. A lost fight (the alley ambush or the warehouse) used to
end with a "Defeat" screen and an autosave reload. The fog lore (`docs/wanderer.md`) already explains what happens to
someone the city does not remember: they dissolve into the void of the Rift. The gate spat the Wanderer out on the
Market once, at the start of the game.

## Options

What happens after a defeat:
1. **fog and gate** (chosen): the character dissolves into the mist, sees a fragment of the Wanderer's past, and the
   gate spits them out again near the Market entrance;
2. waking up on the Market, with no metaphysics;
3. both, depending on the fight.

The cost:
1. story consequences per encounter;
2. "forgetting": −1 maximum HP per defeat, plus half of the gold;
3. no cost.

The user asked for 1 and 2, balanced.

Limit: **none** (chosen); or the second defeat ends the game.

## Decision

Fog and gate, no limit. The cost combines a story consequence with forgetting:

- **Forgetting:** −1 maximum HP per defeat (`{"forget": 1}`), capped at −3 (`GameState.FORGET_CAP`), saved as
  `GameState.forgotten`. The conversation with your past self (ADR 0011, `memory/fade`, `{"remember": true}`)
  restores it all: once you remember who you were, the city remembers you.
- **Gold is lost only where the story says so:** the bandits rob half (`{"gold_fraction": 0.5}`), and the Unravelers
  don't care about money. Taking half the gold on every defeat on top of −1 HP would hit a level-1 character twice
  for one loss.
- **Encounter consequences** (`on_defeat` in `data/encounters.json`):
  - ambush (`defeat_leave`): the bandits leave with half your gold, `ambush_done` with no reward or Rust Token, and
    the lead to the warehouse still appears in the journal;
  - warehouse: the Unravelers turn `wary`, both doors are shut (`front_open` and `back_open` cleared), and Sever
    hides the key deeper (`key_hidden`: stealth at the chest DC 16 instead of 14, through the back door DC 15
    instead of 13). The enemies stay, so the fight can be retried (the Doorkeeper threat or forcing the back door).
- **Party:** the whole party returns at full HP (after the forgetting) at the map's `player_start`.

### The semi-cutscene

`data/dialogues/rift.json` plays as a semi-cutscene. Any dialogue node with `"scene": "<id>"` uses the same
presentation:
- a full-screen painted still `assets/cutscenes/<id>.png` (FLUX.2 klein), with a slow push-in;
- animated Rift fog over it (`shaders/rift_fog.gdshader`) and letterbox bars;
- the subtitle is typed at the pace of the voice clips (click to skip);
- choices appear centred below.

The defeat sequence runs like this:
1. the screen floods violet (`hud.fog_transition`);
2. the rift scene plays:
   - the first defeat shows `fall` (dissolving, `rift_void`), then `queue` (the warden refusing a woman with a child,
     `rift_queue`);
   - the second shows `fall_again`, then `ledger` (forty-three refusals in one day, `rift_ledger`);
   - later defeats show the generic `start`;
   - each fragment adds a journal entry;
3. a brass flash: "THE GATE SPITS YOU OUT AGAIN".

## Consequences

- The "Defeat" screen is gone from normal play. The autosave before each fight still exists.
- The fragments add to the Wanderer arc without becoming required beats: players who never lose miss nothing needed
  to understand the finale.
- New effects: `forget`, `remember` and `gold_fraction`. New condition: `not_flags`. `story check` now also rejects
  unknown condition keys (a typo used to make a condition always true).
- `story paths` does not simulate defeats yet, so it lists the `key_hidden` choices (`backdoor/picked/2`,
  `chest/start/2`) as unseen. To do: a defeat branch in `_fight`.
- Semi-cutscenes are a first step towards the cutscene pipeline in `docs/todo.md`: still image, pan, subtitle and
  voice. Camera moves on the 3D map and actor movement are not included.
