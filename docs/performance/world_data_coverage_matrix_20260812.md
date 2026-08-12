# WWO WORLD DATA COVERAGE MATRIX — BATCH 2

Read-only deterministic inventory of every JSON file below `data/world_map`.

- Tool: `wwo_world_data_coverage_audit_batch_2` schema v1
- Files: **183**; raw size: **47.58 MiB**
- Manifest validation: **PASS**
- Authoritative world-map JSON was not modified.

## Category coverage

| Category | Files | Raw bytes | Records | Objects | Arrays | Geometry vertices | Decoded estimate | Parse errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| city_detail_country_shard | 143 | 22.02 MiB | 52056 | 52199 | 52342 | 0 | 94.87 MiB | 0 |
| city_detail_metadata | 2 | 35.1 KiB | 300 | 305 | 447 | 0 | 180.5 KiB | 0 |
| city_detail_region_shard | 13 | 16.08 MiB | 36871 | 36884 | 36897 | 0 | 67.68 MiB | 0 |
| historical | 8 | 6.32 MiB | 5235 | 5556 | 320135 | 925954 | 35.34 MiB | 0 |
| runtime_loader | 16 | 3.12 MiB | 544 | 3920 | 120635 | 200203 | 19.19 MiB | 0 |
| runtime_supporting | 1 | 4.4 KiB | 0 | 59 | 57 | 0 | 25.1 KiB | 0 |

## Runtime-loader matrix

| Path | Present | Category | Bytes | SHA-256 prefix | Parse |
|---|---|---|---:|---|---|
| `world_coastlines.json` | yes | runtime_loader | 439.9 KiB | `2c47f66e49af` | ok |
| `countries.json` | yes | runtime_loader | 175.2 KiB | `29159c677756` | ok |
| `regions.json` | yes | runtime_loader | 441.1 KiB | `65e885135016` | ok |
| `cities.json` | yes | runtime_loader | 7.3 KiB | `62466f51461e` | ok |
| `ports.json` | yes | runtime_loader | 1.9 KiB | `05a11d928080` | ok |
| `rail_segments.json` | yes | runtime_loader | 1.6 KiB | `83303792e438` | ok |
| `road_segments.json` | yes | runtime_loader | 468 B | `d34edf3ab6bf` | ok |
| `shipping_routes.json` | yes | runtime_loader | 859 B | `3812b7e48128` | ok |
| `characters.json` | yes | runtime_loader | 6.6 KiB | `3e801c64bd31` | ok |
| `name_pool_fr.json` | yes | runtime_loader | 10.4 KiB | `a5ce3ad10b8d` | ok |
| `relationships.json` | yes | runtime_loader | 6.3 KiB | `e54d39945fb0` | ok |
| `organizations.json` | yes | runtime_loader | 11.3 KiB | `7b2d9c5dc440` | ok |
| `institutions.json` | yes | runtime_loader | 10.3 KiB | `f41f6ac544bc` | ok |
| `world_activity.json` | yes | runtime_loader | 4.5 KiB | `6039bee199be` | ok |
| `map_modes.json` | yes | runtime_loader | 1.9 KiB | `fb94900bb014` | ok |
| `map_geometry_cache.json` | yes | runtime_loader | 2.03 MiB | `816acc92ba54` | ok |

## Largest structures

| Kind | File | Path | Count |
|---|---|---|---:|
| file | `city_detail/countries/US.json` | — | 3369040 |
| file | `city_detail/countries/IN.json` | — | 2868836 |
| file | `city_detail/countries/DE.json` | — | 1390213 |
| records | `city_detail/countries/US.json` | `$.cities` | 7555 |
| records | `city_detail/countries/IN.json` | `$.cities` | 6526 |
| records | `city_detail/countries/DE.json` | `$.cities` | 3076 |
| array | `city_detail/countries/US.json` | `$.cities` | 7555 |
| array | `city_detail/countries/IN.json` | `$.cities` | 6526 |
| file | `city_detail/index.json` | — | 35669 |
| file | `city_detail/LICENSE.json` | — | 239 |
| records | `city_detail/index.json` | `$.countries` | 144 |
| records | `city_detail/index.json` | `$.countries[42].shards` | 13 |
| records | `city_detail/index.json` | `$.countries[0].shards` | 1 |
| array | `city_detail/index.json` | `$.countries` | 144 |
| array | `city_detail/index.json` | `$.countries[42].shards` | 13 |
| file | `city_detail/france/FR-44.json` | — | 2415886 |
| file | `city_detail/france/FR-76.json` | — | 2095488 |
| file | `city_detail/france/FR-75.json` | — | 2041032 |
| records | `city_detail/france/FR-44.json` | `$.cities` | 5295 |
| records | `city_detail/france/FR-76.json` | `$.cities` | 4612 |
| records | `city_detail/france/FR-75.json` | `$.cities` | 4459 |
| array | `city_detail/france/FR-44.json` | `$.cities` | 5295 |
| array | `city_detail/france/FR-76.json` | `$.cities` | 4612 |
| file | `world_admin1.json` | — | 5897821 |
| file | `historical/cshapes_1900_snapshot.json` | — | 523432 |
| file | `historical/political_units_1900.json` | — | 85456 |
| records | `world_admin1.json` | `$.regions` | 4589 |
| records | `historical/cshapes_1900_snapshot.json` | `$.features` | 151 |
| records | `historical/political_units_1900.json` | `$.units` | 151 |
| array | `world_admin1.json` | `$.regions` | 4589 |
| array | `historical/cshapes_1900_snapshot.json` | `$.features[52].geometry.coordinates[68][0]` | 1739 |
| file | `map_geometry_cache.json` | — | 2128382 |
| file | `regions.json` | — | 451662 |
| file | `world_coastlines.json` | — | 450480 |
| records | `countries.json` | `$.countries` | 177 |
| records | `world_coastlines.json` | `$.features` | 177 |
| records | `regions.json` | `$.administrative_units` | 98 |
| array | `map_geometry_cache.json` | `$.macro_regions[8].lods.lod4[6].triangles` | 2403 |
| array | `map_geometry_cache.json` | `$.country_lods.lod4[159].polygons[7].triangles` | 1596 |
| file | `country_flag_palettes.json` | — | 4472 |
| array | `country_flag_palettes.json` | `$.palettes.AUT.colors` | 4 |
| array | `country_flag_palettes.json` | `$.palettes.ZAF.colors` | 4 |

