# World names and aliases

This directory documents the Batch 1 names foundation. The generated files in
`data/staging/world_names/` are derived from existing repository data and do
not replace the production country, region, city, organization, institution,
character, or port catalogs.

Run the builder from the repository root with the bundled Python runtime:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m tools.world_names.world_names --root 'D:\wwo' --starting-master '4b738ab'
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
