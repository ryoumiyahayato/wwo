# WWO WORLD DATA FOUNDATION — BATCH 1 REPORT

## Scope and execution state

This report records the actual Batch 1 execution against the live repository state. The audit is read-only against authoritative `data/world_map/**`; no vNext system, PR branch, or production source data was changed.

- Live starting `origin/master`: `4b738ab8b0a21e8685aae95381717e9efd2327a8`
- Branch: `chore/world-data-foundation-audit-20260812`
- HEAD: `4b738ab8b0a21e8685aae95381717e9efd2327a8`
- Dedicated worktree: isolated worktree for this branch (local path intentionally omitted from tracked output).

## Phases actually completed

- Phase A — inventoried schemas, loaders, IDs, foreign keys, coordinate fields, source fields, and required/optional policy.
- Phase B — parsed references and checked empty/duplicate IDs, dangling references, placeholder references, prefix/type contradictions, and cross-catalog links.
- Phase C — checked source geometry for coordinate validity, empty/zero-area rings, ring closure, duplicate points, and self-intersections; projected map-cache geometry was handled under its own schema.
- Phase D — generated the country and major historical-entity coverage matrix without inventing historical facts.
- Phase E — generated mechanically safe normalization candidates; no uncertain source edit was proposed.
- Phase F — generated derived reverse-index and geometry/flag staging candidates only.
- Phase G — implemented and ran the standalone deterministic validator and focused tests.
- Phase H — inspected local raster assets; preprocessing was skipped because all 60 rasters are historical flags, not an unambiguous source map.

## Inventory

- JSON files parsed: 183
- Countries: 177
- Regions: 9 macro regions and 98 administrative units
- Curated cities: 32
- Ports: 8
- Road / rail / shipping links: 3 / 9 / 3
- Historical political entities: 61
- Organizations / institutions / character seeds: 11 / 7 / 2
- Source geometry-bearing objects: 5,015
- Modern city-detail records: 88,927 across 156 shard files

## Referential integrity

- Dangling foreign keys: 0
- Duplicate, empty, or duplicate stable IDs: 0
- Placeholder foreign-key warnings: 6, all in `institutions.json`
- Real unresolved references were not converted into placeholders and no uncertain reference was auto-fixed.

## Geometry QA

- Potential self-intersecting rings: 104 in `world_admin1.json`
- Zero-area findings: 0
- Empty-geometry findings: 0
- Non-finite JSON constants: rejected by the parser
- Source geometry was not rewritten.
- The Robinson projected map cache was validated as projected cache data rather than incorrectly applying lon/lat source-ring rules.

## Coverage matrix

Status is repository coverage in the current scope, not a claim that a missing record historically did not exist. The curated modern catalog and France-focused scenario are not exhaustive.

| Dataset / relation | COMPLETE | PARTIAL | MISSING | NOT_APPLICABLE | AMBIGUOUS |
|---|---:|---:|---:|---:|---:|
| regions | 1 | 0 | 0 | 176 | 0 |
| administrative_units | 1 | 0 | 0 | 176 | 0 |
| curated cities | 1 | 11 | 166 | 0 | 0 |
| capital mapping | 1 | 0 | 176 | 0 | 0 |
| ports | 0 | 4 | 173 | 0 | 0 |
| road connectivity | 0 | 2 | 175 | 0 | 0 |
| rail connectivity | 0 | 1 | 176 | 0 | 0 |
| shipping routes | 0 | 4 | 173 | 0 | 0 |
| geometry | 177 | 0 | 0 | 0 | 0 |
| historical 1900 identity | 161 | 0 | 10 | 0 | 6 |
| institutions | 0 | 1 | 176 | 0 | 0 |
| organizations | 0 | 1 | 176 | 0 | 0 |
| character/person seed | 0 | 1 | 0 | 176 | 0 |

For 50 major historical profiles, geometry coverage is 48 COMPLETE and 2 MISSING. Historical identity gaps and ambiguities require source-backed research.

