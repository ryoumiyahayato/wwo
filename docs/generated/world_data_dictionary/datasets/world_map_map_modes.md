# world_map.map_modes

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Map modes, zoom thresholds, label budgets, and layer-display policy.

- Path: `data/world_map/map_modes.json`
- Source files: `1`
- Record count (primary collection): `4`
- Documents: `1`
- Root type: `object`
- Primary record path: `modes[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `modes[]` | 4 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` values come from explicit loader/validator evidence and are not silently merged into observed facts.

| field | scope | observed type | nullable | required by observation | required status | missing / records | default | unique | ID | foreign key | enum candidates | min–max | examples | evidence || --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `boundary_notice` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["当前世界政治边界采用现代 Natural Earth 几何，仅用于 UI、缩放、标签和地图模式验证。国家名称及颜色包含 1900 年主题占位，不代表准确的 1900 年疆域、殖民体系或国际关系。"] | — | ["当前世界政治边界采用现代 Natural Earth 几何，仅用于 UI、缩放、标签和地图模式验证。国家名称及颜色包含 1900 年主题占位，不代表准确的 1900 年疆域、殖民体系或国际关系。"] | OBSERVED |
| `detail_node_policy` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"far":"hidden","middle":"hidden","near":"visible_local_and_selected_context"}] | OBSERVED |
| `detail_node_policy.far` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["hidden"] | — | ["hidden"] | OBSERVED |
| `detail_node_policy.middle` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["hidden"] | — | ["hidden"] | OBSERVED |
| `detail_node_policy.near` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["visible_local_and_selected_context"] | — | ["visible_local_and_selected_context"] | OBSERVED |
| `label_budgets` | `document` | object / declared `object` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"far":{"administrative":"<nested>","city":"<nested>","country":"<nested>","region":"<nested>","transport":"<nested>"},"middle":{"administrative":"<nested>","city":"<nested>","... | OBSERVED + DECLARED |
| `label_budgets.far` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"administrative":0,"city":4,"country":12,"region":0,"transport":0}] | OBSERVED |
| `label_budgets.far.administrative` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.0–0.0 | [0] | OBSERVED |
| `label_budgets.far.city` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED |
| `label_budgets.far.country` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 12.0–12.0 | [12] | OBSERVED |
| `label_budgets.far.region` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.0–0.0 | [0] | OBSERVED |
| `label_budgets.far.transport` | `document` | number / declared `object` | False | True | required-by-observation | 0 / 1 | {} | True | — | — | [] | 0.0–0.0 | [0] | OBSERVED + DECLARED |
| `label_budgets.middle` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"administrative":0,"city":10,"country":12,"region":0,"transport":4}] | OBSERVED |
| `label_budgets.middle.administrative` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.0–0.0 | [0] | OBSERVED |
| `label_budgets.middle.city` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 10.0–10.0 | [10] | OBSERVED |
| `label_budgets.middle.country` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 12.0–12.0 | [12] | OBSERVED |
| `label_budgets.middle.region` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.0–0.0 | [0] | OBSERVED |
| `label_budgets.middle.transport` | `document` | number / declared `object` | False | True | required-by-observation | 0 / 1 | {} | True | — | — | [] | 4.0–4.0 | [4] | OBSERVED + DECLARED |
| `label_budgets.near` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"administrative":24,"city":20,"country":5,"region":12,"transport":18}] | OBSERVED |
| `label_budgets.near.administrative` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 24.0–24.0 | [24] | OBSERVED |
| `label_budgets.near.city` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 20.0–20.0 | [20] | OBSERVED |
| `label_budgets.near.country` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 5.0–5.0 | [5] | OBSERVED |
| `label_budgets.near.region` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 12.0–12.0 | [12] | OBSERVED |
| `label_budgets.near.transport` | `document` | number / declared `object` | False | True | required-by-observation | 0 / 1 | {} | True | — | — | [] | 18.0–18.0 | [18] | OBSERVED + DECLARED |
| `levels` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"far":{"id":"<nested>","label":"<nested>"},"middle":{"id":"<nested>","label":"<nested>"},"near":{"id":"<nested>","label":"<nested>"}}] | OBSERVED |
| `levels.far` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"id":"world","label":"世界远景"}] | OBSERVED |
| `levels.far.id` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | primary_candidate | — | ["world"] | — | ["world"] | OBSERVED + DECLARED |
| `levels.far.label` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["世界远景"] | — | ["世界远景"] | OBSERVED |
| `levels.middle` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"id":"western_europe","label":"欧洲中景"}] | OBSERVED |
| `levels.middle.id` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | primary_candidate | — | ["western_europe"] | — | ["western_europe"] | OBSERVED + DECLARED |
| `levels.middle.label` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["欧洲中景"] | — | ["欧洲中景"] | OBSERVED |
| `levels.near` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"id":"local_detail","label":"地点近景"}] | OBSERVED |
| `levels.near.id` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | primary_candidate | — | ["local_detail"] | — | ["local_detail"] | OBSERVED + DECLARED |
| `levels.near.label` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["地点近景"] | — | ["地点近景"] | OBSERVED |
| `modes` | `document` | array / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [[{"description":"<nested>","icon":"<nested>","id":"<nested>","label":"<nested>"},{"description":"<nested>","icon":"<nested>","id":"<nested>","label":"<nested>"},{"description":... | OBSERVED |
| `modes[]` | `modes[]` | object / declared `—` | False | True | required-by-observation | 0 / 4 | null | — | — | — | [] | — | [{"description":"仅在战争示例中增加控制覆盖、战线与战区标签","icon":"⚔","id":"war","label":"战争状态"},{"description":"在同一地理底图上叠加人口密度","icon":"●","id":"population","label":"人口"},{"description":"在同一地理底图上... | OBSERVED |
| `modes[].description` | `modes[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["仅在战争示例中增加控制覆盖、战线与战区标签","在同一地理底图上叠加人口密度","在同一地理底图上叠加市场状态","强调国家填充、国境和法理标签"] | — | ["仅在战争示例中增加控制覆盖、战线与战区标签","在同一地理底图上叠加人口密度","在同一地理底图上叠加市场状态"] | OBSERVED |
| `modes[].icon` | `modes[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["¤","◇","●","⚔"] | — | ["¤","◇","●"] | OBSERVED |
| `modes[].id` | `modes[]` | string / declared `string` | False | True | required-by-observation | 0 / 4 | — | True | primary_candidate | — | ["legal","market","population","war"] | — | ["legal","market","population"] | OBSERVED + DECLARED |
| `modes[].label` | `modes[]` | string / declared `—` | False | True | required-by-observation | 0 / 4 | null | True | — | — | ["人口","区域市场","战争状态","法理归属"] | — | ["人口","区域市场","战争状态"] | OBSERVED |
| `peace_note` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["和平状态：战争模式仍使用相同底图，但不显示战线。"] | — | ["和平状态：战争模式仍使用相同底图，但不显示战线。"] | OBSERVED |
| `prototype_only` | `document` | boolean / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | — | [true] | OBSERVED |
| `schema_version` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 3.0–3.0 | [3] | OBSERVED |
| `shared_basemap_id` | `document` | string / declared `string` | False | True | required-by-observation | 0 / 1 | — | True | reference_candidate | — | ["natural_earth_110m_v2_1"] | — | ["natural_earth_110m_v2_1"] | OBSERVED + DECLARED |
| `transport_legend` | `document` | object / declared `—` | False | True | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [{"border":"浅色细实线 · 国境","front":"红色锯齿粗线 · 战线","rail":"双线枕木 · 陆地铁路","road":"细虚线 · 一般陆路","shipping":"蓝色长虚线 · 海运航线"}] | OBSERVED |
| `transport_legend.border` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["浅色细实线 · 国境"] | — | ["浅色细实线 · 国境"] | OBSERVED |
| `transport_legend.front` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["红色锯齿粗线 · 战线"] | — | ["红色锯齿粗线 · 战线"] | OBSERVED |
| `transport_legend.rail` | `document` | string / declared `object` | False | True | required-by-observation | 0 / 1 | [] | True | — | — | ["双线枕木 · 陆地铁路"] | — | ["双线枕木 · 陆地铁路"] | OBSERVED + DECLARED |
| `transport_legend.road` | `document` | string / declared `object` | False | True | required-by-observation | 0 / 1 | [] | True | — | — | ["细虚线 · 一般陆路"] | — | ["细虚线 · 一般陆路"] | OBSERVED + DECLARED |
| `transport_legend.shipping` | `document` | string / declared `object` | False | True | required-by-observation | 0 / 1 | [] | True | — | — | ["蓝色长虚线 · 海运航线"] | — | ["蓝色长虚线 · 海运航线"] | OBSERVED + DECLARED |
| `war_note` | `document` | string / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | ["战争视觉示例：静态覆盖，不运行任何战争模拟。"] | — | ["战争视觉示例：静态覆盖，不运行任何战争模拟。"] | OBSERVED |
| `zoom` | `document` | object / declared `object` | False | True | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"factor":1.24,"far_max":1.5,"france_focus":18.0,"maximum":480.0,"middle_max":6.2,"minimum":0.82}] | OBSERVED + DECLARED |
| `zoom.factor` | `document` | number / declared `number` | False | True | required-by-observation | 0 / 1 | 1.26 | True | — | — | [] | 1.24–1.24 | [1.24] | OBSERVED + DECLARED |
| `zoom.far_max` | `document` | number / declared `number` | False | True | required-by-observation | 0 / 1 | 1.5 | True | — | — | [] | 1.5–1.5 | [1.5] | OBSERVED + DECLARED |
| `zoom.france_focus` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 18.0–18.0 | [18.0] | OBSERVED |
| `zoom.maximum` | `document` | number / declared `number,object` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 480.0–480.0 | [480.0] | OBSERVED + DECLARED |
| `zoom.middle_max` | `document` | number / declared `number` | False | True | required-by-observation | 0 / 1 | 6.2 | True | — | — | [] | 6.2–6.2 | [6.2] | OBSERVED + DECLARED |
| `zoom.minimum` | `document` | number / declared `number,object` | False | True | required-by-observation | 0 / 1 | 0.82 | True | — | — | [] | 0.82–0.82 | [0.82] | OBSERVED + DECLARED |
| `zoom.player_location_focus` | `document` | number / declared `number` | False | True | required-by-observation | 0 / 1 | 0.0 | True | — | — | [] | 420.0–420.0 | [420.0] | OBSERVED + DECLARED |
| `zoom.v2_1_1_maximum` | `document` | number / declared `—` | False | True | required-by-observation | 0 / 1 | null | True | — | — | [] | 12.0–12.0 | [12.0] | OBSERVED |

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
