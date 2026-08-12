# world_map.countries

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Country map-node catalog, labels, geometry links, and display metadata.

- Path: `data/world_map/countries.json`
- Source files: `1`
- Record count (primary collection): `177`
- Documents: `1`
- Root type: `object`
- Primary record path: `countries[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `countries[]` | 177 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `countries` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"boundary_status":"<nested>","capital_city_id":"<nested>","data_code":"<nested>","diplomacy":"<nested>","display_name_zh":"<nested>","emblem_type":"<nested>"},{"boundary_stat... | OBSERVED |
| `countries[]` | `countries[]` | object / declared `—` | False | True | required-by-observation | 0 / 177 | null | — | — | — | [] | — | [{"boundary_status":"modern_natural_earth_prototype_geometry","capital_city_id":"paris","data_code":"FRA","diplomacy":"和平 · 与邻国保持外交关系","display_name_zh":"法兰西共和国","emblem_type":"... | OBSERVED |
| `countries[].boundary_status` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | ["modern_natural_earth_prototype_geometry"] | — | ["modern_natural_earth_prototype_geometry"] | OBSERVED |
| `countries[].capital_city_id` | `countries[]` | string / declared `—` | False | False | optional-by-observation | 176 / 177 | null | True | reference_candidate | — | ["paris"] | — | ["paris"] | OBSERVED |
| `countries[].data_code` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["AFG","AGO","ALB"] | OBSERVED |
| `countries[].diplomacy` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | ["公开外交资料待扩充","和平 · 与邻国保持外交关系"] | — | ["公开外交资料待扩充","和平 · 与邻国保持外交关系"] | OBSERVED |
| `countries[].display_name_zh` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["不丹","东帝汶","中华民国"] | OBSERVED + DECLARED |
| `countries[].emblem_type` | `countries[]` | string / declared `—` | False | False | optional-by-observation | 176 / 177 | null | True | — | — | ["french_tricolor_rf"] | — | ["french_tricolor_rf"] | OBSERVED |
| `countries[].formal_name_zh` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["不丹","东帝汶","中华民国"] | OBSERVED |
| `countries[].geometry_feature_ids` | `countries[]` | array / declared `—` | False | True | required-by-observation | 0 / 177 | null | — | reference_candidate | world_map.historical.cshapes_1900_snapshot, world_map.world_coastlines | [] | — | [["ne_admin0_1159320319"],["ne_admin0_1159320323"],["ne_admin0_1159320325"]] | OBSERVED |
| `countries[].geometry_feature_ids[]` | `countries[].geometry_feature_ids[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | True | reference_candidate | world_map.historical.cshapes_1900_snapshot, world_map.world_coastlines | [] | — | ["ne_admin0_1159320319","ne_admin0_1159320323","ne_admin0_1159320325"] | OBSERVED |
| `countries[].geometry_iso_a3` | `countries[]` | array / declared `—` | False | True | required-by-observation | 0 / 177 | [] | — | — | — | [] | — | [["AFG"],["AGO"],["ALB"]] | OBSERVED + DECLARED |
| `countries[].geometry_iso_a3[]` | `countries[].geometry_iso_a3[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | [] | True | — | — | [] | — | ["AFG","AGO","ALB"] | OBSERVED + DECLARED |
| `countries[].government_name` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | ["二元君主国","君主立宪制","帝国","政体资料待扩充","第三共和国","联邦共和国"] | — | ["二元君主国","君主立宪制","帝国"] | OBSERVED |
| `countries[].id` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | — | True | primary_candidate | — | [] | — | ["argentine_republic","austro_hungarian_empire","british_empire"] | OBSERVED + DECLARED |
| `countries[].label_anchor` | `countries[]` | array / declared `—` | False | True | required-by-observation | 0 / 177 | null | — | — | — | [] | — | [[-1.0369,7.7176],[-1.3639,12.673],[-10.0164,10.6185]] | OBSERVED |
| `countries[].label_anchor[]` | `countries[].label_anchor[]` | number / declared `—` | False | True | required-by-observation | 0 / 354 | null | True | — | — | [] | -102.2894–177.9754 | [-0.4377,-0.9544,-1.0369] | OBSERVED |
| `countries[].label_lon_lat` | `countries[]` | array / declared `—` | False | True | required-by-observation | 0 / 177 | null | — | — | — | [] | — | [[-1.0369,7.7176],[-1.3639,12.673],[-10.0164,10.6185]] | OBSERVED |
| `countries[].label_lon_lat[]` | `countries[].label_lon_lat[]` | number / declared `—` | False | True | required-by-observation | 0 / 354 | null | True | — | — | [] | -102.2894–177.9754 | [-0.4377,-0.9544,-1.0369] | OBSERVED |
| `countries[].label_priority` | `countries[]` | number / declared `integer` | False | True | required-by-observation | 0 / 177 | 0 | False | — | — | [] | 56.0–100.0 | [100,56,62] | OBSERVED + DECLARED |
| `countries[].legal_color` | `countries[]` | string / declared `—` | False | False | optional-by-observation | 176 / 177 | null | True | — | — | ["#6689a4"] | — | ["#6689a4"] | OBSERVED |
| `countries[].market_color` | `countries[]` | string / declared `—` | False | False | optional-by-observation | 176 / 177 | null | True | — | — | ["#5f9f8c"] | — | ["#5f9f8c"] | OBSERVED |
| `countries[].max_zoom` | `countries[]` | number / declared `number` | False | True | required-by-observation | 0 / 177 | 99.0 | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED + DECLARED |
| `countries[].min_zoom` | `countries[]` | number / declared `number` | False | True | required-by-observation | 0 / 177 | 0.0 | False | — | — | [] | 0.82–3.2 | [0.82,0.9,1.15] | OBSERVED + DECLARED |
| `countries[].name` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | — | True | — | — | [] | — | ["不丹","东帝汶","中华民国"] | OBSERVED + DECLARED |
| `countries[].native_name` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["Afghanistan","Albania","Algeria"] | OBSERVED |
| `countries[].native_name_source` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | ["natural_earth_name_en_fallback","v2_1_theme_override"] | — | ["natural_earth_name_en_fallback","v2_1_theme_override"] | OBSERVED |
| `countries[].neutral_land_color` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | #738077 | False | — | — | ["#6e7c71","#6e7d76","#6f806e","#737b70","#747a68","#777d68","#7b806d","#7b8178"] | — | ["#6e7c71","#6e7d76","#6f806e"] | OBSERVED + DECLARED |
| `countries[].object_level` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | ["country"] | — | ["country"] | OBSERVED |
| `countries[].population_color` | `countries[]` | string / declared `—` | False | False | optional-by-observation | 176 / 177 | null | True | — | — | ["#d48756"] | — | ["#d48756"] | OBSERVED |
| `countries[].source_iso_a3` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | [] | — | ["-99","AFG","AGO"] | OBSERVED |
| `countries[].stable_id` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | primary_candidate | — | [] | — | ["argentine_republic","austro_hungarian_empire","british_empire"] | OBSERVED + DECLARED |
| `countries[].theme_label_placeholder` | `countries[]` | boolean / declared `boolean` | False | True | required-by-observation | 0 / 177 | true | False | — | — | [] | — | [false,true] | OBSERVED + DECLARED |
| `countries[].visible_zoom_min` | `countries[]` | number / declared `number` | False | True | required-by-observation | 0 / 177 | 99.0 | False | — | — | [] | 0.82–3.2 | [0.82,0.9,1.15] | OBSERVED + DECLARED |
| `countries[].war_color` | `countries[]` | string / declared `—` | False | False | optional-by-observation | 176 / 177 | null | True | — | — | ["#537a93"] | — | ["#537a93"] | OBSERVED |
| `hierarchy` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["world/country"] | — | ["world/country"] | OBSERVED |
| `historical_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["世界边界采用现代 Natural Earth 几何。主要国家保留 1900 年主题名称，其余国家名称用于完整标签与交互覆盖，不代表完整历史疆域。"] | — | ["世界边界采用现代 Natural Earth 几何。主要国家保留 1900 年主题名称，其余国家名称用于完整标签与交互覆盖，不代表完整历史疆域。"] | OBSERVED |
| `name_coverage` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"display_name_zh":177,"formal_name_zh":177,"label_anchor":177,"native_name":177,"records":177}] | OBSERVED |
| `name_coverage.display_name_zh` | `document` | number / declared `string` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 177.0–177.0 | [177] | OBSERVED + DECLARED |
| `name_coverage.formal_name_zh` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 177.0–177.0 | [177] | OBSERVED |
| `name_coverage.label_anchor` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 177.0–177.0 | [177] | OBSERVED |
| `name_coverage.native_name` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 177.0–177.0 | [177] | OBSERVED |
| `name_coverage.records` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 177.0–177.0 | [177] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
