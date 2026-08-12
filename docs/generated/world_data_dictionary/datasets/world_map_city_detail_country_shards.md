# world_map.city_detail.country_shards

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Modern city detail shards grouped by country; loaded lazily for regional reference.

- Path: `data/world_map/city_detail/countries/*.json`
- Source files: `143`
- Record count (primary collection): `52056`
- Documents: `143`
- Root type: `object`
- Primary record path: `cities[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `cities[]` | 52056 | 143 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `bounds` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 143 | null | — | — | — | [] | — | [[-117.06583,14.53588,-86.73105,32.63075],[-135.05375,42.05009,-52.70931,63.74697],[-161.75583,19.59333,-67.8403,64.85694]] | OBSERVED |
| `bounds[]` | `bounds[]` | number / declared `—` | False | True | required-by-observation | 0 / 572 | null | False | — | — | [] | -161.75583–177.5103 | [-0.6,-10.17083,-117.06583] | OBSERVED |
| `cities` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 143 | null | — | — | — | [] | — | [[{"admin1_code":"<nested>","admin2_code":"<nested>","admin3_code":"<nested>","admin4_code":"<nested>","ascii_name":"<nested>","continent":"<nested>"},{"admin1_code":"<nested>",... | OBSERVED |
| `cities[]` | `cities[]` | object / declared `—` | False | True | required-by-observation | 0 / 52056 | null | — | — | — | [] | — | [{"admin1_code":"","admin2_code":"","admin3_code":"","admin4_code":"","ascii_name":"Admiralty","continent":"AS"},{"admin1_code":"","admin2_code":"","admin3_code":"","admin4_code... | OBSERVED |
| `cities[].admin1_code` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["","00","001"] | OBSERVED |
| `cities[].admin2_code` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["","0","00"] | OBSERVED |
| `cities[].admin3_code` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["","00070","00100"] | OBSERVED |
| `cities[].admin4_code` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["","0009","0012721"] | OBSERVED |
| `cities[].ascii_name` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["'Abas Abad","'Abasan al Jadidah","'Abasan al Kabirah"] | OBSERVED |
| `cities[].continent` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | ["AS","EU","NA"] | — | ["AS","EU","NA"] | OBSERVED |
| `cities[].country_code` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["AD","AE","AF"] | OBSERVED |
| `cities[].curated_city_id` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | reference_candidate | — | [""] | — | [""] | OBSERVED |
| `cities[].feature_code` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | ["PPL","PPLA","PPLA2","PPLA3","PPLA4","PPLA5","PPLC","PPLCH","PPLF","PPLG","PPLH","PPLL","PPLQ","PPLR","PPLS","PPLW","PPLX","STLMT"] | — | ["PPL","PPLA","PPLA2"] | OBSERVED |
| `cities[].historical_theme_override` | `cities[]` | boolean / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | [false] | OBSERVED |
| `cities[].id` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | True | primary_candidate | — | [] | — | ["geonames:10002798","geonames:100077","geonames:10014879"] | OBSERVED |
| `cities[].label_priority` | `cities[]` | number / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | 38.0–100.0 | [100,38,48] | OBSERVED |
| `cities[].lon_lat` | `cities[]` | array / declared `—` | False | True | required-by-observation | 0 / 52056 | null | — | — | — | [] | — | [[-0.0016,51.50971],[-0.00421,51.687],[-0.00438,53.36664]] | OBSERVED |
| `cities[].lon_lat[]` | `cities[].lon_lat[]` | number / declared `—` | False | True | required-by-observation | 0 / 104112 | null | False | — | — | [] | -161.75583–177.5103 | [-0.0016,-0.00421,-0.00438] | OBSERVED |
| `cities[].major` | `cities[]` | boolean / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | [false,true] | OBSERVED |
| `cities[].modern_geography` | `cities[]` | boolean / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | [true] | OBSERVED |
| `cities[].name` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["'Abās Ābād","'Alī Ābād-e Katūl","'s-Gravenland"] | OBSERVED |
| `cities[].native_name` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["'Abās Ābād","'Alī Ābād-e Katūl","'s-Gravenland"] | OBSERVED |
| `cities[].population` | `cities[]` | number / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | 0.0–24874500.0 | [0,10,1000] | OBSERVED |
| `cities[].record_type` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | ["city"] | — | ["city"] | OBSERVED |
| `cities[].timezone` | `cities[]` | string / declared `—` | False | True | required-by-observation | 0 / 52056 | null | False | — | — | [] | — | ["Africa/Ceuta","America/Anchorage","America/Anguilla"] | OBSERVED |
| `continent` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | ["AS","EU","NA"] | — | ["AS","EU","NA"] | OBSERVED |
| `count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | [] | 1.0–7555.0 | [1,10,1012] | OBSERVED |
| `country_code` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | True | — | — | [] | — | ["AD","AE","AF"] | OBSERVED |
| `country_name` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | True | — | — | [] | — | ["Afghanistan","Aland Islands","Albania"] | OBSERVED |
| `dataset` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | ["modern_city_detail"] | — | ["modern_city_detail"] | OBSERVED |
| `generated_at` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | ["2026-07-22T05:25:11+00:00"] | — | ["2026-07-22T05:25:11+00:00"] | OBSERVED |
| `license` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | ["Creative Commons Attribution 4.0"] | — | ["Creative Commons Attribution 4.0"] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `shard_id` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | True | reference_candidate | — | [] | — | ["AD","AE","AF"] | OBSERVED |
| `source` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 143 | null | False | — | — | ["GeoNames"] | — | ["GeoNames"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
