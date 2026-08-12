# world_map.characters

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Prototype character identity, action, status, and plan-display definitions.

- Path: `data/world_map/characters.json`
- Source files: `1`
- Record count (primary collection): `1`
- Documents: `1`
- Root type: `object`
- Primary record path: `document`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `identities.<key>` | 2 | 1 |
| `identities.<key>.status_indicators[]` | 6 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `identities` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"official":{"access_summary":"<nested>","age":"<nested>","agenda":"<nested>","allowance":"<nested>","authority_source":"<nested>","available_actions":"<nested>"},"worker":{"ac... | OBSERVED |
| `identities.<key>` | `identities.<key>` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [{"access_summary":"个人生活、所属机构、辖区议程与受限上级事务","age":41,"agenda":"协调巴黎—里尔铁路运输延误","allowance":"交通津贴 8 法郎/月","authority_source":"地方行政职位","available_actions":["<nested>","<nested>","<n... | OBSERVED |
| `identities.<key>.access_summary` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["个人生活、所属机构、辖区议程与受限上级事务","个人生活、雇主、工会与公开信息"] | — | ["个人生活、所属机构、辖区议程与受限上级事务","个人生活、雇主、工会与公开信息"] | OBSERVED |
| `identities.<key>.age` | `identities.<key>` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | [] | 32.0–41.0 | [32,41] | OBSERVED |
| `identities.<key>.agenda` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["协调巴黎—里尔铁路运输延误"] | — | ["协调巴黎—里尔铁路运输延误"] | OBSERVED |
| `identities.<key>.allowance` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["交通津贴 8 法郎/月","轮班津贴 2 法郎/周"] | — | ["交通津贴 8 法郎/月","轮班津贴 2 法郎/周"] | OBSERVED |
| `identities.<key>.authority_source` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["地方行政职位"] | — | ["地方行政职位"] | OBSERVED |
| `identities.<key>.available_actions` | `identities.<key>` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [["学习","工作投入","休整"],["提交议程","协调项目","查阅程序"]] | OBSERVED |
| `identities.<key>.available_actions[]` | `identities.<key>.available_actions[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | ["休整","协调项目","学习","工作投入","提交议程","查阅程序"] | — | ["休整","协调项目","学习"] | OBSERVED |
| `identities.<key>.cash` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["42 法郎","86 法郎"] | — | ["42 法郎","86 法郎"] | OBSERVED |
| `identities.<key>.city_id` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["lille"] | — | ["lille"] | OBSERVED |
| `identities.<key>.culture_id` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | — | — | ["fra"] | — | ["fra"] | OBSERVED |
| `identities.<key>.current_work` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["北部省省政府 · 公共工程处","里尔机械制造公司 · 本周 46 小时"] | — | ["北部省省政府 · 公共工程处","里尔机械制造公司 · 本周 46 小时"] | OBSERVED |
| `identities.<key>.debt_burden` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["个人债务暂无 · 家庭负担占位","分期工具款 3 法郎/月 · 家庭负担占位"] | — | ["个人债务暂无 · 家庭负担占位","分期工具款 3 法郎/月 · 家庭负担占位"] | OBSERVED |
| `identities.<key>.department` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["公共工程处"] | — | ["公共工程处"] | OBSERVED |
| `identities.<key>.display_name_zh` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["皮埃尔·勒费弗尔","阿尔贝·迪蒙"] | — | ["皮埃尔·勒费弗尔","阿尔贝·迪蒙"] | OBSERVED |
| `identities.<key>.employer` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["里尔机械制造公司"] | — | ["里尔机械制造公司"] | OBSERVED |
| `identities.<key>.employer_id` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | reference_candidate | — | ["enterprise_lille_mechanical"] | — | ["enterprise_lille_mechanical"] | OBSERVED |
| `identities.<key>.expenses` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["本月支出 111 法郎","本月支出 87 法郎"] | — | ["本月支出 111 法郎","本月支出 87 法郎"] | OBSERVED |
| `identities.<key>.fatigue` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | — | — | ["!"] | — | ["!"] | OBSERVED |
| `identities.<key>.health` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | — | — | ["✓"] | — | ["✓"] | OBSERVED |
| `identities.<key>.household` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["2 人住户 · 里尔市内公寓","3 人住户 · 里尔工人街区租住房"] | — | ["2 人住户 · 里尔市内公寓","3 人住户 · 里尔工人街区租住房"] | OBSERVED |
| `identities.<key>.id` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | semantic_id | — | ["character_albert_dumont","character_pierre_lefevre"] | — | ["character_albert_dumont","character_pierre_lefevre"] | OBSERVED |
| `identities.<key>.income` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["本月收入 128 法郎","本月收入 96 法郎"] | — | ["本月收入 128 法郎","本月收入 96 法郎"] | OBSERVED |
| `identities.<key>.institution` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["北部省省政府"] | — | ["北部省省政府"] | OBSERVED |
| `identities.<key>.institution_budget_source` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["北部省预算拨款 · 公共工程处执行额 68%"] | — | ["北部省预算拨款 · 公共工程处执行额 68%"] | OBSERVED |
| `identities.<key>.institution_id` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.institutions | ["prefecture_nord"] | — | ["prefecture_nord"] | OBSERVED |
| `identities.<key>.institution_position` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["公共工程处事务员"] | — | ["公共工程处事务员"] | OBSERVED |
| `identities.<key>.jurisdiction` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["北部省"] | — | ["北部省"] | OBSERVED |
| `identities.<key>.jurisdiction_id` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | reference_candidate | — | ["departement_nord"] | — | ["departement_nord"] | OBSERVED |
| `identities.<key>.life_summary` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["工作繁重，家庭稳定","生活稳定，疲劳需要注意"] | — | ["工作繁重，家庭稳定","生活稳定，疲劳需要注意"] | OBSERVED |
| `identities.<key>.migration_background` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | — | — | ["none"] | — | ["none"] | OBSERVED |
| `identities.<key>.monthly_balance` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["+17 法郎","+9 法郎"] | — | ["+17 法郎","+9 法郎"] | OBSERVED |
| `identities.<key>.monthly_salary` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["月薪 120 法郎"] | — | ["月薪 120 法郎"] | OBSERVED |
| `identities.<key>.name` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["皮埃尔·勒费弗尔","阿尔贝·迪蒙"] | — | ["皮埃尔·勒费弗尔","阿尔贝·迪蒙"] | OBSERVED |
| `identities.<key>.name_source` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | — | — | ["prototype_v2_fr_pool"] | — | ["prototype_v2_fr_pool"] | OBSERVED |
| `identities.<key>.nationality_id` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | reference_candidate | — | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `identities.<key>.native_name` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["Albert Dumont","Pierre Lefèvre"] | — | ["Albert Dumont","Pierre Lefèvre"] | OBSERVED |
| `identities.<key>.occupation` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["机械装配工","行政公务员"] | — | ["机械装配工","行政公务员"] | OBSERVED |
| `identities.<key>.organization_position` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["第三车间联络员"] | — | ["第三车间联络员"] | OBSERVED |
| `identities.<key>.pay_cycle` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["每周六支付","每月末支付"] | — | ["每周六支付","每月末支付"] | OBSERVED |
| `identities.<key>.plan` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["夜校机械制图课","巴黎—里尔铁路运输协调案"] | — | ["夜校机械制图课","巴黎—里尔铁路运输协调案"] | OBSERVED |
| `identities.<key>.plan_detail` | `identities.<key>` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [{"authority":"个人学习安排与夜校学员资格","duration":"预计 3 周","effects":["<nested>","<nested>","<nested>"],"goal":"完成本阶段机械制图课程并提交作业。","next_step":"完成本周投影图作业","resources":"学费已缴；需要制图工具与稳定出勤"}... | OBSERVED |
| `identities.<key>.plan_detail.authority` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["个人学习安排与夜校学员资格","公共工程处事务员职位；处主任授权"] | — | ["个人学习安排与夜校学员资格","公共工程处事务员职位；处主任授权"] | OBSERVED |
| `identities.<key>.plan_detail.duration` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["预计 12 日","预计 3 周"] | — | ["预计 12 日","预计 3 周"] | OBSERVED |
| `identities.<key>.plan_detail.effects` | `identities.<key>` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [["北部省铁路通行效率小幅改善","里尔地区运输成本可能下降","公共工程处协调负担增加","需要铁路公司和省政府会签"],["机械制图实践继续积累","晚间休息时间减少","可为机械行业岗位申请补充资历"]] | OBSERVED |
| `identities.<key>.plan_detail.effects[]` | `identities.<key>.plan_detail.effects[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["公共工程处协调负担增加","北部省铁路通行效率小幅改善","可为机械行业岗位申请补充资历","晚间休息时间减少","机械制图实践继续积累","里尔地区运输成本可能下降","需要铁路公司和省政府会签"] | — | ["公共工程处协调负担增加","北部省铁路通行效率小幅改善","可为机械行业岗位申请补充资历"] | OBSERVED |
| `identities.<key>.plan_detail.goal` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["完成本阶段机械制图课程并提交作业。","缓解巴黎—里尔铁路运输延误。"] | — | ["完成本阶段机械制图课程并提交作业。","缓解巴黎—里尔铁路运输延误。"] | OBSERVED |
| `identities.<key>.plan_detail.next_step` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["完成本周投影图作业","提交北部省运输影响摘要并请求处主任签发会签函"] | — | ["完成本周投影图作业","提交北部省运输影响摘要并请求处主任签发会签函"] | OBSERVED |
| `identities.<key>.plan_detail.resources` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["学费已缴；需要制图工具与稳定出勤","本处差旅额度、运输报表与铁路公司书面回复"] | — | ["学费已缴；需要制图工具与稳定出勤","本处差旅额度、运输报表与铁路公司书面回复"] | OBSERVED |
| `identities.<key>.plan_detail.responsible` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["皮埃尔·勒费弗尔 · 里尔工人夜校","阿尔贝·迪蒙 · 北部省公共工程处"] | — | ["皮埃尔·勒费弗尔 · 里尔工人夜校","阿尔贝·迪蒙 · 北部省公共工程处"] | OBSERVED |
| `identities.<key>.plan_detail.stage` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["基础投影练习","跨单位会签准备"] | — | ["基础投影练习","跨单位会签准备"] | OBSERVED |
| `identities.<key>.plan_detail.stop_conditions` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["省政府拒绝会签、铁路公司不提供容量表或预算冻结","连续缺课或疲劳状态恶化"] | — | ["省政府拒绝会签、铁路公司不提供容量表或预算冻结","连续缺课或疲劳状态恶化"] | OBSERVED |
| `identities.<key>.plan_detail.success_detail` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["当前有效值 58；成功线 45。正向：已有基础、学费已缴。风险：轮班疲劳。","当前有效值 61；成功线 45。正向：准备充分、处内支持。风险：跨部门会签与铁路公司回复未完成。"] | — | ["当前有效值 58；成功线 45。正向：已有基础、学费已缴。风险：轮班疲劳。","当前有效值 61；成功线 45。正向：准备充分、处内支持。风险：跨部门会签与铁路公司回复未完成。"] | OBSERVED |
| `identities.<key>.plan_detail.success_label` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["存在风险","把握较高"] | — | ["存在风险","把握较高"] | OBSERVED |
| `identities.<key>.plan_detail.success_symbol` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["!","✓"] | — | ["!","✓"] | OBSERVED |
| `identities.<key>.plan_detail.time_cost` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["个人投入 6 个工作日；机构协调约 12 日","每周 3 个晚间"] | — | ["个人投入 6 个工作日；机构协调约 12 日","每周 3 个晚间"] | OBSERVED |
| `identities.<key>.plan_detail.title` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["夜校机械制图课","巴黎—里尔铁路运输协调案"] | — | ["夜校机械制图课","巴黎—里尔铁路运输协调案"] | OBSERVED |
| `identities.<key>.plan_status` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["! 存在风险","✓ 把握较高"] | — | ["! 存在风险","✓ 把握较高"] | OBSERVED |
| `identities.<key>.position` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["公共工程处事务员","第三车间联络员"] | — | ["公共工程处事务员","第三车间联络员"] | OBSERVED |
| `identities.<key>.primary_concern` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["夜校与轮班挤占休息时间","铁路运输延误需要跨单位协调"] | — | ["夜校与轮班挤占休息时间","铁路运输延误需要跨单位协调"] | OBSERVED |
| `identities.<key>.procedures` | `identities.<key>` | array / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | — | — | — | [] | — | [["提交处内事务","发起跨单位会签","查阅本处预算"]] | OBSERVED |
| `identities.<key>.procedures[]` | `identities.<key>.procedures[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | ["发起跨单位会签","提交处内事务","查阅本处预算"] | — | ["发起跨单位会签","提交处内事务","查阅本处预算"] | OBSERVED |
| `identities.<key>.region` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | — | — | ["北部工业带 · 里尔"] | — | ["北部工业带 · 里尔"] | OBSERVED |
| `identities.<key>.region_id` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.regions | ["northern_industrial_belt"] | — | ["northern_industrial_belt"] | OBSERVED |
| `identities.<key>.role` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["机械装配工","行政公务员"] | — | ["机械装配工","行政公务员"] | OBSERVED |
| `identities.<key>.school` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["里尔工人夜校"] | — | ["里尔工人夜校"] | OBSERVED |
| `identities.<key>.school_id` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | reference_candidate | — | ["school_lille_workers_evening"] | — | ["school_lille_workers_evening"] | OBSERVED |
| `identities.<key>.status_indicators` | `identities.<key>` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | — | — | — | [] | — | [[{"id":"<nested>","impact":"<nested>","label":"<nested>","reason":"<nested>","state":"<nested>","suggestion":"<nested>"},{"id":"<nested>","impact":"<nested>","label":"<nested>"... | OBSERVED |
| `identities.<key>.status_indicators[]` | `identities.<key>.status_indicators[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [{"id":"fatigue","impact":"可能拖慢文书复核","label":"疲劳","reason":"铁路协调文书增加加班","state":"需要注意","suggestion":"将非紧急档案交由书记员整理"},{"id":"fatigue","impact":"可能降低晚间学习效率","label":"疲劳","reason":... | OBSERVED |
| `identities.<key>.status_indicators[].id` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | primary_candidate | — | ["fatigue","health","stress"] | — | ["fatigue","health","stress"] | OBSERVED |
| `identities.<key>.status_indicators[].impact` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | ["协调案可能延期","可正常履行职务","可正常工作与学习","可能拖慢文书复核","可能降低晚间学习效率","暂无直接行动限制"] | — | ["协调案可能延期","可正常履行职务","可正常工作与学习"] | OBSERVED |
| `identities.<key>.status_indicators[].label` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | ["健康","压力","疲劳"] | — | ["健康","压力","疲劳"] | OBSERVED |
| `identities.<key>.status_indicators[].reason` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | ["住户收支仍有小额结余","本周轮班与夜校重叠","跨部门会签尚未完成","近期无明显伤病","铁路协调文书增加加班"] | — | ["住户收支仍有小额结余","本周轮班与夜校重叠","跨部门会签尚未完成"] | OBSERVED |
| `identities.<key>.status_indicators[].state` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | ["可控","存在风险","正常","需要注意"] | — | ["可控","存在风险","正常"] | OBSERVED |
| `identities.<key>.status_indicators[].suggestion` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | ["优先取得铁路公司与省政府会签","保留应急现金","安排一次完整休整","将非紧急档案交由书记员整理","维持休息与饮食","维持日常作息"] | — | ["优先取得铁路公司与省政府会签","保留应急现金","安排一次完整休整"] | OBSERVED |
| `identities.<key>.status_indicators[].symbol` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | ["!","✓"] | — | ["!","✓"] | OBSERVED |
| `identities.<key>.status_indicators[].trend` | `identities.<key>.status_indicators[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | ["保持稳定","基本稳定","缓慢上升","近期上升"] | — | ["保持稳定","基本稳定","缓慢上升"] | OBSERVED |
| `identities.<key>.stress` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | True | — | — | ["!","✓"] | — | ["!","✓"] | OBSERVED |
| `identities.<key>.subordinates` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["行政书记员 4 人"] | — | ["行政书记员 4 人"] | OBSERVED |
| `identities.<key>.supervisor` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["公共工程处主任"] | — | ["公共工程处主任"] | OBSERVED |
| `identities.<key>.union` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["北部省金属工人工会"] | — | ["北部省金属工人工会"] | OBSERVED |
| `identities.<key>.union_id` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | reference_candidate | — | ["union_metalworkers_nord"] | — | ["union_metalworkers_nord"] | OBSERVED |
| `identities.<key>.union_position` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["第三车间联络员"] | — | ["第三车间联络员"] | OBSERVED |
| `identities.<key>.upstream_locked` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["🔒 调整北部省总预算 · 需要省长授权并履行预算程序"] | — | ["🔒 调整北部省总预算 · 需要省长授权并履行预算程序"] | OBSERVED |
| `identities.<key>.weekly_wage` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["周薪 24 法郎"] | — | ["周薪 24 法郎"] | OBSERVED |
| `identities.<key>.work_contract` | `identities.<key>` | string / declared `—` | False | False | False | False | optional-by-observation | 1 / 2 | null | True | — | — | ["计时工资 · 周结 · 工会协议覆盖"] | — | ["计时工资 · 周结 · 工会协议覆盖"] | OBSERVED |
| `identities.<key>.workplace_city_id` | `identities.<key>` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 2 | null | False | reference_candidate | — | ["lille"] | — | ["lille"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
