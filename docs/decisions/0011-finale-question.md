# 0011. The finale as a question: a conversation with your past self

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

Writing rule 8 says the climax is a question, not a boss fight. In `docs/todo.md` the finale was to ask "why did you give up your name?",
with answers that depend on what the character did on the Market. Until now the memory (at Mirela's or at the
Arch) was one node with the oath, followed straight by the decision: give the key back or cross the Arch.
Motivations (ADR 0009) and the word register (ADR 0010) were built to feed this moment.

## Options

Who asks:
1. **your past self in the memory** (chosen by the user);
2. the gate or Arch itself;
3. Mirela or Lis.

Length:
1. **three questions** (chosen by the user);
2. one question;
3. a full dispute with a tension track (narrative mechanic 3, planned for the next chapter).

Mechanical effect:
1. epilogue and flags only;
2. **plus Heroic Inspiration for honesty**, granted at the start of the next chapter (chosen by the user).

## Decision

The memory becomes a conversation in its own dialogue, `data/dialogues/memory.json`. The speaker is "Ty sprzed
przysięgi" ("You, Before the Oath"), with the player's own portrait (`portrait: "pc"` → `pc_<class>`) and a
whispering voice (`memory` in `voices.json`).

1. **"Why did I give up my name?"**
   - Three general answers: no one should decide alone, tiredness, "I don't know".
   - One answer per motivation option, 16 in all. The player sees their own four, and each grants inspiration
     once (ADR 0009).
   - Each category has its own reaction (`why_strength`, `why_flaw`, `why_desire`, `why_fear`).
   - Flags: `finale_why_<power|tired|unknown|strength|flaw|desire|fear>`.
2. **"Did you keep your word here?"** The past self reads the register.
   - A clean record (`word_clean`) lets the player say "yes" truthfully.
   - Anything broken or any lie offers two answers: admit it, or claim "yes". Claiming "yes" adds the lie
     `self_kept`, exposed at once, because you cannot fool yourself.
   - With no words at all, the answer is "I gave no one my word".
   - Honest answers set `finale_honest`: the next chapter starts with Heroic Inspiration, and the ending screen
     says so. Lying sets `finale_word_lied`.
3. **"Who are you now?"** The flags are:
   - `finale_self_new`: today's name;
   - `finale_self_old`: the Wanderer, reclaiming the name;
   - `finale_self_open`: undecided.

   The last node sets `memory_done`, adds a journal entry and returns to the scene the player came from.

Flow and engine:

- **Entry.** `mirela/wanderer_memory` and `arch/wanderer_memory` offer "[Close your eyes and return to the
  memory]" next to "I need a moment". The decision nodes (`mirela/return`, `arch/with_key`) offer it again until
  `memory_done`. The decision itself is never locked, so the player can still postpone or skip.
- **Cross-dialogue choice.** The new choice key `"dialogue": "<id>"` switches the conversation to another dialogue
  file. `"next"` is then a node in that file. `memory_at_mirela` / `memory_at_arch` pick the way back.
- **Epilogue.** The ending screen opens with the epilogue: the reason (with the motivation's name), who you are now,
  and the honesty line. The word register follows.
- New conditions:
  - `word_clean` (true/false);
  - `words_max: [state, n]`;
  - `any` as a state in `words_min` / `words_max`.

## Consequences

- `DialogueRunner.use_dialogue`; the world takes the voice and portrait from the current dialogue id. `story
  check` validates cross-dialogue targets, and `story paths` follows them.
- `finale_honest` and the `finale_*` flags are for the next chapter, which does not exist yet. The inspiration is a
  promise written on the ending screen, to be granted when chapter 2 starts.
- The past self is voiced as a man, and the Polish text addresses the player in the masculine, as everywhere else
  in the game. A female voice variant would need either player-gender data or a neutral voice. This is an open
  point.
- The old direct choices ("Porozmawiajmy o kluczu", "Przyjrzyj się Łukowi z kluczem w dłoni") were removed from
  the memory nodes. Tests go through the conversation (`_through_memory`).
