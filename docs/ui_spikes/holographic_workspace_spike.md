# Holographic workspace UI spike

## Status

This is an isolated, runnable UI spike. It is not the formal main interface.

The formal entry remains:

`run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"`

The spike has been verified with the official Godot 4.6.3 Linux build in GitHub Actions:

- project import and GDScript parsing passed;
- the spike scene loaded without `SCRIPT ERROR` or Godot `ERROR:` log entries;
- the GL Compatibility renderer loaded both the 3D hemisphere shader and the procedural background shader;
- the targeted interaction probe passed;
- global, workspace, France-focus, city and all nine macro-region views were rendered as real 1280×720 Godot screenshots.

## What rotates

The visible world does rotate.

The transparent front-hemisphere shell stays fixed. Country outlines, coastlines, state markers and a restrained latitude/longitude grid are rotated through the same `yaw` and `tilt` basis inside that shell. Keeping the already-clipped shell fixed avoids rotating a cut surface into an invalid viewing orientation, while the moving geography and grid preserve the visual result of rotating the observed world.

The interaction probe sends real mouse-button and mouse-motion events and confirms that dragging changes `yaw`. Release retains short inertia, and left/right edge hover applies slow rotation.

## Spatial flow

The player-facing flow is:

1. global country overview on the 3D hemisphere;
2. France country-focus view with nine selectable macro regions;
3. selected macro-region view with its constituent administrative subdivisions and city entries;
4. city view with configured institutions, institution parent links and configured character badges.

The nine French macro regions are not selected at global scale. France is selected first, then opened as an enlarged country-focus view where the macro-region polygons are clickable.

## France regional coverage

All nine configured macro regions are implemented and included in automated screenshots:

1. Northern Industrial Belt;
2. Paris Basin;
3. Normandy;
4. Brittany;
5. Loire Valley;
6. Aquitaine;
7. Massif Central;
8. Rhône Valley;
9. Mediterranean Coast.

Every macro region has:

- one or more real administrative-unit polygons from `regions.json`;
- separately rendered subdivision fills and borders;
- subdivision hover and click selection;
- administrative source-code labels;
- at least one city entry;
- previous/next region navigation.

The repository data contains 96 metropolitan administrative units assigned across the nine macro regions. Their geometry is based on Natural Earth modern French department/province boundaries. It is a reliable spatial planning reference for the spike, but it is not falsely presented as an exact reconstruction of every French boundary in 1900. The repository itself notes known historical differences such as the former Seine department.

A bounded set of additional French city anchors is installed only inside the isolated spike runtime so that every macro region can demonstrate city entry. These additions do not modify formal `cities.json`, saves or formal map systems. Cities without configured institution data say so rather than receiving fictional institutions.

## Corrected regional projection

The former region view stretched longitude and latitude independently to fill the panel, which visibly flattened or widened some regions.

The region layer now uses one uniform geographic scale. Longitude is adjusted by the cosine of the reference latitude, latitude and longitude then share the same pixel scale, and the result is centered inside the available map rectangle. The interaction probe checks this ratio numerically.

A small offset shadow and differentiated subdivision fills provide restrained depth separation. The region layer remains a deliberate enlarged planning map rather than pretending to be another globe. It is no longer geometrically squashed.

No synthetic transport network is drawn. The previous arbitrary line joining cities by longitude was removed. City markers retain their actual configured or spike-supplemented coordinates.

## Background

The solid black background has been replaced by a procedural GL-compatible canvas shader with:

- a very dark navy/green gradient;
- sparse stars of several restrained scales;
- low-opacity cool and warm cloud bands;
- a soft vignette.

The background is intentionally subdued so it does not turn the interface into a bright science-fiction HUD or compete with the map and corner controls. It uses no external image asset and adds no runtime animation cost.

## Data used

