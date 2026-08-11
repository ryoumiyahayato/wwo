# WWO WORLD DATA FOUNDATION — BATCH 2 REPORT

## Scope

Batch 2 continued the same safe boundary after the Batch 1 checkpoint: data and asset coverage, deterministic QA, manifests, and derived staging only. No gameplay architecture, vNext system, PR branch, authoritative JSON, or image asset was modified.

- Branch: `chore/world-data-foundation-audit-20260812`
- Batch 1 checkpoint: `a60a872`
- Base/live master: `4b738ab8b0a21e8685aae95381717e9efd2327a8`

## Actual work completed

1. Added `build_batch2_artifacts.py` for deterministic data, asset, corpus, gap, and staging manifests.
2. Added six-case machine-readable QA corpus covering finite/non-finite JSON, valid/invalid/zero-area rings, and canonical ring rotation.
3. Added manifest/staging tests and a corpus executor that runs every fixture case against the Batch 1 validator helpers.
4. Indexed every `data/world_map/**/*.json` file and every 1900 historical-flag PNG reference.
5. Added a source/asset gap report without inventing historical records or changing source files.
6. Measured output determinism and one controlled runtime baseline for both tools.

## Exact results

- Data files: 183.
- Data parse errors: 0.
- Deterministic data digest: `63380bd60a75d6dd58a40267ccb93f80a947fefe08fee09c823f92162232fe00`.
- Historical flag records: 61; asset references: 60; PNG files: 60.
- Verified asset hashes: 60/60.
- Missing assets, hash mismatches, and orphan assets: 0 / 0 / 0.
- Rendered asset dimensions: 60 files at `288x192`; upstream source dimensions are retained as metadata and deliberately not treated as rendered-PNG equality requirements.
- Regression corpus cases: 6; all executed successfully.
- Full focused tests: 11/11 passed in 20.669 seconds.
- Batch 2 generator: exit 0, 1,337.35 ms measured once.
- Batch 1 validator with `--allow-errors`: exit 0, 18,350.37 ms measured once.
- Two consecutive generator runs produced byte-identical SHA-256 outputs for all five Batch 2 JSON manifests.

The remaining findings are inherited from Batch 1 and remain explicit: 104 potential `world_admin1` self-intersections and 6 placeholder institutional references. Historical identity ambiguity and coverage gaps remain manual backlog, not mechanically fabricated data.

## Created files

- `tools/world_data/build_batch2_artifacts.py`
- `tests/world_data/fixtures/qa_corpus.json`
- `tests/world_data/test_batch2_artifacts.py`
- `tests/world_data/test_batch2_corpus_execution.py`
- `local-artifacts/world-data-audit/batch2_data_manifest.json`
- `local-artifacts/world-data-audit/batch2_asset_manifest.json`
- `local-artifacts/world-data-audit/batch2_regression_manifest.json`
- `local-artifacts/world-data-audit/batch2_gap_report.json`
- `local-artifacts/world-data-audit/batch2_asset_staging_candidates.json`
- `local-artifacts/world-data-audit/batch2_report.md`

All staging entries declare `authoritative_source_modified: false`.

## Batch 3 backlog

- Compare loader-declared data paths with actual JSON files.
- Generate a loader/data contract matrix and report unused or missing datasets.
- Build a country-to-flag asset coverage matrix using existing IDs only.
- Generate deterministic record signatures for representative catalog collections.
- Add contract and signature regression tests.
- Re-run validator, manifests, performance, determinism, and worktree hygiene checks.
