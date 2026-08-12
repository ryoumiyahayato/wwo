# world_map.institutions

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Institution nodes, hierarchy, permissions, and public/worker display definitions.

- Path: `data/world_map/institutions.json`
- Source files: `1`
- Record count (primary collection): `7`
- Documents: `1`
- Root type: `object`
- Primary record path: `institutions[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `institutions[]` | 7 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `country` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"display_name_zh":"法兰西共和国","emblem_type":"french_tricolor_rf","formal_name_zh":"法兰西第三共和国","government_name":"第三共和国","id":"country_fra","native_name":"République française"}] | OBSERVED |
| `country.display_name_zh` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["法兰西共和国"] | — | ["法兰西共和国"] | OBSERVED |
| `country.emblem_type` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["french_tricolor_rf"] | — | ["french_tricolor_rf"] | OBSERVED |
| `country.formal_name_zh` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["法兰西第三共和国"] | — | ["法兰西第三共和国"] | OBSERVED |
| `country.government_name` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["第三共和国"] | — | ["第三共和国"] | OBSERVED |
| `country.id` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | primary_candidate | — | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `country.native_name` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["République française"] | — | ["République française"] | OBSERVED |
| `country.news` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["《里尔公报》· 静态原型条目"] | — | ["《里尔公报》· 静态原型条目"] | OBSERVED |
| `country.prototype_status` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["静态制度语义原型"] | — | ["静态制度语义原型"] | OBSERVED |
| `country.public_organizations` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["北部省劳动监察处","里尔市政厅"]] | OBSERVED |
| `country.public_organizations[]` | `country.public_organizations[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["北部省劳动监察处","里尔市政厅"] | — | ["北部省劳动监察处","里尔市政厅"] | OBSERVED |
| `country.public_policy` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["原型议程：工厂安全检查公告"] | — | ["原型议程：工厂安全检查公告"] | OBSERVED |
| `institutions` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"administrative_level":"<nested>","administrative_unit_id":"<nested>","agenda":"<nested>","authority_source":"<nested>","budget_source":"<nested>","child_institution_ids":"<n... | OBSERVED |
| `institutions[]` | `institutions[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"administrative_level":"arrondissement","administrative_unit_id":"arrondissement_lille","agenda":"汇总区内铁路运输影响报告","authority_source":"区级行政职位与省政府授权程序","budget_source":"北部省省政府区级行政... | OBSERVED |
| `institutions[].administrative_level` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["arrondissement","commune","departement","national"] | — | ["arrondissement","commune","departement"] | OBSERVED |
| `institutions[].administrative_unit_id` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | reference_candidate | — | ["arrondissement_lille","commune_lille","commune_marseille_placeholder","country_fra","departement_nord","departement_seine_inferieure_placeholder"] | — | ["arrondissement_lille","commune_lille","commune_marseille_placeholder"] | OBSERVED |
| `institutions[].agenda` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["协调巴黎—里尔铁路运输延误","安排里尔机械企业安全检查原型条目","整理东部泊位扩充原型议程","整理塞纳河口货运报告","整理工厂安全检查的市政配合事项","汇总区内铁路运输影响报告","铁路支出与工厂安全议题的静态占位"] | — | ["协调巴黎—里尔铁路运输延误","安排里尔机械企业安全检查原型条目","整理东部泊位扩充原型议程"] | OBSERVED |
| `institutions[].authority_source` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["劳动监察职务与检查程序","区级行政职位与省政府授权程序","宪制与议会程序","市镇职务与市议会程序","港务行政程序","省级行政职位","省级行政职位与法定行政程序"] | — | ["劳动监察职务与检查程序","区级行政职位与省政府授权程序","宪制与议会程序"] | OBSERVED |
| `institutions[].budget_source` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["中央劳动事务预算的省级执行款","北部省省政府区级行政拨款","国家预算","国家预算省级拨款与依法核定的地方款项","港务费与中央补助","省级行政拨款","里尔市镇预算与依法核定的补助"] | — | ["中央劳动事务预算的省级执行款","北部省省政府区级行政拨款","国家预算"] | OBSERVED |
| `institutions[].child_institution_ids` | `institutions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | reference_candidate | — | [] | — | [["mairie_lille"],["sous_prefecture_lille"],[]] | OBSERVED |
| `institutions[].child_institution_ids[]` | `institutions[].child_institution_ids[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | reference_candidate | — | ["mairie_lille","sous_prefecture_lille"] | — | ["mairie_lille","sous_prefecture_lille"] | OBSERVED |
| `institutions[].city_id` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["lille","marseille","paris","rouen"] | — | ["lille","marseille","paris"] | OBSERVED |
| `institutions[].collaboration_units` | `institutions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [["勒阿弗尔港务机构"],["北部省省政府","北部省劳动监察处"],["北部省省政府","里尔市政厅","工厂安全委员会"]] | OBSERVED |
| `institutions[].collaboration_units[]` | `institutions[].collaboration_units[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 14 | null | False | — | — | ["勒阿弗尔港务机构","北部省劳动监察处","北部省省政府","工厂安全委员会","巴黎—里尔铁路协调委员会","市政卫生事务处","海关","议会委员会","里尔市政厅"] | — | ["勒阿弗尔港务机构","北部省劳动监察处","北部省省政府"] | OBSERVED |
| `institutions[].department` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["公共工程处","劳动监察处","市政书记处","港务处","行政书记处","议会"] | — | ["公共工程处","劳动监察处","市政书记处"] | OBSERVED |
| `institutions[].departments` | `institutions[]` | array / declared `—` | False | False | False | False | optional-by-observation | 6 / 7 | null | — | — | — | [] | — | [["公共工程处","劳动监察处","卫生事务处","财政事务处"]] | OBSERVED |
| `institutions[].departments[]` | `institutions[].departments[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | — | — | ["公共工程处","劳动监察处","卫生事务处","财政事务处"] | — | ["公共工程处","劳动监察处","卫生事务处"] | OBSERVED |
| `institutions[].id` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | primary_candidate | — | ["labor_inspectorate_nord","mairie_lille","marseille_port_authority","national_assembly","prefecture_nord","prefecture_seine_inferieure","sous_prefecture_lille"] | — | ["labor_inspectorate_nord","mairie_lille","marseille_port_authority"] | OBSERVED |
| `institutions[].institution_kind` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["labor_inspectorate","mairie","national_legislature","port_authority","prefecture","sous_prefecture"] | — | ["labor_inspectorate","mairie","national_legislature"] | OBSERVED |
| `institutions[].jurisdiction` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["全国","北部省","塞纳-下游省（主题占位）","里尔区","里尔市","马赛港区"] | — | ["全国","北部省","塞纳-下游省（主题占位）"] | OBSERVED |
| `institutions[].label_priority` | `institutions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 68.0–100.0 | [100,68,72] | OBSERVED |
| `institutions[].lon_lat` | `institutions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [[1.11,49.44],[2.3186,48.8619],[3.052,50.635]] | OBSERVED |
| `institutions[].lon_lat[]` | `institutions[].lon_lat[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 14 | null | True | — | — | [] | 1.11–50.637 | [1.11,2.3186,3.052] | OBSERVED |
| `institutions[].mandate` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["办理市镇公共服务与市政议程","地方交通与港口协调","执行省级行政事务并协调市镇公共工程","承接省级行政程序并协调区内市镇","检查工厂安全与劳动条件","港口调度与检疫","立法与预算审议"] | — | ["办理市镇公共服务与市政议程","地方交通与港口协调","执行省级行政事务并协调市镇公共工程"] | OBSERVED |
| `institutions[].max_zoom` | `institutions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED |
| `institutions[].min_zoom` | `institutions[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | 6.4–7.4 | [6.4,6.8,7.0] | OBSERVED |
| `institutions[].name` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["众议院","北部省劳动监察处","北部省省政府","塞纳-下游省省政府","里尔区副省长公署","里尔市政厅","马赛港务机构"] | — | ["众议院","北部省劳动监察处","北部省省政府"] | OBSERVED |
| `institutions[].native_name` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["Administration du port de Marseille","Chambre des députés","Inspection du travail du Nord","Mairie de Lille","Préfecture de la Seine-Inférieure","Préfecture du Nord","Sous-pré... | — | ["Administration du port de Marseille","Chambre des députés","Inspection du travail du Nord"] | OBSERVED |
| `institutions[].object_level` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["institution"] | — | ["institution"] | OBSERVED |
| `institutions[].official_view` | `institutions[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"precision":"公开议程与行政通报","primary_action":"提交行政报告","summary":"需要中央部门批准；当前只能提交行政报告","visibility":"known_locked"},{"precision":"区级协调摘要","primary_action":"请求区级协作","summary":"可查阅里尔... | OBSERVED |
| `institutions[].official_view.precision` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["公开议程与行政通报","区级协调摘要","协作事项","执行进度","跨省摘要","部门、辖区与预算来源"] | — | ["公开议程与行政通报","区级协调摘要","协作事项"] | OBSERVED |
| `institutions[].official_view.primary_action` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["处理当前议程","提交行政报告","请求区级协作","请求协作","请求协查","请求市政协作","请求跨省协作"] | — | ["处理当前议程","提交行政报告","请求区级协作"] | OBSERVED |
| `institutions[].official_view.summary` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["不在当前职责范围；可请求跨省协作","可协查执行进度；当前不可访问内部预算","可提交处内议程、协调项目并查阅公共工程处预算","可查看与公共工程处相关的市政协作事项","可查看跨省协调摘要","可查阅里尔区提交的运输影响报告","需要中央部门批准；当前只能提交行政报告"] | — | ["不在当前职责范围；可请求跨省协作","可协查执行进度；当前不可访问内部预算","可提交处内议程、协调项目并查阅公共工程处预算"] | OBSERVED |
| `institutions[].official_view.visibility` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["internal","known_locked","operable"] | — | ["internal","known_locked","operable"] | OBSERVED |
| `institutions[].parent_country_id` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.countries | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `institutions[].parent_institution` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["","内政部（主题占位）","北部省省政府","商务、工业、邮电部劳动事务体系（主题占位）","商务与海运主管机关（主题占位）","里尔区副省长公署"] | — | ["","内政部（主题占位）","北部省省政府"] | OBSERVED |
| `institutions[].parent_institution_id` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | reference_candidate | — | ["","commerce_ministry_placeholder","interior_ministry_placeholder","labor_ministry_placeholder","prefecture_nord","sous_prefecture_lille"] | — | ["","commerce_ministry_placeholder","interior_ministry_placeholder"] | OBSERVED |
| `institutions[].parent_region_id` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.regions | ["mediterranean_coast","normandy","northern_industrial_belt","paris_basin"] | — | ["mediterranean_coast","normandy","northern_industrial_belt"] | OBSERVED |
| `institutions[].procedures` | `institutions[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [["公开辩论","委员会审议"],["市政登记","议程提交","公开公告"],["提交处内事务","跨单位会签","项目执行复核"]] | OBSERVED |
| `institutions[].procedures[]` | `institutions[].procedures[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 16 | null | True | — | — | ["公开公告","公开辩论","委员会审议","市政登记","排期检查","提交处内事务","提交整改通知","提交省政府会签","检疫会签","登记市镇报告","登记投诉","议程提交","货运协调会签","跨单位会签","靠泊许可","项目执行复核"] | — | ["公开公告","公开辩论","委员会审议"] | OBSERVED |
| `institutions[].supervisor` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["北部省劳动监察员","北部省省长","塞纳-下游省省长","港务负责人","议长","里尔区副省长","里尔市长"] | — | ["北部省劳动监察员","北部省省长","塞纳-下游省省长"] | OBSERVED |
| `institutions[].upstream_locked` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["🔒 修改全国劳动规章 · 需要中央部门批准","🔒 全国铁路投资排序 · 仅可按程序上报","🔒 全国铁路调度 · 需要跨部门会签","🔒 国际航运条约","🔒 地方官员无立法表决权 · 当前只能提交建议","🔒 省级行政任命与全国立法 · 需要省长或中央部门批准","🔒 调整省级总预算 · 需要省长授权"] | — | ["🔒 修改全国劳动规章 · 需要中央部门批准","🔒 全国铁路投资排序 · 仅可按程序上报","🔒 全国铁路调度 · 需要跨部门会签"] | OBSERVED |
| `institutions[].worker_view` | `institutions[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"precision":"公开公告","primary_action":"查看公告","summary":"可查看港口与交通公告","visibility":"public"},{"precision":"公开办事程序","primary_action":"查看区级公告","summary":"可查看里尔区公开行政程序","visibility":... | OBSERVED |
| `institutions[].worker_view.precision` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["公开公告","公开办事程序","公开摘要","公开新闻","公开服务","公开船期","公开议程"] | — | ["公开公告","公开办事程序","公开摘要"] | OBSERVED |
| `institutions[].worker_view.primary_action` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["查看公告","查看公开新闻","查看公开检查","查看区级公告","查看市政服务","查看省级公告","查看船期"] | — | ["查看公告","查看公开新闻","查看公开检查"] | OBSERVED |
| `institutions[].worker_view.summary` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["公开服务、办事程序与北部省公告","公开议程、新闻与议员名录","可查看公开船期与招工公告","可查看市政服务、登记与公开公告","可查看检查公告与投诉渠道","可查看港口与交通公告","可查看里尔区公开行政程序"] | — | ["公开服务、办事程序与北部省公告","公开议程、新闻与议员名录","可查看公开船期与招工公告"] | OBSERVED |
| `institutions[].worker_view.visibility` | `institutions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["public"] | — | ["public"] | OBSERVED |
| `official_locks` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["分配北部省总预算：需要省级预算程序权限","任命机构负责人：需要法定任命权","国家政策表决：超出当前职位与辖区"]] | OBSERVED |
| `official_locks[]` | `official_locks[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | ["任命机构负责人：需要法定任命权","分配北部省总预算：需要省级预算程序权限","国家政策表决：超出当前职位与辖区"] | — | ["任命机构负责人：需要法定任命权","分配北部省总预算：需要省级预算程序权限","国家政策表决：超出当前职位与辖区"] | OBSERVED |
| `official_permissions` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["提交公共工程处事务","发起跨单位会签","协调辖区公共项目","查阅本处预算"]] | OBSERVED |
| `official_permissions[]` | `official_permissions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | — | — | ["协调辖区公共项目","发起跨单位会签","提交公共工程处事务","查阅本处预算"] | — | ["协调辖区公共项目","发起跨单位会签","提交公共工程处事务"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 3.0–3.0 | [3] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
