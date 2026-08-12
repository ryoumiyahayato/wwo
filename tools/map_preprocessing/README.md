# WWO map asset preprocessing

This package is a read-only analysis and candidate-generation boundary for map
assets. It never rewrites files under `data/world_map/` and never treats a
generated visual cutout as spatial authority.

The repository command is:

```text
<bundled-python> -m tools.map_preprocessing.pipeline --root . all
<bundled-python> -m tools.map_preprocessing.pipeline --root . determinism
```

The default output is `artifacts/map-preprocessing/batch1/`, which is ignored
by the repository. It contains:

- `inventory.json`: raster/vector/source-file inventory with hashes, image
  dimensions, alpha availability, declared coordinate convention, and declared
  provenance.
- `crosswalk.json`: country, region, city, port, route, and dated historical
  entity relationships to geometry and source assets.
- `geometry_qa.json`: read-only ring, polygon, bounds, winding, fragment,
  duplicate, and finite-coordinate findings.
- `run_summary.json` and `benchmark.json`: stable result hashes and timings.
- `determinism.json`: replay/hash comparison for the three report products.

`preprocess` accepts a source PNG plus either a PNG mask or a geometry JSON/id.
It writes a padded alpha cutout, mask, checkerboard preview, and manifest to a
separate candidate directory. The source file is hashed and never overwritten.
The manifest shape is documented in `manifest.schema.json`.

The current repository has no map raster or vector source, so Batch 1 runs the
inventory, crosswalk, geometry QA, schemas, and tests while reporting actual
map cutout generation as blocked. The 1900 flag PNGs remain visual flag assets;
they are not used as spatial map sources.

## R1 safety contract

Every write is fail-closed to a strict descendant of `artifacts/map-preprocessing/`. Repository root, `.git/`, `data/world_map/`, tracked authoritative files, outside paths, and canonical/symlink escapes are rejected without redirection. Source and input-mask hashes are captured before writes and neither input is overwritten. Candidate filenames combine a sanitized stem with a deterministic hash of the original entity ID, so `a/b` and `a_b` cannot silently collide.

Geometry uses an explicit coordinate contract: `PIXEL` means top-left canvas pixels; `WGS84` requires finite source bounds and records the equirectangular mapping and y-axis convention. Malformed points/rings are errors, not filtered vertices. Mask input requires explicit `alpha` or `grayscale` mode; dimension mismatch is rejected unless nearest-neighbor resampling is explicitly enabled and recorded. Published manifests are validated against the actual files, dimensions, hashes, bboxes, coordinate contract, mask semantics, and path separation.

Generated visuals are candidate-only and never spatial authority. The current repository has no approved map raster/vector source, so real candidate cutouts remain `0` with dynamic status `BLOCKED_NO_SOURCE_MAP_ASSET`. Historical flag PNGs are excluded from spatial sourcing.