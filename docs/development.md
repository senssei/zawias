# Development

## Requirements

- Godot 4.7.x (the project uses the *Compatibility* renderer) and export templates 4.7.2 for builds.
- Git LFS for binary assets (`git lfs install` before cloning).
- The asset pipeline has its own requirements (see [asset-pipeline.md](asset-pipeline.md)); playing and
  changing code don't need it.

## Debug flags

Pass after `--`, e.g. `godot --path . -- --quickstart --class=rogue --lang=en`.

On WSL2 Mesa may fall back to the CPU renderer (`llvmpipe`, a few FPS). Use the GPU through D3D12 with `GALLIUM_DRIVER=d3d12 godot --path . -- --quickstart` (the overlay and the startup log show `D3D12 (NVIDIA ...)`).

| Group | Flags |
|---|---|
| Start and state | `--quickstart [--class=fighter\|rogue\|wizard\|cleric] [--map=id]`, `--creation`, `--encounter=ambush`, `--dialogue=mirela`, `--goto=x,y`, `--flags=a,b`, `--xp=N [--levelup]`, `--settings`, `--openmap`, `--join=lis` |
| Language and look | `--lang=pl\|en`, `--nopaint` (blockout instead of the painting) |
| Camera and movement | `--zoom=n`, `--camat=x,y`, `--camyaw=degrees` (blockout only), `--walkto=x,y` |
| Screenshots | `--shot=file.png` (frame 40, then quit), `--shotseq=dir[,start,every,count]`, `--showcase` (no HUD), `--clean[=arch]`, `--credits` |
| Diagnostics | `--debug` (overlay on from the start; F3 toggles it anywhere: FPS, frame time, draw calls, VRAM, GPU, player cell), `--fps` (average and 1% low over 8 s after warm-up, then quit), `--audiolog`, `--paintshots=dir` (blockout renders for painting) |

## Tests

```bash
./run_tests.sh                       # SPDX, story check, story lint --strict, then all GUT tests, headless
./run_tests.sh -gselect=test_assets  # one file (GUT needs the "test" prefix)
```

## Dev tools (`tools/dev`)

| Tool | Purpose |
|---|---|
| `actor_textures.gd` | lists textures each actor model really uses; run before deleting files in `assets/actors` (imported scenes reference extracted PNGs in binary, a text grep misses them) |
| `check_depth_import.gd` | verifies the imported depth map equals the PNG |
| `measure_gait.gd`, `measure_slide.gd` | foot contact phases and foot sliding of walk cycles |
| `depth_compare.py` | compares depth estimators on the painting |
| `audio_check.py` | silence, clipping and loop seam of WAV files, with a spectrogram sheet |
| `voice_check.py` | Whisper transcribes every voice clip and compares it with the manifest text (run with the ComfyUI venv) |
| `spdx_check.py` | every file has an SPDX license (header or `REUSE.toml`) with its text in `LICENSES/`; runs first in `run_tests.sh` |

## Release checklist

1. `./run_tests.sh` is green (the asset test catches broken models and missing files).
2. Bump `application/config/version` in `project.godot` and `file_version` / `product_version` in `export_presets.cfg`.
3. Export both presets; `chmod +x build/windows/zawias.exe` if you run it from WSL.
4. Smoke-test both builds: menu, new game, one dialogue, one fight, save/load, both languages, sound on Windows.
5. Package and upload (see `tools/release/`).
