# 0013. Saving through memory anchors

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

The Wanderer fell out of the city's memory when they gave the gate their name. The fog thins only where someone
remembers (`docs/wanderer.md`), and defeat now dissolves the party into that fog (ADR 0012). Saving anywhere with F5
does not fit a character whom nobody remembers. The user picked "memory anchors" from three proposals:
1. memory anchors (chosen);
2. three notches on the hand as limited save slots;
3. the ledger of crossings as a save screen.

## Decision

Saving means that someone has remembered you.

- `data/anchors.json` lists the anchors. Each has its own save slot, `anchor_<id>`, and an optional `lost_if`
  condition.

  | Anchor | How | Cost | Lost when |
  |---|---|---|---|
  | Dorn | every bed at the inn | the bed (2 gp, 4 with `dorn_cold`) | never |
  | Lis | "Record in the Echo where my story stands", in the Archive or in the party | free | the Echo turns `wary` |
  | Kwit | "Enter me in the register" | 1 gp | the Inscribed turn `wary` |
  | Hask | "Put me in the gate register" | 1 gp | the Inscribed turn `wary` |
  | Mirela | "Will you remember me?" while the quest is open | free | her promise (`mirela_key`) is broken |

- The effect `{"remember_me": "<anchor>"}` is a world request: the save happens after the conversation, at the
  player's position. The condition `{"anchor": "<id>"}` holds while the anchor still remembers you, so the choice
  disappears once the anchor is lost.
- **Load** (F9, the main menu "Load game") opens "Who remembers you?". It lists every save, newest first:
  - "Remembered by: Dorn …", with character, level, time and the last journal line;
  - "The moment before a fight" (`auto`, made before every fight);
  - "Suspended game (returns once)";
  - "Old save" for the legacy `slot1`.

  Below the list is each anchor's status. Loading an anchor save logs "Dorn remembers you, and the city sees you
  again".
- **F5** without an anchor only squeezes the fog (see below). The setting
  "Save anywhere" (off by default) turns F5 back into a quick save (`quick`), for players who want it.
- **Quitting:** the pause menu's "Save and quit" became "Suspend and quit to menu". It writes `suspend`, which is
  deleted once loaded, so quitting never loses progress and can't be used as a free save point.

### Show, don't tell (the user's direction)

Saving never announces itself in text:

- Choices don't say "(save)": "Enter me in the register, in case the city forgets me (1 gp)", "Will you remember me,
  if the mist takes me?".
- Each anchor that can remember you carries a dim brass mark of three lines above its head, the same mark as on the
  Wanderer's palm. The one who remembered you last carries a bright mark, and the mark disappears when the anchor is
  lost.
- When someone remembers you:
  - their mark flares;
  - the fog around the player pulls back (reveal radius +4);
  - a soft brass flash comes in from the screen edges.
- F5 where no one remembers you shows no message: the Rift fog briefly closes in around the screen.
- Loading shows no log line either: the screen starts violet and the fog parts.

## Consequences

- The word register and faction reputation now cost something tangible: breaking your word to Mirela, or angering
  the Inscribed, removes a save point. A save made earlier keeps working, because it holds a world where they
  still remember you.
- Dorn and Lis (in the party) are always available, so a careful player is never more than a short walk from a save.
  Anchors cost at most 1 gp.
- The autosave before each fight stays, which keeps ADR 0012's defeat flow safe and gives an undo for a bad fight.
- `story check` validates `anchor` and `remember_me`.
- Open: anchors in later chapters (each map should have at least two, one of them free).
