# world_map.regions

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Map regions and administrative-unit geometry/catalog data.

- Path: `data/world_map/regions.json`
- Source files: `1`
- Record count (primary collection): `9`
- Documents: `1`
- Root type: `object`
- Primary record path: `regions[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `administrative_units[]` | 98 | 1 |
| `administrative_units[].geometry[]` | 110 | 1 |
| `regions[]` | 9 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `administrative_geometry_notice` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["省界采用 Natural Earth 1:10m 现代法国省级边界，作为 1900 主题的可靠简化占位；塞纳省等历史差异尚未完整录入。"] | — | ["省界采用 Natural Earth 1:10m 现代法国省级边界，作为 1900 主题的可靠简化占位；塞纳省等历史差异尚未完整录入。"] | OBSERVED |
| `administrative_units` | `document` | array / declared `array` | False | True | False | False | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"administrative_level":"<nested>","display_name_zh":"<nested>","geometry":"<nested>","geometry_source":"<nested>","id":"<nested>","jurisdiction_name":"<nested>"},{"administra... | OBSERVED + DECLARED |
| `administrative_units[]` | `administrative_units[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | — | — | — | [] | — | [{"administrative_level":"arrondissement","display_name_zh":"里尔区","geometry":["<nested>"],"geometry_source":"simplified local review placeholder","id":"arrondissement_lille","ju... | OBSERVED |
| `administrative_units[].administrative_level` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | ["arrondissement","commune","departement"] | — | ["arrondissement","commune","departement"] | OBSERVED |
| `administrative_units[].display_name_zh` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | True | — | — | [] | — | ["上加龙省","上卢瓦尔省","上塞纳省"] | OBSERVED |
| `administrative_units[].geometry` | `administrative_units[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | — | — | — | [] | — | [[{"holes":"<nested>","outer":"<nested>"},{"holes":"<nested>","outer":"<nested>"},{"holes":"<nested>","outer":"<nested>"}],[{"holes":"<nested>","outer":"<nested>"},{"holes":"<ne... | OBSERVED |
| `administrative_units[].geometry[]` | `administrative_units[].geometry[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 110 | null | — | — | — | [] | — | [{"holes":["<nested>","<nested>"],"outer":["<nested>","<nested>","<nested>","<nested>"]},{"holes":["<nested>"],"outer":["<nested>","<nested>","<nested>","<nested>"]},{"holes":[]... | OBSERVED |
| `administrative_units[].geometry[].holes` | `administrative_units[].geometry[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 110 | null | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<nested>"]],[["<nested>","<nested>","<nested>","<nested>"]],[]] | OBSERVED |
| `administrative_units[].geometry[].holes[]` | `administrative_units[].geometry[].holes[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 5 | null | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED |
| `administrative_units[].geometry[].holes[][]` | `administrative_units[].geometry[].holes[][]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 79 | null | — | — | — | [] | — | [[-0.0635,43.3673],[-0.064,43.3592],[-0.0645,43.3728]] | OBSERVED |
| `administrative_units[].geometry[].holes[][][]` | `administrative_units[].geometry[].holes[][][]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 158 | null | False | — | — | [] | -0.1386–50.1739 | [-0.0635,-0.064,-0.0645] | OBSERVED |
| `administrative_units[].geometry[].outer` | `administrative_units[].geometry[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 110 | null | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED |
| `administrative_units[].geometry[].outer[]` | `administrative_units[].geometry[].outer[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 21873 | null | — | — | — | [] | — | [[-0.0,45.1575],[-0.0003,43.9149],[-0.0003,44.4202]] | OBSERVED |
| `administrative_units[].geometry[].outer[][]` | `administrative_units[].geometry[].outer[][]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 43746 | null | False | — | — | [] | -5.1328–51.0875 | [-0.0,-0.0003,-0.0012] | OBSERVED |
| `administrative_units[].geometry_source` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | ["Natural Earth 1:10m Admin 1 modern department boundary; reliable simplified placeholder for the 1900 theme","simplified local review placeholder"] | — | ["Natural Earth 1:10m Admin 1 modern department boundary; reliable simplified placeholder for the 1900 theme","simplified local review placeholder"] | OBSERVED |
| `administrative_units[].historical_context` | `administrative_units[]` | string / declared `—` | False | False | False | False | optional-by-observation | 97 / 98 | null | True | — | — | ["巴黎相关行政区占位；1900 年塞纳省制度边界尚未完整录入"] | — | ["巴黎相关行政区占位；1900 年塞纳省制度边界尚未完整录入"] | OBSERVED |
| `administrative_units[].id` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | True | primary_candidate | — | [] | — | ["arrondissement_lille","commune_lille","departement_fr_01"] | OBSERVED |
| `administrative_units[].jurisdiction_name` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | True | — | — | [] | — | ["上加龙省","上卢瓦尔省","上塞纳省"] | OBSERVED |
| `administrative_units[].label_anchor` | `administrative_units[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | — | — | — | [] | — | [[-0.2887,49.0601],[-0.3008,46.5681],[-0.5155,44.7339]] | OBSERVED |
| `administrative_units[].label_anchor[]` | `administrative_units[].label_anchor[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 196 | null | False | — | — | [] | -3.9264–50.64 | [-0.2887,-0.3008,-0.5155] | OBSERVED |
| `administrative_units[].label_priority` | `administrative_units[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | [] | 45.0–96.0 | [45,78,82] | OBSERVED |
| `administrative_units[].max_zoom` | `administrative_units[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED |
| `administrative_units[].min_zoom` | `administrative_units[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | [] | 8.4–20.0 | [12.5,17.0,20.0] | OBSERVED |
| `administrative_units[].modern_region_name` | `administrative_units[]` | string / declared `—` | False | False | False | False | optional-by-observation | 2 / 98 | null | False | — | — | ["Auvergne-Rhône-Alpes","Bourgogne-Franche-Comté","Bretagne","Centre-Val de Loire","Corse","Grand Est","Hauts-de-France","Normandie","Nouvelle-Aquitaine","Occitanie","Pays de la... | — | ["Auvergne-Rhône-Alpes","Bourgogne-Franche-Comté","Bretagne"] | OBSERVED |
| `administrative_units[].name` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | True | — | — | [] | — | ["上加龙省","上卢瓦尔省","上塞纳省"] | OBSERVED |
| `administrative_units[].native_name` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | True | — | — | [] | — | ["Ain","Aisne","Allier"] | OBSERVED |
| `administrative_units[].object_level` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | ["administrative_unit"] | — | ["administrative_unit"] | OBSERVED |
| `administrative_units[].parent_country_id` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.countries | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `administrative_units[].parent_id` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | reference_candidate | — | ["arrondissement_lille","country_fra","departement_nord"] | — | ["arrondissement_lille","country_fra","departement_nord"] | OBSERVED |
| `administrative_units[].region_kind` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | ["historical_administrative_unit"] | — | ["historical_administrative_unit"] | OBSERVED |
| `administrative_units[].repair_notes` | `administrative_units[]` | array / declared `—` | False | False | False | False | optional-by-observation | 2 / 98 | null | — | — | — | [] | — | [[]] | OBSERVED |
| `administrative_units[].source_code` | `administrative_units[]` | string / declared `—` | False | False | False | False | optional-by-observation | 2 / 98 | null | True | — | — | [] | — | ["FR-01","FR-02","FR-03"] | OBSERVED |
| `administrative_units[].stable_id` | `administrative_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | True | primary_candidate | — | [] | — | ["arrondissement_lille","commune_lille","departement_fr_01"] | OBSERVED |
| `administrative_units[].visible_zoom_min` | `administrative_units[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 98 | null | False | — | — | [] | 8.4–20.0 | [12.5,17.0,20.0] | OBSERVED |
| `coverage` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"macro_region_count":9,"metropolitan_department_count":96,"unassigned_department_codes":[]}] | OBSERVED |
| `coverage.macro_region_count` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 9.0–9.0 | [9] | OBSERVED |
| `coverage.metropolitan_department_count` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 96.0–96.0 | [96] | OBSERVED |
| `coverage.unassigned_department_codes` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[]] | OBSERVED |
| `focus_country_id` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | reference_candidate | — | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `macro_region_notice` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["游戏宏观地区由行政单位组合形成，不等同于历史行政区划。"] | — | ["游戏宏观地区由行政单位组合形成，不等同于历史行政区划。"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `regions` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"administrative_level":"<nested>","administrative_unit_ids":"<nested>","display_name_zh":"<nested>","geometry_composition":"<nested>","id":"<nested>","institution_ids":"<nest... | OBSERVED |
| `regions[]` | `regions[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | — | — | [] | — | [{"administrative_level":"gameplay_macro","administrative_unit_ids":["<nested>","<nested>","<nested>","<nested>"],"display_name_zh":"中央高原","geometry_composition":"runtime union ... | OBSERVED |
| `regions[].administrative_level` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | ["gameplay_macro"] | — | ["gameplay_macro"] | OBSERVED |
| `regions[].administrative_unit_ids` | `regions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | reference_candidate | — | [] | — | [["departement_fr_06","departement_fr_04","departement_fr_05","departement_fr_65"],["departement_fr_08","departement_fr_55","departement_fr_54","departement_fr_57"],["departemen... | OBSERVED |
| `regions[].administrative_unit_ids[]` | `regions[].administrative_unit_ids[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 96 | null | True | reference_candidate | — | [] | — | ["departement_fr_01","departement_fr_02","departement_fr_03"] | OBSERVED |
| `regions[].display_name_zh` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["中央高原","北部工业带","卢瓦尔河谷","地中海沿岸","巴黎盆地","布列塔尼","罗讷河谷","诺曼底","阿基坦"] | — | ["中央高原","北部工业带","卢瓦尔河谷"] | OBSERVED |
| `regions[].geometry_composition` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | ["runtime union of referenced administrative unit polygons"] | — | ["runtime union of referenced administrative unit polygons"] | OBSERVED |
| `regions[].id` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | primary_candidate | — | ["aquitaine","brittany","loire_valley","massif_central","mediterranean_coast","normandy","northern_industrial_belt","paris_basin","rhone_valley"] | — | ["aquitaine","brittany","loire_valley"] | OBSERVED |
| `regions[].institution_ids` | `regions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.institutions | [] | — | [["marseille_port_authority"],["national_assembly"],["prefecture_nord","labor_inspectorate_nord","sous_prefecture_lille","mairie_lille"]] | OBSERVED |
| `regions[].institution_ids[]` | `regions[].institution_ids[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.institutions | ["labor_inspectorate_nord","mairie_lille","marseille_port_authority","national_assembly","prefecture_nord","prefecture_seine_inferieure","sous_prefecture_lille"] | — | ["labor_inspectorate_nord","mairie_lille","marseille_port_authority"] | OBSERVED |
| `regions[].label_anchor` | `regions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | — | — | [] | — | [[-0.1,44.25],[-3.15,48.05],[0.0,46.9]] | OBSERVED |
| `regions[].label_anchor[]` | `regions[].label_anchor[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 18 | null | False | — | — | [] | -3.15–50.35 | [-0.1,-3.15,0.0] | OBSERVED |
| `regions[].label_lon_lat` | `regions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | — | — | [] | — | [[-0.1,44.25],[-3.15,48.05],[0.0,46.9]] | OBSERVED |
| `regions[].label_lon_lat[]` | `regions[].label_lon_lat[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 18 | null | False | — | — | [] | -3.15–50.35 | [-0.1,-3.15,0.0] | OBSERVED |
| `regions[].label_priority` | `regions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | [] | 72.0–100.0 | [100,72,74] | OBSERVED |
| `regions[].legal_color` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["#68879f","#6b89a0","#6f8da6","#708fa7","#7191a8","#7394ad","#748e9f","#7799b1","#7897ad"] | — | ["#68879f","#6b89a0","#6f8da6"] | OBSERVED |
| `regions[].market` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["农业与港口行业观察","地中海港口行业观察","塞纳河口行业观察","山地农业行业观察","机械与纺织行业观察","沿海食品行业观察","煤炭与机械行业观察","葡萄酒与农业行业观察","首都综合市场"] | — | ["农业与港口行业观察","地中海港口行业观察","塞纳河口行业观察"] | OBSERVED |
| `regions[].market_color` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["#4f9c82","#5b958d","#60917e","#639082","#65927d","#6e9472","#748c72","#bc8353","#c0834e"] | — | ["#4f9c82","#5b958d","#60917e"] | OBSERVED |
| `regions[].market_state` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | ["静态原型占位"] | — | ["静态原型占位"] | OBSERVED |
| `regions[].max_zoom` | `regions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED |
| `regions[].min_zoom` | `regions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | [] | 6.21–6.21 | [6.21] | OBSERVED |
| `regions[].name` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["中央高原","北部工业带","卢瓦尔河谷","地中海沿岸","巴黎盆地","布列塔尼","罗讷河谷","诺曼底","阿基坦"] | — | ["中央高原","北部工业带","卢瓦尔河谷"] | OBSERVED |
| `regions[].native_name` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["Aquitaine","Bassin parisien","Bretagne","Ceinture industrielle du Nord","Littoral méditerranéen","Massif central","Normandie","Val de Loire","Vallée du Rhône"] | — | ["Aquitaine","Bassin parisien","Bretagne"] | OBSERVED |
| `regions[].object_level` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | ["region"] | — | ["region"] | OBSERVED |
| `regions[].parent_country_id` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.countries | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `regions[].population` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | ["中等","极高","较低","较高","高"] | — | ["中等","极高","较低"] | OBSERVED |
| `regions[].population_color` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | ["#8f9167","#9a8d62","#a9895e","#af8a5d","#b98a5a","#c47e54","#c58053","#d7794b","#dc7449"] | — | ["#8f9167","#9a8d62","#a9895e"] | OBSERVED |
| `regions[].region_kind` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | ["gameplay_macro_region"] | — | ["gameplay_macro_region"] | OBSERVED |
| `regions[].stable_id` | `regions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | primary_candidate | — | ["aquitaine","brittany","loire_valley","massif_central","mediterranean_coast","normandy","northern_industrial_belt","paris_basin","rhone_valley"] | — | ["aquitaine","brittany","loire_valley"] | OBSERVED |
| `regions[].visible_zoom_min` | `regions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | [] | 6.21–6.21 | [6.21] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED |
| `source` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"dataset":"Natural Earth Vector 1:10m Admin 1 States/Provinces","license":"Public domain","upstream_url":"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master... | OBSERVED |
| `source.dataset` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["Natural Earth Vector 1:10m Admin 1 States/Provinces"] | — | ["Natural Earth Vector 1:10m Admin 1 States/Provinces"] | OBSERVED |
| `source.license` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["Public domain"] | — | ["Public domain"] | OBSERVED |
| `source.upstream_url` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson"] | — | ["https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_1_states_provinces.geojson"] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
