# WWO data and asset provenance

This directory contains the machine-readable provenance manifest for the
WWO DATA & ASSET PROVENANCE AUDIT. Batch 1 covers tracked files below:

- `data/**`
- `assets/**`
- `docs/**`

The manifest records file size and SHA-256, category, source or generated
status, explicit source locators, explicitly recorded licenses, derived-from
relationships, generators, confidence, review status, and audit issues.

Provenance policy:

- A source or license is known only when the repository contains explicit
  evidence for it.
- Otherwise the manifest uses `SOURCE_UNKNOWN`, `LICENSE_UNKNOWN`, or
  `PROVENANCE_INCOMPLETE` as appropriate.
- An online match or a dataset name without a locator is not treated as proof
  of the current file's origin.
- Unknown licenses are validator warnings, not legal conclusions.
- The dependency graph represents `source -> generator -> generated output`.
- No formal assets are regenerated or deleted by the audit.

The manifest is generated from tracked files and is intended to be rerun after
source or asset changes. Reviewers should inspect the repository evidence
listed in each entry before treating a provenance chain as complete.

Batch 2 adds `provenance_reference_matrix.json`. It statically inventories
tracked producers, consumers, repository path literals, write-site candidates,
and candidate dependency edges under `scripts/**`, `scenes/**`, `shaders/**`,
`tests/**`, and `tools/**`. Dynamic test fixtures are marked
`INTENTIONAL_TEST_FIXTURE`; candidate edges remain review-required and do not
become authoritative provenance automatically.

Batch 3 adds two low-risk derived records under `tests/provenance/`:

- `provenance_regression_corpus.json` pins a compact, deterministic copy of
  manifest records and the manifest hash for regression checks. It is a
  deterministic regression/drift snapshot, not independent historical evidence
  and cannot establish source or license truth.
- `provenance_review_backlog.json` ranks only evidence-backed review candidates
  from the manifest and reference matrix. It is not an instruction to modify
  authoritative data, infer licenses, or regenerate assets.

The reference matrix deliberately excludes JSON audit outputs under tests/provenance/ from its runtime producer/consumer scope. Those records are validated separately; excluding them prevents the audit from treating its own serialized evidence as game data references or stale runtime artifacts.


## Economic resource pilot units and scale comparisons (2026-10-30)

`data/land/economic_resources_france_pilot.json` states the existing quantity units and opt-in developer scale assumptions. Native grain, coal and flour use `development_kg`; reporting them as tonnes uses 1/1000, without granting national coverage, macro inventory or currency conversion. Bread in the original scale controls remains a developer piece without a mass/calorie conversion. Original land is 10 × 100m²; the 100/1000 scale configurations declare 10/100ha of hypothetical capacity in the same formal French resource/place identities. Historical cultivated area, population/land ratios, seed/yield rates and geological quantities remain unknown or developer assumptions.

The source URLs support modern agricultural/mineral presence only. No new geographic dataset was downloaded. Legacy pilot routes and nodes use developer business quantities/day. The pilot StockLots inventory has no attached physical warehouse capacity; regional Shared facility and payload conversions remain separate. No steel/grain mass equivalence or physical railway capacity is inferred.

## Household circulation proportions (2026-10-30)

The opt-in cycle comparison keeps 10ha and assigns 40 automatic adult equivalents, not the original scale control's 600 residents. Selected daily needs are 500g dry-staple equivalent (600g for miners) and 10MJ fuel input per person. Grain/flour provide 1000g per kg; the cycle-only bread recipe uses 0.5kg flour per piece, without claiming a measured wet loaf mass. Food services are a mass approximation, not nutritional equivalence. Other food groups, clothing, soap, lighting, housing, water and healthcare remain unmapped in this slice.

