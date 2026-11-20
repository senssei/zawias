# 0010. Word register: oaths and lies

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

Writing rules 3 ("words as deeds") and 8 ("the finale as a conversation") ask for promises and lies with
consequences. The finale of the whole game is about an oath: the Wanderer gave the gate their name. Until now, a
promise was only a flag (`kept_key`, `promise_dorn`) and a lie only showed up when it was caught
(`kwit_bluff_exposed`). Nothing tracked the player's word as a whole.

## Options

1. **Register plus reactions** (chosen by the user): effects and conditions for oaths and lies; Kwit and Lis comment
   on the player's word; the ending screen lists every word.
2. Register and ending summary only, without new NPC reactions: the cheapest option.
3. Register plus a world effect: each broken word shrinks the fog reveal radius by one cell ("the city remembers you
   less"). This needs a balance pass.

Visibility: a journal section, chosen by the user, or a hidden tally shown only at the end.

## Decision

Option 1, with the register shown in the journal.

- `data/words.json` lists each word: `kind` (`oath` or `lie`), `text` (a first-person journal line) and an optional
  `kept_at_end` (a promise of silence counts as kept when the chapter ends).
- States:
  - oath: `open`, then `kept` or `broken`;
  - lie: `hidden`, then `exposed`.
- Effects:
  - `oath` (from no state to `open`), `oath_kept` and `oath_broken` (only from `open`);
  - `lie` (to `hidden`) and `lie_exposed` (only from `hidden`).

  Each change adds a log line. Because of the state guards, an effect can sit on every ending node: portal breaks
  Mirela's promise only if it is still open.
- Conditions:
  - `{"word": [id, state]}`;
  - `{"words_min": [state, n]}`, where state can also be `lie` (all lies, hidden or not).
- Factions as ideas (rule 5):
  - The Inscribed keep the register and know only public facts. Kwit reads it out (`kwit/ledger`): empty,
    `ledger_open` (a debt) or `ledger_bad` (a broken word or an exposed lie).
  - The Echo remembers everything said. Lis (`lis/words`) also knows lies nobody caught (`words_lies`).
- Barks:
  - Mirela: an open promise, before the key is back;
  - Hask: the promise to Mirela is broken;
  - Dorn: the promise about Ardan is open.
- The ending screen lists every word and adds one sentence:
  - something broken or exposed: "Zawias remembers broken words longer than names";
  - only hidden lies: "the Echo will remember";
  - a clean record: "The Wanderer once started out the same way".

Words on the Market:

| Id | Kind | Given | Resolved |
|---|---|---|---|
| `mirela_key` | oath | `mirela/accept` | kept: `mirela/returned`; broken: `mirela/keep`, `arch/portal` |
| `pchla_silence` | oath | "I won't tell" in `pchla/scared` | kept at the end of the chapter |
| `dorn_ardan` | oath | `dorn/promise` (loyalty) | open: beyond the Arch, next chapter |
| `kwit_custodian` | lie | deception at Kwit, success | exposed: failed check or `kwit/bluff_exposed` |
| `doorkeeper_message` | lie | deception at the Doorkeeper, success | exposed: failed check |
| `token_brothers` | lie | the Rust Token at the Doorkeeper | exposed: failed check |

## Consequences

- `GameState.words` is saved. Older saves load with an empty register.
- `story check` validates word ids, kinds per effect and states in conditions.
- No mechanical cost yet: the register changes dialogue and the ending, not numbers. Option 3 (fog radius) stays
  possible for a later chapter.
- `promise_dorn` was replaced by the word `dorn_ardan`.
- Debug: `--words=id:state,...`, `--journal`, `--ending=portal|returned`.
- Next: the finale question "why did you give up your name?" should read this register together with the
  motivations (ADR 0009).
