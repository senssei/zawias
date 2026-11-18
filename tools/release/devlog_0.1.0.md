# itch.io devlog: 0.1.0

Paste into *Devlog → Create new post*.
- **Type**: Release.
- **Cover**: `docs/media/showcase.jpg`.
- **Inline images**: `docs/media/blockout.jpg` and `docs/media/en_market.jpg`, placed next to each other in the painted-area section.

---

**Title**: Zawias 0.1.0: how a painted RPG gets made on one GPU

**Body**:

Zawias 0.1.0 is out for Windows and Linux. It is a vertical slice: one district, one quest, four classes, levels 1 to 3, on the D&D 2024 rules (SRD 5.2). This first devlog is about how it was made, not what's in it. The making-of is the more unusual part.

### The rule: everything local

Every asset in the game was generated on one home graphics card (an RTX 5070), with open models and no cloud services:

- **Concept art and portraits**: FLUX.2 [klein] 4B
- **3D characters**: TRELLIS.2, then automatic cleanup, palette matching and a rig from Quaternius' animation library (CC0)
- **The painted map**: FLUX again, painting over a 3D blockout in a 3×3 grid of tiles
- **Depth for the painting**: Depth Anything V2
- **Music**: ACE-Step 1.5
- **Sound effects**: synthesized in numpy, no samples

The whole cast of 14 characters takes about 11 minutes to generate. The map takes about 6.

### The painted area

The backgrounds are paintings, but the characters are 3D, and they walk behind buildings and cast shadows on the painted cobbles. How it works:

- The map is rendered from the game camera as a plain blockout.
- That render is repainted.
- Each painted pixel gets a depth value.
- At runtime the painting is pushed back into 3D using that depth.

*(blockout.jpg → en_market.jpg)*

The painter sometimes invents a house where the map has a street. A checker places a virtual character on every walkable cell and flags cells where the painting hides it but the blockout doesn't. Characters hidden behind roofs show up as colored silhouettes: blue for you, gold for NPCs, red for enemies.

### Built with an AI agent, checked by tests

The code (about 6,700 lines of GDScript) was written together with a coding agent. The agent wrote code and also took screenshots of the running game and looked at them.

What held it together is 46 automated tests. The most important one plays the whole quest by itself: every class on every route (talk, sneak, fight), with a save and load in the middle, and fights played by the AI on both sides.

That test is also why the default difficulty is **Story**: in simulation, the wizard won the warehouse fight once in 40 tries on plain SRD.

The most useful lesson: a test that only reads text files is not enough. I deleted "unused" textures, the fighter model silently stopped loading, and every test stayed green. Now a test loads every model, portrait and sound the game uses.

### Open source

The game is free. The code (MIT) and the whole asset pipeline are on GitHub: https://github.com/senssei/zawias. The docs explain the painted-area technique, the dialogue format and how to add a language. The game ships in English and Polish.

The release is non-commercial because the large depth model is licensed CC-BY-NC.

### What's next

Depends on you. If you play it, tell me:
- which route you took;
- how long it took;
- whether *Story* felt too easy.

Bug reports are welcome in the comments or as GitHub issues.
