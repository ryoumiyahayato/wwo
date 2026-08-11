# WWO 1900 World Data Source Pack — Batch 1

## Scope and handoff state

This batch establishes an isolated, provenance-first staging pack for the 1900-03-12 world snapshot. It does not promote any fact into runtime-authoritative data and does not alter gameplay balance, simulation formulas, or vNext code.

- Starting `origin/master`: `4b738ab8b0a21e8685aae95381717e9efd2327a`
- Working branch: `data/1900-world-source-pack-20260812`
- Working tree: `D:\wwo\worktrees\data-1900-world-source-pack-20260812`
- Snapshot date: `1900-03-12`
- Runtime-authoritative data changed: **NO**
- Runtime integration: **NO**
- Gameplay balancing: **NO**

## Inventory completed

The inventory distinguishes named historical records from supporting geometry, flags, and transport fixtures:

| Area | Records / objects | Treatment |
| --- | ---: | --- |
| Aggregate historical political entities | 61 | Existing prototype source inventory |
| Historical event overlays | 4 | Existing conflict/event overlays; not merged as facts |
| Dated political units | 151 | Existing CShapes-derived snapshot |
| Major state profiles | 50 | Existing profile inventory |
| Historical administrative country rows | 15 | Existing regional coverage |
| Economy polity crosswalk rows | 2 | Existing supporting inventory |
| **Named historical record total** | **283** | Count used by the pack manifest |
| CShapes feature geometries | 151 | Supporting geometry, not a new fact layer |
| Flag records | 151 | Supporting presentation inventory |
| Current countries | 177 | Canonical ID inventory |
| Current regions / administrative units | 9 / 98 | Supporting map inventory |
| Current cities / ports | 32 / 8 | Incomplete historical coverage |
| Rail / shipping route fixtures | 9 / 3 | Incomplete historical coverage |

The existing vNext politics fixture is excluded from the source pack. The inventory also identifies nine current country records not referenced by the historical aggregate crosswalk: `country_prk`, `country_sds`, `country_ata`, `country_sol`, `country_tto`, `country_atf`, `country_cyn`, `country_kos`, and `country_lux`.

## Canonical crosswalk

The crosswalk contains all 61 aggregate historical entities and all 177 current canonical country IDs. Matching is conservative: a composite, fragmented, contested, or personal-union entity is not collapsed into a modern country merely to improve coverage.

| Status | Count |
| --- | ---: |
| EXACT | 40 |
| LIKELY | 16 |
| AMBIGUOUS | 5 |
| NO_MATCH | 0 |

`EXACT` is reserved for a one-to-one current canonical ID resolution. `LIKELY` records a source-backed composite or otherwise qualified mapping. `AMBIGUOUS` preserves the uncertainty for review. The five ambiguous records are not automatic authoritative candidates.

## Source manifest

Seven sources are catalogued with locator, source type, date, license or usage limit, and access date in [`source_manifest.json`](../../../data/staging/1900/source_manifest.json):

1. CShapes 2.0 official dataset page and its 1886–2019 historical border/capital coverage.
2. The CShapes 2.0 publication and DOI record.
3. The repository's existing transformed 1900 snapshot and attribution record.
4. *The Statesman's Year-Book* 1900 contemporary reference source.
5. The U.S. Census Bureau's official 1900 population report.
6. The Maddison Project historical development data landing page.
7. Clio Infra historical social and economic indicators.

The first staging facts use the existing CShapes-derived repository snapshot and retain source locators; the additional sources are registered for subsequent batches and are not silently substituted for missing facts.

## First staging facts

[`source_records.json`](../../../data/staging/1900/source_records.json) contains 28 high-confidence or reviewable facts, all marked `STAGED_NOT_RUNTIME`:

- 20 `entity_exists` records for dated political entities, including their source-reported capital names where available.
- 8 `sovereignty_relationship` records covering dominion, condominium, colony, protectorate, and controlled-territory examples.
- Confidence split: 20 `high`, 8 `medium`.
- No gameplay coefficient, production value, combat value, or inferred institutional score is staged.

