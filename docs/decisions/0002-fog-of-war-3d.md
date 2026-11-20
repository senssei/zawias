# 0002. Fog of war in the painted 3D world

- **Status:** Accepted
- **Date:** 2026-11-19

## Context

Fog of war existed only on the map and minimap (`GameState.explored`), drawn as hard square cells with holes
behind stalls. The 3D world showed everything, and the atmospheric fog of the blockout renderer
(`Environment.fog`) is switched off in painted mode, so the painted market had no fog at all.

## Options

1. **Darken unexplored cells**: cheap, but the painting is one image, so a black overlay looks like missing data.
2. **Mist in the painting shader**: a mask of explored cells sampled by `paint_depth.gdshader` at the reconstructed
   surface point, mixed with animated noise in the fog colour. It covers roofs at the right place, gives soft
   edges and doubles as atmosphere.
3. **Volumetric fog**: real depth, but expensive on WSL/llvmpipe and hard to match the painted light.

## Decision

Option 2. `FogOfWar` (`scripts/world/fog_of_war.gd`) builds the mask: one pixel per cell, upscaled ×4 with cubic
interpolation in the engine. That replaced a GDScript blur, which cost about 180k iterations per new reveal.
The shader adds a faint moving haze over explored ground (`mist_amount`) as the atmospheric fog. NPCs, objects
and 3D props on unexplored cells are hidden but stay in the world. On the map, holes behind props are patched
(at least 5 of 8 revealed neighbours) and the fog edge gets a soft fringe. Quest targets show through the fog.

## Consequences

- Look parameters live in the shader: `fog_amount`, `fog_color`, `mist_amount`.
- `--nofog` for clean promotional shots; paint pipeline shots never create the fog.
- Blockout mode (`--nopaint`) still has no 3D fog of war.
- Combat reveals the cells around enemies, so fights never happen inside the mist.
- Tests: `test_fog_of_war_mask_and_actors` in `tests/unit/test_map.gd`.
