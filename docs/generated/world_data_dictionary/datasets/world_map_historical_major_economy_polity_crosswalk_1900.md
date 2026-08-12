# world_map.historical.major_economy_polity_crosswalk_1900

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Crosswalk between major economy entities and 1900 political units.

- Path: `data/world_map/historical/major_economy_polity_crosswalk_1900.json`
- Source files: `1`
- Record count (primary collection): `2`
- Documents: `1`
- Root type: `object`
- Primary record path: `records[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `records[]` | 2 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `policy` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"all_crosswalk_exceptions_must_be_explicit":true,"economy_count_is_not_world_polity_count":true,"one_economy_may_cover_multiple_map_units":true}] | OBSERVED |
| `policy.all_crosswalk_exceptions_must_be_explicit` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.economy_count_is_not_world_polity_count` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.one_economy_may_cover_multiple_map_units` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `records` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"economy_entity_id":"<nested>","mapping_mode":"<nested>","polity_ids":"<nested>","reason_zh":"<nested>"},{"economy_entity_id":"<nested>","mapping_mode":"<nested>","polity_ids... | OBSERVED + DECLARED |
| `records[]` | `records[]` | object / declared `array` | False | True | required-by-observation | 0 / 2 | [] | — | — | — | [] | — | [{"economy_entity_id":"australia_colonies_1900","mapping_mode":"historical_economic_aggregate","polity_ids":["<nested>","<nested>","<nested>","<nested>"],"reason_zh":"1900年澳大利亚联... | OBSERVED + DECLARED |
| `records[].economy_entity_id` | `records[]` | string / declared `string` | False | True | required-by-observation | 0 / 2 | — | True | reference_candidate | — | ["australia_colonies_1900","kingdom_of_luxembourg"] | — | ["australia_colonies_1900","kingdom_of_luxembourg"] | OBSERVED + DECLARED |
| `records[].mapping_mode` | `records[]` | string / declared `—` | False | True | required-by-observation | 0 / 2 | null | True | — | — | ["historical_economic_aggregate","historical_name_alias"] | — | ["historical_economic_aggregate","historical_name_alias"] | OBSERVED |
| `records[].polity_ids` | `records[]` | array / declared `—` | False | True | required-by-observation | 0 / 2 | [] | — | reference_candidate | world_map.historical.political_units_1900 | [] | — | [["cshapes_gw_901","cshapes_gw_902","cshapes_gw_903","cshapes_gw_904"],["grand_duchy_of_luxembourg"]] | OBSERVED + DECLARED |
| `records[].polity_ids[]` | `records[].polity_ids[]` | string / declared `—` | False | True | required-by-observation | 0 / 7 | [] | True | reference_candidate | world_map.historical.political_units_1900 | ["cshapes_gw_901","cshapes_gw_902","cshapes_gw_903","cshapes_gw_904","cshapes_gw_905","cshapes_gw_906","grand_duchy_of_luxembourg"] | — | ["cshapes_gw_901","cshapes_gw_902","cshapes_gw_903"] | OBSERVED + DECLARED |
| `records[].reason_zh` | `records[]` | string / declared `—` | False | True | required-by-observation | 0 / 2 | null | True | — | — | ["1900年澳大利亚联邦尚未成立；高细节经济记录聚合六个自治殖民地，地图仍分别保留六个政治单元。","经济目录旧名与1900政治地图中的卢森堡大公国规范ID不同。"] | — | ["1900年澳大利亚联邦尚未成立；高细节经济记录聚合六个自治殖民地，地图仍分别保留六个政治单元。","经济目录旧名与1900政治地图中的卢森堡大公国规范ID不同。"] | OBSERVED |
| `schema_id` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | — | — | ["major_economy_polity_crosswalk_1900_v1"] | — | ["major_economy_polity_crosswalk_1900_v1"] | OBSERVED + DECLARED |
| `snapshot_date` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["1900-03-12"] | — | ["1900-03-12"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
