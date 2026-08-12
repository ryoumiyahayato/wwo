# world_map.shipping_routes

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Shipping routes connecting map port nodes.

- Path: `data/world_map/shipping_routes.json`
- Source files: `1`
- Record count (primary collection): `3`
- Documents: `1`
- Root type: `object`
- Primary record path: `routes[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `routes[]` | 3 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `routes` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"from_port_id":"<nested>","id":"<nested>","max_zoom":"<nested>","min_zoom":"<nested>","name":"<nested>","to_port_id":"<nested>"},{"from_port_id":"<nested>","id":"<nested>","m... | OBSERVED |
| `routes[]` | `routes[]` | object / declared `—` | False | True | required-by-observation | 0 / 3 | null | — | — | — | [] | — | [{"from_port_id":"port_le_havre","id":"shipping_atlantic","max_zoom":3.6,"min_zoom":0.95,"name":"北大西洋航线","to_port_id":"port_new_york"},{"from_port_id":"port_le_havre","id":"ship... | OBSERVED |
| `routes[].from_port_id` | `routes[]` | string / declared `—` | False | True | required-by-observation | 0 / 3 | null | False | reference_candidate | — | ["port_le_havre","port_marseille"] | — | ["port_le_havre","port_marseille"] | OBSERVED |
| `routes[].id` | `routes[]` | string / declared `string` | False | True | required-by-observation | 0 / 3 | — | True | primary_candidate | — | ["shipping_atlantic","shipping_channel","shipping_mediterranean"] | — | ["shipping_atlantic","shipping_channel","shipping_mediterranean"] | OBSERVED + DECLARED |
| `routes[].max_zoom` | `routes[]` | number / declared `number` | False | True | required-by-observation | 0 / 3 | 99.0 | True | — | — | [] | 3.6–96.0 | [3.6,6.2,96.0] | OBSERVED + DECLARED |
| `routes[].min_zoom` | `routes[]` | number / declared `number` | False | True | required-by-observation | 0 / 3 | 0.0 | True | — | — | [] | 0.95–1.55 | [0.95,1.3,1.55] | OBSERVED + DECLARED |
| `routes[].name` | `routes[]` | string / declared `string` | False | True | required-by-observation | 0 / 3 | — | True | — | — | ["北大西洋航线","地中海东部航线","英吉利海峡航线"] | — | ["北大西洋航线","地中海东部航线","英吉利海峡航线"] | OBSERVED + DECLARED |
| `routes[].to_port_id` | `routes[]` | string / declared `—` | False | True | required-by-observation | 0 / 3 | null | True | reference_candidate | — | ["port_alexandria","port_london","port_new_york"] | — | ["port_alexandria","port_london","port_new_york"] | OBSERVED |
| `routes[].type` | `routes[]` | string / declared `—` | False | True | required-by-observation | 0 / 3 | null | False | — | — | ["shipping"] | — | ["shipping"] | OBSERVED |
| `routes[].waypoints_lon_lat` | `routes[]` | array / declared `—` | False | True | required-by-observation | 0 / 3 | null | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED |
| `routes[].waypoints_lon_lat[]` | `routes[].waypoints_lon_lat[]` | array / declared `—` | False | True | required-by-observation | 0 / 14 | null | — | — | — | [] | — | [[-0.2,51.1],[-0.7,50.1],[-18.0,50.0]] | OBSERVED |
| `routes[].waypoints_lon_lat[][]` | `routes[].waypoints_lon_lat[][]` | number / declared `—` | False | True | required-by-observation | 0 / 28 | null | False | — | — | [] | -74.0–51.5 | [-0.2,-0.7,-18.0] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 2.0–2.0 | [2] | OBSERVED |
| `type` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["shipping"] | — | ["shipping"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
