# Holographic workspace UI spike

## Status

This PR is an **未经 Godot 4.6.3 运行验证的 UI spike 草稿**. The code has received structural review and direct fixes, but script parsing, scene loading, shader compilation, real input behavior, performance, and screenshots still require a Godot runtime.

The formal entry remains `run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"` in `project.godot`; this spike does not replace it.

## Isolation

All runtime files remain under:

- `scenes/ui_spikes/holographic_workspace/`
- `scripts/ui_spikes/holographic_workspace/`
- `shaders/ui_spikes/holographic_workspace/`

No formal save, time, character, economy, politics, military, or map-scope system is modified.

## Data used

- World coastline background: `world_coastlines.json` feature polygon outer rings.
- Selectable world-layer regions: French macro regions from `regions.json`.
- Macro-region boundaries: `regions[].administrative_unit_ids` mapped to `administrative_units[].geometry[].outer`.
- City-to-region mapping: `cities[].parent_region_id`.
- Cities without `parent_region_id` are world markers only and are not offered as region-layer entries.
- Regions without mapped cities display `当前大区没有配置城市入口`; there is no hidden Paris fallback.

## Current spatial model

The 3D object is a static front-hemisphere shell rendered by an orthographic `Camera3D`. The camera is a sibling of the hemisphere mesh, so it no longer rotates with the mesh.

Geographic data uses one shared projection:

1. lon/lat → unit-sphere point;
2. apply player yaw and tilt to the geographic point;
3. reject points on the hidden back hemisphere;
4. project visible `x/y` coordinates into the same screen circle used by the orthographic 3D shell.

The shell stays fixed while geographic content rotates underneath it. This avoids the previous mismatch between “rotate an already-cut hemisphere” and “rotate a full globe, then select the visible half”.

World-region selection uses visible region anchor points. Real administrative polygons remain visible boundaries, but partially clipped polygons are not closed into synthetic hit areas at the hemisphere edge.

## Performance measures

- JSON is read only during `_ready()`.
- Coastline and administrative polygon lines are decimated to bounded point counts at load time.
- Region hit testing scans only the nine visible macro-region anchors.
- `_process()` runs only during drag inertia or edge-hover rotation.
- The 3D SubViewport is static and uses `UPDATE_ONCE`; it is disabled and hidden outside the world layer.
- World, region, and city layers are not rendered simultaneously.

## How to run

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Controls:

- F1: hemisphere-focused layout.
- F2: operation-workspace layout.
- Left-drag: rotate geographic content with short inertia.
- Hover near the left/right edge: slow rotation.
- Click a visible French macro-region anchor: select the region and open the top information layer.
- Click `进入大区`: enter the 2D region layer.
- Click a configured city button: enter the city placeholder layer.
- `返回上层`, `返回世界`, or Esc: navigate back.

## Remaining validation

Before merge, a Godot 4.6.3 runtime must still confirm:

- GDScript parsing;
- scene loading;
- front-hemisphere mesh visibility and winding;
- shader compilation;
- F1/F2/Esc handling;
- drag, inertia, edge hover, selection, and three-layer navigation;
- F1/F2 visual alignment at 1280×720;
- resized-window layout;
- actual screenshots and basic performance.
