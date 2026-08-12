# world_map.cities

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Sparse world-map city node catalog used by the shared basemap.

- Path: `data/world_map/cities.json`
- Source files: `1`
- Record count (primary collection): `32`
- Documents: `1`
- Root type: `object`
- Primary record path: `cities[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `cities[]` | 32 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `cities` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"id":"<nested>","label_priority":"<nested>","lon_lat":"<nested>","major":"<nested>","max_zoom":"<nested>","min_zoom":"<nested>"},{"arrondissement_id":"<nested>","commune_id":... | OBSERVED |
| `cities[]` | `cities[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | — | — | — | [] | — | [{"arrondissement_id":"arrondissement_lille","commune_id":"commune_lille","departement_id":"departement_nord","id":"lille","label_priority":98,"lon_lat":["<nested>","<nested>"]}... | OBSERVED |
| `cities[].arrondissement_id` | `cities[]` | string / declared `—` | False | False | False | False | optional-by-observation | 31 / 32 | null | True | reference_candidate | — | ["arrondissement_lille"] | — | ["arrondissement_lille"] | OBSERVED |
| `cities[].commune_id` | `cities[]` | string / declared `—` | False | False | False | False | optional-by-observation | 31 / 32 | null | True | reference_candidate | — | ["commune_lille"] | — | ["commune_lille"] | OBSERVED |
| `cities[].departement_id` | `cities[]` | string / declared `—` | False | False | False | False | optional-by-observation | 31 / 32 | null | True | reference_candidate | — | ["departement_nord"] | — | ["departement_nord"] | OBSERVED |
| `cities[].id` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | True | primary_candidate | — | ["alexandria","antwerp","beijing","berlin","bordeaux","brest","brussels","buenos_aires","calais","cologne","dover","ghent","istanbul","kolkata","kortrijk","le_havre","lille","lo... | — | ["alexandria","antwerp","beijing"] | OBSERVED |
| `cities[].label_priority` | `cities[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | — | — | [] | 61.0–100.0 | [100,61,68] | OBSERVED |
| `cities[].lon_lat` | `cities[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | — | — | — | [] | — | [[-0.1276,51.5072],[-0.5792,44.8378],[-1.5536,47.2184]] | OBSERVED |
| `cities[].lon_lat[]` | `cities[].lon_lat[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 64 | null | True | — | — | [] | -77.0369–139.6917 | [-0.1276,-0.5792,-1.5536] | OBSERVED |
| `cities[].major` | `cities[]` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | — | — | [] | — | [false,true] | OBSERVED |
| `cities[].max_zoom` | `cities[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | — | — | [] | 200.0–200.0 | [200.0] | OBSERVED |
| `cities[].min_zoom` | `cities[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | — | — | [] | 0.85–6.4 | [0.85,0.9,0.95] | OBSERVED |
| `cities[].name` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | True | — | — | ["东京","亚历山大港","伦敦","加尔各答","加来","勒阿弗尔","北京","华盛顿","南特","君士坦丁堡","图卢兹","图尔奈","圣彼得堡","多佛","安特卫普","巴黎","布宜诺斯艾利斯","布雷斯特","布鲁塞尔","斯特拉斯堡","柏林","根特","波尔多","科特赖克","科隆","纽约","维也纳","莫斯科","里... | — | ["东京","亚历山大港","伦敦"] | OBSERVED |
| `cities[].native_name` | `cities[]` | string / declared `—` | False | False | False | False | optional-by-observation | 24 / 32 | null | True | — | — | ["Antwerpen","Bruxelles","Dover","Gent","Kortrijk","Köln","Lille","Tournai"] | — | ["Antwerpen","Bruxelles","Dover"] | OBSERVED |
| `cities[].object_level` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | — | — | ["city"] | — | ["city"] | OBSERVED |
| `cities[].parent_country_id` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.countries | ["argentine_republic","austro_hungarian_empire","british_empire","country_bel","country_fra","german_empire","japanese_empire","ottoman_empire","qing_empire","russian_empire","u... | — | ["argentine_republic","austro_hungarian_empire","british_empire"] | OBSERVED |
| `cities[].parent_region_id` | `cities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 32 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.regions | ["","aquitaine","brittany","loire_valley","mediterranean_coast","normandy","northern_industrial_belt","paris_basin","rhone_valley"] | — | ["","aquitaine","brittany"] | OBSERVED |
| `cities[].player_city` | `cities[]` | boolean / declared `—` | False | False | False | False | optional-by-observation | 31 / 32 | null | True | — | — | [] | — | [true] | OBSERVED |
| `cities[].theme_label_placeholder` | `cities[]` | boolean / declared `—` | False | False | False | False | optional-by-observation | 31 / 32 | null | True | — | — | [] | — | [true] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 3.0–3.0 | [3] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
