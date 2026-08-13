# world_map.ports

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Sparse port node catalog used by transport routes.

- Path: `data/world_map/ports.json`
- Source files: `1`
- Record count (primary collection): `8`
- Documents: `1`
- Root type: `object`
- Primary record path: `ports[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `ports[]` | 8 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `ports` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"city_id":"<nested>","id":"<nested>","label_priority":"<nested>","lon_lat":"<nested>","max_zoom":"<nested>","min_zoom":"<nested>"},{"city_id":"<nested>","id":"<nested>","labe... | OBSERVED |
| `ports[]` | `ports[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | — | — | — | [] | — | [{"city_id":"alexandria","id":"port_alexandria","label_priority":64,"lon_lat":["<nested>","<nested>"],"max_zoom":6.2,"min_zoom":1.7},{"city_id":"bordeaux","id":"port_bordeaux","... | OBSERVED |
| `ports[].city_id` | `ports[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["alexandria","bordeaux","brest","calais","le_havre","london","marseille","new_york"] | — | ["alexandria","bordeaux","brest"] | OBSERVED |
| `ports[].id` | `ports[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | True | primary_candidate | — | ["port_alexandria","port_bordeaux","port_brest","port_calais","port_le_havre","port_london","port_marseille","port_new_york"] | — | ["port_alexandria","port_bordeaux","port_brest"] | OBSERVED |
| `ports[].label_priority` | `ports[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | False | — | — | [] | 58.0–88.0 | [58,60,64] | OBSERVED |
| `ports[].lon_lat` | `ports[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | — | — | — | [] | — | [[-0.58,44.84],[-4.49,48.39],[-74.0,40.7]] | OBSERVED |
| `ports[].lon_lat[]` | `ports[].lon_lat[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 16 | null | True | — | — | [] | -74.0–51.5 | [-0.58,-4.49,-74.0] | OBSERVED |
| `ports[].max_zoom` | `ports[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | False | — | — | [] | 6.2–96.0 | [6.2,96.0] | OBSERVED |
| `ports[].min_zoom` | `ports[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | False | — | — | [] | 1.6–6.4 | [1.6,1.65,1.7] | OBSERVED |
| `ports[].name` | `ports[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | True | — | — | ["亚历山大港","伦敦港","加来港","勒阿弗尔港","布雷斯特港","波尔多港","纽约港","马赛港"] | — | ["亚历山大港","伦敦港","加来港"] | OBSERVED |
| `ports[].object_level` | `ports[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | False | — | — | ["port"] | — | ["port"] | OBSERVED |
| `ports[].parent_country_id` | `ports[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.countries | ["british_empire","country_fra","ottoman_empire","united_states"] | — | ["british_empire","country_fra","ottoman_empire"] | OBSERVED |
| `ports[].parent_region_id` | `ports[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 8 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.regions | ["","aquitaine","brittany","mediterranean_coast","normandy","northern_industrial_belt"] | — | ["","aquitaine","brittany"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 2.0–2.0 | [2] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
