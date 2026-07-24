# Holographic workspace UI spike

## Status

This PR is an **未经 Godot 4.6.3 运行验证的 UI spike 草稿**. Its input, navigation, data-loading and rendering paths have been statically reviewed and repaired, but script parsing, scene loading, shader compilation, real input behavior, visual quality and performance still require a Godot runtime.

The formal entry remains `run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"` in `project.godot`; this spike does not replace it.

## Isolation

All runtime files remain under:

- `scenes/ui_spikes/holographic_workspace/`
- `scripts/ui_spikes/holographic_workspace/`
- `shaders/ui_spikes/holographic_workspace/`

No formal save, time, character, economy, politics, military, or formal map-scope system is modified.

## Implemented spatial flow

The sample now uses four explicit navigation states:

1. global country overview on the 3D hemisphere;
2. France country-focus view with nine selectable macro regions;
3. a selected region view with real administrative geometry, mapped cities and configured institutions;
4. a city view with configured institutions, institution parent links and configured character badges.

The nine French macro regions are no longer selected on the global hemisphere at world scale. The user first selects France, then enters the country-focus layer where actual region polygons can be clicked.

## Data used

- Global country outlines and country names: every feature in `world_coastlines.json`; the old arbitrary 160-ring cutoff has been removed.
- Country IDs: `iso_a3`, with France normalized to `country_fra`.
- Macro-region boundaries: `regions[].administrative_unit_ids` mapped to `administrative_units[].geometry[].outer`.
- City-to-region mapping: `cities[].parent_region_id`.
- Institutions: `institutions.json`, including `city_id`, `parent_region_id`, `lon_lat`, `agenda`, `mandate` and `parent_institution_id`.
- Character badges and corner profile: `characters.json` identities.
- World status markers: a bounded set derived from configured institution agendas; they can also be opened from the activity corner.

Cities without `parent_region_id` are not offered as region-layer entries. Regions without mapped cities display `当前大区没有配置城市入口`; there is no hidden Paris fallback. Cities without configured institutions say so rather than generating fictional local places.

## Rendering and projection

The 3D object is a static front-hemisphere shell rendered by an orthographic `Camera3D`. The camera is a sibling of the hemisphere mesh.

The scene has explicit draw ordering:

1. background `ColorRect` behind the parent;
2. 3D SubViewport behind the parent;
3. geographic overlays, information surfaces and HUD drawn by the root Control above the SubViewport.

The SubViewport owns a separate `World3D` and uses `stretch=true`; only the container size is changed by the layout code.

Global geographic projection:

1. lon/lat is converted to a unit-sphere vector once at load time;
2. yaw and tilt are applied when the projection cache is rebuilt;
3. the hidden hemisphere is rejected;
4. line crossings at the horizon are interpolated and split;
5. visible screen segments are cached until the angle or layout changes.

Projection no longer allocates a Dictionary for every geographic point. All country exterior rings are loaded and simplified with a bounded Ramer-Douglas-Peucker pass instead of retaining only the first records or using fixed-step skipping.

France country-focus uses a separate enlarged 2D projection inside the hemisphere work area. Mainland region bounds filter unrelated overseas country polygons from that focus display.

## Implemented interaction

- F1/F2 switch the two layout presets through `_unhandled_key_input()`.
- Left drag rotates global geographic data; release preserves short inertia.
- Hovering near the left/right hemisphere edge rotates slowly.
- Major visible country anchors can be selected in the global view.
- France can be entered from the global selection, the workspace panel or the country corner panel.
- Actual region polygons can be selected in France focus.
- Region city markers and city buttons enter the city layer.
- Institution nodes in the city layer open an information surface.
- Esc closes the active modal surface first, then navigates back by one spatial layer.
- The F2 workspace can be collapsed and reopened.
- The top information surface uses a Tween-driven slide transition.

## Functional four-corner HUD

- Country corner opens the configured country/government surface and can locate France.
- Character corner opens real worker/official profile data and can switch the displayed profile.
- Time corner provides pause, 1×, 2× and 4× controls for a spike-local clock.
- Activity corner opens configured institution agendas, marks them read and can locate an agenda on the world view.

These controls are spike-local and do not modify the formal game time, save, character or political systems.

## Performance measures

- JSON is read only during `_ready()`.
- Geographic coordinates are converted to unit vectors at load time.
- Global projected line segments are cached and rebuilt only after rotation or layout changes.
- Country and event hit testing uses a bounded set of visible anchors, not every polygon vertex.
- Region polygon hit testing happens only in the France-focus view.
- `_process()` runs only during drag inertia or edge-hover rotation.
- The 3D SubViewport uses `UPDATE_ONCE`; it is disabled and hidden outside the world layer.
- The SubViewport has `own_world_3d=true`.
- World, region, and city layers are not rendered simultaneously.
- A small derived script contains final navigation, text-overflow and responsive-node corrections instead of repeatedly replacing the large base spike script.

## How to run

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Suggested review flow:

1. rotate the global hemisphere;
2. select France and choose `进入国家`;
3. select one of the nine macro regions;
4. choose `进入大区`;
5. enter a mapped city;
6. open an institution node;
7. return through city, region, France focus and global world;
8. test every corner panel, F1/F2 and the collapsible F2 workspace.

## Remaining validation

Before merge, a Godot 4.6.3 runtime must still confirm:

- base and derived GDScript parsing;
- scene loading and inherited method dispatch;
- front-hemisphere mesh visibility and winding;
- shader compilation;
- background → SubViewport → overlay draw order;
- F1/F2/Esc handling;
- drag, inertia and edge-hover rotation;
- country, event, region, city and institution selection;
- complete global → France → region → city → return flow;
- all four corner panels and the spike-local clock;
- top information animation and click blocking;
- 1280×720 layout and smaller resizable-window layouts;
- actual screenshots and basic CPU/GPU performance.

Do not merge before these runtime checks are complete.
