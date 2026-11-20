# 0003. `narrator_quotes`: quotes read by the narrator

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

Voice segmentation (`VoiceLines.segments`) gives narration to the narrator and every quote to the speaking NPC.
In Mirela's memory scene the quoted oath is spoken by the player character, so it would have been read in
Mirela's voice. The player character has no voice.

## Options

1. **Rewrite the text** so the oath is reported speech: changes approved writing and the translation.
2. **A new quote style for "not the speaker"** (e.g. «…»): invisible convention, easy to break when editing.
3. **A node field** `"narrator_quotes": [i]`: the i-th quote is recorded in the narrator's voice. The manifest
   and in-game segments stay the same, and only voice selection in `comfy_voice.py` changes.

## Decision

Option 3, used in `mirela/wanderer_memory`.

## Consequences

- The text and subtitles are unchanged; the oath plays in the narrator's voice.
- Indices count quotes in the node text, so reordering quotes in an edit needs the field updated.
- If the player character ever gets a voice, the same field can point to it instead.
