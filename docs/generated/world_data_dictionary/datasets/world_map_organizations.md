# world_map.organizations

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Organization catalog and worker/official identity interaction definitions.

- Path: `data/world_map/organizations.json`
- Source files: `1`
- Record count (primary collection): `11`
- Documents: `1`
- Root type: `object`
- Primary record path: `catalog[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `catalog[]` | 11 | 1 |
| `identities.<key>` | 2 | 1 |
| `identities.<key>.discover[]` | 6 | 1 |
| `identities.<key>.owned[]` | 4 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `catalog` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"city_id":"<nested>","country_id":"<nested>","emblem":"<nested>","fictional_but_culturally_consistent":"<nested>","id":"<nested>","industry_id":"<nested>"},{"city_id":"<neste... | OBSERVED + DECLARED |
| `catalog[]` | `catalog[]` | object / declared `—` | False | True | required-by-observation | 0 / 11 | [] | — | — | — | [] | — | [{"city_id":"lille","country_id":"country_fra","emblem":"§","fictional_but_culturally_consistent":true,"id":"association_civil_servants_nord","industry_id":"civil_service"},{"ci... | OBSERVED + DECLARED |
| `catalog[].city_id` | `catalog[]` | string / declared `string` | False | True | required-by-observation | 0 / 11 | — | False | reference_candidate | world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["lille","paris"] | — | ["lille","paris"] | OBSERVED + DECLARED |
| `catalog[].country_id` | `catalog[]` | string / declared `string` | False | True | required-by-observation | 0 / 11 | — | False | reference_candidate | world_map.countries | ["country_fra"] | — | ["country_fra"] | OBSERVED + DECLARED |
| `catalog[].emblem` | `catalog[]` | string / declared `—` | False | True | required-by-observation | 0 / 11 | null | False | — | — | ["§","═","◇","◉","⚙","✦"] | — | ["§","═","◇"] | OBSERVED |
| `catalog[].fictional_but_culturally_consistent` | `catalog[]` | boolean / declared `—` | False | False | optional-by-observation | 1 / 11 | null | False | — | — | [] | — | [true] | OBSERVED |
| `catalog[].id` | `catalog[]` | string / declared `string` | False | True | required-by-observation | 0 / 11 | — | True | primary_candidate | — | ["association_civil_servants_nord","association_industry_commerce_nord","committee_paris_lille_rail","committee_public_works_nord","coop_lille_workers_consumption","enterprise_l... | — | ["association_civil_servants_nord","association_industry_commerce_nord","committee_paris_lille_rail"] | OBSERVED + DECLARED |
| `catalog[].industry_id` | `catalog[]` | string / declared `—` | False | False | optional-by-observation | 1 / 11 | null | False | reference_candidate | — | ["civil_service","industry_and_commerce","mechanical_manufacturing","metalworking","public_finance","public_works","rail_transport","retail_food_fuel","worker_education"] | — | ["civil_service","industry_and_commerce","mechanical_manufacturing"] | OBSERVED |
| `catalog[].institution_id` | `catalog[]` | string / declared `string` | False | False | optional-by-observation | 10 / 11 | — | True | reference_candidate | world_map.institutions | ["prefecture_nord"] | — | ["prefecture_nord"] | OBSERVED + DECLARED |
| `catalog[].lon_lat` | `catalog[]` | array / declared `—` | False | False | optional-by-observation | 7 / 11 | null | — | — | — | [] | — | [[3.0,50.61],[3.064,50.637],[3.08,50.63]] | OBSERVED |
| `catalog[].lon_lat[]` | `catalog[].lon_lat[]` | number / declared `—` | False | True | required-by-observation | 0 / 8 | null | True | — | — | [] | 3.0–50.637 | [3.0,3.064,3.08] | OBSERVED |
| `catalog[].map_node_default` | `catalog[]` | boolean / declared `—` | False | True | required-by-observation | 0 / 11 | null | False | — | — | [] | — | [false] | OBSERVED |
| `catalog[].max_zoom` | `catalog[]` | number / declared `number` | False | False | optional-by-observation | 7 / 11 | 99.0 | False | — | — | [] | 96.0–96.0 | [96.0] | OBSERVED + DECLARED |
| `catalog[].min_zoom` | `catalog[]` | number / declared `number` | False | False | optional-by-observation | 7 / 11 | 0.0 | False | — | — | [] | 6.8–7.0 | [6.8,7.0] | OBSERVED + DECLARED |
| `catalog[].name` | `catalog[]` | string / declared `string` | False | True | required-by-observation | 0 / 11 | — | True | — | — | ["北部省公共工程委员会","北部省公务人员协会","北部省工业与商业协会","北部省机械行业联合会","北部省省政府","北部省金属工人工会","巴黎—里尔铁路协调委员会","财政部地方预算档案处","里尔工人夜校","里尔工人消费合作社","里尔机械制造公司"] | — | ["北部省公共工程委员会","北部省公务人员协会","北部省工业与商业协会"] | OBSERVED + DECLARED |
| `catalog[].native_name` | `catalog[]` | string / declared `—` | False | True | required-by-observation | 0 / 11 | null | True | — | — | ["Association des fonctionnaires du Nord","Association industrielle et commerciale du Nord","Bureau des archives budgétaires locales","Commission de coordination ferroviaire Par... | — | ["Association des fonctionnaires du Nord","Association industrielle et commerciale du Nord","Bureau des archives budgétaires locales"] | OBSERVED |
| `catalog[].object_level` | `catalog[]` | string / declared `—` | False | True | required-by-observation | 0 / 11 | null | False | — | — | ["organization"] | — | ["organization"] | OBSERVED |
| `catalog[].organization_kind` | `catalog[]` | string / declared `—` | False | True | required-by-observation | 0 / 11 | null | True | — | — | ["central_public_office","cooperative","education","enterprise","government_workplace","industry_association","industry_federation","interagency_committee","labor_union","profes... | — | ["central_public_office","cooperative","education"] | OBSERVED |
| `catalog[].parent_region_id` | `catalog[]` | string / declared `string` | False | True | required-by-observation | 0 / 11 | — | False | reference_candidate | world_map.regions | ["northern_industrial_belt","paris_basin"] | — | ["northern_industrial_belt","paris_basin"] | OBSERVED + DECLARED |
| `identities` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"official":{"discover":"<nested>","owned":"<nested>"},"worker":{"discover":"<nested>","owned":"<nested>"}}] | OBSERVED |
| `identities.<key>` | `identities.<key>` | object / declared `—` | False | True | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [{"discover":["<nested>","<nested>","<nested>"],"owned":["<nested>","<nested>"]}] | OBSERVED |
| `identities.<key>.discover` | `identities.<key>` | array / declared `—` | False | True | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [[{"access":"<nested>","allowance":"<nested>","available_position":"<nested>","contact_source":"<nested>","department":"<nested>","eligible":"<nested>"},{"access":"<nested>","al... | OBSERVED |
| `identities.<key>.discover[]` | `identities.<key>.discover[]` | object / declared `—` | False | True | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [{"access":"! 需要公共工程处主任提名","allowance":"铁路差旅实报实销","available_position":"协调文书员","contact_source":"关系人物引荐","department":"运输协调组","eligible":"议题与当前职务相关"},{"access":"! 需要熟练工推荐","allo... | OBSERVED |
| `identities.<key>.discover[].access` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["! 需要公共工程处主任提名","! 需要熟练工推荐","× 当前只能查看公开资料","✓ 可申请列席项目会议","✓ 当前可接触","🔒 当前只能查看公开目录"] | — | ["! 需要公共工程处主任提名","! 需要熟练工推荐","× 当前只能查看公开资料"] | OBSERVED |
| `identities.<key>.discover[].allowance` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["会议日交通津贴 4 法郎/月","出差实报实销","午餐补贴","无固定津贴","铁路差旅实报实销"] | — | ["会议日交通津贴 4 法郎/月","出差实报实销","午餐补贴"] | OBSERVED |
| `identities.<key>.discover[].available_position` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["仓储协助员","协调文书员","技术记录员","简报抄写员","行政书记员","预算档案助理"] | — | ["仓储协助员","协调文书员","技术记录员"] | OBSERVED |
| `identities.<key>.discover[].contact_source` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["关系人物引荐","同地区公开组织公告","同地区行政公报","当前工作单位关联","行业公开记录","行政公开记录"] | — | ["关系人物引荐","同地区公开组织公告","同地区行政公报"] | OBSERVED |
| `identities.<key>.discover[].department` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["书记处","地方预算档案组","技术记录处","行业简报处","运输协调组","采购与仓储组"] | — | ["书记处","地方预算档案组","技术记录处"] | OBSERVED |
| `identities.<key>.discover[].eligible` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["个人目前不具企业会员资格","任职与议题范围符合","可查看公开进度","符合地区居民基本条件","职业方向符合","议题与当前职务相关"] | — | ["个人目前不具企业会员资格","任职与议题范围符合","可查看公开进度"] | OBSERVED |
| `identities.<key>.discover[].entry_method` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["中央财政部门任命或公开考试","企业会员提名或受聘进入书记处","提交处主任签署的列席申请","携住址证明到公开窗口登记","由会员熟练工提交推荐","由所属部门提出书面提名"] | — | ["中央财政部门任命或公开考试","企业会员提名或受聘进入书记处","提交处主任签署的列席申请"] | OBSERVED |
| `identities.<key>.discover[].function` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["保管地方预算档案与公开目录","协商铁路容量与货运优先级","协调道路、建筑与市镇工程","发布北部省工业与运输简报","机械行业交流与工作引荐","集中采购食品与燃料"] | — | ["保管地方预算档案与公开目录","协商铁路容量与货运优先级","协调道路、建筑与市镇工程"] | OBSERVED |
| `identities.<key>.discover[].known_reason` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["所属公共工程处收到委员会公开会议通知","玩家可通过工厂公开行业记录获知该协会","玩家在里尔市政公告栏看到登记信息","省政府公开目录列出该中央档案处","铁路调度文员勒内可提供委员会公开联络方式","雇主与行业联合会共享公开招聘简报"] | — | ["所属公共工程处收到委员会公开会议通知","玩家可通过工厂公开行业记录获知该协会","玩家在里尔市政公告栏看到登记信息"] | OBSERVED |
| `identities.<key>.discover[].missing_conditions` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["一名有效推荐人","中央部门批准与财政档案资历","企业提名与商业资历","处主任提名与委员会确认","处主任签署","无"] | — | ["一名有效推荐人","中央部门批准与财政档案资历","企业提名与商业资历"] | OBSERVED |
| `identities.<key>.discover[].organization_id` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | reference_candidate | world_map.organizations | ["association_industry_commerce_nord","committee_paris_lille_rail","committee_public_works_nord","coop_lille_workers_consumption","office_local_budget_records","union_mechanical... | — | ["association_industry_commerce_nord","committee_paris_lille_rail","committee_public_works_nord"] | OBSERVED |
| `identities.<key>.discover[].pay_cycle` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["每周支付","每月支付"] | — | ["每周支付","每月支付"] | OBSERVED |
| `identities.<key>.discover[].position_authority` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["在授权范围内调阅与编目档案","抄录公开统计资料","整理技术记录与会员名册","汇总运力报表与会签意见","登记入库与领取单据","登记议程与会签文件"] | — | ["在授权范围内调阅与编目档案","抄录公开统计资料","整理技术记录与会员名册"] | OBSERVED |
| `identities.<key>.discover[].position_requirements` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["商业文书经验；协会会员推荐","机械行业经历；熟练工推荐","行政文书资历；公开考试或部门借调","识字；可在周末轮班","财政文书资历；中央部门任命","铁路或公共工程文书经历；部门任命"] | — | ["商业文书经验；协会会员推荐","机械行业经历；熟练工推荐","行政文书资历；公开考试或部门借调"] | OBSERVED |
| `identities.<key>.discover[].position_salary` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["周薪 18 法郎","周薪 26 法郎","月薪 105 法郎","月薪 110 法郎","月薪 72 法郎","月薪 96 法郎"] | — | ["周薪 18 法郎","周薪 26 法郎","月薪 105 法郎"] | OBSERVED |
| `identities.<key>.discover[].position_work` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["协助食品和燃料入库","整理地方预算档案索引","整理工业与运输简报底稿","整理道路、建筑和市镇工程会议文书","汇总机械行业岗位和技术资料","维护巴黎—里尔协调案文书"] | — | ["协助食品和燃料入库","整理地方预算档案索引","整理工业与运输简报底稿"] | OBSERVED |
| `identities.<key>.discover[].primary_action` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["了解列席程序","查看公开章程","查看公开记录","查看行业记录","请求引荐"] | — | ["了解列席程序","查看公开章程","查看公开记录"] | OBSERVED |
| `identities.<key>.discover[].supervisor` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["书记处主任","仓储主管","委员会秘书","委员会秘书长","档案处主任","联合会书记"] | — | ["书记处主任","仓储主管","委员会秘书"] | OBSERVED |
| `identities.<key>.discover[].type` | `identities.<key>.discover[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["中央财政档案机构","地方公共委员会","消费合作社","行业协会","行业联合会","跨机构协调委员会"] | — | ["中央财政档案机构","地方公共委员会","消费合作社"] | OBSERVED |
| `identities.<key>.owned` | `identities.<key>` | array / declared `—` | False | True | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [[{"authority":"<nested>","compensation":"<nested>","department":"<nested>","organization_id":"<nested>","position":"<nested>","primary_action":"<nested>"},{"authority":"<nested... | OBSERVED |
| `identities.<key>.owned[]` | `identities.<key>.owned[]` | object / declared `—` | False | True | required-by-observation | 0 / 4 | null | — | — | — | [] | — | [{"authority":"参加专业讨论、提交培训建议","compensation":"会员职位 · 无薪酬","department":"行政事务组","organization_id":"association_civil_servants_nord","position":"普通会员","primary_action":"查看协会事务"},{... | OBSERVED |
| `identities.<key>.owned[].authority` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["参加专业讨论、提交培训建议","参加课程与学员讨论","召集车间会议、提交成员诉求","提交处内事务、协调项目、查阅本处预算"] | — | ["参加专业讨论、提交培训建议","参加课程与学员讨论","召集车间会议、提交成员诉求"] | OBSERVED |
| `identities.<key>.owned[].compensation` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["会员职位 · 无薪酬","志愿职位 · 无固定薪酬","无薪酬 · 已缴本期学费","月薪 120 法郎 · 交通津贴 8 法郎/月"] | — | ["会员职位 · 无薪酬","志愿职位 · 无固定薪酬","无薪酬 · 已缴本期学费"] | OBSERVED |
| `identities.<key>.owned[].department` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["公共工程处","夜间技术班","行政事务组","金属工人分会第三车间"] | — | ["公共工程处","夜间技术班","行政事务组"] | OBSERVED |
| `identities.<key>.owned[].organization_id` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | reference_candidate | world_map.organizations | ["association_civil_servants_nord","school_lille_workers_evening","union_metalworkers_nord","workplace_prefecture_nord"] | — | ["association_civil_servants_nord","school_lille_workers_evening","union_metalworkers_nord"] | OBSERVED |
| `identities.<key>.owned[].position` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["公共工程处事务员","普通会员","机械制图班学员","第三车间联络员"] | — | ["公共工程处事务员","普通会员","机械制图班学员"] | OBSERVED |
| `identities.<key>.owned[].primary_action` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["查看协会事务","查看机构事务","查看组织事务","查看课程事务"] | — | ["查看协会事务","查看机构事务","查看组织事务"] | OBSERVED |
| `identities.<key>.owned[].project` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["工资谈判准备 · 文书汇总阶段","机械制图课程 · 基础投影阶段","行政培训计划 · 议题征集阶段","铁路运输协调案 · 会签准备阶段"] | — | ["工资谈判准备 · 文书汇总阶段","机械制图课程 · 基础投影阶段","行政培训计划 · 议题征集阶段"] | OBSERVED |
| `identities.<key>.owned[].secondary_action` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | False | — | — | ["参与培训项目","参与当前项目","继续当前课程"] | — | ["参与培训项目","参与当前项目","继续当前课程"] | OBSERVED |
| `identities.<key>.owned[].supervisor` | `identities.<key>.owned[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["公共工程处主任","分会书记","协会理事","课程教师"] | — | ["公共工程处主任","分会书记","协会理事"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 3.0–3.0 | [3] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
