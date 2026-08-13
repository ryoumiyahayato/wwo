# WWO map asset preprocessing — Batch 1

This batch adds a non-destructive asset engineering boundary around the
existing map data. The tool reads authoritative JSON and existing geometry but
does not rewrite it. Candidate visual output belongs under ignored
`artifacts/map-preprocessing/` or another explicitly local directory.

## Pipeline contract

```text
source map -> canonical canvas -> entity polygon/mask -> alpha cutout
           -> tight bbox -> padded bbox -> normalized output -> preview -> manifest
```

The `preprocess` command can receive an existing mask or rasterize a selected
polygon from a supported JSON geometry document. It records the source hash,
entity ID, mask/crop bounding boxes, canvas/output sizes, processing
parameters, and generator version. It uses deterministic nearest-neighbor
resampling and stable filenames. Inputs are never overwritten.

## Batch 1 evidence

The repository contains 60 RGBA 1900 flag PNGs, all 288×192. It contains no
map raster, SVG, GeoJSON, or other standalone vector asset suitable for a map
cutout. The batch therefore does not create a false cutout; it runs the
tooling, schema validation, crosswalk, geometry QA, and synthetic cutout tests.
Flags are linked as historical visual sources only.

The current source relationships are:

- 177 current country records resolve to 177 Natural Earth coastline features.
- 96 administrative-unit source codes resolve to Natural Earth admin-1
  features; the focused regions file contains 98 administrative units.
- 151 dated political units resolve to all 151 CShapes snapshot features.
- The world admin-1 provider has many additional global features outside the
  focused project crosswalk; these are reported as unreferenced provider data,
  not automatically mapped into project authority.

## Determinism and QA

Inventory, crosswalk, and geometry QA outputs are canonical JSON products. The
replay command builds them twice and compares SHA-256 hashes. Geometry QA
checks finite coordinates, invalid/empty rings, zero area, duplicate vertices
and polygons, self intersections, bounds, hole containment, winding, and
small fragments. Mask QA checks emptiness, full opacity, tiny coverage,
fragments, holes, and candidate bounds.

The only generated previews are candidate cutout previews produced when a
caller supplies a suitable source. Large previews and binary candidates remain
local-only.

## R1 safety contract

Writes are fail-closed to strict descendants of the ignored `artifacts/map-preprocessing/` tree. Repository root, `.git/`, `data/world_map/`, tracked authoritative files, outside paths, and canonical/symlink escapes are rejected rather than redirected. Source and input-mask hashes are captured before writes; source assets and masks are never overwritten. Sanitized entity-ID stems include a deterministic hash of the original ID and the manifest retains the original ID.

`PIXEL` geometry maps directly to a top-left canvas. `WGS84` geometry requires explicit finite source bounds and records the mapping and y-axis convention. Malformed points/rings produce explicit errors. Mask mode is explicit (`alpha`, `grayscale`, or derived `geometry`); dimension mismatch is rejected unless nearest-neighbor resampling is opted in and recorded. Published manifests validate required fields, actual file references, dimensions, hashes, positive in-canvas bboxes, coordinate contract, alpha/mask semantics, and distinct paths.

Generated visuals remain candidate-only and cannot become spatial authority. The source-absence status is derived from the inventory and provenance/license/coordinate-contract fields: with no approved source it is `BLOCKED_NO_SOURCE_MAP_ASSET`; a future approved source is not blocked by a permanent constant. Historical flag PNGs remain visual-only and are never map-space sources.

Source admission is explicit. The default `approved_spatial` contract resolves
the existing `docs/data_sources/provenance_manifest.json` by canonical path and
requires a unique approved map-visual PNG record with matching size/hash,
license, locator, review status, and coordinate convention. Missing, unrelated,
historical-flag, malformed, or hash-mismatched records fail closed. Synthetic
fixtures require the explicit CLI/API contract `synthetic_test`; their manifest
state is marked synthetic and they are excluded from real repository source
discovery.
