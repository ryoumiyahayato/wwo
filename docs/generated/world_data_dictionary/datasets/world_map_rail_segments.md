# world_map.rail_segments

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Rail transport segments connecting map city nodes.

- Path: `data/world_map/rail_segments.json`
- Source files: `1`
- Record count (primary collection): `9`
- Documents: `1`
- Root type: `object`
- Primary record path: `segments[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `segments[]` | 9 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 2.0–2.0 | [2] | OBSERVED |
| `segments` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"from_city_id":"<nested>","id":"<nested>","label_priority":"<nested>","main":"<nested>","max_zoom":"<nested>","min_zoom":"<nested>"},{"from_city_id":"<nested>","id":"<nested>... | OBSERVED |
| `segments[]` | `segments[]` | object / declared `—` | False | True | required-by-observation | 0 / 9 | null | — | — | — | [] | — | [{"from_city_id":"bordeaux","id":"rail_bordeaux_toulouse","main":false,"max_zoom":96.0,"min_zoom":6.4,"to_city_id":"toulouse"},{"from_city_id":"lille","id":"rail_lille_calais","... | OBSERVED |
| `segments[].from_city_id` | `segments[]` | string / declared `string` | False | True | required-by-observation | 0 / 9 | — | False | reference_candidate | — | ["bordeaux","lille","lyon","nantes","paris","rouen"] | — | ["bordeaux","lille","lyon"] | OBSERVED + DECLARED |
| `segments[].id` | `segments[]` | string / declared `string` | False | True | required-by-observation | 0 / 9 | — | True | primary_candidate | — | ["rail_bordeaux_toulouse","rail_lille_calais","rail_lyon_marseille","rail_nantes_bordeaux","rail_paris_lille","rail_paris_lyon","rail_paris_nantes","rail_paris_rouen","rail_roue... | — | ["rail_bordeaux_toulouse","rail_lille_calais","rail_lyon_marseille"] | OBSERVED + DECLARED |
| `segments[].label_priority` | `segments[]` | number / declared `integer` | False | False | optional-by-observation | 4 / 9 | 0 | True | — | — | [] | 88.0–100.0 | [100,88,92] | OBSERVED + DECLARED |
| `segments[].main` | `segments[]` | boolean / declared `boolean` | False | True | required-by-observation | 0 / 9 | false | False | — | — | [] | — | [false,true] | OBSERVED + DECLARED |
| `segments[].max_zoom` | `segments[]` | number / declared `number` | False | True | required-by-observation | 0 / 9 | 99.0 | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED + DECLARED |
| `segments[].min_zoom` | `segments[]` | number / declared `number` | False | True | required-by-observation | 0 / 9 | 0.0 | False | — | — | [] | 1.5–6.4 | [1.5,1.55,1.6] | OBSERVED + DECLARED |
| `segments[].name` | `segments[]` | string / declared `string` | False | False | optional-by-observation | 4 / 9 | — | True | — | — | ["巴黎—南特铁路","巴黎—里尔铁路","巴黎—里昂铁路","巴黎—鲁昂铁路","里昂—马赛铁路"] | — | ["巴黎—南特铁路","巴黎—里尔铁路","巴黎—里昂铁路"] | OBSERVED + DECLARED |
| `segments[].to_city_id` | `segments[]` | string / declared `string` | False | True | required-by-observation | 0 / 9 | — | True | reference_candidate | — | ["bordeaux","calais","le_havre","lille","lyon","marseille","nantes","rouen","toulouse"] | — | ["bordeaux","calais","le_havre"] | OBSERVED + DECLARED |
| `segments[].type` | `segments[]` | string / declared `—` | False | True | required-by-observation | 0 / 9 | null | False | — | — | ["rail"] | — | ["rail"] | OBSERVED |
| `type` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["rail"] | — | ["rail"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