The source-record contract is defined in [`source_record.schema.json`](../../../data/staging/1900/source_record.schema.json). Stable IDs, explicit date intervals, source locators, ambiguity notes, conflict groups, and review status are mandatory fields.

## Conflict handling

[`conflict_register.json`](../../../data/staging/1900/conflict_register.json) currently has zero conflicts requiring review. This means the first batch did not merge competing source values; it does not claim that historical disagreements do not exist. Future conflicting facts must receive a conflict group, retain both source values, and remain out of runtime until reviewed. Existing four repository event overlays are tracked as an inventory item rather than treated as resolved source conflicts.

## Coverage gaps and next actions

The most important missing categories are global administrative-unit coverage, capital and major-city identity, port identity, rail and maritime connections, population and urbanization, industry and resources, office holders and institutions, military and naval bases, and legally distinct colonial/diplomatic relationships. Historical geometry exceptions also need explicit composed or fragmented representations.

The complete ranked Top 50 backlog is in [`priority_backlog.json`](../../../data/staging/1900/priority_backlog.json) and is reproduced below by rank and target ID:

1. `crosswalk:political_units_1900_to_canonical`
2. `capital:40_exact_entities_to_city_ids`
3. `relationship:98_controller_links`
4. `admin1:british_india_1900`
5. `admin1:french_colonial_empire_1900`
6. `admin1:german_colonial_empire_1900`
7. `admin1:ottoman_empire_1900`
8. `admin1:qing_empire_1900`
9. `admin1:russian_empire_1900`
10. `admin1:austria_hungary_1900`
11. `population:country_totals_1900`
12. `population:united_states_1900`
13. `population:british_empire_1900`
14. `population:qing_empire_1900`
15. `population:russian_empire_1900`
16. `population:india_1901`
17. `population:japan_1900`
18. `population:austria_hungary_1900`
19. `population:ottoman_empire_1900`
20. `urbanization:major_cities_1900`
21. `city:historical_capital_aliases`
22. `port:major_port_identity`
23. `port:london`
24. `port:calcutta`
25. `port:manila`
26. `port:alexandria`
27. `port:new_york`
28. `rail:europe_major_lines`
29. `rail:british_india_network`
30. `rail:united_states_network`
31. `rail:trans_siberian_status`
32. `maritime:suez_route`
33. `maritime:north_atlantic`
34. `maritime:indian_ocean`
35. `industry:coal_regions_1900`
36. `industry:iron_and_steel_regions_1900`
37. `resource:oil_fields_1900`
38. `resource:chile_copper_nitrate`
39. `resource:southeast_asia_rubber`
40. `resource:argentine_grain_and_livestock`
41. `government:regime_labels_1900`
42. `leadership:office_holders_1900`
43. `military:formations_and_totals`
44. `naval:strategic_bases`
45. `institutions:major_state_institutions`
46. `colonial:legal_status_and_control`
47. `diplomacy:bilateral_relations_1900`
48. `city:major_city_identity_1900`
49. `geometry:historical_exceptions`
50. `review:source_conflict_queue`

## Validation and protected scope

The standalone validator is [`validate_1900_source_pack.py`](../../../tools/historical_data/validate_1900_source_pack.py). It checks JSON parsing, schema-required fields, source IDs, canonical ID coverage, duplicate and overlapping facts, crosswalk status totals, provenance, conflict policy, backlog size, and deterministic SHA-256 digests. The successful run reported:

- 0 errors and 0 warnings.
- 50 backlog targets.
- 7 manifest sources.
- 61 crosswalk records with 40 EXACT, 16 LIKELY, 5 AMBIGUOUS, and 0 NO_MATCH.
- 28 staging records with 20 `entity_exists` and 8 `sovereignty_relationship` facts.
- 0 conflicts requiring review.

The pack is confined to `data/staging/1900/`, `docs/data_sources/1900/`, and the dedicated validator. Protected runtime data, vNext scripts, workflows, and authoritative country/region/city/political-entity/institution/organization files are unchanged.

Repository-level `git diff --check`, the unified validation script, and the final branch handoff are recorded in the task handoff after those commands complete.
