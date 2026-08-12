# world_map.historical.historical_admin1_1900

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

1900 country-to-administrative-unit reference used by the historical admin view.

- Path: `data/world_map/historical/historical_admin1_1900.json`
- Source files: `1`
- Record count (primary collection): `15`
- Documents: `1`
- Root type: `object`
- Primary record path: `countries[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `countries[]` | 15 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `countries` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"entity_id":"<nested>","geometry_status":"<nested>","level_name_zh":"<nested>","source_basis":"<nested>","units":"<nested>"},{"entity_id":"<nested>","geometry_status":"<neste... | OBSERVED + DECLARED |
| `countries[]` | `countries[]` | object / declared `array` | False | True | required-by-observation | 0 / 15 | [] | — | — | — | [] | — | [{"entity_id":"austria_hungary","geometry_status":"historical_names_verified_geometry_digitization_required","level_name_zh":"帝国两部分、王冠领与共管领地","source_basis":"1867年二元体制及1900年王冠领体... | OBSERVED + DECLARED |
| `countries[].entity_id` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 15 | — | True | reference_candidate | world_map.historical_political_entities_1900 | ["austria_hungary","british_isles_1900","cshapes_gw_750","dominion_of_canada","empire_of_japan","german_empire","grand_duchy_of_luxembourg","kingdom_of_belgium","kingdom_of_ital... | — | ["austria_hungary","british_isles_1900","cshapes_gw_750"] | OBSERVED + DECLARED |
| `countries[].geometry_status` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 15 | — | False | — | — | ["historical_names_verified_geometry_digitization_required","historical_names_verified_historical_geometry_available_from_census_sources","historical_names_verified_modern_cross... | — | ["historical_names_verified_geometry_digitization_required","historical_names_verified_historical_geometry_available_from_census_sources","historical_names_verified_modern_cross... | OBSERVED + DECLARED |
| `countries[].level_name_zh` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 15 | 一级行政区 | False | — | — | ["区","州与领地","帝国两部分、王冠领与共管领地","府县与北海道","总督区、边疆区与直属省群","构成王国与行政县体系","直属省、首席专员省与土邦体系","省","省与边疆将军辖区","省与领地","维拉耶特与独立桑贾克","邦国与帝国直辖领"] | — | ["区","州与领地","帝国两部分、王冠领与共管领地"] | OBSERVED + DECLARED |
| `countries[].source_basis` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 15 | — | True | — | — | ["1833省制在1900年的延续；加那利群岛尚未分省","1867年二元体制及1900年王冠领体系","1900年九省制，布拉班特尚未拆分","1900年人口普查：45州及领地","1900年加拿大自治领省区体系","1900年十一省制，弗莱福兰尚不存在","1900年英属印度行政体系；不使用1911年后的省名","1901人口普查前后的英格兰、威尔... | — | ["1833省制在1900年的延续；加那利群岛尚未分省","1867年二元体制及1900年王冠领体系","1900年九省制，布拉班特尚未拆分"] | OBSERVED + DECLARED |
| `countries[].units` | `countries[]` | array / declared `array` | False | True | required-by-observation | 0 / 15 | [] | — | — | — | [] | — | [["下奥地利","上奥地利","萨尔茨堡","施蒂里亚"],["东京府","京都府","大阪府","神奈川县"],["伊斯坦布尔","埃迪尔内维拉耶特","萨洛尼卡维拉耶特","科索沃维拉耶特"]] | OBSERVED + DECLARED |
| `countries[].units[]` | `countries[].units[]` | string / declared `array` | False | True | required-by-observation | 0 / 327 | [] | False | — | — | [] | — | ["三重县","上奥地利","上艾瑟尔省"] | OBSERVED + DECLARED |
| `policy` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"missing_geometry_must_not_be_invented":true,"modern_admin_names_forbidden":true,"modern_geometry_may_only_be_used_with_explicit_crosswalk":true}] | OBSERVED + DECLARED |
| `policy.missing_geometry_must_not_be_invented` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.modern_admin_names_forbidden` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.modern_geometry_may_only_be_used_with_explicit_crosswalk` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `snapshot_date` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["1900-03-12"] | — | ["1900-03-12"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
