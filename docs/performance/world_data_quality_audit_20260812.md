# WWO WORLD DATA QUALITY AUDIT — BATCH 4

Read-only structural QA for city-detail references, runtime metadata and stable IDs.

- Result: **PASS**; errors: **0**; warnings: **0**
- Authoritative world-map JSON modified: **NO**

## Metrics

| Metric | Value |
|---|---:|
| index_country_entries | 144 |
| referenced_shards | 156 |
| actual_shards | 156 |
| index_record_count | 88927 |
| shard_record_count | 88927 |
| duplicate_city_ids | 0 |
| same_shard_duplicate_ids | 0 |
| cross_shard_duplicate_ids | 0 |
| city_stable_id_records_checked | 88927 |
| invalid_city_coordinates | 0 |
| count_mismatches | 0 |
| invalid_bounds | 0 |
| france_shard_count | 13 |
| france_shard_record_count | 36871 |
| optional_orphan_shards | 0 |
| required_orphan_shards | 0 |
| runtime_file_count | 16 |
| runtime_missing | [] |
| runtime_bad_schema | [] |
| runtime_schema_versions | {"1": 2, "2": 5, "3": 6, "4": 3} |
| runtime_missing_prototype_flag | [] |
| runtime_root_types | {"dict": 16} |
| runtime_supporting_file_count | 2 |
| runtime_supporting_missing | [] |
| runtime_supporting_bad_schema | [] |
| runtime_supporting_schema_versions | {"1": 2} |
| runtime_supporting_root_types | {"dict": 2} |
| stable_id_records_checked | 244 |
| stable_id_missing | 0 |
| stable_id_duplicate_arrays | 0 |

## Issues

| Severity | Code | Path | Message |
|---|---|---|---|
| — | — | — | No issues found. |

## Mechanically safe backlog

| ID | Status | Item | Revisit trigger |
|---|---|---|---|
| B4-01 | no_action_needed | Preserve unique stable IDs across city-detail shards. | `duplicate_city_ids > 0` |
| B4-02 | no_action_needed | Keep shard declared counts and index counts synchronized. | `count_mismatches > 0 or CITY_INDEX_COUNT issue` |
| B4-03 | no_action_needed | Reject non-finite or out-of-range city coordinates before shard generation. | `invalid_city_coordinates > 0` |
| B4-04 | no_action_needed | Keep all runtime-loader documents at schema_version 1 until an explicit migration exists. | `runtime_bad_schema is non-empty` |
| B4-05 | review_only | Review any runtime document that lacks prototype_only=true before promoting it to authoritative runtime input. | `runtime_missing_prototype_flag is non-empty` |

- Any future source-data change should rerun the Batch 2 manifest and Batch 3 corpus before review.
- This audit intentionally does not infer historical correctness or gameplay balance.
