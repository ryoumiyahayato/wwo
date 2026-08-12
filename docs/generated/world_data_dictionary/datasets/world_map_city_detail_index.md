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

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `countries` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"bounds":"<nested>","continent":"<nested>","count":"<nested>","country_code":"<nested>","country_name":"<nested>","shards":"<nested>"},{"bounds":"<nested>","continent":"<nest... | OBSERVED + DECLARED |
| `countries[]` | `countries[]` | object / declared `array` | False | True | required-by-observation | 0 / 144 | [] | — | — | — | [] | — | [{"bounds":["<nested>","<nested>","<nested>","<nested>"],"continent":"AS","count":1,"country_code":"CC","country_name":"Cocos Islands","shards":["<nested>"]},{"bounds":["<nested... | OBSERVED + DECLARED |
| `countries[].bounds` | `countries[]` | array / declared `array` | False | True | required-by-observation | 0 / 144 | [] | — | — | — | [] | — | [[-117.06583,14.53588,-86.73105,32.63075],[-135.05375,42.05009,-52.70931,63.74697],[-161.75583,19.59333,-67.8403,64.85694]] | OBSERVED + DECLARED |
| `countries[].bounds[]` | `countries[].bounds[]` | number / declared `array` | False | True | required-by-observation | 0 / 576 | [] | False | — | — | [] | -161.75583–177.5103 | [-0.6,-10.17083,-117.06583] | OBSERVED + DECLARED |
| `countries[].continent` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 144 | — | False | — | — | ["AS","EU","NA"] | — | ["AS","EU","NA"] | OBSERVED + DECLARED |
| `countries[].count` | `countries[]` | number / declared `—` | False | True | required-by-observation | 0 / 144 | null | False | — | — | [] | 1.0–36871.0 | [1,10,1012] | OBSERVED |
| `countries[].country_code` | `countries[]` | string / declared `string` | False | True | required-by-observation | 0 / 144 | — | True | — | — | [] | — | ["AD","AE","AF"] | OBSERVED + DECLARED |
| `countries[].country_name` | `countries[]` | string / declared `—` | False | True | required-by-observation | 0 / 144 | null | True | — | — | [] | — | ["Afghanistan","Aland Islands","Albania"] | OBSERVED |
| `countries[].municipality_count` | `countries[]` | number / declared `—` | False | False | optional-by-observation | 143 / 144 | null | True | — | — | [] | 34742.0–34742.0 | [34742] | OBSERVED |
| `countries[].municipality_detail` | `countries[]` | boolean / declared `boolean` | False | False | optional-by-observation | 143 / 144 | false | True | — | — | [] | — | [true] | OBSERVED + DECLARED |
| `countries[].shards` | `countries[]` | array / declared `array` | False | True | required-by-observation | 0 / 144 | [] | — | — | — | [] | — | [[{"admin1_code":"<nested>","bounds":"<nested>","count":"<nested>","id":"<nested>","path":"<nested>"},{"admin1_code":"<nested>","bounds":"<nested>","count":"<nested>","id":"<nes... | OBSERVED + DECLARED |
| `countries[].shards[]` | `countries[].shards[]` | object / declared `array` | False | True | required-by-observation | 0 / 156 | [] | — | — | — | [] | — | [{"admin1_code":"11","bounds":["<nested>","<nested>","<nested>","<nested>"],"count":1671,"id":"FR-11","path":"france/FR-11.json"},{"admin1_code":"24","bounds":["<nested>","<nest... | OBSERVED + DECLARED |
| `countries[].shards[].admin1_code` | `countries[].shards[]` | string / declared `—` | False | False | optional-by-observation | 143 / 156 | null | True | — | — | ["11","24","27","28","32","44","52","53","75","76","84","93","94"] | — | ["11","24","27"] | OBSERVED |
| `countries[].shards[].bounds` | `countries[].shards[]` | array / declared `array` | False | True | required-by-observation | 0 / 156 | [] | — | — | — | [] | — | [[-0.28528,42.36028,4.796,45.02083],[-1.77444,42.87306,2.56278,47.13722],[-1.86639,48.22611,1.7801,50.06056]] | OBSERVED + DECLARED |
| `countries[].shards[].bounds[]` | `countries[].shards[].bounds[]` | number / declared `array` | False | True | required-by-observation | 0 / 624 | [] | False | — | — | [] | -161.75583–177.5103 | [-0.28528,-0.6,-1.03722] | OBSERVED + DECLARED |
| `countries[].shards[].count` | `countries[].shards[]` | number / declared `—` | False | True | required-by-observation | 0 / 156 | null | False | — | — | [] | 1.0–7555.0 | [1,10,1012] | OBSERVED |
| `countries[].shards[].id` | `countries[].shards[]` | string / declared `string` | False | True | required-by-observation | 0 / 156 | — | True | primary_candidate | — | [] | — | ["AD","AE","AF"] | OBSERVED + DECLARED |
| `countries[].shards[].path` | `countries[].shards[]` | string / declared `string` | False | True | required-by-observation | 0 / 156 | — | True | — | — | [] | — | ["countries/AD.json","countries/AE.json","countries/AF.json"] | OBSERVED + DECLARED |
| `dataset` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["modern_city_detail"] | — | ["modern_city_detail"] | OBSERVED |
| `generated_at` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["2026-07-22T05:25:11+00:00"] | — | ["2026-07-22T05:25:11+00:00"] | OBSERVED |
| `geographic_scope` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["Europe","Asia","North America"]] | OBSERVED |
| `geographic_scope[]` | `geographic_scope[]` | string / declared `—` | False | True | required-by-observation | 0 / 3 | null | True | — | — | ["Asia","Europe","North America"] | — | ["Asia","Europe","North America"] | OBSERVED |
| `historical_status` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | — | — | ["modern_reference_only"] | — | ["modern_reference_only"] | OBSERVED + DECLARED |
| `runtime_policy` | `document` | object / declared `object` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"country_cache_limit":12,"load_mode":"viewport_intersecting_shards","visible_label_budget":180,"visible_node_budget":1600}] | OBSERVED + DECLARED |
| `runtime_policy.country_cache_limit` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 12.0–12.0 | [12] | OBSERVED + DECLARED |
| `runtime_policy.load_mode` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["viewport_intersecting_shards"] | — | ["viewport_intersecting_shards"] | OBSERVED |
| `runtime_policy.visible_label_budget` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 180.0–180.0 | [180] | OBSERVED + DECLARED |
| `runtime_policy.visible_node_budget` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1600.0–1600.0 | [1600] | OBSERVED + DECLARED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `source` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"download_root":"https://download.geonames.org/export/dump/","inputs":["<nested>","<nested>","<nested>"],"license":"Creative Commons Attribution 4.0","license_url":"https://cr... | OBSERVED |
| `source.download_root` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["https://download.geonames.org/export/dump/"] | — | ["https://download.geonames.org/export/dump/"] | OBSERVED |
| `source.inputs` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["cities5000.zip","FR.zip","countryInfo.txt"]] | OBSERVED |
| `source.inputs[]` | `source.inputs[]` | string / declared `—` | False | True | required-by-observation | 0 / 3 | null | True | — | — | ["FR.zip","cities5000.zip","countryInfo.txt"] | — | ["FR.zip","cities5000.zip","countryInfo.txt"] | OBSERVED |
| `source.license` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Creative Commons Attribution 4.0"] | — | ["Creative Commons Attribution 4.0"] | OBSERVED |
| `source.license_url` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["https://creativecommons.org/licenses/by/4.0/"] | — | ["https://creativecommons.org/licenses/by/4.0/"] | OBSERVED |
| `source.name` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["GeoNames"] | — | ["GeoNames"] | OBSERVED |
| `totals` | `document` | object / declared `object` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"countries":144,"france_municipalities":34742,"records":88927,"shards":156}] | OBSERVED + DECLARED |
| `totals.countries` | `document` | number / declared `array` | False | True | required-by-observation | 0 / 1 | [] | True | — | — | [] | 144.0–144.0 | [144] | OBSERVED + DECLARED |
| `totals.france_municipalities` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | 0 | True | — | — | [] | 34742.0–34742.0 | [34742] | OBSERVED + DECLARED |
| `totals.records` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | 0 | True | — | — | [] | 88927.0–88927.0 | [88927] | OBSERVED + DECLARED |
| `totals.shards` | `document` | number / declared `array` | False | True | required-by-observation | 0 / 1 | [] | True | — | — | [] | 156.0–156.0 | [156] | OBSERVED + DECLARED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
