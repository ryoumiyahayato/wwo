# World names and aliases

This directory documents the Batch 1 names foundation. The generated files in
`data/staging/world_names/` are derived from existing repository data and do
not replace the production country, region, city, organization, institution,
character, or port catalogs.

Run the builder from the repository root with Python available on `PATH`:

```powershell
python -m tools.world_names.world_names --root . --starting-master '4b738ab'
```

The builder produces:

- `name_inventory.json`: merged entity inventory with source paths, current/display names, aliases, parent context, and historical periods.
- `aliases.json`: evidence-backed alias staging records. Every record keeps its source, date bounds, language/script hints, alias type, and confidence.
- `collision_report.json`: exact-name, normalized-name, spelling, historical/current, empty-name, and ID/name review findings.
- `search_index.json`: deterministic `normalized_name -> [stable IDs]` candidates. One-to-many mappings are preserved; source-record keys without an authoritative ID are excluded.

Normalization is only for search and comparison. It applies Unicode NFKC,
case folding, safe punctuation normalization, and whitespace folding. It does
not transliterate, translate, or become an identity key.

The default run scans all JSON files under `data/world_map/` for coverage. The
modern GeoNames city shards and geometry/runtime support files are reported as
read-only sources but are not staged as 1900 authoritative entities. Use
`--include-modern-reference` only for a deliberately larger research export.
## Batch 2 coverage and regression artifacts

Batch 2 also scans every repository data/**/*.json source while excluding the
generated data/staging/world_names/ directory from source coverage. It writes:

- coverage_manifest.json: deterministic source paths, SHA-256 digests, parse
  status, name-field counts, and staging status.
- remaining_gaps.json: excluded name-bearing sources and field groups without
  promoting them to authoritative entities.
- deterministic_corpus.json: artifact/source hashes and normalizer regression
  fixtures.

To write a separate Batch 2 report, pass
--report-path docs/world_names/BATCH_2_REPORT.md --batch-label "BATCH 2".
## Batch 3 non-authoritative review candidates

The separate review-candidate tool reads excluded non-modern source records and
writes only source-record-keyed candidates:

- review_candidates.json: direct repository name observations with source
  pointers and no authoritative identity.
- candidate_collision_ledger.json: preserved normalized one-to-many groups for
  manual review; no historical contradiction is inferred.
- artifact_manifest.json: deterministic paths, SHA-256 hashes, record counts,
  schema versions, and a source-input fingerprint. It excludes this manifest
  and excludes observational timing.
- performance_benchmark.json: local-only NON_DETERMINISTIC_OBSERVATIONAL
  timing output. It is ignored, is not part of the manifest, and must not be
  used as evidence of byte-identical regeneration.

The candidate validator independently rereads each source file, pointer,
field, value, source hash, and source-record identity. The staged validator
regenerates core and candidate artifacts from the tracked source tree and
compares canonical output with the tracked artifacts.

Run it with:
python -m tools.world_names.review_candidates --root D:/wwo --benchmark-repetitions 3
