# Holographic workspace UI spike

## Status

This is an isolated, runnable Godot 4.6.3 UI spike. It does not replace the formal main interface.

The formal entry remains:

`run/main_scene="res://scenes/v2_3/v2_3_life_loop_menu.tscn"`

The spike is verified in GitHub Actions with the official Godot 4.6.3 Linux build, GL Compatibility rendering, real mouse/key interaction probes, focused product regressions, Windows export and installer compilation.

## Global historical model

The global hemisphere no longer treats the 177 modern Natural Earth features as 177 sovereign states in 1900.

`historical_political_entities_1900.json` groups modern geometry into approximate political entities for the selected 1900 date, including:

- French Third Republic and French colonial territories;
- United Kingdom and overseas British territories;
- German Empire and German colonial territories;
- Austria-Hungary;
- Russian Empire;
- Ottoman Empire;
- Qing Empire;
- Empire of Japan and Korean Empire;
- United States and overseas control areas;
- other European, Asian, African and American states or dependencies configured in the file.

Modern polygons not yet assigned to an explicit historical entity remain visible only as low-priority `待校订领土`. They are not presented as verified 1900 sovereign states.

This is a prototype historical aggregation layer, not exact historical GIS. It replaces the most misleading modern-state interpretation, but complex colonial borders, protectorates, leases, disputed areas and historical provincial boundaries still require dedicated source data.

## Distinctive political-entity skins

The global fill is no longer produced by blurred vertex-color interpolation.

Each political entity uses a cached 144×96 procedural texture. Standard horizontal, vertical, cross, canton, disc and quartered structures are supported. Several politically important or visually distinctive entities receive dedicated patterns:

- British Union structure;
- United States stripes and canton;
- Qing yellow field with central dragon-like disc structure;
- Japanese sun disc;
- Ottoman crescent structure;
- Austria-Hungary dual-monarchy structure;
- Nepal double pennant;
- Bhutan diagonal dragon-like structure.

The texture is clipped to the entity polygon. A small UV displacement and brightness modulation produce restrained cloth motion without deforming the political boundary.

Automated tests sample the generated textures and require distinct signatures for the major entities. Boundary animation is tested separately: alpha and width change slowly while the projected geometry checksum remains unchanged.

## Rotation, zoom and labels

The transparent front-hemisphere shell remains fixed. Geography, political fills, borders, war fronts, state markers and longitude/latitude grid rotate through the shared `yaw` and `tilt` transform.

- left drag rotates the world;
- release keeps short inertia;
- left/right edge hover produces slow rotation;
- mouse wheel changes bounded global zoom;
- the global range is 74% to 600%;
- `放大定位` recentres the selected entity and computes a fit zoom from its angular extent.

The minimum screenshot is the complete hemisphere overview. At high zoom the hemisphere extends outside the viewport, allowing small entities such as Nepal and Bhutan to remain complete and readable instead of being represented only by an anchor.

Label LOD is progressive:

- far overview: no persistent political-entity names;
- medium zoom: high-priority entities begin to appear;
- high zoom: more names appear with a bounded label count and collision filtering;
- selected and hovered entities remain identifiable at all zoom levels.

The moon is visible only in the global 3D overview and medium zoom. It is hidden during close country reading and in flat political, regional and city layers.

## Political borders and war layer

Historical political borders use merged entity outlines rather than drawing every modern polygon as a separate sovereign border.

- sovereign and imperial entities use a solid slowly pulsing outline;
- dependencies and autonomous areas use dashed outlines;
- provisional territories are visually subdued;
- contested or fragmented areas use warmer warning colors;
- selected and hovered entities receive stronger outlines.

`historical_political_entities_1900.json` also defines prototype conflict paths for the selected date, including the Second Boer War, Boxer crisis, Philippine-American War and War of the Golden Stool. The global `战争边界` control toggles this layer.

War paths and historical borders are visual planning data, not a complete operational front simulation. They do not alter formal military systems.

## Global hierarchy

The generic hierarchy for non-France entities is:

1. global historical political entity;
2. member territory or political holding;
3. first-level administrative region;
4. first-level-region local view.

For an entity with one member territory, that territory is selected automatically. For a territory with one first-level region, the hierarchy automatically skips the redundant selection layer.

All configured global territories can use `world_admin1.json`, generated from Natural Earth admin-1 geometry by `tools/build_world_admin1.py`.

Current generated audit:

- 4,589 first-level regions;
- 251 country or territory codes;
- 6,334 polygons.

These admin-1 boundaries are a modern fallback when historical regional geometry is unavailable. The interface states this explicitly and does not claim that every region matches 1900.