- Global country outlines and names: all features in `world_coastlines.json`.
- Country IDs: `iso_a3`, with France normalized to `country_fra`.
- Macro regions: `regions[].administrative_unit_ids`.
- Administrative subdivisions: `administrative_units[].geometry[].outer`.
- Formal region cities: `cities[].parent_region_id` and `cities[].lon_lat`.
- Institutions: `institutions.json`, including `city_id`, `parent_region_id`, `lon_lat`, `agenda`, `mandate` and `parent_institution_id`.
- Character profiles: `characters.json` identities.
- World status markers: a bounded set derived from configured institution agendas.

## Rendering structure

The scene draw order is explicit:

1. procedural background `ColorRect`;
2. isolated `World3D` SubViewport containing the fixed front-hemisphere shell;
3. rotating cached geographic overlays and all HUD surfaces above the SubViewport.

The camera is a sibling of the hemisphere mesh. The SubViewport uses `own_world_3d=true`, GL Compatibility and `UPDATE_ONCE`; it is disabled and hidden outside the world level.

Global lon/lat coordinates are converted to unit-sphere vectors once at load time. Projection results are cached until rotation or layout changes. Hidden-hemisphere lines are split at an interpolated horizon crossing. Projection does not allocate a Dictionary for every point.

All coastline rings are loaded and simplified with a bounded Ramer-Douglas-Peucker pass rather than the former first-160-ring cutoff or fixed-step skipping.

## Functional interaction

- F1/F2 switch the two layout presets through `_unhandled_key_input()`.
- Left drag rotates global geography and the latitude/longitude grid.
- Release retains short inertia.
- Hovering near the hemisphere left/right edge applies slow rotation.
- Country anchors can be discovered and selected globally.
- France can be entered from global selection or the country HUD surface.
- Actual region polygons can be selected in France focus.
- All nine macro regions can be reviewed with previous/next controls.
- Administrative subdivisions can be hovered and selected inside a macro region.
- Region city markers and buttons enter the city layer.
- Institution nodes in the city layer open the top information surface.
- Esc closes active information/HUD surfaces before returning one spatial level.
- The F2 workspace can be collapsed and reopened.
- The top information surface uses a Tween slide transition.

## Functional four-corner HUD

- Country corner opens configured country/government information and can locate France.
- Character corner opens configured worker/official data and switches the displayed profile.
- Time corner controls pause and 1×/2×/4× speed for a spike-local clock.
- Activity corner opens configured institution agendas, marks them read and locates an agenda in France focus.

These controls remain spike-local and do not alter formal game systems.

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

- F1/F2 switching;
- drag changing `yaw`;
- France country selection and focus entry;
- exactly nine macro regions;
- geometry, administrative subdivisions and city coverage for every region;
- the corrected uniform regional projection ratio;
- macro-region polygon selection;
- Northern Industrial Belt subdivision rendering;
- previous/next region controls;
- region and city entry;
- 3D viewport shutdown outside the world level;
- Esc return through city → region → country focus → global;
- country-corner opening;
- 4× speed control.

The screenshot job produces dedicated images for every one of the nine macro regions and fails unless all nine files exist.

## How to run locally

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Suggested review flow:

1. rotate the global hemisphere;
2. select France and choose `进入国家`;
3. select one of the nine macro regions;
4. choose `进入大区`;
5. use `上一个大区` and `下一个大区` to review all regions;
6. hover or click administrative subdivisions;
7. enter a mapped city and open an institution node;
8. return through city, region, France focus and global;
9. test every corner panel, F1/F2 and the collapsible F2 workspace.

## Known limitations

- Only France has a detailed country-focus implementation. Other countries are selectable global objects but do not receive fabricated internal data.
- Modern Natural Earth department geometry is a documented visual planning reference, not an exact 1900 boundary reconstruction.
- Spike-supplemented cities provide geographic entry coverage but do not fabricate institutions or gameplay content.
- CI covers 1280×720. Manual review remains useful for multiple window dimensions, prolonged edge-hover feel and target-hardware CPU/GPU measurements.
- The runtime remains intentionally isolated and should be decomposed before any future production integration.