- [Allen (2001), Table 3 and bread discussion](https://web.mit.edu/14.731/papers/greatdivergence.pdf): a comparative European basket includes 182kg bread/person/year and other foods, plus 5 million BTU annual fuel. It is not a measured 1900 Rouen/Lyon diet. The paper's approximate 83% flour extraction supports only an order-of-magnitude comparison with the cycle's developer 80% recipe.
- [IPCC 2006, Volume 2, Chapter 1, Table 1.2](https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/2_Volume2/V2_1_Ch1_Introduction.pdf): other bituminous coal has default net calorific value 25.8MJ/kg, with a 19.9–30.5 range. The selected 25MJ/kg is fuel energy, not useful stove heat or measured Loire coal.
- [FAO/WHO/UNU energy requirements](https://www.fao.org/4/Y5686e/y5686e07.htm): energy needs depend on body size and activity. The cycle's 400–650g staple and 8–16MJ fuel developer ranges do not specify a complete diet or a historical minimum.

Yield, seed rate, labor, population assignment, weather, wage, currency, mining quantity and transport quotas remain explicit developer assumptions. Regrouping the cycle land into 100 × 1000m² changes allocation granularity, not total capacity. No new GIS was acquired.

The old `wwo-economy/scripts/world/global_commodity_reference.gd` uses developer tonnes/day across 50 regions and 16 goods, with wheat demand 180 tonnes/million people/day. Its `flows` are estimated daily dispatches of statistical buffers, without executable stock, orders or Ledger payments. Read-only original day-84/day-86 save observations and the unresolved remembered “34K” figure are distinguished in [the current economy review](../economy/ECONOMY_SYSTEM_REVIEW.md#2026-10-30聚合市场数量与计算成本). Old saves were not advanced or rewritten.

## London CITY water reference (2026-10-29)

This section describes the R63 central reference. The historical miniature below
replaces its limited two-section display in the current London CITY profile.

`data/local/london_city_water.json` is a bounded Presentation derivative of modern OpenStreetMap water relations [28934](https://www.openstreetmap.org/relation/28934) (version 78) and [70347](https://www.openstreetmap.org/relation/70347) (version 49). Acquisition used the official OSM API `/api/0.6/relation/{id}/full.json`. Copies of the API responses are retained in `../offline-map-sources/london_1890s/osm-28934.json` and `../offline-map-sources/london_1890s/osm-70347.json` (paths relative to the project root). They total 987,848 bytes; the shipped derivative is 79,230 bytes. No country-wide hydrology was acquired.

License: [Open Database License 1.0 and OSM attribution](https://www.openstreetmap.org/copyright), © OpenStreetMap contributors. The derived water data remains ODbL. Source versions, element dates, retrieval date, license and attribution are also stored in the JSON and displayed in CITY. This is modern water reference, not surveyed 1900 riverbanks, land ownership, navigability or transport capacity.

`tools/map/build_london_city_water.py` reconstructs the source outer/inner rings, unions the two sections, clips to longitude -0.175…-0.045 and latitude 51.478…51.522, simplifies by 1.5m, and triangulates. The output has 904 vertices and 986 water triangles. Original boundary segments and clipping limits are separate. Source section ends are bounded reference limits, not evidence that the river ends there. The renderer labels the reference ends, keeps REGION for distant context, and does not extend a fixed-width strip into missing bank data. Buildings are schematic and excluded from the reference water and its bank clearance. No new historical street or building coordinates are inferred.

## London historical miniature preparation (2026-10-30, local work)

The current `data/local/london_city_overview.json` selects the historical
footprint derivative. It no longer uses the five anchored rooftop clusters or
the two-section R63 water display. The existing CITY camera, LOCAL viewport,
resource loading and formal place identity remain in use.

- Buildings: [Petitpierre et al., corrected corr_v1](https://zenodo.org/records/21282700),
  CC BY 4.0. The read-only EPSG:3857 layer contains **1,299,040** features:
  1,240,127 regular, 58,696 compound and 217 without a class. The text
  description's older 1,299,029 total is not substituted for the actual count.
  Survey 1891–1895; publication 1893–1896. The source reports six missing
  sheets, small-feature errors and inconsistencies at sheet edges. Detection
  accuracy quoted by the authors applies to their raw extraction, not our LOD.
- Historical reference: [NLS London 1890s index](https://maps.nls.uk/os/townplans-england/london-1056-1890s.html)
  and [an indexed 1894/1895 sheet](https://maps.nls.uk/view/101202420), CC-BY (NLS).
  Bounded native map tiles were inspected at the waterfront, dense centre,
  outer Crouch End and a sheet boundary. Thirteen primary corridors, eight
  bridges and nine open spaces are selected, approximate presentation inputs.
  Their widths are display widths. Other footprint gaps are not classified as
  roads. No building use, height, property or route capacity is inferred.
- Water: official OSM API geometry, ODbL 1.0, acquired 2026-10-30. Source
  objects, versions and timestamps are retained in the derivative index.
  Neighbouring supplied Thames polygons are united without invented connecting
  strips; islands and holes remain. The main river continues beyond the allowed
  background view. Selected modern park lakes and surviving docks are included.
  Modern banks do not restore historic infilled dock basins, all tributaries or
  every small pond. Water colour is a map style, not a depth measurement.

The 640,135,168-byte corrected GeoPackage, OSM responses, reference tiles and
numeric mesh intermediates stay in `D:/programs/WWO/offline-map-sources/london_1890s`,
outside the exported project. Only compressed meshes, a small index, structure
configuration and [credits](../../assets/settlements/london_1890s/CREDITS.txt) ship.

`tools/map/build_city_miniature.py` uses the actual footprint directions and
voids. It generates 3km partitions, a 12m overview grid and a 4m district grid,
one-pixel bounded closing and topology-preserving simplification. It does not
erase original buildings to force an approximate street or park. Modern water
has a 5m clearance. Polygon holes remain. `tools/map/save_city_meshes.gd`
converts numeric geometry to compressed ArrayMesh resources. No runtime GIS
parsing or per-building nodes are introduced. The 8m display height is an
assumption, not measured historical height or a new simulation asset.

The initial overview follows the largest connected 3km cells with at least
10% footprint-derived built cover; its extent is approximately 27×18km. It is
framing, not a historic administrative boundary. The full source extent remains
available in the spatial partitions. Camera-background bounds and footprint
coverage are separate. No population-based circle or modern Greater London
boundary is substituted for the building data.


Mesh positions are baked through the existing `RegionProjection` spherical
azimuthal equidistant chart (radius 6371008.8m), using the profile anchor. The
numeric production grid is equirectangular only as an intermediate. Explicit
whole-city framing rebases the same camera chart so meshes, labels and anchors
share a coordinate basis. The final derived directory is 19,254,000 bytes.
The DOI publisher and main NLS index did not return readable content in this
run (TLS/HTTP 405); the Zenodo README, corrected database, official NLS item
metadata and bounded original map tiles were used. No full-paper read is claimed.


### 2026-10-30 London water display LOD

The current CITY water uses three offline ArrayMesh derivatives of the same
cached `thames-presentation-union.geojson`, with 2/5/10m topology-preserving
simplification. The main connected channel and holes are retained. Separate
subpixel pools may be omitted. Source-window edges are excluded from the shore
fringe. The 3.2/6.4/12.8m alpha fringe is cartographic antialiasing, not surveyed
land or a claim about historical banks. All three levels use the original city
projection anchor. No new source acquisition or historical shoreline inference
was performed. Existing OSM object versions, attribution and ODbL remain in the
presentation index. The raw source and prior water assets are preserved.


### 2026-10-30 London CITY–REGION handoff

The existing CITY OSM union is reused. OSM river ways 66997114 and 515944056
supply the actual missing Dartford–Gravesend water, without a synthetic connector.
A local OSM coast query and adjacent coastline ways from the official OSM API
supply the paired estuary land/sea/coast display. The final coastline source has
974 ways and is 8,972,222 bytes, retained at
`D:/programs/WWO/offline-map-sources/london_1890s/estuary-coast-handoff.json`.
The original `estuary-coast-local.json`, water union and gap-water JSON are kept.
The acquisition metadata contains the actual API URLs and completeness bounds.
The adopted coast window is [0.18, 51.1, 1.6, 51.9]. The two original medium
shards remain intact; only their index descriptors select new local derivatives.

OSM coastline direction (land on the left) is used for polygonization. The
preprocessor rejects dangling/cut source lines, preserves island holes, applies
10m display simplification, and partitions matching physical land and water.
10m is a display tolerance, not measured positional accuracy. The original NE
reference continues outside the acquired window; its earlier raw source file
was unavailable in this workspace, so the original-source versus old 300m
simplification contribution is not separately quantified. The old display
geometry itself already contains the observed large angles.

These remain modern physical references, not reconstructed 1900 tidal levels,
shoreline engineering, reclaimed docks or tributary coverage. Attribution:
[OpenStreetMap contributors, ODbL](https://www.openstreetmap.org/copyright).
The historical political ink remains a separate sourced layer; clipping it to
physical land adds no historical ownership evidence.
