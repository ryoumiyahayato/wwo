# Holographic workspace UI spike

## Status

This is an isolated, runnable UI spike. It is not the formal main interface.

The formal entry remains:

`run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"`

The spike is verified with the official Godot 4.6.3 Linux build in GitHub Actions:

- project import and strict GDScript parsing pass;
- the spike scene loads without `SCRIPT ERROR` or Godot `ERROR:` log entries;
- the GL Compatibility renderer loads the hemisphere, moon and procedural background shaders;
- the targeted interaction probe passes;
- far, medium and near global zoom states, workspace, France focus, city and all nine macro-region views are rendered as real 1280×720 Godot screenshots.

## What rotates

The visible world rotates.

The transparent front-hemisphere shell stays fixed. Country outlines, coastlines, country flag skins, state markers and a restrained latitude/longitude grid rotate through the same `yaw` and `tilt` basis inside that shell. Keeping the already-clipped shell fixed avoids rotating a cut surface into an invalid viewing orientation, while the moving geography and grid preserve the visual result of rotating the observed world.

The interaction probe sends real mouse-button and mouse-motion events and confirms that dragging changes `yaw`. Release retains short inertia, and left/right edge hover applies slow rotation.

## Global country flag skins and zoom LOD

The global hemisphere no longer relies on persistent country names at the far overview scale.

Every visible country polygon receives a low-saturation, semi-transparent flag-like skin. Explicit palettes cover the principal powers and a broad set of other countries in `country_flag_palettes.json`. Countries without an explicit palette still receive a deterministic restrained fallback palette, so no visible country is left unfilled.

The palette is intentionally an identification layer rather than a literal cloth texture:

- common vertical, horizontal, cross, canton, disc and quartered structures are represented;
- complex coats of arms are not reproduced;
- historical great-power colors are preferred where configured, such as black-white-red for the German Empire;
- the polygon boundary never deforms;
- a low-frequency color and brightness wave gives the interior a mild flag-surface motion.

The flag animation is driven by a 0.12-second low-frequency timer. It redraws only the isolated global sample while the global country view is visible. Geography projection is not rebuilt for every animation tick.

The mouse wheel controls a bounded global zoom from 74% to 124%. The 3D orthographic camera and 2D projection radius change together.

Display levels are:

- far view: flag skins and borders, with no persistent country-name layer;
- medium view: the most important country names begin to fade in;
- near view: a larger bounded set of country names appears;
- selected or hovered countries retain immediate identification at every zoom.

Country names use priority limits and approximate collision rectangles. They are never intended to label all 177 country features simultaneously.

The moon is available as a global spatial reference at overview and medium zoom. It is hidden at close country-reading zoom and outside the global 3D country view so it does not crowd the map or float beside the flat France-focus view.

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

The repository data contains 96 metropolitan administrative units assigned across the nine macro regions. Their geometry is based on Natural Earth modern French department/province boundaries. It is a reliable spatial planning reference for the spike, but it is not presented as an exact reconstruction of every French boundary in 1900. The repository notes known historical differences such as the former Seine department.

A bounded set of additional French city anchors exists only inside the isolated spike runtime so every macro region can demonstrate city entry. These additions do not modify formal `cities.json`, saves or formal map systems. Cities without configured institution data say so rather than receiving fictional institutions.

## Corrected regional projection

The former region view stretched longitude and latitude independently to fill the panel, which visibly flattened or widened some regions.

The region layer now uses one uniform geographic scale. Longitude is adjusted by the cosine of the reference latitude, latitude and longitude then share the same pixel scale, and the result is centered inside the available map rectangle. The interaction probe checks this ratio numerically.

A small offset shadow and differentiated subdivision fills provide restrained depth separation. The region layer remains a deliberate enlarged planning map rather than pretending to be another globe. It is no longer geometrically squashed.

No synthetic transport network is drawn. The previous arbitrary line joining cities by longitude was removed. City markers retain their actual configured or spike-supplemented coordinates.

## Background

The solid black background is replaced by a procedural GL-compatible canvas shader with:

