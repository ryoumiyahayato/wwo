# world_map.historical_political_entities_1900

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Historical political entity list and explicit approximation/conflict notes.

- Path: `data/world_map/historical_political_entities_1900.json`
- Source files: `1`
- Record count (primary collection): `61`
- Documents: `1`
- Root type: `object`
- Primary record path: `entities[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `conflicts[]` | 4 | 1 |
| `entities[]` | 61 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `approximation_notice` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["本文件将现有 Natural Earth 现代国家多边形聚合为约1900年的政治实体、殖民地与受保护领地，用于全息空间导航样机。它修正现代177国直接作为1900主权国家的问题，但不是逐点考证的1900历史边界。复杂殖民地、附庸、租借地和边境争议仍需未来以历史GIS数据替换。"] | — | ["本文件将现有 Natural Earth 现代国家多边形聚合为约1900年的政治实体、殖民地与受保护领地，用于全息空间导航样机。它修正现代177国直接作为1900主权国家的问题，但不是逐点考证的1900历史边界。复杂殖民地、附庸、租借地和边境争议仍需未来以历史GIS数据替换。"] | OBSERVED |
| `conflicts` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"end_date":"<nested>","id":"<nested>","name_zh":"<nested>","paths":"<nested>","severity":"<nested>","start_date":"<nested>"},{"end_date":"<nested>","id":"<nested>","name_zh":... | OBSERVED |
| `conflicts[]` | `conflicts[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | — | — | — | [] | — | [{"end_date":"1900-09-30","id":"war_of_golden_stool","name_zh":"金凳子战争","paths":["<nested>"],"severity":1,"start_date":"1900-03-01"},{"end_date":"1901-09-07","id":"boxer_uprising... | OBSERVED |
| `conflicts[].end_date` | `conflicts[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | — | — | ["1900-09-30","1901-09-07","1902-05-31","1902-07-02"] | — | ["1900-09-30","1901-09-07","1902-05-31"] | OBSERVED |
| `conflicts[].id` | `conflicts[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | primary_candidate | — | ["boxer_uprising","philippine_american_war","second_boer_war","war_of_golden_stool"] | — | ["boxer_uprising","philippine_american_war","second_boer_war"] | OBSERVED |
| `conflicts[].name_zh` | `conflicts[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | — | — | ["义和团运动与八国联军干涉","第二次布尔战争","美菲战争","金凳子战争"] | — | ["义和团运动与八国联军干涉","第二次布尔战争","美菲战争"] | OBSERVED |
| `conflicts[].paths` | `conflicts[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>"]],[["<nested>","<nested>","<nested>","<nested>"]],[["<nested>","<nested>","<nested>"],["<nested... | OBSERVED |
| `conflicts[].paths[]` | `conflicts[].paths[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]],[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED |
| `conflicts[].paths[][]` | `conflicts[].paths[][]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 20 | null | — | — | — | [] | — | [[-0.8,6.2],[-1.2,6.5],[-1.62,6.69]] | OBSERVED |
| `conflicts[].paths[][][]` | `conflicts[].paths[][][]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 40 | null | False | — | — | [] | -30.73–120.98 | [-0.8,-1.2,-1.62] | OBSERVED |
| `conflicts[].severity` | `conflicts[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | False | — | — | [] | 1.0–3.0 | [1,2,3] | OBSERVED |
| `conflicts[].start_date` | `conflicts[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | — | — | ["1899-02-04","1899-10-11","1899-11-01","1900-03-01"] | — | ["1899-02-04","1899-10-11","1899-11-01"] | OBSERVED |
| `conflicts[].type` | `conflicts[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | False | — | — | ["contested_front","war_front"] | — | ["contested_front","war_front"] | OBSERVED |
| `entities` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"colors":"<nested>","core_members":"<nested>","detail_mode":"<nested>","id":"<nested>","label_rank":"<nested>","members":"<nested>"},{"colors":"<nested>","detail_mode":"<nest... | OBSERVED |
| `entities[]` | `entities[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | — | — | — | [] | — | [{"colors":["<nested>","<nested>","<nested>","<nested>"],"core_members":["<nested>","<nested>"],"detail_mode":"territories","id":"austria_hungary","label_rank":1,"members":["<ne... | OBSERVED |
| `entities[].colors` | `entities[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | — | — | — | [] | — | [["#181817","#D7D1C5","#92343D"],["#191817","#C3A246","#8E343D"],["#1C1B19","#8E343D","#3D684F"]] | OBSERVED |
| `entities[].colors[]` | `entities[].colors[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 177 | null | False | — | — | [] | — | ["#181817","#191817","#1C1B19"] | OBSERVED |
| `entities[].core_members` | `entities[]` | array / declared `—` | False | False | False | False | optional-by-observation | 51 / 61 | null | — | — | — | [] | — | [["AUT","HUN"],["CHN"],["COL"]] | OBSERVED |
| `entities[].core_members[]` | `entities[].core_members[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 11 | null | True | — | — | ["AUT","CHN","COL","DNK","FRA","GBR","HUN","ITA","JPN","RUS","TUR"] | — | ["AUT","CHN","COL"] | OBSERVED |
| `entities[].detail_mode` | `entities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | False | — | — | ["france","single","territories"] | — | ["france","single","territories"] | OBSERVED |
| `entities[].id` | `entities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | True | primary_candidate | — | [] | — | ["arabian_polities","argentina_1900","austria_hungary"] | OBSERVED |
| `entities[].label_rank` | `entities[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | False | — | — | [] | 1.0–5.0 | [1,2,3] | OBSERVED |
| `entities[].members` | `entities[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | — | — | — | [] | — | [["AFG"],["AGO","MOZ","GNB","TLS"],["ARG"]] | OBSERVED |
| `entities[].members[]` | `entities[].members[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 168 | null | True | — | — | [] | — | ["AFG","AGO","ALB"] | OBSERVED |
| `entities[].name_zh` | `entities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["不丹王国","丹麦王国","乌拉圭东岸共和国"] | OBSERVED |
| `entities[].pattern` | `entities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | False | — | — | ["canton","cross","diagonal","disc","horizontal","quartered","solid","vertical"] | — | ["canton","cross","diagonal"] | OBSERVED |
| `entities[].short_name_zh` | `entities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["不丹","丹麦","乌拉圭"] | OBSERVED |
| `entities[].sovereign_id` | `entities[]` | string / declared `—` | False | False | False | False | optional-by-observation | 53 / 61 | null | True | reference_candidate | — | ["british_isles_1900","country_fra","german_empire","kingdom_of_belgium","kingdom_of_netherlands","kingdom_of_portugal","kingdom_of_spain","united_states_1900"] | — | ["british_isles_1900","country_fra","german_empire"] | OBSERVED |
| `entities[].status` | `entities[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 61 | null | False | — | — | ["autonomous","contested","dependency","empire","fragmented","personal_union","sovereign"] | — | ["autonomous","contested","dependency"] | OBSERVED |
| `fallback_notice` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["未被明确映射的现代多边形会保留为低优先级‘待校订领土’，仅在高倍率显示，不宣称其为1900独立国家。"] | — | ["未被明确映射的现代多边形会保留为低优先级‘待校订领土’，仅在高倍率显示，不宣称其为1900独立国家。"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `year` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1900.0–1900.0 | [1900] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
