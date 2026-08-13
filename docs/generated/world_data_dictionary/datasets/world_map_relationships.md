# world_map.relationships

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Prototype persistent relationship display records and relationship actions.

- Path: `data/world_map/relationships.json`
- Source files: `1`
- Record count (primary collection): `10`
- Documents: `1`
- Root type: `object`
- Primary record path: `relationships[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `relationships[]` | 10 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `relationships` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"affinity":"<nested>","available_relationship_actions":"<nested>","category":"<nested>","city_id":"<nested>","common":"<nested>","common_contacts":"<nested>"},{"category":"<n... | OBSERVED |
| `relationships[]` | `relationships[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | — | — | — | [] | — | [{"affinity":"友好","available_relationship_actions":["<nested>","<nested>","<nested>","<nested>"],"category":"亲近关系","city_id":"lille","common":"共同联系人 2 人","common_contacts":"共同联系... | OBSERVED |
| `relationships[].affinity` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["友好"] | — | ["友好"] | OBSERVED |
| `relationships[].available_relationship_actions` | `relationships[]` | array / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | — | — | — | [] | — | [["联系","请求帮助","引荐","调查"]] | OBSERVED |
| `relationships[].available_relationship_actions[]` | `relationships[].available_relationship_actions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 5 | null | True | — | — | ["引荐","查看共同关系","联系","请求帮助","调查"] | — | ["引荐","查看共同关系","联系"] | OBSERVED |
| `relationships[].category` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["亲近关系","公开人物","可经引荐接触","普通熟人","经常接触"] | — | ["亲近关系","公开人物","可经引荐接触"] | OBSERVED |
| `relationships[].city_id` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["lille"] | — | ["lille"] | OBSERVED |
| `relationships[].common` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["共同联系人 1 人","共同联系人 2 人","共同联系人 3 人","共同联系人 4 人","可由公共工程处主任引荐","可由夜校教师引荐","可由让娜引荐","可经工会书记引荐","无直接共同关系"] | — | ["共同联系人 1 人","共同联系人 2 人","共同联系人 3 人"] | OBSERVED |
| `relationships[].common_contacts` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["共同联系人 2 人"] | — | ["共同联系人 2 人"] | OBSERVED |
| `relationships[].common_organizations` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["北部省金属工人工会"] | — | ["北部省金属工人工会"] | OBSERVED |
| `relationships[].common_work` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["里尔机械制造公司第三车间"] | — | ["里尔机械制造公司第三车间"] | OBSERVED |
| `relationships[].contact` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["公开但不可直接联系","只能通过机构渠道","同一工作地点","电车约 25 分钟","通过合作社公开窗口","通过工会联系","里尔市内可达","需要引荐","需要正式渠道"] | — | ["公开但不可直接联系","只能通过机构渠道","同一工作地点"] | OBSERVED |
| `relationships[].culture_id` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["fra"] | — | ["fra"] | OBSERVED |
| `relationships[].display_name_zh` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | — | — | ["克莱尔·勒诺","勒内·博内","埃莉斯·富尼耶","埃莱娜·福尔","朱尔·马丁","波利娜·梅西耶","玛丽·贝尔纳","让娜·勒鲁瓦","路易·莫罗","马塞尔·德洛姆"] | — | ["克莱尔·勒诺","勒内·博内","埃莉斯·富尼耶"] | OBSERVED |
| `relationships[].employer_id` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 8 / 10 | null | False | reference_candidate | — | ["enterprise_lille_mechanical"] | — | ["enterprise_lille_mechanical"] | OBSERVED |
| `relationships[].familiarity` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["熟悉 · 经常见面"] | — | ["熟悉 · 经常见面"] | OBSERVED |
| `relationships[].id` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | primary_candidate | — | ["claire","elise","helene","jeanne","jules","louis","marcel","marie","pauline","rene"] | — | ["claire","elise","helene"] | OBSERVED |
| `relationships[].institution_id` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 8 / 10 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.institutions | ["mairie_lille"] | — | ["mairie_lille"] | OBSERVED |
| `relationships[].last_interaction` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["2 个月前","3 天前","5 个月前","今天 · 讨论夜班安排","从未直接互动"] | — | ["2 个月前","3 天前","5 个月前"] | OBSERVED |
| `relationships[].migration_background` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["none"] | — | ["none"] | OBSERVED |
| `relationships[].name` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | — | — | ["克莱尔·勒诺","勒内·博内","埃莉斯·富尼耶","埃莱娜·福尔","朱尔·马丁","波利娜·梅西耶","玛丽·贝尔纳","让娜·勒鲁瓦","路易·莫罗","马塞尔·德洛姆"] | — | ["克莱尔·勒诺","勒内·博内","埃莉斯·富尼耶"] | OBSERVED |
| `relationships[].name_source` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["prototype_v2_fr_pool"] | — | ["prototype_v2_fr_pool"] | OBSERVED |
| `relationships[].nationality_id` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | reference_candidate | — | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `relationships[].native_name` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | — | — | ["Claire Renaud","Hélène Faure","Jeanne Leroy","Jules Martin","Louis Moreau","Marcel Delorme","Marie Bernard","Pauline Mercier","René Bonnet","Élise Fournier"] | — | ["Claire Renaud","Hélène Faure","Jeanne Leroy"] | OBSERVED |
| `relationships[].obligations` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["曾代换一次轮班；可请求一次工作引荐"] | — | ["曾代换一次轮班；可请求一次工作引荐"] | OBSERVED |
| `relationships[].occupation` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | — | — | ["《里尔公报》编辑","仓库记账员","公共卫生医师","合作社记账员","夜校教师","工会分会书记","机械质检员","车床工","里尔市议员","铁路调度文员"] | — | ["《里尔公报》编辑","仓库记账员","公共卫生医师"] | OBSERVED |
| `relationships[].organization_id` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 6 / 10 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.organizations | ["committee_paris_lille_rail","coop_lille_workers_consumption","school_lille_workers_evening","union_metalworkers_nord"] | — | ["committee_paris_lille_rail","coop_lille_workers_consumption","school_lille_workers_evening"] | OBSERVED |
| `relationships[].region` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["里尔 · 北部工业带"] | — | ["里尔 · 北部工业带"] | OBSERVED |
| `relationships[].region_id` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.regions | ["northern_industrial_belt"] | — | ["northern_industrial_belt"] | OBSERVED |
| `relationships[].relation` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | ["仅有公开认知","友好的邻居","可信赖的同事","尊敬的老师","尚未直接认识","工作关系良好","曾在公开会议交谈","谨慎的组织关系"] | — | ["仅有公开认知","友好的邻居","可信赖的同事"] | OBSERVED |
| `relationships[].relation_type` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["同事与朋友"] | — | ["同事与朋友"] | OBSERVED |
| `relationships[].status` | `relationships[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | — | — | ["公开参与工厂卫生调查","公开支持工厂安全检查","公开支持工厂检查","关注铁路与劳工议题","参与合作社食品采购","参与铁路运输协调文书","收入似乎稳定","正在准备工资谈判","正在照料母亲","近期课程繁忙"] | — | ["公开参与工厂卫生调查","公开支持工厂安全检查","公开支持工厂检查"] | OBSERVED |
| `relationships[].trust` | `relationships[]` | string / declared `—` | False | False | False | False | optional-by-observation | 9 / 10 | null | True | — | — | ["较高 · 愿意交换工作消息"] | — | ["较高 · 愿意交换工作消息"] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 2.0–2.0 | [2] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
