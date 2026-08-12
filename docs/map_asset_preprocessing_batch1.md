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
