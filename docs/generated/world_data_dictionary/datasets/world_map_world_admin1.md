# world_map.world_admin1

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

World administrative-level-1 reference records.

- Path: `data/world_map/world_admin1.json`
- Source files: `1`
- Record count (primary collection): `4589`
- Documents: `1`
- Root type: `object`
- Primary record path: `regions[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `regions[]` | 4589 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `audit` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"countries_without_admin1_are_expected":true,"country_count":251,"polygon_count":6334,"region_count":4589}] | OBSERVED |
| `audit.countries_without_admin1_are_expected` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `audit.country_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 251.0–251.0 | [251] | OBSERVED |
| `audit.polygon_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 6334.0–6334.0 | [6334] | OBSERVED |
| `audit.region_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 4589.0–4589.0 | [4589] | OBSERVED |
| `regions` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"code":"<nested>","country_iso_a3":"<nested>","id":"<nested>","label_lon_lat":"<nested>","label_rank":"<nested>","min_zoom":"<nested>"},{"code":"<nested>","country_iso_a3":"<... | OBSERVED + DECLARED |
| `regions[]` | `regions[]` | object / declared `array` | False | True | required-by-observation | 0 / 4589 | [] | — | — | — | [] | — | [{"code":"-99-X02~","country_iso_a3":"CLP","id":"CLP+00?","label_lon_lat":["<nested>","<nested>"],"label_rank":20,"min_zoom":11.0},{"code":"-99-X03~","country_iso_a3":"CSI","id"... | OBSERVED + DECLARED |
| `regions[].code` | `regions[]` | string / declared `string` | False | True | required-by-observation | 0 / 4589 | 未配置 | False | — | — | [] | — | ["-99-X02~","-99-X03~","-99-X04~"] | OBSERVED + DECLARED |
| `regions[].country_iso_a3` | `regions[]` | string / declared `string` | False | True | required-by-observation | 0 / 4589 | — | False | — | — | [] | — | ["ABW","AFG","AGO"] | OBSERVED + DECLARED |
| `regions[].id` | `regions[]` | string / declared `string` | False | True | required-by-observation | 0 / 4589 | — | True | primary_candidate | — | [] | — | ["ABW-5150","AFG-1741","AFG-1742"] | OBSERVED + DECLARED |
| `regions[].label_lon_lat` | `regions[]` | array / declared `—` | False | True | required-by-observation | 0 / 4589 | [] | — | — | — | [] | — | [[-0.0113,51.4418],[-0.0126,51.5949],[-0.0128,42.1863]] | OBSERVED + DECLARED |
| `regions[].label_lon_lat[]` | `regions[].label_lon_lat[]` | number / declared `—` | False | True | required-by-observation | 0 / 9178 | [] | False | — | — | [] | -178.72–179.903 | [-0.0083,-0.0113,-0.0126] | OBSERVED + DECLARED |
| `regions[].label_rank` | `regions[]` | number / declared `integer` | False | True | required-by-observation | 0 / 4589 | 6 | False | — | — | [] | 2.0–20.0 | [10,2,20] | OBSERVED + DECLARED |
| `regions[].min_zoom` | `regions[]` | number / declared `—` | False | True | required-by-observation | 0 / 4589 | null | False | — | — | [] | 2.0–18.0 | [10.0,11.0,18.0] | OBSERVED |
| `regions[].name` | `regions[]` | string / declared `string` | False | True | required-by-observation | 0 / 4589 | null | False | — | — | [] | — | ["A'ana","Aargau","Aberdeen"] | OBSERVED + DECLARED |
| `regions[].name_zh` | `regions[]` | string / declared `string` | False | True | required-by-observation | 0 / 4589 | — | False | — | — | [] | — | ["丁利","丁吉拉伊省","万丹省"] | OBSERVED + DECLARED |
| `regions[].polygons` | `regions[]` | array / declared `array` | False | True | required-by-observation | 0 / 4589 | [] | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<n... | OBSERVED + DECLARED |
| `regions[].polygons[]` | `regions[].polygons[]` | array / declared `array` | False | True | required-by-observation | 0 / 6334 | [] | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED + DECLARED |
| `regions[].polygons[][]` | `regions[].polygons[][]` | array / declared `array` | False | True | required-by-observation | 0 / 275168 | [] | — | — | — | [] | — | [[-0.0003,43.9149],[-0.001,14.1852],[-0.0012,44.4104]] | OBSERVED + DECLARED |
| `regions[].polygons[][][]` | `regions[].polygons[][][]` | number / declared `array` | False | True | required-by-observation | 0 / 550336 | [] | False | — | — | [] | -180.0–180.0 | [-0.0003,-0.0007,-0.0009] | OBSERVED + DECLARED |
| `regions[].type` | `regions[]` | string / declared `string` | False | True | required-by-observation | 0 / 4589 | Region | False | — | — | [] | — | ["Administrative County","Administrative State","Administrative Zone"] | OBSERVED + DECLARED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `source` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"dataset":"Natural Earth 1:10m Admin-1 States and Provinces","historical_notice":"Modern admin-1 geometry used only as an approximate fallback where dedicated 1900 subdivision... | OBSERVED |
| `source.dataset` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Natural Earth 1:10m Admin-1 States and Provinces"] | — | ["Natural Earth 1:10m Admin-1 States and Provinces"] | OBSERVED |
| `source.historical_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Modern admin-1 geometry used only as an approximate fallback where dedicated 1900 subdivisions are unavailable."] | — | ["Modern admin-1 geometry used only as an approximate fallback where dedicated 1900 subdivisions are unavailable."] | OBSERVED |
| `source.license` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["Public domain"] | — | ["Public domain"] | OBSERVED |
| `source.upstream` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["nvkelso/natural-earth-vector geojson/ne_10m_admin_1_states_provinces.geojson"] | — | ["nvkelso/natural-earth-vector geojson/ne_10m_admin_1_states_provinces.geojson"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
