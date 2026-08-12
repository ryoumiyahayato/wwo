# WWO World Data Dictionary — Batch 1

<!-- GENERATED FILE. Run tools/world_data_dictionary/generate.py to refresh. -->

This reference is generated from `data/world_map/**`, pure JSON data under `data/vnext/**`, and related loader/parser/validator evidence. It is an inventory of the current state, not a schema redesign.

## Evidence contract

- `OBSERVED`: directly measured from the current JSON files.
- `DECLARED`: exact normalized full-field-path evidence from a loader, validator, or source-config contract.
- `HEURISTIC`: leaf-only, test, tooling, and name-based evidence retained for review; it is not schema authority.
- `RUNTIME_SNAPSHOT`: restore/validator requirements for derived runtime state, not source JSON requirements.
- `ID_KIND_CONSTRAINT`: stable-ID syntax/kind validation only; it does not prove catalog membership.
- `FOREIGN_KEY`: only a resolved loader/catalog reference is declared; name-based links remain candidates or ambiguous.
- `OBSERVED + DECLARED`: both kinds of evidence exist; differences remain visible in each field row.

## Summary

| metric | value |
| --- | ---: |
| datasets documented | 30 |
| fields documented | 1246 |
| declared-schema fields | 60 |
| observed-only fields | 1186 |
| type inconsistencies | 0 |
| potentially ignored/obsolete leads | 1121 |
| foreign-key relationships | 0 |
| foreign-key candidates | 47 |
| ambiguous relationships | 56 |
| data files scanned | 184 |
| loader sources scanned | 99 |

## Dataset reference

| dataset | path | records | fields |
| --- | --- | ---: | ---: |
| [vnext.politics.state_politics_1900](vnext_politics_state_politics_1900.md) | `data/vnext/politics/state_politics_1900.json` | 1 | 117 |
| [world_map.characters](world_map_characters.md) | `data/world_map/characters.json` | 1 | 90 |
| [world_map.cities](world_map_cities.md) | `data/world_map/cities.json` | 32 | 21 |
| [world_map.city_detail.LICENSE](world_map_city_detail_LICENSE.md) | `data/world_map/city_detail/LICENSE.json` | 1 | 5 |
| [world_map.city_detail.country_shards](world_map_city_detail_country_shards.md) | `data/world_map/city_detail/countries/*.json` | 52056 | 35 |
| [world_map.city_detail.france_shards](world_map_city_detail_france_shards.md) | `data/world_map/city_detail/france/*.json` | 36871 | 37 |
| [world_map.city_detail.index](world_map_city_detail_index.md) | `data/world_map/city_detail/index.json` | 144 | 41 |
| [world_map.countries](world_map_countries.md) | `data/world_map/countries.json` | 177 | 45 |
| [world_map.country_flag_palettes](world_map_country_flag_palettes.md) | `data/world_map/country_flag_palettes.json` | 57 | 7 |
| [world_map.historical.cshapes_1900_snapshot](world_map_historical_cshapes_1900_snapshot.md) | `data/world_map/historical/cshapes_1900_snapshot.json` | 151 | 34 |
| [world_map.historical.flags_1900](world_map_historical_flags_1900.md) | `data/world_map/historical/flags_1900.json` | 61 | 37 |
| [world_map.historical.historical_admin1_1900](world_map_historical_historical_admin1_1900.md) | `data/world_map/historical/historical_admin1_1900.json` | 15 | 14 |
| [world_map.historical.major_economy_polity_crosswalk_1900](world_map_historical_major_economy_polity_crosswalk_1900.md) | `data/world_map/historical/major_economy_polity_crosswalk_1900.json` | 2 | 13 |
| [world_map.historical.major_state_profiles_1900](world_map_historical_major_state_profiles_1900.md) | `data/world_map/historical/major_state_profiles_1900.json` | 50 | 22 |
| [world_map.historical.political_units_1900](world_map_historical_political_units_1900.md) | `data/world_map/historical/political_units_1900.json` | 151 | 33 |
| [world_map.historical_political_entities_1900](world_map_historical_political_entities_1900.md) | `data/world_map/historical_political_entities_1900.json` | 61 | 33 |
| [world_map.institutions](world_map_institutions.md) | `data/world_map/institutions.json` | 7 | 63 |
| [world_map.map_geometry_cache](world_map_map_geometry_cache.md) | `data/world_map/map_geometry_cache.json` | 1 | 179 |
| [world_map.map_modes](world_map_map_modes.md) | `data/world_map/map_modes.json` | 4 | 60 |
| [world_map.name_pool_fr](world_map_name_pool_fr.md) | `data/world_map/name_pool_fr.json` | 28 | 25 |
| [world_map.organizations](world_map_organizations.md) | `data/world_map/organizations.json` | 11 | 55 |
| [world_map.ports](world_map_ports.md) | `data/world_map/ports.json` | 8 | 15 |
| [world_map.rail_segments](world_map_rail_segments.md) | `data/world_map/rail_segments.json` | 9 | 14 |
| [world_map.regions](world_map_regions.md) | `data/world_map/regions.json` | 9 | 76 |
| [world_map.relationships](world_map_relationships.md) | `data/world_map/relationships.json` | 10 | 35 |
| [world_map.road_segments](world_map_road_segments.md) | `data/world_map/road_segments.json` | 3 | 11 |
| [world_map.shipping_routes](world_map_shipping_routes.md) | `data/world_map/shipping_routes.json` | 3 | 15 |
| [world_map.world_activity](world_map_world_activity.md) | `data/world_map/world_activity.json` | 6 | 35 |
| [world_map.world_admin1](world_map_world_admin1.md) | `data/world_map/world_admin1.json` | 4589 | 27 |
| [world_map.world_coastlines](world_map_world_coastlines.md) | `data/world_map/world_coastlines.json` | 177 | 52 |

