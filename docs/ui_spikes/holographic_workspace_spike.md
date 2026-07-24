# Holographic workspace UI spike

## Status

This is an isolated, runnable UI spike. It is not the formal main interface.

The formal entry remains:

`run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"`

The spike has now been verified with the official Godot 4.6.3 Linux build in GitHub Actions:

- project import and GDScript parsing passed;
- the spike scene loaded without `SCRIPT ERROR` or Godot `ERROR:` log entries;
- the GL Compatibility renderer loaded the shader and 3D viewport;
- a targeted interaction probe passed;
- five real 1280×720 Godot screenshots were rendered and uploaded as the `holographic-workspace-screenshots` artifact.

The PR remains Draft because visual acceptance, manual resizable-window review and hardware performance review are still user-facing decisions.

## Isolation

Runtime and verification files are limited to:

- `scenes/ui_spikes/holographic_workspace/`
- `scripts/ui_spikes/holographic_workspace/`
- `shaders/ui_spikes/holographic_workspace/`
- `.github/workflows/holographic-workspace-spike.yml`
- `docs/ui_spikes/holographic_workspace_spike.md`

No formal save, formal time, character simulation, economy, politics, military or formal map-scope implementation is modified.

## Implemented spatial flow

The sample uses three player-facing spatial levels with a country-focus submode inside the world level:

1. global country overview on the 3D hemisphere;
2. France country-focus view with nine selectable macro regions;
3. selected region view with real administrative geometry, mapped cities and configured institutions;
4. city view with configured institutions, institution parent links and configured character badges.

The nine French macro regions are not selected at global scale. The user selects France first, then enters the enlarged country-focus view where actual region polygons are clickable. This removes the previous cluster of nine overlapping region hit areas on the global hemisphere.

## Data used

- Global country outlines and names: all features in `world_coastlines.json`.
- Country IDs: `iso_a3`, with France normalized to `country_fra`.
- Macro regions: `regions[].administrative_unit_ids` mapped to `administrative_units[].geometry[].outer`.
- Region cities: `cities[].parent_region_id` and `cities[].lon_lat`.
- Institutions: `institutions.json`, including `city_id`, `parent_region_id`, `lon_lat`, `agenda`, `mandate` and `parent_institution_id`.
- Character profiles: `characters.json` identities.
- World status markers: a bounded set derived from configured institution agendas.

Cities without `parent_region_id` are not offered as region entries. Regions without mapped cities display `当前大区没有配置城市入口`. Cities without configured institutions explicitly report that no institution nodes are configured.

## Rendering structure

The scene draw order is explicit:

1. background `ColorRect`;
2. isolated `World3D` SubViewport containing the fixed front-hemisphere shell;
3. cached geographic overlays and all HUD surfaces drawn above the SubViewport.

The camera is a sibling of the hemisphere mesh, so it does not rotate with the shell. Player rotation is applied to the geographic data. The SubViewport uses `own_world_3d=true`, GL Compatibility and `UPDATE_ONCE`; it is disabled and hidden outside the world level.

Global lon/lat coordinates are converted to unit-sphere vectors once at load time. Projection results are cached until rotation or layout changes. Hidden-hemisphere lines are split at an interpolated horizon crossing. Projection does not allocate a Dictionary for every point.

All coastline rings are loaded. They are simplified with a bounded Ramer-Douglas-Peucker pass instead of using the former first-160-ring cutoff or fixed-step skipping.

France country focus uses an enlarged flat projection and low-saturation region fills. Internal administrative-unit borders are not drawn in the country-focus view; selected or hovered macro regions receive a visible border. The detailed region level retains the configured administrative geometry.

## Implemented interaction

- F1/F2 switch the two layout presets through `_unhandled_key_input()`.
- Left drag rotates the global geographic layer and release retains short inertia.
- Hovering near the hemisphere left/right edge applies slow rotation.
- Country anchors can be discovered on hover and selected in the global view.
- France can be entered from the global selection or country HUD surface.
- Actual region polygons can be selected in France focus.
- Region city markers and buttons enter the city layer.
- Institution nodes in the city layer open the top information surface.
- Esc closes the active information/HUD surface before returning one spatial level.
- The F2 workspace can be collapsed and reopened.
- The top information surface uses a Tween slide transition and closes immediately when entering the region level.

## Functional four-corner HUD

- Country corner opens configured country/government information and can locate France.
- Character corner opens configured worker/official data and switches the displayed profile.
- Time corner controls pause and 1×/2×/4× speed for a spike-local clock.
- Activity corner opens configured institution agendas, marks them read and locates an agenda in France focus.

These controls are spike-local and do not alter formal game systems.

## Performance measures

- JSON is read once during `_ready()`.
- Geographic coordinates are converted once at load time.
- Global projected segments are rebuilt only after rotation or layout changes.
- Country/event hit testing uses visible anchors rather than polygon-vertex scans.
- Region polygon hit testing occurs only in France focus.
- `_process()` runs only during inertia or edge-hover rotation.
- The 3D SubViewport is refreshed once after a layout change and disabled outside the world level.
- World, region and city levels are not rendered simultaneously.

## Automated verification

Workflow:

`.github/workflows/holographic-workspace-spike.yml`

The workflow uses Godot 4.6.3 and fails when logs contain `SCRIPT ERROR` or Godot `ERROR:` entries. It performs:

1. project import;
2. direct spike-scene loading;
3. an Xvfb interaction probe;
4. GL Compatibility screenshot capture;
5. screenshot artifact upload.

The interaction probe verifies:

- F1/F2 layout switching;
- hemisphere drag changing yaw;
- France country selection;
- France focus entry;
- macro-region polygon selection;
- region and city entry;
- 3D viewport shutdown outside the world level;
- Esc return through city → region → country focus → global;
- country-corner opening;
- 4× speed control.

## How to run locally

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Suggested review flow:

1. rotate the global hemisphere;
2. select France and choose `进入国家`;
3. select one of the nine macro regions;
4. choose `进入大区`;
5. enter a mapped city;
6. open an institution node;
7. return through city, region, France focus and global;
8. test every corner panel, F1/F2 and the collapsible F2 workspace.

## Known limitations

- Only France has a detailed country-focus implementation. Other countries are selectable global objects but do not have fabricated internal region data.
- Region transport links are derived from mapped city coordinates for this visual spike; they are not the formal transport network.
- City views only show institutions and characters currently present in repository data.
- CI screenshots use an installed Noto CJK system font. The runtime also requests common Windows, macOS and Noto CJK system fonts without bundling a font file.
- The automated run covers 1280×720. Manual review is still required for multiple resized-window dimensions, prolonged edge-hover feel and real GPU/CPU measurements.

Do not merge until those remaining visual and manual checks are accepted.
