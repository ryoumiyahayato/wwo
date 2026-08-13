# world_map.country_flag_palettes

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Country color palettes used by the map flag/identity presentation.

- Path: `data/world_map/country_flag_palettes.json`
- Source files: `1`
- Record count (primary collection): `57`
- Documents: `1`
- Root type: `object`
- Primary record path: `palettes.<key>`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `palettes.<key>` | 57 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `palettes` | `document` | object / declared `object` | False | True | False | False | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"AFG":{"colors":"<nested>","pattern":"<nested>"},"ARG":{"colors":"<nested>","pattern":"<nested>"},"AUS":{"colors":"<nested>","pattern":"<nested>"},"AUT":{"colors":"<nested>","... | OBSERVED + DECLARED |
| `palettes.<key>` | `palettes.<key>` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 57 | null | — | — | — | [] | — | [{"colors":["<nested>","<nested>","<nested>","<nested>"],"pattern":"quartered"},{"colors":["<nested>","<nested>","<nested>"],"pattern":"canton"},{"colors":["<nested>","<nested>"... | OBSERVED |
| `palettes.<key>.colors` | `palettes.<key>` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 57 | null | — | — | — | [] | — | [["#171717","#EEEAE0","#9E3136"],["#183B70","#EEEDE6","#9A3038"],["#191817","#C8A443","#9A3038"]] | OBSERVED |
| `palettes.<key>.colors[]` | `palettes.<key>.colors[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 159 | null | False | — | — | [] | — | ["#171717","#183B70","#191817"] | OBSERVED |
| `palettes.<key>.pattern` | `palettes.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 57 | null | False | — | — | ["canton","cross","disc","horizontal","quartered","solid","vertical"] | — | ["canton","cross","disc"] | OBSERVED |
| `prototype_notice` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["用于1900主题全息半球的低饱和识别色。复杂纹章仅保留主色结构；未列国家由运行时生成克制的旗帜式回退配色。"] | — | ["用于1900主题全息半球的低饱和识别色。复杂纹章仅保留主色结构；未列国家由运行时生成克制的旗帜式回退配色。"] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