## Top 30 data-schema ambiguities

The list is sorted by risk/severity and stable dataset/field order. High-risk items are the most likely to cause a future Agent to insert an invalid ID, wrong type, or undocumented enum value.

| # | risk | severity | kind | dataset | field | why it matters |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | high | high | `foreign_key_ambiguous_target` | `vnext.politics.state_politics_1900` | `forces[].force_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 2 | high | high | `foreign_key_ambiguous_target` | `vnext.politics.state_politics_1900` | `government_group_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 3 | high | high | `foreign_key_ambiguous_target` | `vnext.politics.state_politics_1900` | `government_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 4 | high | high | `foreign_key_ambiguous_target` | `world_map.characters` | `identities.<key>.city_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 5 | high | high | `foreign_key_ambiguous_target` | `world_map.countries` | `countries[].geometry_feature_ids` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 6 | high | high | `foreign_key_ambiguous_target` | `world_map.countries` | `countries[].geometry_feature_ids[]` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 7 | high | high | `foreign_key_ambiguous_target` | `world_map.historical.political_units_1900` | `units[].geometry_feature_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 8 | high | high | `foreign_key_ambiguous_target` | `world_map.institutions` | `institutions[].city_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 9 | high | high | `foreign_key_ambiguous_target` | `world_map.organizations` | `catalog[].city_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 10 | high | high | `foreign_key_ambiguous_target` | `world_map.ports` | `ports[].city_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 11 | high | high | `foreign_key_ambiguous_target` | `world_map.relationships` | `relationships[].city_id` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 12 | high | high | `foreign_key_ambiguous_target` | `world_map.world_activity` | `items[].city_ids` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 13 | high | high | `foreign_key_ambiguous_target` | `world_map.world_activity` | `items[].city_ids[]` | ID-like field matches multiple plausible target datasets; no target was selected. |
| 14 | high | medium | `duplicate_semantic_fields` | `world_map.countries` | `id / stable_id` | Both look like entity identifiers; the authoritative identity is not declared by the data file. |
| 15 | high | medium | `duplicate_semantic_fields` | `world_map.map_geometry_cache` | `id / stable_id` | Both look like entity identifiers; the authoritative identity is not declared by the data file. |
| 16 | high | medium | `duplicate_semantic_fields` | `world_map.regions` | `id / stable_id` | Both look like entity identifiers; the authoritative identity is not declared by the data file. |
| 17 | high | medium | `duplicate_semantic_fields` | `world_map.world_coastlines` | `id / stable_id` | Both look like entity identifiers; the authoritative identity is not declared by the data file. |
| 18 | high | medium | `foreign_key_unclear_target` | `vnext.politics.state_politics_1900` | `active_policy_ids` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 19 | high | medium | `foreign_key_unclear_target` | `vnext.politics.state_politics_1900` | `active_policy_ids[]` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 20 | high | medium | `foreign_key_unclear_target` | `vnext.politics.state_politics_1900` | `state_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 21 | high | medium | `foreign_key_unclear_target` | `world_map.characters` | `identities.<key>.employer_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 22 | high | medium | `foreign_key_unclear_target` | `world_map.characters` | `identities.<key>.jurisdiction_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 23 | high | medium | `foreign_key_unclear_target` | `world_map.characters` | `identities.<key>.nationality_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 24 | high | medium | `foreign_key_unclear_target` | `world_map.characters` | `identities.<key>.school_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 25 | high | medium | `foreign_key_unclear_target` | `world_map.characters` | `identities.<key>.union_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 26 | high | medium | `foreign_key_unclear_target` | `world_map.characters` | `identities.<key>.workplace_city_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 27 | high | medium | `foreign_key_unclear_target` | `world_map.cities` | `cities[].arrondissement_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 28 | high | medium | `foreign_key_unclear_target` | `world_map.cities` | `cities[].commune_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 29 | high | medium | `foreign_key_unclear_target` | `world_map.cities` | `cities[].departement_id` | ID-like field has no reliable target dataset from name or resolver evidence. |
| 30 | high | medium | `foreign_key_unclear_target` | `world_map.city_detail.country_shards` | `cities[].curated_city_id` | ID-like field has no reliable target dataset from name or resolver evidence. |

## Generated files

- `dictionary.json`: machine-readable dictionary, evidence, relationships, and findings.
- `README.md`: this index and the top ambiguity list.
- `datasets/*.md`: one human-readable reference per logical dataset.

Production data modified: **NO**.
