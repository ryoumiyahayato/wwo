# WWO 1900 World Data Source Pack — Batch 2

## Scope

Batch 2 mechanically expands the isolated staging layer from the repository's existing `data/world_map/historical/political_units_1900.json`. It copies dated political-unit identity, relationship, capital, geometry-provider, flag-reference, and data-quality fields without adding external facts, modern geometry, gameplay values, or runtime integration.

- Snapshot: `1900-03-12`
- Input units: 151
- Input SHA-256: `d62a8d9c566c1dfea9d57fc197a6fa3606c6be259782a582050aeaffa002c5f9`
- Explicit controller links: 96
- Snapshot-active units: 151
- Exact current-country ID matches: 5
- Explicit `NO_MATCH` units: 146
- Runtime-authoritative data changed: **NO**
- vNext/core gameplay changed: **NO**
- Modern geometry fallback: **NO**

Canonical resolution is intentionally `EXACT_ID_ONLY`: a historical unit receives a canonical entity ID only when its existing unit ID exactly equals an existing current country ID. The other 146 units remain explicit `NO_MATCH`; no name-based, territorial, or political inference is performed.

## Actual artifacts

- [`political_unit_records_1900.json`](../../../data/staging/1900/political_unit_records_1900.json): 151 unit records and 96 relationship records.
- [`batch2_political_unit_records.schema.json`](../../../data/staging/1900/batch2_political_unit_records.schema.json): machine-readable contract for the Batch 2 payload.
- [`batch2_manifest.json`](../../../data/staging/1900/batch2_manifest.json): input/output hashes, counts, and protected-scope declarations.
- [`batch2_deterministic_corpus.json`](../../../data/staging/1900/batch2_deterministic_corpus.json): expected input/output digest and summary corpus.
- [`build_1900_source_pack_batch2.py`](../../../tools/historical_data/build_1900_source_pack_batch2.py): deterministic generator.
- [`validate_1900_source_pack_batch2.py`](../../../tools/historical_data/validate_1900_source_pack_batch2.py): independent source-to-staging and manifest validator.
- [`test_1900_source_pack_batch2_determinism.py`](../../../tools/historical_data/test_1900_source_pack_batch2_determinism.py): two-clean-directory deterministic regression test.

Every generated record is `STAGED_NOT_RUNTIME`, has `runtime_authority: false`, points to the existing repository source path, and retains the source interval. Every controller ID resolves to another unit in the same dated snapshot; unresolved controller IDs: zero.

## Validation results

Batch 2 validator: **PASS** (`0` errors). It independently checked JSON/schema contract fields, exact source-unit coverage, duplicate IDs, date intervals, snapshot activity, capitals, geometry metadata, controller references, relationship parity, exact-ID matching, provenance, runtime guards, and SHA-256 manifest/corpus consistency.

Reported metrics:

- `source_units`: 151
- `staged_units`: 151
- `staged_relationships`: 96
- canonical matches: `EXACT_ID=5`, `NO_MATCH=146`
- status counts: sovereign 53, dependency 78, protectorate 12, occupied 3, contested 2, colony 1, condominium 1, dominion 1
- record SHA-256: `77f15d349ff11a0d4753aa80851d7cb9bd8cc69a23ab84f41280836df2338771`
- manifest SHA-256: `294df7a82d5d131f905c833036bc65515dfa268029b693e4be180fae95dbb0a7`
- deterministic corpus SHA-256: `fbff8d95182b5e3b137704202c71e1d9314a470aef2f30e7365c2710b0c7d614`

Deterministic regression: **PASS**. The generator was run twice in clean temporary directories; `political_unit_records_1900.json`, `batch2_manifest.json`, and `batch2_deterministic_corpus.json` matched byte-for-byte and matched the committed outputs.

## Remaining gaps and next safe work

The exact-ID-only result exposes the remaining historical-unit-to-current-country crosswalk gap without hiding it. Further mapping requires historical judgment for names, successor states, composite territories, and legal/control distinctions, so it remains in the existing backlog rather than being inferred here.

The next mechanically safe candidates are validator integration across Batch 1 and Batch 2, source-file inventory digest checks, and additional deterministic coverage for existing city/port/rail/route records. New historical values should remain out of staging until they have a source locator and an explicit review decision.