At global zoom 220% or greater, the selected territory's admin-1 boundaries can appear directly on the globe. At higher zoom, a bounded set of admin-1 labels is shown.

## France hierarchy

France retains its dedicated sample hierarchy:

1. French Third Republic on the global hemisphere;
2. France focus with nine macro regions;
3. selected macro region with constituent administrative subdivisions and city entries;
4. city with configured institutions, parent links and character badges.

The nine macro regions are:

1. Northern Industrial Belt;
2. Paris Basin;
3. Normandy;
4. Brittany;
5. Loire Valley;
6. Aquitaine;
7. Massif Central;
8. Rhône Valley;
9. Mediterranean Coast.

The region layer uses one geographic scale with longitude corrected by the cosine of reference latitude. It no longer stretches latitude and longitude independently. No synthetic transport network is drawn.

## Background and moon

The background is a procedural, GL-compatible dark starfield with:

- restrained navy/green gradient;
- sparse stars at several scales;
- low-opacity cool and warm cloud bands;
- soft vignette;
- fixed star positions with slow phase-shifted brightness changes.

The moon is a real `SphereMesh` in the isolated 3D SubViewport with a procedural lit surface. It is not a 2D circle.

## Rendering and performance structure

The draw order is:

1. procedural background;
2. isolated `World3D` SubViewport with hemisphere and moon;
3. cached geographic overlays, entity textures, borders, fronts and HUD.

Global lon/lat points are converted to unit-sphere vectors at load time. Projection results are cached until rotation, zoom, selection or layout changes. Back-hemisphere lines and polygons are clipped at the horizon.

Flag animation reuses cached textures and projected polygons. It does not rebuild geographic data every timer tick.

The global admin-1 file is generated deterministically in CI and loaded by the isolated spike. Production integration should later split or lazily load this data according to selected entity.

## Functional controls

- F1/F2 layout switching;
- global drag, inertia and edge-hover rotation;
- wheel zoom from overview to small-state reading scale;
- political-entity selection and fit zoom;
- war-layer toggle;
- generic entity → territory → admin-1 → local navigation;
- France → macro region → subdivision/city navigation;
- Esc closes information/HUD surfaces first, then returns one spatial level;
- collapsible F2 workspace;
- functional country, character, local-time-speed and activity corners.

Spike time and HUD controls remain isolated and do not alter formal game systems.

## Automated verification

`.github/workflows/holographic-workspace-spike.yml` performs:

1. deterministic global admin-1 generation and audit;
2. project import and strict script parsing;
3. direct spike-scene loading;
4. main interaction probe;
5. independent global admin-1 hierarchy probe;
6. GL Compatibility screenshot capture;
7. screenshot artifact upload.

The probes verify:

- modern Germany is replaced by the German Empire entity;
- major 1900 empires and Nepal/Bhutan exist;
- provisional entities do not replace the entire world;
- distinctive flag-texture signatures;
- border pulse changes without geometry movement;
- war data exists;
- far labels are hidden and high-zoom labels appear;
- Nepal and Bhutan remain readable at bounded maximum zoom;
- German Empire generic focus and admin-1 flow;
- global admin-1 record and country coverage;
- Russian Empire territory aggregation;
- France's nine-region flow and existing city/HUD interactions.

Real screenshots include:

- minimum 1900 world overview;
- war-boundary view;
- high-zoom entity names;
- complete Nepal focus;
- German Empire focus;
- Germany admin-1 and local admin-1 views;
- Russian Empire holdings;
- France focus, nine French macro regions and city view.

## Run locally

Open or run:

`res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn`

Suggested review:

1. rotate the minimum global overview;
2. toggle war boundaries;
3. select and fit Nepal or Bhutan;
4. select the German or Russian Empire and enter its territory hierarchy;
5. inspect a first-level administrative region;
6. return globally and enter France;
7. review all nine French macro regions and a city;
8. test F1/F2 and all four corner controls.

## Known limitations

- historical political boundaries are approximate aggregations of modern geometry;
- global admin-1 boundaries are modern fallback data, not verified 1900 subdivisions;
- provisional territories remain where explicit historical mapping is incomplete;
- the conflict layer is illustrative and not a complete military front database;
- only France has a dedicated hand-shaped macro-region and city sample;
- other entities use the generic member-territory and modern admin-1 fallback hierarchy;
- CI screenshots use 1280×720; manual review remains useful for additional window sizes and target hardware;
- the isolated runtime is deliberately layered for the spike and should be decomposed before production integration.
