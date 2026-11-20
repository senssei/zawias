# Game mechanics

How the game plays, with pointers to the code and data that implement each rule. Content formats are in
[content.md](content.md), code layout in [architecture.md](architecture.md). Decisions that set these rules
(and the numbers behind them) live in [decisions/](decisions/README.md).

## Checks in dialogue

- A choice with `"check"` rolls a skill or ability check against `dc` (`Checks`, `scripts/rules/checks.gd`).
  `adv_if` grants advantage when a condition holds (e.g. Lis's hint before talking to Sever).
- **Heroic Inspiration** (humans: `resourceful`, also the `inspiration` effect) is spent automatically on a failed
  check and rerolls it once (`DialogueRunner.roll_check`). A long rest restores it.
- `once` choices disappear after use; the failure branch must leave another way forward (see Journal below).
- **Degree of success** ([ADR 0008](decisions/0008-degree-of-success.md)). The margin (total − DC) picks a band:
  success by 5+ is a *boon*, success by 0–4 a *cost*, failure by 1–4 a *gain*, failure by 5+ a plain failure.
  A check may add `boon_effects`, `cost_effects` and `gain_effects`; the toast names the band only when it does
  something ("SUCCESS, AND MORE", "SUCCESS, BUT…", "FAILURE, BUT…"). Rusty Market uses it at the Doorkeeper
  (cost: Unravelers wary; boon: Heroic Inspiration), the back-door lock (gain: advantage on the stealth check
  inside), Kwit's trade (cost: 5 gp) and the Arch runes (gain: a journal clue).
- A natural 1 or 20 shows a badge with the roller's name (`HUD.show_d20`), in dialogue and in combat. With a window
  open (map, journal) the badge moves below or above it.

## Defeat into the fog

A lost fight no longer ends the game ([ADR 0012](decisions/0012-defeat-into-fog.md)). The party dissolves into the
Rift fog and sees a fragment of the Wanderer's past as a semi-cutscene (`rift.json`). The gate then spits it out at
the Market entrance at full HP. The cost:
- −1 maximum HP per defeat, at most −3, restored by the conversation with your past self;
- the encounter's `on_defeat`: the bandits rob half the gold; the warehouse shuts its doors and the key is hidden
  deeper (+2 DC).

## The finale question

After the memory (at Mirela's or the Arch) the player can talk to their past self ([ADR 0011](decisions/0011-finale-question.md),
`data/dialogues/memory.json`). It has three questions: why did you give up your name (general answers plus one per
motivation), did you keep your word here (read from the word register; lying to yourself is recorded), and who are
you now. The answers make up the epilogue on the ending screen. Honest answers promise Heroic Inspiration at the
start of the next chapter (`finale_honest`).

## Word register

Promises and lies are tracked in `GameState.words` ([ADR 0010](decisions/0010-word-register.md)), defined in
`data/words.json`. An oath is open, kept or broken; a lie is hidden or exposed. The journal shows them under
"Dane słowo", and the ending screen lists them with one closing sentence. Kwit (the Inscribed) reads out only public
facts: debts, broken words and exposed lies. Lis (the Echo) also knows lies nobody caught. There is no numeric cost.

## Motivations

Character creation adds four picks from `data/motivations.json`: a strength, a flaw, a desire and a fear
([ADR 0009](decisions/0009-motivations.md)). A dialogue choice with `"motivation": "category:option"` appears only
for that motivation, labelled "[Name] …", and grants Heroic Inspiration once per choice (flaws included; their
consequences still apply). The condition `{"motivation": "category:option"}` works everywhere. The character sheet
lists the four picks.

Dorn the innkeeper remembers the Wanderer through his grandmother, whom the warden turned away from the gate. On
the first talk he sees the three lines on the player's hand (`dorn/grudge`, a second source of the `trace`
stage). Pride or distrust makes him charge 4 gp instead of 2 for a bed (`dorn_cold`); after the memory
(`wanderer` stage `revealed`) the player can confess (`dorn/confess`), which restores the normal price.

## Experience and levels

- Level thresholds follow SRD 5.2: 300 XP for level 2, 900 for level 3 (`Abilities.XP_THRESHOLDS`).
- Reaching a threshold queues a level-up (`pending_levels`); the player picks HP, subclass and spells in the
  level-up window (`Leveling`).
