# world_map.strategic_military_overlay

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

Purpose inferred from the data path and loader evidence.

- Path: `data/world_map/strategic_military_overlay.json`
- Source files: `1`
- Record count (primary collection): `10`
- Documents: `1`
- Root type: `object`
- Primary record path: `country_overlays[]`

## Record collections

| path | records | source files |
| --- | ---: | ---: |
| `city_overlays[]` | 7 | 1 |
| `country_overlays[]` | 10 | 1 |
| `region_overlays[]` | 9 | 1 |
| `terrain_profiles[]` | 7 | 1 |
| `transport_profiles[]` | 3 | 1 |

## Fields

`OBSERVED` values come from JSON. `DECLARED` requires exact normalized field-path evidence. `HEURISTIC` and `RUNTIME_SNAPSHOT` evidence never silently become source-schema authority.

| field | scope | observed type | nullable | required by observation | source config required | runtime snapshot required | required status | missing / records | default | unique | ID | foreign key / candidate | enum candidates | min–max | examples | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| `base_dataset` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["data/world_map"] | — | ["data/world_map"] | OBSERVED |
| `battle_rules` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"attack_preparation_hours":24,"attack_ratio_for_hold":0.85,"attack_ratio_for_win":1.25,"attacker_win_loss_rate":0.08,"defender_garrison_loss_rate_on_win":0.72,"defender_win_lo... | OBSERVED + DECLARED |
| `battle_rules.attack_preparation_hours` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 24.0–24.0 | [24] | OBSERVED |
| `battle_rules.attack_ratio_for_hold` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.85–0.85 | [0.85] | OBSERVED |
| `battle_rules.attack_ratio_for_win` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.25–1.25 | [1.25] | OBSERVED |
| `battle_rules.attacker_win_loss_rate` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.08–0.08 | [0.08] | OBSERVED |
| `battle_rules.defender_garrison_loss_rate_on_win` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.72–0.72 | [0.72] | OBSERVED |
| `battle_rules.defender_win_loss_rate` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.18–0.18 | [0.18] | OBSERVED |
| `battle_rules.defense_posture_multiplier` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 1.2–1.2 | [1.2] | OBSERVED |
| `battle_rules.minimum_power_factor` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.35–0.35 | [0.35] | OBSERVED |
| `battle_rules.stalemate_loss_rate` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.06–0.06 | [0.06] | OBSERVED |
| `city_overlays` | `document` | array / declared `array` | False | True | False | False | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"city_id":"<nested>","defense_factor":"<nested>","role":"<nested>","strategic_value":"<nested>"},{"city_id":"<nested>","defense_factor":"<nested>","role":"<nested>","strategi... | OBSERVED + DECLARED |
| `city_overlays[]` | `city_overlays[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"city_id":"berlin","defense_factor":1.2,"role":"capital","strategic_value":1.0},{"city_id":"le_havre","defense_factor":1.1,"role":"port","strategic_value":0.8},{"city_id":"lil... | OBSERVED |
| `city_overlays[].city_id` | `city_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.cities, world_map.city_detail.country_shards, world_map.city_detail.france_shards | ["berlin","le_havre","lille","london","lyon","marseille","paris"] | — | ["berlin","le_havre","lille"] | OBSERVED |
| `city_overlays[].defense_factor` | `city_overlays[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | 1.08–1.2 | [1.08,1.1,1.12] | OBSERVED |
| `city_overlays[].role` | `city_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | ["capital","port","rail_hub"] | — | ["capital","port","rail_hub"] | OBSERVED |
| `city_overlays[].strategic_value` | `city_overlays[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | False | — | — | [] | 0.8–1.0 | [0.8,0.84,0.86] | OBSERVED |
| `country_overlays` | `document` | array / declared `array` | False | True | False | False | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"country_id":"<nested>","initial_controller_id":"<nested>","initial_garrison_personnel":"<nested>","resources":"<nested>","strategic_value":"<nested>","terrain_id":"<nested>"... | OBSERVED + DECLARED |
| `country_overlays[]` | `country_overlays[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | — | — | — | [] | — | [{"country_id":"argentine_republic","initial_controller_id":"argentine_republic","initial_garrison_personnel":2400,"resources":["<nested>","<nested>"],"strategic_value":0.62,"te... | OBSERVED |
| `country_overlays[].country_id` | `country_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.countries | ["argentine_republic","austro_hungarian_empire","british_empire","country_bel","german_empire","japanese_empire","ottoman_empire","qing_empire","russian_empire","united_states"] | — | ["argentine_republic","austro_hungarian_empire","british_empire"] | OBSERVED |
| `country_overlays[].initial_controller_id` | `country_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | True | reference_candidate | — | ["argentine_republic","austro_hungarian_empire","british_empire","country_bel","german_empire","japanese_empire","ottoman_empire","qing_empire","russian_empire","united_states"] | — | ["argentine_republic","austro_hungarian_empire","british_empire"] | OBSERVED |
| `country_overlays[].initial_garrison_personnel` | `country_overlays[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | [] | 2400.0–6000.0 | [2400,3000,3300] | OBSERVED |
| `country_overlays[].resources` | `country_overlays[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | — | — | — | [] | — | [["coal","steel","industry","rail_hub"],["coal","steel","rail_hub"],["food","coal","industry","port_access"]] | OBSERVED |
| `country_overlays[].resources[]` | `country_overlays[].resources[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 29 | null | False | — | — | ["coal","food","industry","iron","port_access","rail_hub","shipping_hub","steel"] | — | ["coal","food","industry"] | OBSERVED |
| `country_overlays[].strategic_value` | `country_overlays[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | — | — | [] | 0.62–0.9 | [0.62,0.68,0.72] | OBSERVED |
| `country_overlays[].terrain_id` | `country_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 10 | null | False | reference_candidate | — | ["coastal","hills","plains"] | — | ["coastal","hills","plains"] | OBSERVED |
| `overlay_kind` | `document` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | ["military_semantics_only"] | — | ["military_semantics_only"] | OBSERVED |
| `region_overlays` | `document` | array / declared `array` | False | True | False | False | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"initial_controller_id":"<nested>","initial_garrison_personnel":"<nested>","region_id":"<nested>","resources":"<nested>","strategic_value":"<nested>","terrain_id":"<nested>"}... | OBSERVED + DECLARED |
| `region_overlays[]` | `region_overlays[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | — | — | [] | — | [{"initial_controller_id":"country_fra","initial_garrison_personnel":1600,"region_id":"massif_central","resources":["<nested>","<nested>"],"strategic_value":0.48,"terrain_id":"h... | OBSERVED |
| `region_overlays[].initial_controller_id` | `region_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | reference_candidate | — | ["country_fra"] | — | ["country_fra"] | OBSERVED |
| `region_overlays[].initial_garrison_personnel` | `region_overlays[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | — | — | [] | 1600.0–5000.0 | [1600,1800,2100] | OBSERVED |
| `region_overlays[].region_id` | `region_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | reference_candidate | HEURISTIC_FK_CANDIDATE: world_map.regions | ["aquitaine","brittany","loire_valley","massif_central","mediterranean_coast","normandy","northern_industrial_belt","paris_basin","rhone_valley"] | — | ["aquitaine","brittany","loire_valley"] | OBSERVED |
| `region_overlays[].resources` | `region_overlays[]` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | — | — | — | [] | — | [["coal","steel","rail_hub"],["food","industry","rail_hub","capital"],["food","iron"]] | OBSERVED |
| `region_overlays[].resources[]` | `region_overlays[].resources[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 23 | null | False | — | — | ["capital","coal","food","industry","iron","port_access","rail_hub","shipping_hub","steel"] | — | ["capital","coal","food"] | OBSERVED |
| `region_overlays[].strategic_value` | `region_overlays[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | True | — | — | [] | 0.48–1.0 | [0.48,0.55,0.58] | OBSERVED |
| `region_overlays[].terrain_id` | `region_overlays[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 9 | null | False | reference_candidate | — | ["coastal","hills","plains","urban"] | — | ["coastal","hills","plains"] | OBSERVED |
| `resource_ids` | `document` | array / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | — | reference_candidate | — | [] | — | [["food","ammunition","equipment","transport_capacity"]] | OBSERVED |
| `resource_ids[]` | `resource_ids[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 4 | null | True | reference_candidate | — | ["ammunition","equipment","food","transport_capacity"] | — | ["ammunition","equipment","food"] | OBSERVED |
| `schema_version` | `document` | number / declared `integer` | False | True | False | False | required-by-observation | 0 / 1 | -1 | True | — | — | [] | 1.0–1.0 | [1] | OBSERVED + DECLARED |
| `supply_rules` | `document` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | {} | — | — | — | [] | — | [{"equipment_loss_per_day_at_zero":0.025,"full_threshold":0.95,"low_threshold":0.4,"morale_loss_per_day_at_zero":0.05,"morale_recovery_per_day":0.012,"organization_loss_per_day_... | OBSERVED + DECLARED |
| `supply_rules.equipment_loss_per_day_at_zero` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.025–0.025 | [0.025] | OBSERVED |
| `supply_rules.full_threshold` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.95–0.95 | [0.95] | OBSERVED |
| `supply_rules.low_threshold` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.4–0.4 | [0.4] | OBSERVED |
| `supply_rules.morale_loss_per_day_at_zero` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.05–0.05 | [0.05] | OBSERVED |
| `supply_rules.morale_recovery_per_day` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.012–0.012 | [0.012] | OBSERVED |
| `supply_rules.organization_loss_per_day_at_zero` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.07–0.07 | [0.07] | OBSERVED |
| `supply_rules.organization_recovery_per_day` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.018–0.018 | [0.018] | OBSERVED |
| `supply_rules.personnel_loss_per_day_at_zero` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.012–0.012 | [0.012] | OBSERVED |
| `supply_rules.strained_threshold` | `document` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 1 | null | True | — | — | [] | 0.75–0.75 | [0.75] | OBSERVED |
| `terrain_profiles` | `document` | array / declared `array` | False | True | False | False | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"defense_factor":"<nested>","id":"<nested>","movement_factor":"<nested>","supply_factor":"<nested>"},{"defense_factor":"<nested>","id":"<nested>","movement_factor":"<nested>"... | OBSERVED + DECLARED |
| `terrain_profiles[]` | `terrain_profiles[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | — | — | — | [] | — | [{"defense_factor":1.0,"id":"plains","movement_factor":1.0,"supply_factor":1.0},{"defense_factor":1.05,"id":"coastal","movement_factor":0.95,"supply_factor":1.05},{"defense_fact... | OBSERVED |
| `terrain_profiles[].defense_factor` | `terrain_profiles[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 1.0–1.45 | [1.0,1.05,1.1] | OBSERVED |
| `terrain_profiles[].id` | `terrain_profiles[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | primary_candidate | — | ["coastal","desert","forest","hills","mountain","plains","urban"] | — | ["coastal","desert","forest"] | OBSERVED |
| `terrain_profiles[].movement_factor` | `terrain_profiles[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 0.55–1.0 | [0.55,0.65,0.7] | OBSERVED |
| `terrain_profiles[].supply_factor` | `terrain_profiles[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 7 | null | True | — | — | [] | 0.45–1.05 | [0.45,0.62,0.7] | OBSERVED |
| `transport_profiles` | `document` | array / declared `array` | False | True | False | False | required-by-observation | 0 / 1 | [] | — | — | — | [] | — | [[{"minimum_movement_hours":"<nested>","mode":"<nested>","movement_speed_km_per_day":"<nested>"},{"minimum_movement_hours":"<nested>","mode":"<nested>","movement_speed_km_per_da... | OBSERVED + DECLARED |
| `transport_profiles[]` | `transport_profiles[]` | object / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | — | — | — | [] | — | [{"minimum_movement_hours":12,"mode":"rail","movement_speed_km_per_day":320.0},{"minimum_movement_hours":18,"mode":"road","movement_speed_km_per_day":75.0},{"minimum_movement_ho... | OBSERVED |
| `transport_profiles[].minimum_movement_hours` | `transport_profiles[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | [] | 12.0–24.0 | [12,18,24] | OBSERVED |
| `transport_profiles[].mode` | `transport_profiles[]` | string / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | ["rail","road","shipping"] | — | ["rail","road","shipping"] | OBSERVED |
| `transport_profiles[].movement_speed_km_per_day` | `transport_profiles[]` | number / declared `—` | False | True | False | False | required-by-observation | 0 / 3 | null | True | — | — | [] | 75.0–480.0 | [320.0,480.0,75.0] | OBSERVED |

## Geometry evidence

- None observed.

## Notes

- Observed fields and values are derived from the current JSON inputs.
- Declared evidence comes only from explicit loader/validator access, type, default, required-list, or enum evidence.
- This dictionary does not redefine the production schema and does not imply that every loader access is a required field.
