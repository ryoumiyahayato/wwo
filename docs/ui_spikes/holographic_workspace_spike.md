# Holographic workspace UI spike

## Status

This PR is an **未经 Godot 运行验证的 UI spike 草稿** until a Godot 4.6.3 CI or local runtime confirms script parsing, scene loading, shader compilation, interaction, and screenshots.

The previous implementation only had static checks (`git diff --check`, JSON parsing, file existence). It was not a completed or visually verified sample.

## Audit summary

- The formal entry remains `run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"` in `project.godot`; this spike does not replace it.
- The menu scene instantiates `V23LifeLoopMenu` and keeps the ordinary new/load/migrate/quit buttons. The formal game scene instantiates `V23FormalMain`, `WorldMapCanvasPlayer`, and `V23PlayerInterface` as sibling full-screen controls.
- The retained four-corner HUD is drawn by `scripts/world_map/internal/world_map_interface_impl.gd`: country/institution at top-left, time at top-right, character at bottom-left, activity/messages at bottom-right. `scripts/v2_3/v2_3_player_interface.gd` extends it with map scope controls and supply status.
- The current map scopes are switched by `V23PlayerInterface._activate("map_scope")`, which calls `WorldMapCanvas.set_map_scope()` with world, regional, or city scope. `WorldMapCanvasPlayer` customizes city-scope visibility for regional-centre records.
- Existing reusable data includes `countries.json`, `regions.json`, `cities.json`, `world_coastlines.json`, transport segments, ports, institutions, and the map geometry cache. This spike reads the first four directly and leaves the formal canvas untouched.
- Isolation: all new runtime files are under `scenes/ui_spikes/holographic_workspace`, `scripts/ui_spikes/holographic_workspace`, and `shaders/ui_spikes/holographic_workspace`; no formal save, time, character, or map systems are modified.

## Data actually used

- World coastline background: `world_coastlines.json` feature polygon outer rings.
- Selectable world-layer regions: French macro regions from `regions.json`.
- Macro-region boundaries: each region's `administrative_unit_ids` mapped to `regions.json` `administrative_units[].geometry[].outer`; no artificial ellipse boundaries are generated.
- City-to-region mapping: `cities.json` `parent_region_id`. Cities without that field populated are treated as world-important city markers only and are not offered as region-layer city entries.
- If the selected region has no mapped cities, the region layer displays `当前大区没有配置城市入口` and no hidden Paris fallback is used.

## How to run

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Controls:

- F1: hemisphere-focused layout.
- F2: operation-workspace layout.
- Left-drag the hemisphere: rotate with short inertia.
- Hover near the left/right edge of the hemisphere interaction area: slow edge rotation.
- Click a visible French macro-region boundary/anchor: select it and open the top information layer.
- Click `进入大区`: enter the 2D region layer.
- In the region layer, click a configured city `进入城市` button: enter the city placeholder layer.
- `返回上层`, `返回世界`, or Esc navigate back without using continuous cross-layer zoom.

## Implementation notes

- The translucent hemisphere is a real front-hemisphere `ArrayMesh` in an embedded `SubViewport`; it is no longer a flattened full sphere.
- Geographic drawing uses a shared lon/lat → rotated sphere → screen projection path. Back-side points are not drawn or hit-tested, and visible line segments are split when they cross the hidden hemisphere or longitude seam.
- The 2D region layer draws selected macro-region administrative-unit geometry and mapped cities. Traffic lines are explicitly marked as sample placeholders when drawn.
- The city layer is a simplified placeholder with 3–6 local nodes and does not claim to reuse a formal city-local map.

## Known limits

- This spike covers world coastlines as background plus French macro regions as the selectable sample. It is not a global first-level administrative-region system.
- Runtime screenshots and Godot 4.6.3 parse results are still required before this can be considered visually reviewed.
