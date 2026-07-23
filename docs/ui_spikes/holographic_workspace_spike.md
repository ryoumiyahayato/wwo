# Holographic workspace UI spike

## Audit summary

- The formal entry remains `run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"` in `project.godot`; this spike does not replace it.
- The menu scene instantiates `V23LifeLoopMenu` and keeps the ordinary new/load/migrate/quit buttons. The formal game scene instantiates `V23FormalMain`, `WorldMapCanvasPlayer`, and `V23PlayerInterface` as sibling full-screen controls.
- The retained four-corner HUD is drawn by `scripts/world_map/internal/world_map_interface_impl.gd`: country/institution at top-left, time at top-right, character at bottom-left, activity/messages at bottom-right. `scripts/v2_3/v2_3_player_interface.gd` extends it with map scope controls and supply status.
- The current map scopes are switched by `V23PlayerInterface._activate("map_scope")`, which calls `WorldMapCanvas.set_map_scope()` with world, regional, or city scope. `WorldMapCanvasPlayer` customizes city-scope visibility for regional-centre records.
- Existing reusable data includes `countries.json`, `regions.json`, `cities.json`, `world_coastlines.json`, transport segments, ports, institutions, and the map geometry cache. This spike reads the first four directly and leaves the formal canvas untouched.
- Isolation: all new runtime files are under `scenes/ui_spikes/holographic_workspace`, `scripts/ui_spikes/holographic_workspace`, and `shaders/ui_spikes/holographic_workspace`; no formal save, time, character, or map systems are modified.
- Cloud check: no Godot executable was found in this container, so only filesystem/static checks could be attempted here. Real visual screenshots must be taken in a local Godot 4.6.3 editor/runtime.

## How to run

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Controls:

- F1: hemisphere-focused layout.
- F2: operation-workspace layout.
- Left-drag the hemisphere: rotate with short inertia.
- Hover near the left/right edge of the hemisphere interaction area: slow edge rotation.
- Click a nearby macro-region marker: select it and open the top information layer.
- Click `进入大区`: enter the 2D region layer.
- In the region layer, click the map area / enter-city affordance: enter the city layer.
- `返回上层`, `返回世界`, or Esc navigate back without using continuous cross-layer zoom.

## Known limits

- The translucent hemisphere is a real embedded 3D object; geographic outlines are a lightweight 2D projected overlay for rapid comparison.
- Macro-region boundaries are technical placeholders generated around existing region label anchors because formal macro geometry is cached in the 2D map projection rather than stored as original lon/lat polygons.
- The spike intentionally uses sparse city/event markers and sample local institutions; it does not add gameplay systems or save migrations.
