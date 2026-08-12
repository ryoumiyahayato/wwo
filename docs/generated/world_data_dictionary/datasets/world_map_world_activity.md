# world_map.world_activity

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Prototype public activity feed records shown by the map UI.

- Path: `data/world_map/world_activity.json`
- Source files: `1`
- Record count (primary collection): `6`
- Documents: `1`
- Root type: `object`
- Primary record path: `items[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `items[]` | 6 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `default_summary` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"latest_id":"food_price_lille","max_visible_items":1,"transient_seconds":4,"unread_count":4}] | OBSERVED |
| `default_summary.latest_id` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | reference_candidate | — | ["food_price_lille"] | — | ["food_price_lille"] | OBSERVED |
| `default_summary.max_visible_items` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED |
| `default_summary.transient_seconds` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED |
| `default_summary.unread_count` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED |
| `items` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"aggregation_key":"<nested>","detail":"<nested>","group_count":"<nested>","group_key":"<nested>","id":"<nested>","institution_ids":"<nested>"},{"aggregation_key":"<nested>","... | OBSERVED |
| `items[]` | `items[]` | object / declared `—` | False | True | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [{"aggregation_key":"factory_safety_notices","detail":"公告列出里尔机械企业的检查准备事项；仅为静态制度原型条目","group_count":1,"group_key":"factory_safety_notices","id":"factory_safety_notice","instituti... | OBSERVED |
| `items[].aggregation_key` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["factory_safety_notices","local_prices_lille","mechanical_hiring_lille","national_rail_agenda","paris_lille_rail_delay","union_activity_nord"] | — | ["factory_safety_notices","local_prices_lille","mechanical_hiring_lille"] | OBSERVED |
| `items[].city_ids` | `items[]` | array / declared `—` | False | False | optional-by-observation | 5 / 6 | null | — | reference_candidate | world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | [] | — | [["paris","lille"]] | OBSERVED |
| `items[].city_ids[]` | `items[].city_ids[]` | string / declared `—` | False | True | required-by-observation | 0 / 2 | null | True | reference_candidate | world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["lille","paris"] | — | ["lille","paris"] | OBSERVED |
| `items[].detail` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["三份公开招聘告示被聚合为一条静态通知","公告列出里尔机械企业的检查准备事项；仅为静态制度原型条目","公开议程仅用于国家层信息入口的静态验证","公开零售记录显示部分食品报价上升；原型未进行市场结算","六份公开会议记录按地点与周期聚合；原型未运行组织模拟","铁路协调委员会公开简报记录货运时刻变化"] | — | ["三份公开招聘告示被聚合为一条静态通知","公告列出里尔机械企业的检查准备事项；仅为静态制度原型条目","公开议程仅用于国家层信息入口的静态验证"] | OBSERVED |
| `items[].group_count` | `items[]` | number / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | [] | 1.0–6.0 | [1,3,6] | OBSERVED |
| `items[].group_key` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["factory_safety_notices","local_prices_lille","mechanical_hiring_lille","national_rail_agenda","paris_lille_rail_delay","union_activity_nord"] | — | ["factory_safety_notices","local_prices_lille","mechanical_hiring_lille"] | OBSERVED |
| `items[].id` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | primary_candidate | — | ["factory_safety_notice","food_price_lille","hiring_lille_mechanical","national_public_notice","paris_lille_rail_delay","union_activity_nord"] | — | ["factory_safety_notice","food_price_lille","hiring_lille_mechanical"] | OBSERVED |
| `items[].institution_ids` | `items[]` | array / declared `—` | False | True | required-by-observation | 0 / 6 | null | — | reference_candidate | world_map.institutions | [] | — | [["labor_inspectorate_nord"],["national_assembly"],["prefecture_nord"]] | OBSERVED |
| `items[].institution_ids[]` | `items[].institution_ids[]` | string / declared `—` | False | True | required-by-observation | 0 / 3 | null | True | reference_candidate | world_map.institutions | ["labor_inspectorate_nord","national_assembly","prefecture_nord"] | — | ["labor_inspectorate_nord","national_assembly","prefecture_nord"] | OBSERVED |
| `items[].kind` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["event","news","notification"] | — | ["event","news","notification"] | OBSERVED |
| `items[].location_id` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | reference_candidate | — | ["country_fra","departement_nord","lille","northern_industrial_belt"] | — | ["country_fra","departement_nord","lille"] | OBSERVED |
| `items[].location_type` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["administrative_unit","city","country","region"] | — | ["administrative_unit","city","country"] | OBSERVED |
| `items[].object_id` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | reference_candidate | — | ["committee_paris_lille_rail","labor_inspectorate_nord","lille","national_assembly","union_mechanical_nord","union_metalworkers_nord"] | — | ["committee_paris_lille_rail","labor_inspectorate_nord","lille"] | OBSERVED |
| `items[].object_type` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["city","institution","organization"] | — | ["city","institution","organization"] | OBSERVED |
| `items[].occurred_at` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["1900-01-12T12:00:00","1900-03-01T12:00:00","1900-03-09T09:00:00","1900-03-12T08:00:00","1900-03-12T10:30:00","1900-03-12T14:00:00"] | — | ["1900-01-12T12:00:00","1900-03-01T12:00:00","1900-03-09T09:00:00"] | OBSERVED |
| `items[].organization_ids` | `items[]` | array / declared `—` | False | True | required-by-observation | 0 / 6 | null | — | reference_candidate | world_map.organizations | [] | — | [["committee_paris_lille_rail"],["coop_lille_workers_consumption"],["enterprise_lille_mechanical","union_mechanical_nord"]] | OBSERVED |
| `items[].organization_ids[]` | `items[].organization_ids[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | reference_candidate | world_map.organizations | ["committee_paris_lille_rail","coop_lille_workers_consumption","enterprise_lille_mechanical","union_mechanical_nord","union_metalworkers_nord"] | — | ["committee_paris_lille_rail","coop_lille_workers_consumption","enterprise_lille_mechanical"] | OBSERVED |
| `items[].priority` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | ["important","normal","world"] | — | ["important","normal","world"] | OBSERVED |
| `items[].public_channel` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["公开会议记录","公开公告栏","公开报刊","公开简报","公开议程","行业公开记录"] | — | ["公开会议记录","公开公告栏","公开报刊"] | OBSERVED |
| `items[].region_id` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | reference_candidate | world_map.regions | ["northern_industrial_belt","paris_basin"] | — | ["northern_industrial_belt","paris_basin"] | OBSERVED |
| `items[].source` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["《里尔公报》","众议院公开议程","北部省劳动监察处公告","北部省机械行业联合会公开记录","多份工会公开会议记录","巴黎—里尔铁路协调委员会简报"] | — | ["《里尔公报》","众议院公开议程","北部省劳动监察处公告"] | OBSERVED |
| `items[].source_type` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["industry_record","institution_notice","legislative_record","newspaper","organization_bulletin","organization_records"] | — | ["industry_record","institution_notice","legislative_record"] | OBSERVED |
| `items[].time` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["2 个月前","3 天前","今天","刚刚","本周","本月"] | — | ["2 个月前","3 天前","今天"] | OBSERVED |
| `items[].title` | `items[]` | string / declared `—` | False | True | required-by-observation | 0 / 6 | null | True | — | — | ["众议院公开铁路支出议程","北部省五个市镇的工会活动增加","北部省劳动监察处发布工厂安全检查公告","巴黎—里尔铁路运输出现延误","里尔地区三家机械企业缩减招聘","里尔食品价格异常上涨"] | — | ["众议院公开铁路支出议程","北部省五个市镇的工会活动增加","北部省劳动监察处发布工厂安全检查公告"] | OBSERVED |
| `items[].unread` | `items[]` | boolean / declared `—` | False | True | required-by-observation | 0 / 6 | null | False | — | — | [] | — | [false,true] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 3.0–3.0 | [3] | OBSERVED |
| `simulation_status` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["静态原型数据，未运行市场、政策或事件模拟。"] | — | ["静态原型数据，未运行市场、政策或事件模拟。"] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
