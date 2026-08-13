# world_map.road_segments

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Road transport segments connecting map city nodes.

- Path: `data/world_map/road_segments.json`
- Source files: `1`
- Record count (primary collection): `3`
- Documents: `1`
- Root type: `object`
- Primary record path: `segments[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `segments[]` | 3 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 2.0–2.0 | [2] | OBSERVED |
| `segments` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"from_city_id":"<nested>","id":"<nested>","max_zoom":"<nested>","min_zoom":"<nested>","to_city_id":"<nested>","type":"<nested>"},{"from_city_id":"<nested>","id":"<nested>","m... | OBSERVED |
| `segments[]` | `segments[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | — | — | — | [] | — | [{"from_city_id":"lille","id":"road_lille_rouen","max_zoom":96.0,"min_zoom":6.6,"to_city_id":"rouen","type":"road"},{"from_city_id":"lyon","id":"road_lyon_strasbourg","max_zoom"... | OBSERVED |
| `segments[].from_city_id` | `segments[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | reference_candidate | — | ["lille","lyon","rouen"] | — | ["lille","lyon","rouen"] | OBSERVED |
| `segments[].id` | `segments[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | primary_candidate | — | ["road_lille_rouen","road_lyon_strasbourg","road_rouen_paris"] | — | ["road_lille_rouen","road_lyon_strasbourg","road_rouen_paris"] | OBSERVED |
| `segments[].max_zoom` | `segments[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED |
| `segments[].min_zoom` | `segments[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | False | — | — | [] | 6.6–6.6 | [6.6] | OBSERVED |
| `segments[].to_city_id` | `segments[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | reference_candidate | — | ["paris","rouen","strasbourg"] | — | ["paris","rouen","strasbourg"] | OBSERVED |
| `segments[].type` | `segments[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | False | — | — | ["road"] | — | ["road"] | OBSERVED |
| `type` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["road"] | — | ["road"] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
