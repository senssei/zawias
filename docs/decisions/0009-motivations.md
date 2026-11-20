# 0009. Character motivations: strength, flaw, desire, fear

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

The game's theme is identity. The player character, the Wanderer, gave the gate their name, and the finale is
meant to ask "why did you give up your name?" (writing rules 1 and 8). Character creation records what the
character *can* do (class, background, skills), but not who they are. The second narrative-mechanics idea in
`docs/todo.md` was motivations, as in Genesys, under our own names. A player who picks motivations needs to
see them matter in dialogue, and playing them out (flaws included) should pay off.

## Options

1. **Four categories** (strength, flaw, desire, fear), four options each, one pick per category (chosen by the user).
2. **Two categories** (desire, fear): fewer clicks, but fewer dialogue hooks.
3. Reward options:
   - (a) motivation options plus Heroic Inspiration for playing any of them, flaws included (chosen by the user);
   - (b) options only, no reward;
   - (c) inspiration only for strength and desire.

## Decision

Options 1 and 3a.

- The options live in `data/motivations.json`:
  - strength: loyalty, curiosity, compassion, cunning;
  - flaw: pride, greed, anger, distrust;
  - desire: the truth about yourself, wealth, freedom, home;
  - fear: oblivion, helplessness, loneliness, closed doors.

  They were picked to fit Zawias: doors, forgetting, belonging.
- Character creation shows them as four drop-downs above the summary. The default is the first option in each
  category. The character sheet lists them.
- A dialogue choice may carry `"motivation": "category:option"`. It is visible only to a character with that
  motivation and is labelled with its name (e.g. "[Greed] …"). Choosing it grants Heroic Inspiration once per
  choice, and nothing if the character already has it. Acting on a flaw is rewarded too, but the flaw's
  consequence stays (Mirela keeps the price at 100, the Doorkeeper fight starts).
- The condition `{"motivation": "category:option"}` works anywhere conditions do (dialogue, barks, map).

First uses in the Rusty Market:

| Choice | Motivation | Leads to |
|---|---|---|
| Mirela, reward: "A hundred is charity. Two hundred…" | flaw: greed | Mirela refuses (100 stays) |
| Mirela, reward: "I don't want gold. Is there a place for me?" | desire: home | `mirela/home`, flag `mirela_home` |
| Sever: "What would this key open?" | strength: curiosity | `sever/curious`, a journal clue to the entropy argument |
| Doorkeeper: grab him by the collar | flaw: anger | the threat scene (ADR 0007) |
| Hask: "What happens to those the city forgets?" | fear: oblivion | `hask/oblivion`, ties into the fog lore |
| Flea: give him coins anyway (2 gp) | strength: compassion | the same information as paying 5 gp |
| Dorn, his grandmother's grudge: "Someone had to say no." | flaw: pride | Dorn charges double for a bed (`dorn_cold`) |
| Dorn: "How much did they pay you to tell me this?" | flaw: distrust | the bill with three lines (journal), double price |
| Dorn: "What was the warden like?" | desire: truth | tired, not cruel: a journal clue to why the Wanderer gave up the name |
| Dorn: "What was her husband's name? I'll look for him." | strength: loyalty | a promise, the word `dorn_ardan` (ADR 0010) |
| Dorn: "Was she alone all those years?" | fear: loneliness | the inn as a home for the stranded, a free beer |
| Kwit: "The Inscribed knew about the theft and kept quiet" | strength: cunning | the warehouse lead for free (`kwit/cunning`) |
| Mirela, truth: "How much would the highest bidder pay?" | desire: wealth | `mirela/price`, reward raised to 150 (`reward_plus`) |
| The Arch, with the key: "No oath binds me any more" | desire: freedom | `arch/freedom`, the oath reread as an open door |
| Flea: "I won't just stand and watch. Tell me who" | fear: helplessness | the `scared` scene without the Insight check |
| The Door That Isn't: listen at the wall first | fear: closed doors | `hidden_door/listen`, your own voice saying "Not today" |

## Consequences

- `Creature.motivations` is saved with the character. Older saves have none, so those characters simply see no
  motivation choices.
- `story check` validates motivation ids. `story paths` sets `GameState.any_motivation`, so it explores every
  motivation branch and those choices don't appear in the "unseen" list.
- Every option has at least one scene on the Market (as of 2026-11-20). New chapters should add more, and the
  finale should use them.
- Motivation choices are appended at the end of choice lists, so the indices that translation keys and tests
  refer to stay the same.
- Balance impact is small: one inspiration per choice, a character sees only the choices that match their four
  picks (at most four of Dorn's five), and inspiration does not stack. Pride and distrust cost 2 gp more per long rest at
  Dorn's until the player confesses (see `docs/mechanics.md`). Wealth can raise Mirela's reward by 50 gp, and
  cunning or helplessness skip a 10 gp payment or an Insight check: about the same as the existing alternatives.
