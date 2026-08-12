# vnext.politics.state_politics_1900

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

1900 vNext politics configuration consumed to initialize authoritative state politics.

- Path: `data/vnext/politics/state_politics_1900.json`
- Source files: `1`
- Record count (primary collection): `1`
- Documents: `1`
- Root type: `object`
- Primary record path: `document`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `forces[]` | 7 | 1 |
| `policies[]` | 6 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `active_policy_ids` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | reference_candidate | — | [] | — | [["policy:loran_balanced_budget"]] | OBSERVED |
| `active_policy_ids[]` | `active_policy_ids[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | reference_candidate | — | ["policy:loran_balanced_budget"] | — | ["policy:loran_balanced_budget"] | OBSERVED |
| `capacity` | `document` | object / declared `object` | False | True | True | False | declared-required | 0 / 1 | null | — | — | — | [] | — | [{"administrative":72.0,"control":70.0,"corruption":22.0,"enforcement":64.0,"fiscal":68.0}] | OBSERVED + DECLARED |
| `capacity.administrative` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 72.0–72.0 | [72.0] | OBSERVED |
| `capacity.control` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 70.0–70.0 | [70.0] | OBSERVED |
| `capacity.corruption` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 22.0–22.0 | [22.0] | OBSERVED |
| `capacity.enforcement` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 64.0–64.0 | [64.0] | OBSERVED |
| `capacity.fiscal` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 68.0–68.0 | [68.0] | OBSERVED |
| `domain` | `document` | UNOBSERVED / declared `string` | — | — | True | False | unknown | — | null | — | — | — | [] | — | [] | DECLARED |
| `forces` | `document` | array / declared `array` | False | True | True | False | declared-required | 0 / 1 | null | — | — | — | [] | — | [[{"base_government_support":"<nested>","force_id":"<nested>","government_eligible":"<nested>","government_support":"<nested>","influence":"<nested>","institutional_access":"<ne... | OBSERVED + DECLARED |
| `forces[]` | `forces[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"base_government_support":10.0,"force_id":"organization:loran_labor_caucus","government_eligible":true,"government_support":10.0,"influence":18.0,"institutional_access":72.0},... | OBSERVED |
| `forces[].base_government_support` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 10.0–80.0 | [10.0,20.0,25.0] | OBSERVED |
| `forces[].force_id` | `forces[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: vnext.politics.state_politics_1900, world_map.organizations | ["organization:loran_conservative_bloc","organization:loran_government_group","organization:loran_labor_caucus","organization:loran_land_industry","organization:loran_liberal_le... | — | ["organization:loran_conservative_bloc","organization:loran_government_group","organization:loran_labor_caucus"] | OBSERVED |
| `forces[].government_eligible` | `forces[]` | boolean / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | — | [true] | OBSERVED |
| `forces[].government_support` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 10.0–80.0 | [10.0,20.0,25.0] | OBSERVED |
| `forces[].influence` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 4.0–30.0 | [10.0,14.0,17.0] | OBSERVED |
| `forces[].institutional_access` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 58.0–95.0 | [58.0,62.0,68.0] | OBSERVED |
| `forces[].kind` | `forces[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["conservative","government","labor","land_industry","liberal","military","regional"] | — | ["conservative","government","labor"] | OBSERVED |
| `forces[].leader_id` | `forces[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.characters | ["person:loran_conservative_leader","person:loran_industry_leader","person:loran_labor_leader","person:loran_liberal_leader","person:loran_marshal","person:loran_premier","perso... | — | ["person:loran_conservative_leader","person:loran_industry_leader","person:loran_labor_leader"] | OBSERVED |
| `forces[].mobilization_capacity` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 36.0–90.0 | [36.0,48.0,52.0] | OBSERVED |
| `forces[].name` | `forces[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | ["Conservative bloc","Government group","Labor and socialist caucus","Land and industrial interests","Liberal league","Military command","Regional and national interests"] | — | ["Conservative bloc","Government group","Labor and socialist caucus"] | OBSERVED |
| `forces[].policy_preferences` | `forces[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"labor":-10.0,"military_mobilization":20.0,"public_order":40.0,"social_spending":0.0,"tax":10.0,"trade":20.0},{"labor":-15.0,"military_mobilization":90.0,"public_order":80.0,"... | OBSERVED |
| `forces[].policy_preferences.labor` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | -60.0–80.0 | [-10.0,-15.0,-45.0] | OBSERVED |
| `forces[].policy_preferences.military_mobilization` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | -30.0–90.0 | [-20.0,-30.0,0.0] | OBSERVED |
| `forces[].policy_preferences.public_order` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | -20.0–80.0 | [-20.0,10.0,20.0] | OBSERVED |
| `forces[].policy_preferences.social_spending` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | -40.0–85.0 | [-20.0,-25.0,-40.0] | OBSERVED |
| `forces[].policy_preferences.tax` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -40.0–35.0 | [-20.0,-40.0,0.0] | OBSERVED |
| `forces[].policy_preferences.trade` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -10.0–70.0 | [-10.0,0.0,20.0] | OBSERVED |
| `forces[].pressure_response` | `forces[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"casualty_pressure":-0.1,"fiscal_pressure":-0.16,"growth_signal":0.1,"military_result_signal":0.02,"mobilization_pressure":-0.28,"price_pressure":-0.42},{"casualty_pressure":-... | OBSERVED |
| `forces[].pressure_response.casualty_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -0.42–-0.1 | [-0.1,-0.15,-0.18] | OBSERVED |
| `forces[].pressure_response.fiscal_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -0.2–0.12 | [-0.08,-0.12,-0.16] | OBSERVED |
| `forces[].pressure_response.growth_signal` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | 0.04–0.35 | [0.04,0.08,0.1] | OBSERVED |
| `forces[].pressure_response.military_result_signal` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 0.02–0.48 | [0.02,0.04,0.1] | OBSERVED |
| `forces[].pressure_response.mobilization_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -0.28–0.3 | [-0.12,-0.16,-0.22] | OBSERVED |
| `forces[].pressure_response.price_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -0.42–-0.12 | [-0.12,-0.15,-0.2] | OBSERVED |
| `forces[].pressure_response.shortage_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | -0.4–-0.15 | [-0.15,-0.18,-0.22] | OBSERVED |
| `forces[].pressure_response.unemployment_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | -0.62–-0.08 | [-0.08,-0.12,-0.18] | OBSERVED |
| `forces[].pressure_response.war_pressure` | `forces[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | -0.22–0.42 | [-0.16,-0.18,-0.2] | OBSERVED |
| `government_group_id` | `document` | string / declared `—` | False | True | True | False | declared-required | 0 / 1 | — | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.organizations, vnext.politics.state_politics_1900 | ["organization:loran_government_group"] | — | ["organization:loran_government_group"] | OBSERVED + DECLARED |
| `government_id` | `document` | string / declared `—` | False | True | True | False | declared-required | 0 / 1 | — | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.organizations, vnext.politics.state_politics_1900 | ["organization:loran_government"] | — | ["organization:loran_government"] | OBSERVED + DECLARED |
| `government_leader_id` | `document` | string / declared `—` | False | True | True | False | declared-required | 0 / 1 | — | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.characters | ["person:loran_premier"] | — | ["person:loran_premier"] | OBSERVED + DECLARED |
| `legitimacy` | `document` | number / declared `number` | False | True | False | False | required-by-observation | 0 / 1 | 60.0 | True | — | — | [] | 68.0–68.0 | [68.0] | OBSERVED + DECLARED |
| `policies` | `document` | array / declared `array` | False | True | True | False | declared-required | 0 / 1 | null | — | — | — | [] | — | [[{"administrative_demand":"<nested>","domain":"<nested>","fiscal_demand":"<nested>","name":"<nested>","policy_id":"<nested>","political_relief":"<nested>"},{"administrative_dem... | OBSERVED + DECLARED |
| `policies[]` | `policies[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [{"administrative_demand":15.0,"domain":"tax","fiscal_demand":10.0,"name":"Balanced public budget","policy_id":"policy:loran_balanced_budget","political_relief":{"fiscal_pressur... | OBSERVED |
| `policies[].administrative_demand` | `policies[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | [] | 15.0–45.0 | [15.0,20.0,25.0] | OBSERVED |
| `policies[].domain` | `policies[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | ["labor","military_mobilization","public_order","social_spending","tax","trade"] | — | ["labor","military_mobilization","public_order"] | OBSERVED + DECLARED |
| `policies[].fiscal_demand` | `policies[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | [] | 10.0–60.0 | [10.0,15.0,20.0] | OBSERVED |
| `policies[].name` | `policies[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | — | — | ["Balanced public budget","Labor and wage relief","Military mobilization order","Public order administration","Social relief spending","Strategic trade protection"] | — | ["Balanced public budget","Labor and wage relief","Military mobilization order"] | OBSERVED |
| `policies[].policy_id` | `policies[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: vnext.politics.state_politics_1900 | ["policy:loran_balanced_budget","policy:loran_labor_relief","policy:loran_military_mobilization","policy:loran_public_order","policy:loran_social_spending","policy:loran_trade_p... | — | ["policy:loran_balanced_budget","policy:loran_labor_relief","policy:loran_military_mobilization"] | OBSERVED |
| `policies[].political_relief` | `policies[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [{"fiscal_pressure":45.0},{"mobilization_pressure":18.0,"war_pressure":48.0},{"price_pressure":18.0,"unemployment_pressure":55.0}] | OBSERVED |
| `policies[].political_relief.fiscal_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 5 / 6 | null | True | — | — | [] | 45.0–45.0 | [45.0] | OBSERVED |
| `policies[].political_relief.mobilization_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 5 / 6 | null | True | — | — | [] | 18.0–18.0 | [18.0] | OBSERVED |
| `policies[].political_relief.price_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 4 / 6 | null | True | — | — | [] | 18.0–22.0 | [18.0,22.0] | OBSERVED |
| `policies[].political_relief.shortage_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 4 / 6 | null | True | — | — | [] | 20.0–35.0 | [20.0,35.0] | OBSERVED |
| `policies[].political_relief.unemployment_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 4 / 6 | null | True | — | — | [] | 55.0–78.0 | [55.0,78.0] | OBSERVED |
| `policies[].political_relief.war_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 5 / 6 | null | True | — | — | [] | 48.0–48.0 | [48.0] | OBSERVED |
| `policies[].position` | `policies[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | [] | -55.0–70.0 | [-20.0,-55.0,60.0] | OBSERVED |
| `policies[].pressure_targets` | `policies[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | — | — | — | [] | — | [{"casualty_pressure":60.0,"mobilization_pressure":80.0,"war_pressure":80.0},{"fiscal_pressure":70.0},{"price_pressure":20.0,"shortage_pressure":50.0}] | OBSERVED |
| `policies[].pressure_targets.casualty_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 5 / 6 | null | True | — | — | [] | 60.0–60.0 | [60.0] | OBSERVED |
| `policies[].pressure_targets.fiscal_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 5 / 6 | null | True | — | — | [] | 70.0–70.0 | [70.0] | OBSERVED |
| `policies[].pressure_targets.mobilization_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 5 / 6 | null | True | — | — | [] | 80.0–80.0 | [80.0] | OBSERVED |
| `policies[].pressure_targets.price_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 3 / 6 | null | False | — | — | [] | 20.0–25.0 | [20.0,25.0] | OBSERVED |
| `policies[].pressure_targets.shortage_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 4 / 6 | null | True | — | — | [] | 50.0–55.0 | [50.0,55.0] | OBSERVED |
| `policies[].pressure_targets.unemployment_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 4 / 6 | null | True | — | — | [] | 60.0–85.0 | [60.0,85.0] | OBSERVED |
| `policies[].pressure_targets.war_pressure` | `policies[]` | number / declared `—` | False | False | False | False | optional-by-observation | 4 / 6 | null | True | — | — | [] | 20.0–80.0 | [20.0,80.0] | OBSERVED |
| `policies[].required_control` | `policies[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 6 | null | False | — | — | [] | 30.0–45.0 | [30.0,35.0,40.0] | OBSERVED |
| `regime_type` | `document` | string / declared `—` | False | True | True | False | declared-required | 0 / 1 | — | True | — | — | ["absolute_monarchy","colonial_administration","constitutional_monarchy","federal_republic","imperial_bureaucracy","military_rule","parliamentary_monarchy","parliamentary_republ... | — | ["federal_republic"] | OBSERVED + DECLARED |
| `runtime_snapshot.active_policies` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.capacity` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.crisis_stage` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].base_government_support` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].force_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: organization | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].government_eligible` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].government_support` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].influence` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].institutional_access` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].kind` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].last_support_delta` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].leader_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: person | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].mobilization_capacity` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].name` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].policy_preferences` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].pressure_response` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.forces[].support_history` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.government_change_history` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.government_group_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: organization | — | [] | — | [] | DECLARED |
| `runtime_snapshot.government_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: organization | — | [] | — | [] | DECLARED |
| `runtime_snapshot.government_leader_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: person | — | [] | — | [] | DECLARED |
| `runtime_snapshot.government_support` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.government_viability` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.instability_streak` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.last_policy_review_period` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.last_pressure_input` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.legitimacy` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.period_index` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].administrative_demand` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].domain` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].fiscal_demand` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].name` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].policy_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: policy | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].political_relief` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].position` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].pressure_targets` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policies[].required_control` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.policy_history` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.recovery_streak` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.regime_type` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.schema_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.stability` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | — | — | [] | — | [] | DECLARED |
| `runtime_snapshot.state_id` | `document` | UNOBSERVED / declared `—` | — | — | False | True | runtime-snapshot-required | — | null | — | ID_KIND_CONSTRAINT: state | — | [] | — | [] | DECLARED |
| `schema_id` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["vnext_state_politics_catalog_v1"] | — | ["vnext_state_politics_catalog_v1"] | OBSERVED |
| `source_notes` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | — | — | [] | — | [["Reuses the Alpha politics issue and policy domains without importing Alpha service state.","Initial force categories follow the coalition and legitimacy design document.","St... | OBSERVED |
| `source_notes[]` | `source_notes[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | ["Initial force categories follow the coalition and legitimacy design document.","Reuses the Alpha politics issue and policy domains without importing Alpha service state.","Sta... | — | ["Initial force categories follow the coalition and legitimacy design document.","Reuses the Alpha politics issue and policy domains without importing Alpha service state.","Sta... | OBSERVED |
| `stability` | `document` | number / declared `number` | False | True | False | False | required-by-observation | 0 / 1 | 60.0 | True | — | — | [] | 70.0–70.0 | [70.0] | OBSERVED + DECLARED |
| `state_id` | `document` | string / declared `—` | False | True | True | False | declared-required | 0 / 1 | — | True | reference_candidate | — | ["state:loran_federation"] | — | ["state:loran_federation"] | OBSERVED + DECLARED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
