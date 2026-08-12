# world_map.name_pool_fr

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

French name-pool entries with culture, gender, class, and region tags.

- Path: `data/world_map/name_pool_fr.json`
- Source files: `1`
- Record count (primary collection): `28`
- Documents: `1`
- Root type: `object`
- Primary record path: `given_names[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `family_names[]` | 34 | 1 |
| `given_names[]` | 28 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `culture_id` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["fra"] | — | ["fra"] | OBSERVED |
| `family_names` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"class_tags":"<nested>","culture_id":"<nested>","display_family_name_zh":"<nested>","gender":"<nested>","native_family_name":"<nested>","region_tags":"<nested>"},{"class_tags... | OBSERVED |
| `family_names[]` | `family_names[]` | object / declared `—` | False | True | required-by-observation | 0 / 34 | null | — | — | — | [] | — | [{"class_tags":["<nested>","<nested>"],"culture_id":"fra","display_family_name_zh":"加尼耶","gender":"any","native_family_name":"Garnier","region_tags":["<nested>"]},{"class_tags":... | OBSERVED |
| `family_names[].class_tags` | `family_names[]` | array / declared `—` | False | True | required-by-observation | 0 / 34 | null | — | — | — | [] | — | [["artisan","worker"],["civil_service","clerk"],["civil_service","commerce"]] | OBSERVED |
| `family_names[].class_tags[]` | `family_names[].class_tags[]` | string / declared `—` | False | True | required-by-observation | 0 / 66 | null | False | — | — | ["artisan","civil_service","clerk","commerce","cooperative","health","middle_class","rail","teacher","union","worker"] | — | ["artisan","civil_service","clerk"] | OBSERVED |
| `family_names[].culture_id` | `family_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 34 | null | False | — | — | ["fra"] | — | ["fra"] | OBSERVED |
| `family_names[].display_family_name_zh` | `family_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 34 | null | True | — | — | [] | — | ["加尼耶","勒格朗","勒诺"] | OBSERVED |
| `family_names[].gender` | `family_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 34 | null | False | — | — | ["any"] | — | ["any"] | OBSERVED |
| `family_names[].native_family_name` | `family_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 34 | null | True | — | — | [] | — | ["André","Bernard","Bertrand"] | OBSERVED |
| `family_names[].region_tags` | `family_names[]` | array / declared `—` | False | True | required-by-observation | 0 / 34 | null | — | — | — | [] | — | [["all"],["nord"]] | OBSERVED |
| `family_names[].region_tags[]` | `family_names[].region_tags[]` | string / declared `—` | False | True | required-by-observation | 0 / 34 | null | False | — | — | ["all","nord"] | — | ["all","nord"] | OBSERVED |
| `given_names` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"class_tags":"<nested>","culture_id":"<nested>","display_given_name_zh":"<nested>","gender":"<nested>","native_given_name":"<nested>","region_tags":"<nested>"},{"class_tags":... | OBSERVED |
| `given_names[]` | `given_names[]` | object / declared `—` | False | True | required-by-observation | 0 / 28 | null | — | — | — | [] | — | [{"class_tags":["<nested>","<nested>"],"culture_id":"fra","display_given_name_zh":"乔治","gender":"male","native_given_name":"Georges","region_tags":["<nested>"]},{"class_tags":["... | OBSERVED |
| `given_names[].class_tags` | `given_names[]` | array / declared `—` | False | True | required-by-observation | 0 / 28 | null | — | — | — | [] | — | [["artisan","commerce"],["artisan","teacher"],["civil_service","middle_class"]] | OBSERVED |
| `given_names[].class_tags[]` | `given_names[].class_tags[]` | string / declared `—` | False | True | required-by-observation | 0 / 56 | null | False | — | — | ["artisan","civil_service","clerk","commerce","cooperative","dock","health","middle_class","rail","teacher","textile","union","worker"] | — | ["artisan","civil_service","clerk"] | OBSERVED |
| `given_names[].culture_id` | `given_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 28 | null | False | — | — | ["fra"] | — | ["fra"] | OBSERVED |
| `given_names[].display_given_name_zh` | `given_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 28 | null | True | — | — | ["乔治","亨利","伊冯娜","保罗","克莱尔","勒内","卡米耶","叙赞娜","吕西","吕西安","埃米尔","埃莉斯","埃莱娜","夏尔","奥古斯特","安德烈","朱尔","波利娜","热尔梅娜","玛丽","玛格丽特","皮埃尔","让娜","路易","路易丝","阿尔贝","马塞尔","马德莱娜"] | — | ["乔治","亨利","伊冯娜"] | OBSERVED |
| `given_names[].gender` | `given_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 28 | null | False | — | — | ["female","male"] | — | ["female","male"] | OBSERVED |
| `given_names[].native_given_name` | `given_names[]` | string / declared `—` | False | True | required-by-observation | 0 / 28 | null | True | — | — | ["Albert","André","Auguste","Camille","Charles","Claire","Georges","Germaine","Henri","Hélène","Jeanne","Jules","Louis","Louise","Lucie","Lucien","Madeleine","Marcel","Marguerit... | — | ["Albert","André","Auguste"] | OBSERVED |
| `given_names[].region_tags` | `given_names[]` | array / declared `—` | False | True | required-by-observation | 0 / 28 | null | — | — | — | [] | — | [["nord","paris"],["nord"],["normandy","nord"]] | OBSERVED |
| `given_names[].region_tags[]` | `given_names[].region_tags[]` | string / declared `—` | False | True | required-by-observation | 0 / 33 | null | False | — | — | ["nord","normandy","paris"] | — | ["nord","normandy","paris"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `scope_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["原型专用常见姓名组合，不代表真实历史人物或完整人口分布。"] | — | ["原型专用常见姓名组合，不代表真实历史人物或完整人口分布。"] | OBSERVED |
| `source_id` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["prototype_v2_fr_pool"] | — | ["prototype_v2_fr_pool"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