## Schema-family matrix

| Root type | Top-level key signature | Files |
|---|---|---:|
| dict | `admin1_code, bounds, cities, continent, count, country_code, country_name, dataset, generated_at, license, municipality_detail, schema_version, shard_id, source` | 13 |
| dict | `administrative_geometry_notice, administrative_units, coverage, focus_country_id, macro_region_notice, prototype_only, regions, schema_version, source` | 1 |
| dict | `administrative_lods, anchors, country_lods, generated_by, graticule, lod_thresholds, macro_regions, projection, prototype_only, schema_version, transport, war_example` | 1 |
| dict | `approximation_notice, conflicts, entities, fallback_notice, prototype_only, schema_version, year` | 1 |
| dict | `attribution, dataset, license, license_url, source` | 1 |
| dict | `audit, coordinate_system, features, prototype_only, schema_version, source` | 1 |
| dict | `audit, regions, schema_version, source` | 1 |
| dict | `boundary_notice, detail_node_policy, label_budgets, levels, modes, peace_note, prototype_only, schema_version, shared_basemap_id, transport_legend, war_note, zoom` | 1 |
| dict | `bounds, cities, continent, count, country_code, country_name, dataset, generated_at, license, schema_version, shard_id, source` | 143 |
| dict | `catalog, identities, prototype_only, schema_version` | 1 |
| dict | `cities, prototype_only, schema_version` | 1 |
| dict | `countries, dataset, generated_at, geographic_scope, historical_status, runtime_policy, schema_version, source, totals` | 1 |
| dict | `countries, hierarchy, historical_notice, name_coverage, prototype_only, schema_version` | 1 |
| dict | `countries, policy, schema_version, snapshot_date` | 1 |
| dict | `country, institutions, official_locks, official_permissions, prototype_only, schema_version` | 1 |
| dict | `culture_id, family_names, given_names, prototype_only, schema_version, scope_notice, source_id` | 1 |
| dict | `default_summary, items, prototype_only, schema_version, simulation_status` | 1 |
| dict | `feature_count, features, provider, schema_version, snapshot_date, source` | 1 |
| dict | `geometry_provider, policy, schema_version, snapshot_date, unit_count, units` | 1 |
| dict | `identities, prototype_only, schema_version` | 1 |
| dict | `observer_notes_zh, profiles, schema_version, selection_policy, snapshot_date` | 1 |
| dict | `palettes, prototype_notice, schema_version` | 1 |
| dict | `policy, record_count, records, schema_version, snapshot_date, unit_flag_mode_counts` | 1 |
| dict | `policy, records, schema_id, snapshot_date` | 1 |
| dict | `ports, prototype_only, schema_version` | 1 |
| dict | `prototype_only, relationships, schema_version` | 1 |
| dict | `prototype_only, routes, schema_version, type` | 1 |
| dict | `prototype_only, schema_version, segments, type` | 2 |

## Determinism and safety

- Files are traversed in sorted relative-path order and each file is parsed sequentially.
- SHA-256, sizes, category summaries, schema families and validation fields are stable for unchanged inputs.
- No synthetic or copied authoritative data is written; output is a manifest/report only.
- Real process RSS/heap is outside this audit's reliable measurement boundary: **NOT MEASURED**.

## Validation

- Full JSON coverage: PASS.
- Runtime loader coverage: 16/16 paths declared and present.
- Focused validator and deterministic replay are tracked separately in the Batch 2/3 test tooling.
