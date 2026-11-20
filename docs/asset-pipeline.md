# Asset pipeline

Everything visual and musical in the game was generated locally on one RTX 5070 (12 GB) with open models,
then processed by deterministic scripts. Entry point: `tools/pipeline/pipeline.sh`. The full manual (Polish),
with every option, is [`tools/pipeline/README.md`](../tools/pipeline/README.md).

```
description (PL) ──castgen (Ollama LLM)──▶ cast/*.txt
cast line ──FLUX.2 [klein]──▶ concept ×3 ──vision QA──▶ best concept
concept ──TRELLIS.2──▶ textured mesh ──prep (Blender)──▶ cleanup, palette, AO, budget
──mixano (UAL skeleton + animations)──▶ assets/actors/<id>.glb ──validate──▶ OK / FAIL
```

## Characters and props

| Step | Tool | Notes |
|---|---|---|
| Cast lines | `castgen`, local LLM (Ollama) | writes `id: description` lines; rejects taken ids, held items, capes and other settings' names |
| Concept | FLUX.2 [klein] 4B in ComfyUI | A-pose, front view, plain background; `--ref` keeps one style across the cast |
| QA | vision model (Ollama) | picks the best of 3 concepts; detects models facing backwards and re-runs prep rotated |
| 3D model | TRELLIS.2 | geometry, UV, base color and normal map; presets `draft` / `final` / `hero` |
| Cleanup and materials | `blender/prep_for_rig.py` | merge, normals, small islands, matte look, **fixed palette** (`palette.json`), AO baked into color (Compatibility has no SSAO), textures ≤ 1024, emission for glowing props |
| Rig and animations | mixano (external), UAL skeleton | `idle walk run attack cast hit death talk punch interact`; legacy path `--rigger ual` (DWPose + Blender) |
| Validation | `validate_glb.py` | ≤ 12.5k triangles, one skin, game animations, texture size, file size |

**Triangle budget**: NPCs 7,000, props 6,000; a cast line can override it (`bandit [tris=12000]: ...`).
In a test on 2026-11-18, 7k NPCs were indistinguishable from 12k in game frames (characters are 100–225 px tall),
but cloaks and loose cloth broke under decimation, so the bandit and player characters stay at 12k.

## Portraits

`pipeline.sh portraits <cast.txt>` makes painted 3/4 busts from the concepts (`assets/portraits/<id>.png`);
props get portraits with `--kind prop`. Dialogue shows the speaker's portrait, the HUD shows `pc_<class>`.

## Sound

- **Music**: ACE-Step 1.5 in ComfyUI (`pipeline.sh music`, list in `cast/audio_music.txt`), silence trimmed and
  seamless loops. `tools/dev/audio_check.py` checks silence, clipping and the loop seam without listening.
- **Effects and ambience**: synthesized in numpy (`pipeline.sh sfx`, `sfx_synth.py`), no samples, no licenses.
  File names are the contract with `scripts/game/audio.gd`, so any file can be swapped for a recording.
- **Character voices**: OmniVoice (k2-fsa, Apache 2.0) through the ComfyUI-OmniVoice-TTS nodes (`pipeline.sh voice`).
  The voice cast lives in `assets/audio/voice/voices.json`: a Voice Design description per character renders one
  reference clip, and every line is then cloned from that clip so the voice stays consistent. Each node is split
  in order: quoted speech goes to the character, the description around it to a narrator voice (`_narrator`).
  Every clip is checked with Whisper and regenerated with another seed when it doesn't say its text. Output goes
  to `assets/audio/voice/<lang>/<dialogue>/<node>_<n>.ogg` plus a `manifest.json` that records the text of each
  clip, and `tests/unit/test_voice.gd` flags clips that no longer
  match the dialogue. In game, the voice language is a separate setting (English by default), so the dialogue
  text works as subtitles. The narrator can be switched off. While a character speaks it plays its `talk`
  animation and its dialogue portrait pulses with the voice level. The OS text-to-speech can optionally read
  lines that have no clip.

## The painted map

See [painted-area.md](painted-area.md).

## Requirements

ComfyUI with native TRELLIS.2 / FLUX.2 / ACE-Step nodes and ComfyUI-OmniVoice-TTS (voices), Blender 5.x, Ollama (optional, for `castgen` and `--qa`),
mixano (optional, for the default rigger). The models are not part of this repository.
