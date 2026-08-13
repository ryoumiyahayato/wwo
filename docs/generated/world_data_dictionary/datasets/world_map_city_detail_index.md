# world_map.city_detail.index

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Index and runtime policy for the modern city-detail shards.

- Path: `data/world_map/city_detail/index.json`
- Source files: `1`
- Record count (primary collection): `144`
- Documents: `1`
- Root type: `object`
- Primary record path: `countries[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `countries[]` | 144 | 1 |
| `countries[].shards[]` | 156 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `countries` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"bounds":"<nested>","continent":"<nested>","count":"<nested>","country_code":"<nested>","country_name":"<nested>","shards":"<nested>"},{"bounds":"<nested>","continent":"<nest... | OBSERVED |
| `countries[]` | `countries[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | — | — | — | [] | — | [{"bounds":["<nested>","<nested>","<nested>","<nested>"],"continent":"AS","count":1,"country_code":"CC","country_name":"Cocos Islands","shards":["<nested>"]},{"bounds":["<nested... | OBSERVED |
| `countries[].bounds` | `countries[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | — | — | — | [] | — | [[-117.06583,14.53588,-86.73105,32.63075],[-135.05375,42.05009,-52.70931,63.74697],[-161.75583,19.59333,-67.8403,64.85694]] | OBSERVED |
| `countries[].bounds[]` | `countries[].bounds[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 576 | null | False | — | — | [] | -161.75583–177.5103 | [-0.6,-10.17083,-117.06583] | OBSERVED |
| `countries[].continent` | `countries[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | False | — | — | ["AS","EU","NA"] | — | ["AS","EU","NA"] | OBSERVED |
| `countries[].count` | `countries[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | False | — | — | [] | 1.0–36871.0 | [1,10,1012] | OBSERVED |
| `countries[].country_code` | `countries[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | True | — | — | [] | — | ["AD","AE","AF"] | OBSERVED |
| `countries[].country_name` | `countries[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | True | — | — | [] | — | ["Afghanistan","Aland Islands","Albania"] | OBSERVED |
| `countries[].municipality_count` | `countries[]` | number / declared `—` | False | False | False | False | optional-by-observation | 143 / 144 | null | True | — | — | [] | 34742.0–34742.0 | [34742] | OBSERVED |
| `countries[].municipality_detail` | `countries[]` | boolean / declared `—` | False | False | False | False | optional-by-observation | 143 / 144 | null | True | — | — | [] | — | [true] | OBSERVED |
| `countries[].shards` | `countries[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 144 | null | — | — | — | [] | — | [[{"admin1_code":"<nested>","bounds":"<nested>","count":"<nested>","id":"<nested>","path":"<nested>"},{"admin1_code":"<nested>","bounds":"<nested>","count":"<nested>","id":"<nes... | OBSERVED |
| `countries[].shards[]` | `countries[].shards[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 156 | null | — | — | — | [] | — | [{"admin1_code":"11","bounds":["<nested>","<nested>","<nested>","<nested>"],"count":1671,"id":"FR-11","path":"france/FR-11.json"},{"admin1_code":"24","bounds":["<nested>","<nest... | OBSERVED |
| `countries[].shards[].admin1_code` | `countries[].shards[]` | string / declared `—` | False | False | False | False | optional-by-observation | 143 / 156 | null | True | — | — | ["11","24","27","28","32","44","52","53","75","76","84","93","94"] | — | ["11","24","27"] | OBSERVED |
| `countries[].shards[].bounds` | `countries[].shards[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 156 | null | — | — | — | [] | — | [[-0.28528,42.36028,4.796,45.02083],[-1.77444,42.87306,2.56278,47.13722],[-1.86639,48.22611,1.7801,50.06056]] | OBSERVED |
| `countries[].shards[].bounds[]` | `countries[].shards[].bounds[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 624 | null | False | — | — | [] | -161.75583–177.5103 | [-0.28528,-0.6,-1.03722] | OBSERVED |
| `countries[].shards[].count` | `countries[].shards[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 156 | null | False | — | — | [] | 1.0–7555.0 | [1,10,1012] | OBSERVED |
| `countries[].shards[].id` | `countries[].shards[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 156 | null | True | primary_candidate | — | [] | — | ["AD","AE","AF"] | OBSERVED |
| `countries[].shards[].path` | `countries[].shards[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 156 | null | True | — | — | [] | — | ["countries/AD.json","countries/AE.json","countries/AF.json"] | OBSERVED |
| `dataset` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["modern_city_detail"] | — | ["modern_city_detail"] | OBSERVED |
| `generated_at` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["2026-07-22T05:25:11+00:00"] | — | ["2026-07-22T05:25:11+00:00"] | OBSERVED |
| `geographic_scope` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["Europe","Asia","North America"]] | OBSERVED |
| `geographic_scope[]` | `geographic_scope[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | ["Asia","Europe","North America"] | — | ["Asia","Europe","North America"] | OBSERVED |
| `historical_status` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["modern_reference_only"] | — | ["modern_reference_only"] | OBSERVED |
| `runtime_policy` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"country_cache_limit":12,"load_mode":"viewport_intersecting_shards","visible_label_budget":180,"visible_node_budget":1600}] | OBSERVED |
| `runtime_policy.country_cache_limit` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 12.0–12.0 | [12] | OBSERVED |
| `runtime_policy.load_mode` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["viewport_intersecting_shards"] | — | ["viewport_intersecting_shards"] | OBSERVED |
| `runtime_policy.visible_label_budget` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 180.0–180.0 | [180] | OBSERVED |
| `runtime_policy.visible_node_budget` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1600.0–1600.0 | [1600] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `source` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"download_root":"https://download.geonames.org/export/dump/","inputs":["<nested>","<nested>","<nested>"],"license":"Creative Commons Attribution 4.0","license_url":"https://cr... | OBSERVED |
| `source.download_root` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["https://download.geonames.org/export/dump/"] | — | ["https://download.geonames.org/export/dump/"] | OBSERVED |
| `source.inputs` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["cities5000.zip","FR.zip","countryInfo.txt"]] | OBSERVED |
| `source.inputs[]` | `source.inputs[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | ["FR.zip","cities5000.zip","countryInfo.txt"] | — | ["FR.zip","cities5000.zip","countryInfo.txt"] | OBSERVED |
| `source.license` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["Creative Commons Attribution 4.0"] | — | ["Creative Commons Attribution 4.0"] | OBSERVED |
| `source.license_url` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["https://creativecommons.org/licenses/by/4.0/"] | — | ["https://creativecommons.org/licenses/by/4.0/"] | OBSERVED |
| `source.name` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["GeoNames"] | — | ["GeoNames"] | OBSERVED |
| `totals` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"countries":144,"france_municipalities":34742,"records":88927,"shards":156}] | OBSERVED |
| `totals.countries` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 144.0–144.0 | [144] | OBSERVED |
| `totals.france_municipalities` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 34742.0–34742.0 | [34742] | OBSERVED |
| `totals.records` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 88927.0–88927.0 | [88927] | OBSERVED |
| `totals.shards` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 156.0–156.0 | [156] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
