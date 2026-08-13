# world_map.historical.cshapes_1900_snapshot

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

1900 CShapes historical political geometry snapshot.

- Path: `data/world_map/historical/cshapes_1900_snapshot.json`
- Source files: `1`
- Record count (primary collection): `151`
- Documents: `1`
- Root type: `object`
- Primary record path: `features[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `features[]` | 151 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `feature_count` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 151.0–151.0 | [151] | OBSERVED |
| `features` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"area_km2":"<nested>","capital":"<nested>","geometry":"<nested>","gwcode":"<nested>","id":"<nested>","source_name":"<nested>"},{"area_km2":"<nested>","capital":"<nested>","ge... | OBSERVED |
| `features[]` | `features[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | — | — | — | [] | — | [{"area_km2":10088.9,"capital":{"lat":"<nested>","lon":"<nested>","name":"<nested>"},"geometry":{"coordinates":"<nested>","type":"<nested>"},"gwcode":3462,"id":"gw_3462","source... | OBSERVED |
| `features[].area_km2` | `features[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | True | — | — | [] | 33.62–22016200.0 | [10088.9,101600.0,102889.0] | OBSERVED |
| `features[].capital` | `features[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | — | — | — | [] | — | [{"lat":-0.21667,"lon":-78.5,"name":"Quito"},{"lat":-12.05,"lon":-77.05,"name":"Lima"},{"lat":-13.65,"lon":32.6333,"name":"Chipata (Fort Jameson)"}] | OBSERVED |
| `features[].capital.lat` | `features[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | False | — | — | [] | -42.85–64.15 | [-0.21667,-12.05,-13.65] | OBSERVED |
| `features[].capital.lon` | `features[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | True | — | — | [] | -157.856–178.43 | [-0.11667,-0.21667,-10.8047] | OBSERVED |
| `features[].capital.name` | `features[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | True | — | — | [] | — | ["Abu Dhabi","Accra","Addis Ababa"] | OBSERVED |
| `features[].geometry` | `features[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | — | — | — | [] | — | [{"coordinates":["<nested>","<nested>","<nested>","<nested>"],"type":"MultiPolygon"},{"coordinates":["<nested>","<nested>","<nested>"],"type":"MultiPolygon"},{"coordinates":["<n... | OBSERVED |
| `features[].geometry.coordinates` | `features[]` | type-conditioned geometry coordinates / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"]],[["<nested>"],["<nested>"],["<nested>","<nested>"]],[["<nested>"],["<nested>"],["<nested>"],["<nested>","<nested>"]]] | OBSERVED |
| `features[].geometry.coordinates[]` | `features[].geometry.coordinates[]` | type-conditioned geometry coordinates / declared `—` | False | True | False | False | required-by-observation | 0 / 1604 | null | — | — | — | [] | — | [[["<nested>","<nested>","<nested>","<nested>"],["<nested>","<nested>","<nested>","<nested>"]],[["<nested>","<nested>","<nested>","<nested>"]],[["<nested>","<nested>"],["<nested... | OBSERVED |
| `features[].geometry.coordinates[][]` | `features[].geometry.coordinates[][]` | type-conditioned geometry coordinates / declared `—` | False | True | False | False | required-by-observation | 0 / 4797 | null | — | — | — | [] | — | [[-0.0,9.275],[-0.0444,11.1018],[-0.0522,35.8061]] | OBSERVED |
| `features[].geometry.coordinates[][][]` | `features[].geometry.coordinates[][][]` | type-conditioned geometry coordinates / declared `—` | False | True | False | False | required-by-observation | 0 / 29190 | null | False | — | — | [] | -92.2189–153.606 | [-0.0,-0.0444,-0.0522] | OBSERVED |
| `features[].geometry.coordinates[][][][]` | `features[].geometry.coordinates[][][][]` | type-conditioned geometry coordinates / declared `—` | False | True | False | False | required-by-observation | 0 / 45332 | null | False | — | — | [] | -180.0–180.0 | [-0.0051,-0.007,-0.0112] | OBSERVED |
| `features[].geometry.type` | `features[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | False | — | — | ["MultiPolygon","Polygon"] | — | ["MultiPolygon","Polygon"] | OBSERVED |
| `features[].gwcode` | `features[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | True | — | — | [] | 2.0–7030.0 | [100,101,110] | OBSERVED |
| `features[].id` | `features[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | True | primary_candidate | — | [] | — | ["gw_100","gw_101","gw_110"] | OBSERVED |
| `features[].source_name` | `features[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | True | — | — | [] | — | ["Afghanistan","Alaska","Algeria"] | OBSERVED |
| `features[].valid_from` | `features[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | False | — | — | [] | — | ["1886-01-01","1886-05-12","1886-12-30"] | OBSERVED |
| `features[].valid_to` | `features[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 151 | null | False | — | — | [] | — | ["1900-06-26","1900-09-04","1900-11-14"] | OBSERVED |
| `provider` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["cshapes_2_0"] | — | ["cshapes_2_0"] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `snapshot_date` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["1900-03-12"] | — | ["1900-03-12"] | OBSERVED |
| `source` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"citation":"Schvitz et al. (2022), Mapping the International System, 1886-2019: The CShapes 2.0 Dataset","commercial_use_allowed":false,"dataset":"CShapes 2.0","download_url":... | OBSERVED |
| `source.citation` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["Schvitz et al. (2022), Mapping the International System, 1886-2019: The CShapes 2.0 Dataset"] | — | ["Schvitz et al. (2022), Mapping the International System, 1886-2019: The CShapes 2.0 Dataset"] | OBSERVED |
| `source.commercial_use_allowed` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [false] | OBSERVED |
| `source.dataset` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["CShapes 2.0"] | — | ["CShapes 2.0"] | OBSERVED |
| `source.download_url` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["https://icr.ethz.ch/data/cshapes/CShapes-2.0.geojson"] | — | ["https://icr.ethz.ch/data/cshapes/CShapes-2.0.geojson"] | OBSERVED |
| `source.license` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["CC BY-NC-SA 4.0"] | — | ["CC BY-NC-SA 4.0"] | OBSERVED |
| `source.selection_rule` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["gwsdate <= 1900-03-12 <= gwedate"] | — | ["gwsdate <= 1900-03-12 <= gwedate"] | OBSERVED |
| `source.simplify_tolerance_degrees` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.08–0.08 | [0.08] | OBSERVED |
| `source.source_page` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["https://icr.ethz.ch/data/cshapes/"] | — | ["https://icr.ethz.ch/data/cshapes/"] | OBSERVED |
| `source.source_sha256` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["384b1ea90b9419f30a858d7ec237c85a22c60d1b35b5f85f215a1204f9989d42"] | — | ["384b1ea90b9419f30a858d7ec237c85a22c60d1b35b5f85f215a1204f9989d42"] | OBSERVED |
| `source.version` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["2.0"] | — | ["2.0"] | OBSERVED |

## Geometry evidence

- `MultiPolygon`: `80` records; shapes `array[array[array[array[number]]]]`; malformed `0`.
- `Polygon`: `71` records; shapes `array[array[array[number]]]`; malformed `0`.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
