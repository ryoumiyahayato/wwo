# world_map.city_detail.france_shards

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Modern French administrative city detail shards; loaded lazily for regional reference.

- Path: `data/world_map/city_detail/france/*.json`
- Source files: `13`
- Record count (primary collection): `36871`
- Documents: `13`
- Root type: `object`
- Primary record path: `cities[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `cities[]` | 36871 | 13 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `admin1_code` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | True | — | — | ["11","24","27","28","32","44","52","53","75","76","84","93","94"] | — | ["11","24","27"] | OBSERVED |
| `bounds` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | — | — | — | [] | — | [[-0.28528,42.36028,4.796,45.02083],[-1.77444,42.87306,2.56278,47.13722],[-1.86639,48.22611,1.7801,50.06056]] | OBSERVED |
| `bounds[]` | `bounds[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 52 | null | True | — | — | [] | -5.0975–51.0714 | [-0.28528,-1.03722,-1.77444] | OBSERVED |
| `cities` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | — | — | — | [] | — | [[{"admin1_code":"<nested>","admin2_code":"<nested>","admin3_code":"<nested>","admin4_code":"<nested>","ascii_name":"<nested>","continent":"<nested>"},{"admin1_code":"<nested>",... | OBSERVED |
| `cities[]` | `cities[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | — | — | — | [] | — | [{"admin1_code":"11","admin2_code":"","admin3_code":"","admin4_code":"","ascii_name":"Marne La Vallee","continent":"EU"},{"admin1_code":"11","admin2_code":"75","admin3_code":"75... | OBSERVED |
| `cities[].admin1_code` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | ["11","24","27","28","32","44","52","53","75","76","84","93","94"] | — | ["11","24","27"] | OBSERVED |
| `cities[].admin2_code` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | ["","01","02"] | OBSERVED |
| `cities[].admin3_code` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | ["","011","012"] | OBSERVED |
| `cities[].admin4_code` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | ["","01001","01002"] | OBSERVED |
| `cities[].ascii_name` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | ["Aast","Abainville","Abancourt"] | OBSERVED |
| `cities[].continent` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | ["EU"] | — | ["EU"] | OBSERVED |
| `cities[].country_code` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | ["FR"] | — | ["FR"] | OBSERVED |
| `cities[].curated_city_id` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | reference_candidate | — | [""] | — | [""] | OBSERVED |
| `cities[].feature_code` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | ["ADM4","PPL","PPLA","PPLA2","PPLA3","PPLA4","PPLA5","PPLC","PPLL","PPLX"] | — | ["ADM4","PPL","PPLA"] | OBSERVED |
| `cities[].historical_theme_override` | `cities[]` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | [false] | OBSERVED |
| `cities[].id` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | True | primary_candidate | — | [] | — | ["geonames:11204239","geonames:11548418","geonames:11919711"] | OBSERVED |
| `cities[].label_priority` | `cities[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | 34.0–100.0 | [100,34,38] | OBSERVED |
| `cities[].lon_lat` | `cities[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | — | — | — | [] | — | [[-0.0001,43.8642],[-0.00028,45.63917],[-0.00056,44.9825]] | OBSERVED |
| `cities[].lon_lat[]` | `cities[].lon_lat[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 73742 | null | False | — | — | [] | -5.0975–51.0714 | [-0.0001,-0.00028,-0.00056] | OBSERVED |
| `cities[].major` | `cities[]` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | [false,true] | OBSERVED |
| `cities[].modern_geography` | `cities[]` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | [true] | OBSERVED |
| `cities[].name` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | ["Aast","Abainville","Abancourt"] | OBSERVED |
| `cities[].native_name` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | — | ["Aast","Abainville","Abancourt"] | OBSERVED |
| `cities[].population` | `cities[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | [] | 0.0–2190327.0 | [0,1,10] | OBSERVED |
| `cities[].record_type` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | ["city","municipality"] | — | ["city","municipality"] | OBSERVED |
| `cities[].timezone` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 36871 | null | False | — | — | ["Europe/Paris"] | — | ["Europe/Paris"] | OBSERVED |
| `continent` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["EU"] | — | ["EU"] | OBSERVED |
| `count` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | True | — | — | [] | 368.0–5295.0 | [1229,1305,1328] | OBSERVED |
| `country_code` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["FR"] | — | ["FR"] | OBSERVED |
| `country_name` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["France"] | — | ["France"] | OBSERVED |
| `dataset` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["modern_city_detail"] | — | ["modern_city_detail"] | OBSERVED |
| `generated_at` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["2026-07-22T05:25:11+00:00"] | — | ["2026-07-22T05:25:11+00:00"] | OBSERVED |
| `license` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["Creative Commons Attribution 4.0"] | — | ["Creative Commons Attribution 4.0"] | OBSERVED |
| `municipality_detail` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `shard_id` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | True | reference_candidate | — | ["FR-11","FR-24","FR-27","FR-28","FR-32","FR-44","FR-52","FR-53","FR-75","FR-76","FR-84","FR-93","FR-94"] | — | ["FR-11","FR-24","FR-27"] | OBSERVED |
| `source` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 13 | null | False | — | — | ["GeoNames"] | — | ["GeoNames"] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
