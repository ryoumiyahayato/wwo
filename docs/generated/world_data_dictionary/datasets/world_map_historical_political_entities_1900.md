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

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `approximation_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["本文件将现有 Natural Earth 现代国家多边形聚合为约1900年的政治实体、殖民地与受保护领地，用于全息空间导航样机。它修正现代177国直接作为1900主权国家的问题，但不是逐点考证的1900历史边界。复杂殖民地、附庸、租借地和边境争议仍需未来以历史GIS数据替换。"] | — | ["本文件将现有 Natural Earth 现代国家多边形聚合为约1900年的政治实体、殖民地与受保护领地，用于全息空间导航样机。它修正现代177国直接作为1900主权国家的问题，但不是逐点考证的1900历史边界。复杂殖民地、附庸、租借地和边境争议仍需未来以历史GIS数据替换。"] | OBSERVED |
| `conflicts` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"end_date":"<nested>","id":"<nested>","name_zh":"<nested>","paths":"<nested>","severity":"<nested>","start_date":"<nested>"},{"end_date":"<nested>","id":"<nested>","name_zh":... | OBSERVED + DECLARED |
| `conflicts[]` | `conflicts[]` | object / declared `array` | False | True | required-by-observation | 0 / 4 | [] | — | — | — | [] | — | [{"end_date":"1900-09-30","id":"war_of_golden_stool","name_zh":"金凳子战争","paths":["<nested>"],"severity":1,"start_date":"1900-03-01"},{"end_date":"1901-09-07","id":"boxer_uprising... | OBSERVED + DECLARED |
| `conflicts[].end_date` | `conflicts[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["1900-09-30","1901-09-07","1902-05-31","1902-07-02"] | — | ["1900-09-30","1901-09-07","1902-05-31"] | OBSERVED |
| `conflicts[].id` | `conflicts[]` | string / declared `boolean,string` | False | True | required-by-observation | 0 / 4 | — | True | primary_candidate | — | ["boxer_uprising","philippine_american_war","second_boer_war","war_of_golden_stool"] | — | ["boxer_uprising","philippine_american_war","second_boer_war"] | OBSERVED + DECLARED |
| `conflicts[].name_zh` | `conflicts[]` | string / declared `string` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["义和团运动与八国联军干涉","第二次布尔战争","美菲战争","金凳子战争"] | — | ["义和团运动与八国联军干涉","第二次布尔战争","美菲战争"] | OBSERVED + DECLARED |
| `conflicts[].paths` | `conflicts[]` | array / declared `array` | False | True | required-by-observation | 0 / 4 | [] | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>"]],[["<nested>","<nested>","<nested>","<nested>"]],[["<nested>","<nested>","<nested>"],["<nested... | OBSERVED + DECLARED |
| `conflicts[].paths[]` | `conflicts[].paths[]` | array / declared `array` | False | True | required-by-observation | 0 / 6 | [] | — | — | — | [] | — | [[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]],[["<nested>","<nested>"],["<nested>","<nested>"],["<nested>","<nested>"]]] | OBSERVED + DECLARED |
| `conflicts[].paths[][]` | `conflicts[].paths[][]` | array / declared `array` | False | True | required-by-observation | 0 / 20 | [] | — | — | — | [] | — | [[-0.8,6.2],[-1.2,6.5],[-1.62,6.69]] | OBSERVED + DECLARED |
| `conflicts[].paths[][][]` | `conflicts[].paths[][][]` | number / declared `array` | False | True | required-by-observation | 0 / 40 | [] | False | — | — | [] | -30.73–120.98 | [-0.8,-1.2,-1.62] | OBSERVED + DECLARED |
| `conflicts[].severity` | `conflicts[]` | number / declared `integer` | False | True | required-by-observation | 0 / 4 | 1 | False | — | — | [] | 1.0–3.0 | [1,2,3] | OBSERVED + DECLARED |
| `conflicts[].start_date` | `conflicts[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["1899-02-04","1899-10-11","1899-11-01","1900-03-01"] | — | ["1899-02-04","1899-10-11","1899-11-01"] | OBSERVED |
| `conflicts[].type` | `conflicts[]` | string / declared `string` | False | True | required-by-observation | 0 / 4 | — | False | — | — | ["contested_front","war_front"] | — | ["contested_front","war_front"] | OBSERVED + DECLARED |
| `entities` | `document` | array / declared `array` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"colors":"<nested>","core_members":"<nested>","detail_mode":"<nested>","id":"<nested>","label_rank":"<nested>","members":"<nested>"},{"colors":"<nested>","detail_mode":"<nest... | OBSERVED + DECLARED |
| `entities[]` | `entities[]` | object / declared `array` | False | True | required-by-observation | 0 / 61 | [] | — | — | — | [] | — | [{"colors":["<nested>","<nested>","<nested>","<nested>"],"core_members":["<nested>","<nested>"],"detail_mode":"territories","id":"austria_hungary","label_rank":1,"members":["<ne... | OBSERVED + DECLARED |
| `entities[].colors` | `entities[]` | array / declared `array` | False | True | required-by-observation | 0 / 61 | [] | — | — | — | [] | — | [["#181817","#D7D1C5","#92343D"],["#191817","#C3A246","#8E343D"],["#1C1B19","#8E343D","#3D684F"]] | OBSERVED + DECLARED |
| `entities[].colors[]` | `entities[].colors[]` | string / declared `array` | False | True | required-by-observation | 0 / 177 | [] | False | — | — | [] | — | ["#181817","#191817","#1C1B19"] | OBSERVED + DECLARED |
| `entities[].core_members` | `entities[]` | array / declared `array` | False | False | optional-by-observation | 51 / 61 | [] | — | — | — | [] | — | [["AUT","HUN"],["CHN"],["COL"]] | OBSERVED + DECLARED |
| `entities[].core_members[]` | `entities[].core_members[]` | string / declared `array` | False | True | required-by-observation | 0 / 11 | [] | True | — | — | ["AUT","CHN","COL","DNK","FRA","GBR","HUN","ITA","JPN","RUS","TUR"] | — | ["AUT","CHN","COL"] | OBSERVED + DECLARED |
| `entities[].detail_mode` | `entities[]` | string / declared `string` | False | True | required-by-observation | 0 / 61 | single | False | — | — | ["france","single","territories"] | — | ["france","single","territories"] | OBSERVED + DECLARED |
| `entities[].id` | `entities[]` | string / declared `boolean,string` | False | True | required-by-observation | 0 / 61 | — | True | primary_candidate | — | [] | — | ["arabian_polities","argentina_1900","austria_hungary"] | OBSERVED + DECLARED |
| `entities[].label_rank` | `entities[]` | number / declared `integer` | False | True | required-by-observation | 0 / 61 | 9 | False | — | — | [] | 1.0–5.0 | [1,2,3] | OBSERVED + DECLARED |
| `entities[].members` | `entities[]` | array / declared `array` | False | True | required-by-observation | 0 / 61 | [] | — | — | — | [] | — | [["AFG"],["AGO","MOZ","GNB","TLS"],["ARG"]] | OBSERVED + DECLARED |
| `entities[].members[]` | `entities[].members[]` | string / declared `array` | False | True | required-by-observation | 0 / 168 | [] | True | — | — | [] | — | ["AFG","AGO","ALB"] | OBSERVED + DECLARED |
| `entities[].name_zh` | `entities[]` | string / declared `string` | False | True | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["不丹王国","丹麦王国","乌拉圭东岸共和国"] | OBSERVED + DECLARED |
| `entities[].pattern` | `entities[]` | string / declared `string` | False | True | required-by-observation | 0 / 61 | solid | False | — | — | ["canton","cross","diagonal","disc","horizontal","quartered","solid","vertical"] | — | ["canton","cross","diagonal"] | OBSERVED + DECLARED |
| `entities[].short_name_zh` | `entities[]` | string / declared `string` | False | True | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["不丹","丹麦","乌拉圭"] | OBSERVED + DECLARED |
| `entities[].sovereign_id` | `entities[]` | string / declared `string` | False | False | optional-by-observation | 53 / 61 | — | True | reference_candidate | — | ["british_isles_1900","country_fra","german_empire","kingdom_of_belgium","kingdom_of_netherlands","kingdom_of_portugal","kingdom_of_spain","united_states_1900"] | — | ["british_isles_1900","country_fra","german_empire"] | OBSERVED + DECLARED |
| `entities[].status` | `entities[]` | string / declared `string` | False | True | required-by-observation | 0 / 61 | sovereign | False | — | — | ["autonomous","contested","dependency","empire","fragmented","personal_union","sovereign"] | — | ["autonomous","contested","dependency"] | OBSERVED + DECLARED |
| `fallback_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["未被明确映射的现代多边形会保留为低优先级‘待校订领土’，仅在高倍率显示，不宣称其为1900独立国家。"] | — | ["未被明确映射的现代多边形会保留为低优先级‘待校订领土’，仅在高倍率显示，不宣称其为1900独立国家。"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `year` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1900.0–1900.0 | [1900] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