## Safe staging and normalization

`staging_candidates.json` contains only derived indexes for country-to-regions, administrative units, cities, ports, organizations, institutions, and characters; city-to-port/road/rail; port-to-shipping-route; region-to-institutions; institution-to-organization/character; organization-to-character; country and historical geometry; and historical flags.

`normalization_candidates.json` contains a single `none` result: no mechanically safe normalization candidate was found. Authoritative source files were not edited.

## Historical and manual backlog

The six placeholder institutional references need an explicit source/manual decision. The 10 missing and 6 ambiguous historical identity mappings need authoritative crosswalk research. Country-level capital, port, road, rail, shipping, organization, institution, and person coverage remains mostly absent outside the curated France-focused scenario. Modern city-detail shards are reference data and are not treated as historical 1900 coverage.

## Tooling and validation results

- Created `tools/world_data/validate_world_data.py`, a stdlib-only, deterministic, read-only validator.
- Created `tests/world_data/test_validate_world_data.py`.
- Focused command: `python -m unittest discover -s tests/world_data -p 'test_*.py' -v` using the configured workspace Python runtime.
- Focused result: 5 tests passed in 19.981 seconds.
- Allow-errors validator result: 110 findings — 104 ERROR and 6 WARNING — exit 0.
- Strict validator result: exit 1, exactly because the 104 geometry findings remain visible.
- JSON/reference/geometry regression: 183 files parsed; dangling 0; duplicate IDs 0; self-intersections 104; zero-area 0; empty geometry 0.
- `git diff --check`: pass; direct trailing-whitespace scan of the untracked source files: pass.
- Audit artifact hygiene: no log, temporary, backup, bytecode, screenshot, or cache files.

## Map preprocessing

Skipped. The repository contains 60 raster assets, all below `assets/historical_flags/1900/`; no unambiguous local raster/source map was available. No original asset or geometry was overwritten.

## Actual files created

- `tools/world_data/validate_world_data.py`
- `tests/world_data/test_validate_world_data.py`
- `local-artifacts/world-data-audit/inventory.json`
- `local-artifacts/world-data-audit/findings.json`
- `local-artifacts/world-data-audit/coverage.json`
- `local-artifacts/world-data-audit/normalization_candidates.json`
- `local-artifacts/world-data-audit/staging_candidates.json`
- `local-artifacts/world-data-audit/report.md` (raw validator report)
- `local-artifacts/world-data-audit/final_report.md` (this complete Batch 1 report)

## Git and publication state

- Working tree: intended untracked audit files only under `tools/world_data`, `tests/world_data`, and `local-artifacts/world-data-audit`.
- Shared main worktree remains on its concurrent branch and its unrelated modifications were not touched.
- Commit: none.
- Push: not performed.
- Pull request: none.

## Highest-value missing-data tasks

1. Source-review the 104 `world_admin1` self-intersection candidates.
2. Resolve the six placeholder institutional foreign keys.
3. Establish an authoritative Australia 1900 identity crosswalk.
4. Establish an authoritative Canada 1900 identity crosswalk.
5. Establish an authoritative Egypt 1900 identity crosswalk.
6. Establish an authoritative India 1900 identity crosswalk.
7. Establish an authoritative New Zealand 1900 identity crosswalk.
8. Establish an authoritative Cuba 1900 identity crosswalk.
9. Resolve the remaining missing historical identity mappings.
10. Resolve the six ambiguous historical identity mappings.
11. Add source-backed capital mappings for major entities.
12. Expand country-to-port coverage with licensed source data.
13. Expand country-to-road connectivity with provenance.
14. Expand country-to-rail connectivity with provenance.
15. Expand port-to-shipping-route coverage.
16. Complete country-to-region and administrative-unit crosswalks.
17. Expand institution coverage where the design requires it.
18. Expand organization coverage where the design requires it.
19. Review the boundary and provenance of person-seed coverage.
20. Create a promotion manifest covering source IDs, geometry repairs, licenses, and historical evidence.
