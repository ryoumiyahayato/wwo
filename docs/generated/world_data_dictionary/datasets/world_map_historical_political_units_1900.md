# world_map.historical.political_units_1900

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

1900 political-unit records linking geometry, flags, and historical identity.

- Path: `data/world_map/historical/political_units_1900.json`
- Source files: `1`
- Record count (primary collection): `151`
- Documents: `1`
- Root type: `object`
- Primary record path: `units[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `units[]` | 151 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `geometry_provider` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["cshapes_2_0"] | — | ["cshapes_2_0"] | OBSERVED |
| `policy` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"all_flag_records_source_backed_or_documented_absence":true,"controller_flag_is_not_local_national_flag":true,"modern_geometry_fallback_allowed":false,"unknown_or_composite_fl... | OBSERVED + DECLARED |
| `policy.all_flag_records_source_backed_or_documented_absence` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.controller_flag_is_not_local_national_flag` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.modern_geometry_fallback_allowed` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [false] | OBSERVED |
| `policy.unknown_or_composite_flags_render_neutral` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `snapshot_date` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | — | — | ["1900-03-12"] | — | ["1900-03-12"] | OBSERVED + DECLARED |
| `unit_count` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 151.0–151.0 | [151] | OBSERVED + DECLARED |
| `units` | `document` | array / declared `array,number,string` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"area_km2":"<nested>","capital":"<nested>","controller_id":"<nested>","data_quality":"<nested>","flag_absence_reason":"<nested>","flag_id":"<nested>"},{"area_km2":"<nested>",... | OBSERVED + DECLARED |
| `units[]` | `units[]` | object / declared `array,number,string` | False | True | required-by-observation | 0 / 151 | null | — | — | — | [] | — | [{"area_km2":10088.9,"capital":{"lat":"<nested>","lon":"<nested>","name":"<nested>"},"controller_id":"austria_hungary","data_quality":"dated_historical_gis","flag_absence_reason... | OBSERVED + DECLARED |
| `units[].area_km2` | `units[]` | number / declared `number` | False | True | required-by-observation | 0 / 151 | 0.0 | True | — | — | [] | 33.62–22016200.0 | [10088.9,101600.0,102889.0] | OBSERVED + DECLARED |
| `units[].capital` | `units[]` | object / declared `object` | False | True | required-by-observation | 0 / 151 | {} | — | — | — | [] | — | [{"lat":-0.21667,"lon":-78.5,"name":"Quito"},{"lat":-12.05,"lon":-77.05,"name":"Lima"},{"lat":-13.65,"lon":32.6333,"name":"Chipata (Fort Jameson)"}] | OBSERVED + DECLARED |
| `units[].capital.lat` | `units[]` | number / declared `number` | False | True | required-by-observation | 0 / 151 | 0.0 | False | — | — | [] | -42.85–64.15 | [-0.21667,-12.05,-13.65] | OBSERVED + DECLARED |
| `units[].capital.lon` | `units[]` | number / declared `number` | False | True | required-by-observation | 0 / 151 | 0.0 | True | — | — | [] | -157.856–178.43 | [-0.11667,-0.21667,-10.8047] | OBSERVED + DECLARED |
| `units[].capital.name` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | — | True | — | — | [] | — | ["Abu Dhabi","Accra","Addis Ababa"] | OBSERVED + DECLARED |
| `units[].controller_id` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | — | False | reference_candidate | — | ["","austria_hungary","british_isles_1900","country_fra","empire_of_japan","german_empire","kingdom_of_denmark","kingdom_of_italy","kingdom_of_netherlands","kingdom_of_portugal"... | — | ["","austria_hungary","british_isles_1900"] | OBSERVED + DECLARED |
| `units[].data_quality` | `units[]` | string / declared `—` | False | True | required-by-observation | 0 / 151 | null | False | — | — | ["dated_historical_gis"] | — | ["dated_historical_gis"] | OBSERVED |
| `units[].flag_absence_reason` | `units[]` | string / declared `boolean,string` | False | True | required-by-observation | 0 / 151 | — | False | — | — | ["","冰岛本地旗帜在1900年尚未正式形成；使用丹麦宗主权识别旗。","地方君主旗与外部控制关系并存，尚无足够证据指定单一标准国旗。","地方苏丹旗资料尚未达到可复原标准。","多个酋长国组成，1900年不存在统一的特鲁西尔国家旗。","现有国旗形成于20世纪中叶，不向1900年倒推。","纽芬兰殖民地1904年红船旗晚于快照日期；1900界面使用... | — | ["","冰岛本地旗帜在1900年尚未正式形成；使用丹麦宗主权识别旗。","地方君主旗与外部控制关系并存，尚无足够证据指定单一标准国旗。"] | OBSERVED + DECLARED |
| `units[].flag_id` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | null | False | reference_candidate | — | [] | — | ["afghanistan_1880","argentina_1861","austria_hungary_civil_1869"] | OBSERVED + DECLARED |
| `units[].flag_mode` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | — | False | — | — | ["controller_identification_flag","documented_absence","local_historical_flag"] | — | ["controller_identification_flag","documented_absence","local_historical_flag"] | OBSERVED + DECLARED |
| `units[].geometry_feature_id` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | — | True | reference_candidate | world_map.historical.cshapes_1900_snapshot, world_map.world_coastlines | [] | — | ["gw_100","gw_101","gw_110"] | OBSERVED + DECLARED |
| `units[].geometry_provider` | `units[]` | string / declared `—` | False | True | required-by-observation | 0 / 151 | null | False | — | — | ["cshapes_2_0"] | — | ["cshapes_2_0"] | OBSERVED |
| `units[].gwcode` | `units[]` | number / declared `integer` | False | True | required-by-observation | 0 / 151 | -1 | True | — | — | [] | 2.0–7030.0 | [100,101,110] | OBSERVED + DECLARED |
| `units[].id` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | null | True | primary_candidate | — | [] | — | ["argentina_1900","austria_hungary","beylicate_of_tunis"] | OBSERVED + DECLARED |
| `units[].label_rank` | `units[]` | number / declared `integer` | False | True | required-by-observation | 0 / 151 | 5 | False | — | — | [] | 1.0–5.0 | [1,2,3] | OBSERVED + DECLARED |
| `units[].name_zh` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | null | True | — | — | [] | — | ["不丹王国","东北罗得西亚","东非保护国"] | OBSERVED + DECLARED |
| `units[].relationship` | `units[]` | string / declared `—` | False | True | required-by-observation | 0 / 151 | null | False | — | — | ["administered_territory","belligerent_state","controlled_territory","crown_colony","dual_control","independent_state","military_occupation","protected_state","protected_territo... | — | ["administered_territory","belligerent_state","controlled_territory"] | OBSERVED |
| `units[].short_name_zh` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | null | True | — | — | [] | — | ["不丹王国","东北罗得西亚","东非保护国"] | OBSERVED + DECLARED |
| `units[].source_name` | `units[]` | string / declared `—` | False | True | required-by-observation | 0 / 151 | null | True | — | — | [] | — | ["Afghanistan","Alaska","Algeria"] | OBSERVED |
| `units[].status` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | null | False | — | — | ["colony","condominium","contested","dependency","dominion","occupied","protectorate","sovereign"] | — | ["colony","condominium","contested"] | OBSERVED + DECLARED |
| `units[].valid_from` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | — | False | — | — | [] | — | ["1886-01-01","1886-05-12","1886-12-30"] | OBSERVED + DECLARED |
| `units[].valid_to` | `units[]` | string / declared `string` | False | True | required-by-observation | 0 / 151 | — | False | — | — | [] | — | ["1900-06-26","1900-09-04","1900-11-14"] | OBSERVED + DECLARED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