- Rusty Market sources: leads 50 each (Kwit, Pchła, Lis's records), ambush 250 + monster XP, key 150 by talking
  or stealing (by fighting: warehouse 100 + monster XP, then 50 from the chest), ending 300. The combat route reaches level 2 before the warehouse:
  Kwit 50 + ambush 275 solo.

## Difficulty

`Difficulty.PRESETS` (`scripts/rules/difficulty.gd`); the setting lives in `user://settings.cfg`.

| Preset | Enemy HP | Enemy to-hit | Solo scaling | Default |
|---|---|---|---|---|
| Opowieść (Story) | ×0.5 | −3 | only encounters that list `story` | yes (the slice is solo) |
| Normalny (Normal) | ×1 | 0 | yes | tests of rules |

**Solo scaling.** An encounter may list enemies in `"solo": {"skip": [...]}`. When the player fights without a
companion, those enemies sit the fight out (a map NPC slips away with a log line, a spawn never appears).
Without `solo.difficulty` this applies on presets with `solo_scaling` (Normal); with it, on the listed presets.
With a companion every fight is full. Current data: the ambush loses its second bandit on both presets, and the
warehouse loses the rust mephit on Normal. [ADR 0001](decisions/0001-solo-encounter-scaling.md) has the numbers.

## Combat

- Turn-based on the map grid (`CombatManager`); initiative, action, bonus action, reaction, movement.
- `surprise_unless_flag`: the party is surprised unless the flag is set (Pchła's warning sets `ambush_warned`).
- Map NPCs with `"encounter"` and `"monster"` join; `"flees": true` escapes at the start (Sever).
- A healing potion is a bonus action. Rest: short rest from the menu (R), long rest at Dorn's inn (2 gold).
- Starting a fight reveals the fog around each enemy (radius 2, line of sight).
- **Unraveler entropy** (warehouse, `"entropy": true`): from round 2, at the start of each round d6. On 1–2 rust
  slows a random combatant until the end of their turn, on 3–4 a random combatant's next weapon attack has
  disadvantage, on 5–6 nothing. Both sides are equally affected. [ADR 0006](decisions/0006-unraveler-entropy.md).
- **Companions.** With the setting "Steruj towarzyszami w walce" (on by default, `Audio.control_companions`), the
  player plays the companion's turns: action bar, spellbook and clicks act for whoever's turn it is
  (`World._acting`, `CombatManager.is_controlled`), and the bar shows the companion's name. Off: the companion
  fights under AI (`AIBasic`). [ADR 0004](decisions/0004-player-controlled-companions.md).

## Exploration and fog of war

**In the story** the fog is the void of the Rift seeping into the city. Zawias holds together because people
remember it, so the mist thins wherever someone looks and remembers; newcomers mostly see mist. Hask explains it at
the gate (`hask/fog`) and adds a hook: there is oddly much of it around the player, as if the city did not
remember them, because the Wanderer gave the gate their name ([wanderer.md](wanderer.md)). The map's hint line
says the same in one sentence.

- **Revealing.** On every step the cells within 8 tiles in line of sight are revealed (`World._reveal_around`).
  Seeing a wall of a named building reveals the whole building. Cells hidden behind a stall or lamp are patched:
  a cell with at least 5 of 8 revealed neighbours is revealed too. The state is saved (`GameState.explored`).
- **Map and minimap** (`MapView`): unexplored cells are dark, with a soft fringe next to explored ones.
  Quest targets stay visible in the fog as a diamond with a name, without the figure (`marker_visibility`).
- **3D world** (painted area only): `FogOfWar` turns the explored cells into a mask (4 samples per cell, cubic
  upscale) for `paint_depth.gdshader`. Unexplored painting is covered by drifting purple mist; explored ground has
  a faint moving haze. NPCs, objects and 3D props on unexplored cells are hidden but stay in the world (map,
  routes, clicks work). `--nofog` turns it off. [ADR 0002](decisions/0002-fog-of-war-3d.md).

## Loot

Containers and dropped items from the map's `loot` list (Rusty Market: two barrels, a crate, a courier's bag;
29 gold and one potion of healing in total). They show on the map and minimap as gold four-pointed stars until
searched, and behind buildings as a gold silhouette (`xray.gdshader` with `push` 0.15 m instead of 1 m, because the
painted cobbles can sit a little above the real floor and would hide a low object together with its silhouette).
Searching takes no check and no time; the combat sims never loot, so balance numbers exclude it.

## Factions

Three factions (`data/factions.json`), each `wary`, `neutral` or `friendly`. The journal shows each faction's
attitude, who they are and what the attitude changes right now. [ADR 0005](decisions/0005-visible-faction-consequences.md).

| Faction | Becomes friendly | Becomes wary | Friendly means | Wary means |
|---|---|---|---|---|
| Inscribed (Kwit, Hask) | paying Kwit | Kwit's contract bluff exposed | cheaper potion; Hask's patrol clears the east alley on request (no fight, no XP) | risk surcharge; a patrol tails you, so the Doorkeeper's "message from above" lie is DC 17 instead of 12 |
| Echo (Lis) | telling Lis your story | none yet | advantage on reading the key records | (Archive closed: no source yet) |
| Unravelers (Doorkeeper, Sever) | Rust Token shown at the door; Sever convinced | Sever intimidated; warehouse fight won; threatening the Doorkeeper and backing off | with the Rust Token, being caught at the chest or back door ends without a fight | the Doorkeeper no longer listens to persuasion |

NPCs also call out lines that depend on the attitude (Hask, Kwit, Doorkeeper, Lis).

**Threat shortcut.** Threatening the Doorkeeper works from level 1 (the warehouse is tuned for level 2). He whistles
for help first (`odzwierny/threat`): fight now, or back off at the cost of the Unravelers turning wary.
[ADR 0007](decisions/0007-level-one-risks.md).

## Whispers and memories in the fog

- Whispers: near an unexplored place tied to the story (east alley, warehouse, Arch), a whisper rises from the
  fog over that spot, at most every 90 s, and only while it is still unexplored.
- Memories: revealing a trace of the Wanderer (worn grooves under the Arch, the reflection in the pool, the sign on
  the alley wall, the sign drawn in the warehouse dust) shows a line over the spot and adds a journal fragment once.
- Data and format: `whispers` and `memories` in the map JSON ([content.md](content.md)).

## The Key Without a Door as a tool

Once the key has reached the player (`key_obtained`), a door appears in the market's north wall between the
Keyworks and the warehouses (map object `hidden_door` with `"if"`). Only the key in hand opens it. Behind it is the
Wanderer's old guardroom with the ledger of crossings, whose last entry says the Wanderer refused passage to the
Curator (journal, 50 XP, item `crossings_ledger`). Without the key, an unopened door is only a pale crack. Lis in
the party comments near the wall. Map objects accept `"if"` (shown only while the condition holds) besides
`hide_if`.

## Companion: Lis

- In the party, Lis comments once on places and choices: near the warehouse or the Arch, after Pchła's warning,
  with Kwit's contract or the Rust Token, after the Wanderer reveal (`"companion": true` barks).
- With Lis in the party, Sever's dialogue has a "[Lis]" option: a persuasion check with advantage, the argument
  that otherwise needs a successful Arcana check in the Archive.

## Quest guidance

- `quest_markers` in the map JSON mark targets per quest stage (`World._quest_targets`); Mirela's hints repeat
  who to ask.
- **Journal hints after failure.** Every failure that closes a route writes where else to go: the Doorkeeper's
  refusal, a jammed lock, a failed shoulder charge, Pchła's silence, Kwit's refusal. The same entry is never added
  twice (`GameState.apply_effects`). Tests in `tests/unit/test_slice.gd` walk these failures.

## Voices

- Narration (text outside quotes) is read by the narrator, quoted speech by the speaker's voice
  (`VoiceLines.segments`). `"narrator_quotes": [i]` in a node gives the i-th quote to the narrator, e.g. the
  player's own oath in Mirela's memory scene. [ADR 0003](decisions/0003-narrator-quotes.md).
- `pipeline.sh story voice` lists nodes without recordings; `story check` warns about key scenes.
