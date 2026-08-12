# world_map.historical.flags_1900

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

1900 political-unit flag assignment snapshot and policy metadata.

- Path: `data/world_map/historical/flags_1900.json`
- Source files: `1`
- Record count (primary collection): `61`
- Documents: `1`
- Root type: `object`
- Primary record path: `records.<key>`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `records.<key>` | 61 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `policy` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"controller_flag_is_explicitly_labeled":true,"documented_absence_uses_neutral_rendering":true,"random_or_hash_flags_allowed":false,"source_asset_required_for_rendered_flag":tr... | OBSERVED + DECLARED |
| `policy.controller_flag_is_explicitly_labeled` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.documented_absence_uses_neutral_rendering` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `policy.random_or_hash_flags_allowed` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [false] | OBSERVED |
| `policy.source_asset_required_for_rendered_flag` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `record_count` | `document` | number / declared `integer` | False | True | required-by-observation | 0 / 1 | 0 | True | — | — | [] | 61.0–61.0 | [61] | OBSERVED + DECLARED |
| `records` | `document` | object / declared `object` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"afghanistan_1880":{"asset_path":"<nested>","asset_sha256":"<nested>","confidence":"<nested>","flag_type":"<nested>","heraldic_zh":"<nested>","id":"<nested>"},"argentina_1861"... | OBSERVED + DECLARED |
| `records.<key>` | `records.<key>` | object / declared `—` | False | True | required-by-observation | 0 / 61 | null | — | — | — | [] | — | [{"asset_path":"","confidence":"high","flag_type":"documented_absence","heraldic_zh":"1900年不存在可诚实归结为单一标准国旗的旗面；界面显示中性斜线。","id":"no_single_standard_flag","ratio":""},{"asset_path"... | OBSERVED |
| `records.<key>.asset_path` | `records.<key>` | string / declared `string` | False | True | required-by-observation | 0 / 61 | — | True | — | — | [] | — | ["","res://assets/historical_flags/1900/afghanistan_1880.png","res://assets/historical_flags/1900/argentina_1861.png"] | OBSERVED + DECLARED |
| `records.<key>.asset_sha256` | `records.<key>` | string / declared `—` | False | False | optional-by-observation | 1 / 61 | null | True | — | — | [] | — | ["00a120b5dac85258bac909dc8647b6719e04657d3617dfe2f21cb7eaf78e5e00","0c0a127313175483406020a81bcff67b9ab6d29a32af97d106fcc2dfb9d5dce6","0e17e7edcbd97d3dac51f31327b050e90341e779a... | OBSERVED |
| `records.<key>.confidence` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | False | — | — | ["high","low","medium"] | — | ["high","low","medium"] | OBSERVED |
| `records.<key>.flag_type` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | False | — | — | ["civil_ensign_interface_identifier","civil_flag","documented_absence","emirate_flag_reconstruction","khanate_flag_reconstruction","khedival_flag","land_flag","national_flag","n... | — | ["civil_ensign_interface_identifier","civil_flag","documented_absence"] | OBSERVED |
| `records.<key>.heraldic_zh` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["1900年不存在可诚实归结为单一标准国旗的旗面；界面显示中性斜线。","上下叠置双三角旗，深红底蓝边，日月具面部；现代矢量依据历史旗帜资料复原。","九道白蓝横纹，左上白色方区内五月太阳。"] | OBSERVED |
| `records.<key>.id` | `records.<key>` | string / declared `string` | False | True | required-by-observation | 0 / 61 | — | True | semantic_id | — | [] | — | ["afghanistan_1880","argentina_1861","austria_hungary_civil_1869"] | OBSERVED + DECLARED |
| `records.<key>.ratio` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | False | — | — | ["","10:19","13:15","15:22","1:1","1:2","28:37","2:3","3:4","3:5","4:7","5:8","5:9","7:10","9:14","non_rectangular"] | — | ["","10:19","13:15"] | OBSERVED |
| `records.<key>.render_mode` | `records.<key>` | string / declared `string` | False | True | required-by-observation | 0 / 61 | — | False | — | — | ["neutral_hatch","source_asset"] | — | ["neutral_hatch","source_asset"] | OBSERVED + DECLARED |
| `records.<key>.snapshot_date` | `records.<key>` | string / declared `string` | False | False | optional-by-observation | 1 / 61 | — | False | — | — | ["1900-03-12"] | — | ["1900-03-12"] | OBSERVED + DECLARED |
| `records.<key>.source_artist` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | False | — | — | [] | — | ["","(of code) User:Makaristos","B1mbo"] | OBSERVED |
| `records.<key>.source_asset` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["","https://upload.wikimedia.org/wikipedia/commons/1/11/Civil_ensign_of_Austria-Hungary_%281869-1918%29.svg","https://upload.wikimedia.org/wikipedia/commons/1/12/Flag_of_El_Sal... | OBSERVED |
| `records.<key>.source_description` | `records.<key>` | string / declared `—` | False | False | optional-by-observation | 1 / 61 | null | True | — | — | [] | — | ["","Civil Ensign of Austria-Hungary between 1869 and 1918. .mw-parser-output .messagebox{margin:4px 0;width:auto;border-collapse:collapse;border:2px solid var(--border-color-pr... | OBSERVED |
| `records.<key>.source_height` | `records.<key>` | number / declared `—` | False | False | optional-by-observation | 1 / 61 | null | False | — | — | [] | 256.0–3371.0 | [1000,1063,1400] | OBSERVED |
| `records.<key>.source_license` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | False | — | — | ["","CC BY-SA 3.0","CC BY-SA 4.0","CC0","Public domain"] | — | ["","CC BY-SA 3.0","CC BY-SA 4.0"] | OBSERVED |
| `records.<key>.source_mime` | `records.<key>` | string / declared `—` | False | False | optional-by-observation | 1 / 61 | null | False | — | — | ["image/png","image/svg+xml"] | — | ["image/png","image/svg+xml"] | OBSERVED |
| `records.<key>.source_page` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["","https://commons.wikimedia.org/wiki/File:Civil_ensign_of_Austria-Hungary_(1869-1918).svg","https://commons.wikimedia.org/wiki/File:Ecuador_(1860-1900).png"] | OBSERVED |
| `records.<key>.source_rendered_png` | `records.<key>` | string / declared `—` | False | False | optional-by-observation | 1 / 61 | null | True | — | — | [] | — | ["https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/Civil_ensign_of_Austria-Hungary_%281869-1918%29.svg/960px-Civil_ensign_of_Austria-Hungary_%281869-1918%29.svg.png","h... | OBSERVED |
| `records.<key>.source_sha1` | `records.<key>` | string / declared `—` | False | False | optional-by-observation | 1 / 61 | null | True | — | — | [] | — | ["032e27bda4cb886bb6080f293d77f51a0eb9fa19","0997787cecec903a557ce84d33e63acd8703e435","0bcc922cc3305450c34a0e13238c7f03d16fd6f4"] | OBSERVED |
| `records.<key>.source_title` | `records.<key>` | string / declared `—` | False | True | required-by-observation | 0 / 61 | null | True | — | — | [] | — | ["","File:Civil ensign of Austria-Hungary (1869-1918).svg","File:Ecuador (1860-1900).png"] | OBSERVED |
| `records.<key>.source_usage_terms` | `records.<key>` | string / declared `—` | False | False | optional-by-observation | 1 / 61 | null | False | — | — | ["Creative Commons Attribution-Share Alike 3.0","Creative Commons Attribution-Share Alike 4.0","Creative Commons Zero, Public Domain Dedication","Public domain"] | — | ["Creative Commons Attribution-Share Alike 3.0","Creative Commons Attribution-Share Alike 4.0","Creative Commons Zero, Public Domain Dedication"] | OBSERVED |
| `records.<key>.source_width` | `records.<key>` | number / declared `—` | False | False | optional-by-observation | 1 / 61 | null | False | — | — | [] | 400.0–6055.0 | [1000,1100,1116] | OBSERVED |
| `records.<key>.valid_from` | `records.<key>` | string / declared `string` | False | True | required-by-observation | 0 / 61 | — | False | — | — | [] | — | ["","1625-01-01","1650-01-01"] | OBSERVED + DECLARED |
| `records.<key>.valid_to` | `records.<key>` | string / declared `string` | False | True | required-by-observation | 0 / 61 | — | False | — | — | [] | — | ["","1900-10-31","1901-01-01"] | OBSERVED + DECLARED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `snapshot_date` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | — | — | ["1900-03-12"] | — | ["1900-03-12"] | OBSERVED + DECLARED |
| `unit_flag_mode_counts` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"controller_identification_flag":85,"documented_absence":6,"local_historical_flag":60}] | OBSERVED |
| `unit_flag_mode_counts.controller_identification_flag` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 85.0–85.0 | [85] | OBSERVED |
| `unit_flag_mode_counts.documented_absence` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | 0 | True | — | — | [] | 6.0–6.0 | [6] | OBSERVED + DECLARED |
| `unit_flag_mode_counts.local_historical_flag` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 60.0–60.0 | [60] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
