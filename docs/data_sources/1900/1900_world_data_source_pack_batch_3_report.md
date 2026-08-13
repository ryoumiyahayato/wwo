# WWO 1900 World Data Source Pack — Batch 3

## Scope

Batch 3 creates mechanically safe source-gap candidates from existing repository records that are useful to the map/economy surface but are not independently proven 1900 historical facts. The original records are copied under an explicit `UNVERIFIED_FOR_1900` status; no city, port, rail, shipping, population, capacity, or route fact is promoted or inferred.

- Snapshot context: `1900-03-12`
- Candidate records: 52
- Candidate split: 32 cities, 8 ports, 9 rail segments, 3 shipping routes
- Digest inventory files: 13
- Runtime-authoritative data changed: **NO**
- vNext/core gameplay changed: **NO**
- Gameplay balance changed: **NO**
- Historical fact inferred: **NO**

Every candidate requires a source locator, historical date interval, and the relevant identity/crosswalk evidence before promotion. Current prototype parent IDs and coordinates are retained only as source-record payloads for review; they are not assertions about the 1900 world.

## Actual artifacts

- [`batch3_source_gap_candidates.json`](../../../data/staging/1900/batch3_source_gap_candidates.json): 52 safety-gated candidates.
- [`batch3_repository_inventory.json`](../../../data/staging/1900/batch3_repository_inventory.json): 13 input files with SHA-256, schema metadata, record counts, and promotion status.
- [`batch3_source_gap_candidates.schema.json`](../../../data/staging/1900/batch3_source_gap_candidates.schema.json): candidate contract.
- [`batch3_manifest.json`](../../../data/staging/1900/batch3_manifest.json): input/output digests and protected-scope flags.
- [`batch3_deterministic_corpus.json`](../../../data/staging/1900/batch3_deterministic_corpus.json): expected digest corpus.
- [`batch3_qa_report.json`](../../../data/staging/1900/batch3_qa_report.json): machine-readable Batch 1–3 aggregate QA.
- [`build_1900_source_pack_batch3.py`](../../../tools/historical_data/build_1900_source_pack_batch3.py): deterministic candidate/inventory generator.
- [`validate_1900_source_pack_batch3.py`](../../../tools/historical_data/validate_1900_source_pack_batch3.py): source-copy, safety, inventory, and digest validator.
- [`test_1900_source_pack_batch3_determinism.py`](../../../tools/historical_data/test_1900_source_pack_batch3_determinism.py): clean-directory byte comparison.
- [`validate_1900_source_pack_batches_1_to_3.py`](../../../tools/historical_data/validate_1900_source_pack_batches_1_to_3.py): aggregate QA runner.

The inventory covers current city/port/rail/shipping prototypes, canonical country/region references, historical admin1 coverage, economy coverage and estimated economy fixtures, compact transport estimates, and existing commodity/economy integration fixtures. All non-reference entries are marked `REVIEW_REQUIRED`; no new numeric estimate or route claim is introduced.

## Validation results

Batch 3 validator: **PASS** with 0 errors. It checked exact source-record copying, candidate IDs, category totals, source digests, inventory paths, prototype/reference classification, promotion guards, manifest/corpus hashes, absence of absolute paths, and `historical_fact=false` / `runtime_authority=false` safety flags.

Deterministic regression: **PASS**. Two clean output directories produced byte-identical `batch3_source_gap_candidates.json`, `batch3_repository_inventory.json`, `batch3_deterministic_corpus.json`, and `batch3_manifest.json`, matching the committed outputs.

Aggregate QA: **PASS**. Batch 1 validator, Batch 2 validator, Batch 3 validator, Batch 2 determinism, and Batch 3 determinism all returned success; the report is [`batch3_qa_report.json`](../../../data/staging/1900/batch3_qa_report.json).

The first Batch 3 validator run caught two classification-rule false positives for `countries.json` and `regions.json`: both are `prototype_only` but are intentionally classified as `canonical_reference` in this inventory. The validator rule was corrected to allow that explicit reference class, and the complete QA suite was rerun successfully.
The resumed repository-wide unified validation was executed once, serially, with the bundled Python runtime on `PATH`. Godot import/script scan and the earlier static stages completed, but the existing `Formal world ten-year balance` stage returned 40 checks with 1 failure: the measured run was `246012934` microseconds against the repository's `180000000` microsecond CI safety threshold. The validation script stopped at that failure, so later unified stages were not claimed as run. This Batch 3 changeset contains no runtime or simulation changes; the failure is recorded as a baseline performance gate and was not bypassed or altered.

Resource-safety record: one full repository validation was run at a time; no process-level parallelism or thread pool was added. The only high-cost phase was that single Godot validation. Determinism tests used two small temporary output directories sequentially and removed them on exit. No large raster/geometry intermediate artifacts were created or retained. The downstream unified tests were not repeated after the performance-gate failure.

## Remaining gaps

The 52 candidates still need historical sources and dated crosswalks before any promotion. This is the correct stopping state for these records because deciding whether a modern prototype city, port, rail segment, or route existed and mattered on 1900-03-12 requires historical judgment. Future mechanical work can continue on source-locator templates, candidate review queues, and deterministic inventory expansion without asserting those facts.