- a very dark navy/green gradient;
- sparse stars of several restrained scales;
- low-opacity cool and warm cloud bands;
- a soft vignette;
- fixed-position stars with slow, phase-shifted sine brightness changes.

Stars do not jump position, flicker on and off or produce rapid flashes. The background shader runs continuously while visible; the country flag wave uses a separate bounded low-frequency redraw.

## Data used

- Global country outlines and names: all features in `world_coastlines.json`.
- Country IDs: `iso_a3`, with France normalized to `country_fra`.
- Explicit country identification palettes: `country_flag_palettes.json`.
- Macro regions: `regions[].administrative_unit_ids`.
- Administrative subdivisions: `administrative_units[].geometry[].outer`.
- Formal region cities: `cities[].parent_region_id` and `cities[].lon_lat`.
- Institutions: `institutions.json`, including `city_id`, `parent_region_id`, `lon_lat`, `agenda`, `mandate` and `parent_institution_id`.
- Character profiles: `characters.json` identities.
- World status markers: a bounded set derived from configured institution agendas.

## Rendering structure

The scene draw order is explicit:

1. procedural background `ColorRect`;
2. isolated `World3D` SubViewport containing the fixed front-hemisphere shell and moon;
3. cached geographic overlays, flag skins and all HUD surfaces above the SubViewport.

The camera is a sibling of the hemisphere mesh. The SubViewport uses `own_world_3d=true`, GL Compatibility and `UPDATE_ONCE`; it is disabled and hidden outside the world level.

Global lon/lat coordinates are converted to unit-sphere vectors once at load time. Projection results are cached until rotation, selection, layout or zoom changes. Hidden-hemisphere lines and country fills are clipped at an interpolated horizon crossing. Flag animation changes only vertex colors and does not rebuild the geographic cache.

All coastline rings are loaded and simplified with a bounded Ramer-Douglas-Peucker pass rather than the former first-160-ring cutoff or fixed-step skipping.

## Functional interaction

- F1/F2 switch the two layout presets through `_unhandled_key_input()`.
- Left drag rotates global geography, flag skins and the latitude/longitude grid.
- Release retains short inertia.
- Hovering near the hemisphere left/right edge applies slow rotation.
- Mouse-wheel input changes bounded global zoom.
- Country anchors can be discovered and selected globally.
- Zoom controls the fade-in of bounded, collision-filtered country names.
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
- a minimum explicit flag-palette count;
- visible-country flag-polygon generation;
- far-zoom country names hidden;
- flag-wave time advancing;
- real mouse-wheel zoom changing both `world_zoom` and the orthographic camera;
- close-zoom country names faded in;
- close-zoom moon suppression and overview restoration;
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

The screenshot job produces far flag overview, medium zoom, close country-name and selected-France global views, plus dedicated images for every one of the nine macro regions.

## How to run locally

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Suggested review flow:

1. use the wheel to compare far flag overview and close country-name view;
2. rotate the global hemisphere;
3. select France and choose `进入国家`;
4. select one of the nine macro regions;
5. choose `进入大区`;
6. use `上一个大区` and `下一个大区` to review all regions;
7. hover or click administrative subdivisions;
8. enter a mapped city and open an institution node;
9. return through city, region, France focus and global;
10. test every corner panel, F1/F2 and the collapsible F2 workspace.

## Known limitations

- Only France has a detailed country-focus implementation. Other countries are selectable global objects but do not receive fabricated internal data.
- Explicit flag palettes simplify complex emblems and do not claim exact vexillological reconstruction for every territory in 1900.
- Countries without an explicit entry use deterministic restrained fallback colors.
- Modern Natural Earth department geometry is a documented visual planning reference, not an exact 1900 boundary reconstruction.
- Spike-supplemented cities provide geographic entry coverage but do not fabricate institutions or gameplay content.
- CI covers 1280×720. Manual review remains useful for multiple window dimensions, prolonged edge-hover feel and target-hardware CPU/GPU measurements.
- The runtime remains intentionally isolated and should be decomposed before any future production integration.
