# world_map.world_coastlines

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

World coastline geometry features for the shared basemap.

- Path: `data/world_map/world_coastlines.json`
- Source files: `1`
- Record count (primary collection): `177`
- Documents: `1`
- Root type: `object`
- Primary record path: `features[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `audit.repaired_features[]` | 1 | 1 |
| `features[]` | 177 | 1 |
| `features[].polygons[]` | 287 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `audit` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"africa_feature_count":51,"fallback_id_count":5,"feature_count":177,"hole_count":1,"outer_ring_count":287,"repaired_features":["<nested>"]}] | OBSERVED |
| `audit.africa_feature_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 51.0–51.0 | [51] | OBSERVED |
| `audit.fallback_id_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 5.0–5.0 | [5] | OBSERVED |
| `audit.feature_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 177.0–177.0 | [177] | OBSERVED |
| `audit.hole_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `audit.outer_ring_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 287.0–287.0 | [287] | OBSERVED |
| `audit.repaired_features` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"iso_a3":"<nested>","name":"<nested>","reason":"<nested>","stable_id":"<nested>"}]] | OBSERVED |
| `audit.repaired_features[]` | `audit.repaired_features[]` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"iso_a3":"SDN","name":"Sudan","reason":["<nested>","<nested>"],"stable_id":"ne_admin0_1159321229"}] | OBSERVED |
| `audit.repaired_features[].iso_a3` | `audit.repaired_features[]` | string / declared `string` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["SDN"] | — | ["SDN"] | OBSERVED + DECLARED |
| `audit.repaired_features[].name` | `audit.repaired_features[]` | string / declared `string` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Sudan"] | — | ["Sudan"] | OBSERVED + DECLARED |
| `audit.repaired_features[].reason` | `audit.repaired_features[]` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["removed self-intersection spike at [33.9634, 9.4643]","removed Robinson-projection self-intersection spike at [23.887, 8.6197]"]] | OBSERVED |
| `audit.repaired_features[].reason[]` | `audit.repaired_features[].reason[]` | string / declared `—` | False | True | required-by-observation | 0 / 2 | null | True | — | — | ["removed Robinson-projection self-intersection spike at [23.887, 8.6197]","removed self-intersection spike at [33.9634, 9.4643]"] | — | ["removed Robinson-projection self-intersection spike at [23.887, 8.6197]","removed self-intersection spike at [33.9634, 9.4643]"] | OBSERVED |
| `audit.repaired_features[].stable_id` | `audit.repaired_features[]` | string / declared `string` | False | True | required-by-observation | 0 / 1 | null | True | primary_candidate | — | ["ne_admin0_1159321229"] | — | ["ne_admin0_1159321229"] | OBSERVED + DECLARED |
| `coordinate_system` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["WGS84 longitude/latitude"] | — | ["WGS84 longitude/latitude"] | OBSERVED |
| `features` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"continent":"<nested>","display_name_zh":"<nested>","fallback_code_used":"<nested>","geometry_type":"<nested>","hole_count":"<nested>","id":"<nested>"},{"continent":"<nested>... | OBSERVED + DECLARED |
| `features[]` | `features[]` | object / declared `array` | False | True | required-by-observation | 0 / 177 | [] | — | — | — | [] | — | [{"continent":"Africa","display_name_zh":"中非共和国","fallback_code_used":false,"geometry_type":"Polygon","hole_count":0,"id":"ne_admin0_1159320463"},{"continent":"Africa","display_... | OBSERVED + DECLARED |
| `features[].continent` | `features[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | — | False | — | — | ["Africa","Antarctica","Asia","Europe","North America","Oceania","Seven seas (open ocean)","South America"] | — | ["Africa","Antarctica","Asia"] | OBSERVED + DECLARED |
| `features[].display_name_zh` | `features[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["不丹","东帝汶","中华人民共和国"] | OBSERVED + DECLARED |
| `features[].fallback_code_used` | `features[]` | boolean / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | [] | — | [false,true] | OBSERVED |
| `features[].geometry_type` | `features[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | ["MultiPolygon","Polygon"] | — | ["MultiPolygon","Polygon"] | OBSERVED |
| `features[].hole_count` | `features[]` | number / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | [] | 0.0–1.0 | [0,1] | OBSERVED |
| `features[].id` | `features[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | primary_candidate | — | [] | — | ["ne_admin0_1159320319","ne_admin0_1159320323","ne_admin0_1159320325"] | OBSERVED + DECLARED |
| `features[].iso_a3` | `features[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["AFG","AGO","ALB"] | OBSERVED + DECLARED |
| `features[].label_rank` | `features[]` | number / declared `integer` | False | True | required-by-observation | 0 / 177 | 9 | False | — | — | [] | 2.0–7.0 | [2,3,4] | OBSERVED + DECLARED |
| `features[].name` | `features[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | — | — | [] | — | ["Afghanistan","Albania","Algeria"] | OBSERVED + DECLARED |
| `features[].outer_ring_count` | `features[]` | number / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | [] | 1.0–30.0 | [1,10,13] | OBSERVED |
| `features[].polygons` | `features[]` | array / declared `array` | False | True | required-by-observation | 0 / 177 | [] | — | — | — | [] | — | [[{"holes":"<nested>","outer":"<nested>"},{"holes":"<nested>","outer":"<nested>"},{"holes":"<nested>","outer":"<nested>"},{"holes":"<nested>","outer":"<nested>"}],[{"holes":"<ne... | OBSERVED + DECLARED |
| `features[].polygons[]` | `features[].polygons[]` | object / declared `array` | False | True | required-by-observation | 0 / 287 | [] | — | — | — | [] | — | [{"holes":["<nested>"],"outer":["<nested>","<nested>","<nested>","<nested>"]},{"holes":[],"outer":["<nested>","<nested>","<nested>","<nested>"]}] | OBSERVED + DECLARED |
| `features[].polygons[].holes` | `features[].polygons[]` | array / declared `—` | False | True | required-by-observation | 0 / 287 | [] | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"]],[]] | OBSERVED + DECLARED |
| `features[].polygons[].holes[]` | `features[].polygons[].holes[]` | array / declared `—` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED + DECLARED |
| `features[].polygons[].holes[][]` | `features[].polygons[].holes[][]` | array / declared `—` | False | True | required-by-observation | 0 / 12 | [] | — | — | — | [] | — | [[26.9993,-29.876],[27.5325,-29.2427],[27.7494,-30.6451]] | OBSERVED + DECLARED |
| `features[].polygons[].holes[][][]` | `features[].polygons[].holes[][][]` | number / declared `—` | False | True | required-by-observation | 0 / 24 | [] | False | — | — | [] | -30.6451–29.3252 | [-28.6475,-28.8515,-28.9556] | OBSERVED + DECLARED |
| `features[].polygons[].outer` | `features[].polygons[]` | array / declared `—` | False | True | required-by-observation | 0 / 287 | null | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED + DECLARED |
| `features[].polygons[].outer[]` | `features[].polygons[].outer[]` | array / declared `—` | False | True | required-by-observation | 0 / 10585 | null | — | — | — | [] | — | [[-0.0498,10.7069],[-0.1275,35.8887],[-0.2286,-71.6377]] | OBSERVED + DECLARED |
| `features[].polygons[].outer[][]` | `features[].polygons[].outer[][]` | number / declared `—` | False | True | required-by-observation | 0 / 21170 | null | False | — | — | [] | -180.0–180.0 | [-0.0498,-0.0572,-0.0581] | OBSERVED + DECLARED |
| `features[].repair_notes` | `features[]` | array / declared `—` | False | True | required-by-observation | 0 / 177 | null | — | — | — | [] | — | [["removed self-intersection spike at [33.9634, 9.4643]","removed Robinson-projection self-intersection spike at [23.887, 8.6197]"],[]] | OBSERVED |
| `features[].repair_notes[]` | `features[].repair_notes[]` | string / declared `—` | False | True | required-by-observation | 0 / 2 | null | True | — | — | ["removed Robinson-projection self-intersection spike at [23.887, 8.6197]","removed self-intersection spike at [33.9634, 9.4643]"] | — | ["removed Robinson-projection self-intersection spike at [23.887, 8.6197]","removed self-intersection spike at [33.9634, 9.4643]"] | OBSERVED |
| `features[].rings` | `features[]` | array / declared `—` | False | True | required-by-observation | 0 / 177 | null | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<n... | OBSERVED |
| `features[].rings[]` | `features[].rings[]` | array / declared `—` | False | True | required-by-observation | 0 / 287 | null | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED |
| `features[].rings[][]` | `features[].rings[][]` | array / declared `—` | False | True | required-by-observation | 0 / 10585 | null | — | — | — | [] | — | [[-0.0498,10.7069],[-0.1275,35.8887],[-0.2286,-71.6377]] | OBSERVED |
| `features[].rings[][][]` | `features[].rings[][][]` | number / declared `—` | False | True | required-by-observation | 0 / 21170 | null | False | — | — | [] | -180.0–180.0 | [-0.0498,-0.0572,-0.0581] | OBSERVED |
| `features[].source_iso_a3` | `features[]` | string / declared `—` | False | True | required-by-observation | 0 / 177 | null | False | — | — | [] | — | ["-99","AFG","AGO"] | OBSERVED |
| `features[].stable_id` | `features[]` | string / declared `string` | False | True | required-by-observation | 0 / 177 | null | True | primary_candidate | — | [] | — | ["ne_admin0_1159320319","ne_admin0_1159320323","ne_admin0_1159320325"] | OBSERVED + DECLARED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 3.0–3.0 | [3] | OBSERVED |
| `source` | `document` | object / declared `string` | False | True | required-by-observation | 0 / 1 | 机构 | — | — | — | [] | — | [{"dataset":"Natural Earth Vector 1:110m Admin 0 Countries","license":"Public domain","processing":"All Polygon and MultiPolygon exteriors retained; true interior rings retained... | OBSERVED + DECLARED |
| `source.dataset` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Natural Earth Vector 1:110m Admin 0 Countries"] | — | ["Natural Earth Vector 1:110m Admin 0 Countries"] | OBSERVED |
| `source.license` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Public domain"] | — | ["Public domain"] | OBSERVED |
| `source.processing` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["All Polygon and MultiPolygon exteriors retained; true interior rings retained separately; coordinates rounded to four decimals; self-intersection spikes repaired without drawi... | — | ["All Polygon and MultiPolygon exteriors retained; true interior rings retained separately; coordinates rounded to four decimals; self-intersection spikes repaired without drawi... | OBSERVED |
| `source.prototype_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["本轮仅用于视觉原型；政治边界仅为视觉原型近似，采用现代 Natural Earth 数据，不作为最终历史地图。"] | — | ["本轮仅用于视觉原型；政治边界仅为视觉原型近似，采用现代 Natural Earth 数据，不作为最终历史地图。"] | OBSERVED |
| `source.terms_url` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["https://www.naturalearthdata.com/about/terms-of-use/"] | — | ["https://www.naturalearthdata.com/about/terms-of-use/"] | OBSERVED |
| `source.upstream_url` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson"] | — | ["https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
