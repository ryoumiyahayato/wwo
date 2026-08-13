# world_map.city_detail.LICENSE

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Attribution and license metadata for the city-detail source dataset.

- Path: `data/world_map/city_detail/LICENSE.json`
- Source files: `1`
- Record count (primary collection): `1`
- Documents: `1`
- Root type: `object`
- Primary record path: `document`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `document` | 1 per source document | — |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `attribution` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["Contains GeoNames geographical data, licensed under CC BY 4.0."] | — | ["Contains GeoNames geographical data, licensed under CC BY 4.0."] | OBSERVED |
| `dataset` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["modern_city_detail"] | — | ["modern_city_detail"] | OBSERVED |
| `license` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["Creative Commons Attribution 4.0"] | — | ["Creative Commons Attribution 4.0"] | OBSERVED |
| `license_url` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["https://creativecommons.org/licenses/by/4.0/"] | — | ["https://creativecommons.org/licenses/by/4.0/"] | OBSERVED |
| `source` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["GeoNames"] | — | ["GeoNames"] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
