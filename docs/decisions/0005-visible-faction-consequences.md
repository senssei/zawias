# 0005. Visible faction consequences, mostly in data

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

Reputation existed (`set_reputation`, the `reputation` condition) but only Kwit's prices reacted to it, and only
Kwit could change it. The plan in [wanderer.md](../wanderer.md) ("Who controls the crossings?") needs factions
the player can feel. The user listed the wanted effects: barks by attitude, Kwit's prices, Hask's patrol helping
or hindering, Unravelers sparing a token-bearer, and a faction panel in the journal.

## Options

1. **A faction system in code** (numeric standing, thresholds, scripted reactions): flexible, but heavy for one map.
2. **Data-driven consequences**: existing conditions and effects on choices, barks and redirects, plus
   `reputation_not`, and `desc`/`effects` text per faction for the journal.

## Decision

Option 2. Every consequence is a condition on content that already exists:

- Hask's patrol is a choice gated by `reputation`.
- The wary-Inscribed lie is a second Doorkeeper choice at DC 17, with the normal one gated by `reputation_not`.
- The token-bearer is spared by a `redirect` on the "caught" nodes.
- Barks by attitude are ordinary `if` barks.

The journal shows `effects[attitude]` so the player sees what an attitude means before testing it.

## Consequences

- Each new consequence costs a few lines of JSON, a translation and a recording. Code changed only for
  `reputation_not`, `near` and the journal panel.
- The `effects` text is a promise. When content changes, the text must change with it. A story pipeline check
  should compare the two; see the story pipeline proposal in [story-pipeline.md](../story-pipeline.md).
- Echo has no source of wariness yet, so "Archive closed" is unreachable for now.
- Appending effects to an existing node shifts the index-based translation keys after it (it happened to Sever's
  and the warehouse's journal lines). Append effects at the end of the list.
- Tests: `tests/unit/test_factions.gd`.
