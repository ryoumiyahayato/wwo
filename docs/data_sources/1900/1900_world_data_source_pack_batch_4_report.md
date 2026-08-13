# WWO 1900 World Data Source Pack — Batch 4

## Scope

Batch 4 turns existing admin1 and economy coverage declarations into an explicit, machine-readable review queue. It does not add historical values, geometry, population, production, prices, transport capacity, or gameplay coefficients.

- Snapshot context: `1900-03-12`
- Admin1 review items: 15
- Admin1 unit names represented by those records: 327
- Economy missing-dimension review items: 161
- Economy dimensions in the source coverage contract: 11
- Total review items: 176
- Historical facts inferred: **NO**
- Numeric values added: **NO**
- Runtime-authoritative data changed: **NO**

## Actual artifacts

- [`batch4_coverage_review_queue.json`](../../../data/staging/1900/batch4_coverage_review_queue.json): 15 admin1 and 161 economy-dimension review items.
- [`batch4_coverage_review_queue.schema.json`](../../../data/staging/1900/batch4_coverage_review_queue.schema.json): queue safety/schema contract.
- [`batch4_manifest.json`](../../../data/staging/1900/batch4_manifest.json): source/output digests and protected-scope flags.
- [`batch4_deterministic_corpus.json`](../../../data/staging/1900/batch4_deterministic_corpus.json): expected input/output hashes and counts.
- [`batch4_qa_report.json`](../../../data/staging/1900/batch4_qa_report.json): aggregate Batch 1–4 focused QA.
- [`build_1900_source_pack_batch4.py`](../../../tools/historical_data/build_1900_source_pack_batch4.py): deterministic queue generator.
- [`validate_1900_source_pack_batch4.py`](../../../tools/historical_data/validate_1900_source_pack_batch4.py): independent source parity and safety validator.
- [`test_1900_source_pack_batch4_determinism.py`](../../../tools/historical_data/test_1900_source_pack_batch4_determinism.py): clean-directory deterministic regression.
- [`validate_1900_source_pack_batches_1_to_4.py`](../../../tools/historical_data/validate_1900_source_pack_batches_1_to_4.py): aggregate focused QA runner.

Each admin1 item requires dated administrative sources, historical unit-name crosswalk, boundary/geometry evidence, and administrative-level definition. Each economy item requires a dated source locator, entity crosswalk, dimension definition, units/reference date, and bounds or uncertainty method. Existing `status`, `verified_dimensions`, and `missing_dimensions` values are copied only as queue inputs.

## Validation results

Aggregate focused QA: **PASS**, 7/7 checks:

- Batch 1 validator: PASS.
- Batch 2 validator: PASS.
- Batch 3 validator: PASS.
- Batch 4 validator: PASS.
- Batch 2 deterministic replay: PASS.
- Batch 3 deterministic replay: PASS.
- Batch 4 deterministic replay: PASS.

Batch 4 outputs were generated twice in clean temporary directories and matched byte-for-byte with the committed queue, corpus, and manifest. No absolute repository path appears in generated output, and all queue records carry `REVIEW_REQUIRED`, `historical_fact=false`, and `runtime_authority=false`.

## Resource-safety record

Batch 4 used sequential Python generation and validation only. No process-level parallelism, thread pool, raster processing, geometry conversion, or large temporary asset was used. Determinism used two small temporary JSON output directories and released them after comparison.
The repository-wide unified validation was not repeated after Batch 4 because this batch changes only isolated staging, manifests, validators, and reports. The resumed Batch 3 validation already exercised the same runtime and recorded the actual baseline failure at the existing ten-year performance gate (`246012934` microseconds versus `180000000`); repeating that unchanged high-cost phase would add machine load without new coverage. Batch 4 therefore uses the focused 7-check aggregate QA as its batch-specific validation.

## Remaining gaps

All 176 items still require historical source review before promotion. Deciding administrative boundaries, historical economic definitions, source dates, and uncertainty bounds requires historical judgment; this batch therefore stops at a safe review queue rather than guessing or modifying runtime data.
