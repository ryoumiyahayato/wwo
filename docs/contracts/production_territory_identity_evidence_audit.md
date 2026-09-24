# Production Territory Identity Evidence Audit

Status: `PRODUCTION_TERRITORY_CATALOG_READY=NO`

Base: `9254f087307eece5646c0180a8bc4d8328b38870`

## Scope

This audit follows the Formal Spatial Authority merge and evaluates whether the repository currently contains sufficient admitted, source-backed geography to construct and seal the single production `VNextTerritoryUnitCatalog`.

No Population, `VNextTerritorialControlLedger`, controller migration, globe/R4, HUD, Economy formula, Organization responsibility, political, social-movement, or demographic changes are included.

## Evidence inspected

- `scripts/vnext/spatial/spatial_catalog.gd`
- `scripts/vnext/spatial/spatial_world.gd`
- `scripts/vnext/territory/territory_unit.gd`
- `scripts/vnext/territory/territory_unit_catalog.gd`
- `scripts/formal/formal_world_simulation.gd`
- `data/world_map/countries.json`
- `data/world_map/regions.json`
- `data/world_map/world_admin1.json`
- `data/world_map/map_geometry_cache.json`
- `data/world_map/historical/cshapes_1900_snapshot.json`
- `local-artifacts/world-data-audit/batch3_loader_contract.json`
- `local-artifacts/world-data-audit/batch4_run_manifest.json`

## Candidate geometry inventory

`data/world_map/regions.json` exposes 96 France administrative-unit geometries and names an upstream Natural Earth Admin-1 source. The file is already admitted through the existing world-map / Spatial loading surface.

However, the same source document explicitly declares:

- `prototype_only: true`
- modern Natural Earth administrative boundaries are being used as a simplified placeholder for the 1900 theme
- the historical administrative differences are not yet fully represented

The existing `countries.json` source likewise declares `prototype_only: true` and describes modern Natural Earth geometry as prototype geometry for historically themed political identities.

The world-data audit also still reports unresolved historical/source work, including manual-or-historical items and geometry/source review work. Those gaps cannot be converted into production territory identity by relabeling current prototype geometry.

## Gate result

SOURCE_GEOMETRY_COUNT=96
TERRITORY_UNIT_COUNT=0
MAPPED_SOURCE_COUNT=0
UNMAPPED_SOURCE_COUNT=96
AMBIGUOUS_SOURCE_COUNT=0
ADJACENCY_SOURCE=UNAVAILABLE_FOR_PRODUCTION
FABRICATED_TERRITORIES=0
FABRICATED_ADJACENCY=0
CATALOG_SEALED=NO
CATALOG_FINGERPRINT=

The 96 administrative-unit polygons are valid evidence to continue auditing, but they are not sufficient to declare a production territory identity universe because their own admitted source contract marks them as prototype / modern-placeholder geometry rather than final production historical territory geometry.

## Exact blockers

1. No source-backed production territory snapshot is currently declared as authoritative for the intended historical world identity universe.
2. The strongest candidate Admin-1 source (`regions.json`) is explicitly prototype-only and explicitly documents modern-boundary placeholder semantics.
3. A stable production `source_snapshot_ref` contract has not yet been established for territory identity. Reusing a prototype resource path or inventing a snapshot identifier would violate the source-first requirement.
4. Production-safe adjacency is not available as an admitted source contract. It may later be mechanically derived from accepted geometry, but tolerance and edge/corner semantics are not currently defined and therefore must not be fabricated.
5. Repository audit artifacts still report unresolved historical/manual source work; this prevents claiming that the current geographic identity evidence has reached production authority status.

## Architectural consequence

No production `VNextTerritoryUnitCatalog` is constructed or composed.

`TERRITORIAL_CONTROL_OWNER=VNextSpatialWorld`

`TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED=NO`

`POPULATION_PRODUCTION_COMPOSED=NO`

Formal schema remains `formal_world_simulation_v10`.

The correct next step is to admit or designate a source-backed production territory snapshot (with explicit provenance and version identity), then implement a narrow deterministic adapter that maps those accepted geometry records to `territory_unit:*` IDs without copying geometry. Only after that evidence exists should Formal bind the sealed catalog fingerprint.
