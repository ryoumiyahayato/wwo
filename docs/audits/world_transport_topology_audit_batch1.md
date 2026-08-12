# WWO WORLD TRANSPORT TOPOLOGY AUDIT — BATCH 1 REPORT

Starting master: `4b738ab8b0a21e8685aae95381717e9efd2327a8`

## Scope and safety boundary

This is a deterministic, read-only audit of the existing world-map transport source data and the current map loader contract. The graph is analysis-only; it is not a gameplay authority and does not integrate Economy, Military, or Spatial systems. No file under `data/world_map/` is rewritten by the tool.

Classification policy: `EXPECTED_ISOLATION` means the catalog gives no evidence that a connection is required; `SUSPICIOUS_ISOLATION` is a review item with a major node, declared port, or administrative coverage signal; `BROKEN_REFERENCE` is a concrete schema/reference/cache failure; `AMBIGUOUS` requires domain confirmation because the current data does not declare intent or directionality.

## Summary

| Metric | Result |
| --- | ---: |
| Transport nodes | 40 (32 city + 8 port) |
| Road edges | 3 |
| Rail edges | 9 |
| Shipping edges | 3 |
| Broken references | 0 |
| Suspicious isolated nodes | 18 |
| Unreachable major entities | 14 |
| Candidate fixes | 0 |
| World-map files scanned | 185 |
| World-map JSON parse errors | 0 |
| Production world data modified | **NO** |

## Loader contract

Static loader contract: **PASS**. The current data loader registers ports, road segments, rail segments, and shipping routes; the map canvas reads the same collections and consumes index-aligned transport geometry from `map_geometry_cache.json`.

| Loader file | Status |
| --- | --- |
| `scripts/world_map/internal/world_map_data_impl.gd` | PASS |
| `scripts/world_map/internal/world_map_canvas_impl.gd` | PASS |

## Connected components

| Mode | Catalog components | Nontrivial components | Largest |
| --- | ---: | ---: | ---: |
| road | 29 | 2 | 3 |
| rail | 23 | 1 | 10 |
| shipping | 5 | 2 | 3 |

Nontrivial component membership:

- `road`: lille, paris, rouen; lyon, strasbourg
- `rail`: bordeaux, calais, le_havre, lille, lyon, marseille, nantes, paris, rouen, toulouse
- `shipping`: port_alexandria, port_marseille; port_le_havre, port_london, port_new_york

## Findings by status

- `BROKEN_REFERENCE`: 0
- `SUSPICIOUS_ISOLATION`: 36
- `AMBIGUOUS`: 10
- `EXPECTED_ISOLATION`: 5

## TOP 30 TRANSPORT TOPOLOGY PROBLEMS

Ordered by gameplay impact (Economy, Military, Spatial), then priority, status, check, and stable subject. Expected isolation is retained in the machine-readable matrix but omitted from this ranked problem list.

| Rank | Priority | Status | Check | Mode | Subject | Impact | Message |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `antwerp` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 2 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `beijing` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 3 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `berlin` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 4 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `brussels` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 5 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `buenos_aires` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 6 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `cologne` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 7 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `ghent` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 8 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `istanbul` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 9 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `kolkata` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 10 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `moscow` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 11 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `st_petersburg` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 12 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `tokyo` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 13 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `vienna` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 14 | P1 | SUSPICIOUS_ISOLATION | `ISOLATED_CITY` | — | `washington` | Economy, Military, Spatial | City has no reachable road, rail, or sea connection in the current topology. |
| 15 | P1 | SUSPICIOUS_ISOLATION | `PORT_WITHOUT_SHIPPING_CONNECTIVITY` | — | `port_bordeaux` | Economy, Military, Spatial | Declared port has no connected shipping route. |
| 16 | P1 | SUSPICIOUS_ISOLATION | `PORT_WITHOUT_SHIPPING_CONNECTIVITY` | — | `port_brest` | Economy, Military, Spatial | Declared port has no connected shipping route. |
| 17 | P1 | SUSPICIOUS_ISOLATION | `PORT_WITHOUT_SHIPPING_CONNECTIVITY` | — | `port_calais` | Economy, Military, Spatial | Declared port has no connected shipping route. |
| 18 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `antwerp` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 19 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `beijing` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 20 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `berlin` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 21 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `brussels` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 22 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `buenos_aires` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 23 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `cologne` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 24 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `ghent` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 25 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `istanbul` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 26 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `kolkata` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 27 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `moscow` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 28 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `st_petersburg` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 29 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `tokyo` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |
| 30 | P1 | SUSPICIOUS_ISOLATION | `UNREACHABLE_MAJOR_NODE` | — | `vienna` | Economy, Military, Spatial | Major city is absent from every connected transport mode. |

## Connectivity matrix

Semantics: road/rail/sea columns mean the entity has a non-self reachable path in that mode. For cities and ports, sea uses an associated port; for countries and regions, a column is true when any declared child city/port has that reachability. Multimodal means one representative child can use at least two of road, rail, and sea through the explicit city-port transfer relationship.

| Type | Entity | Road | Rail | Sea | Multimodal | Isolation class | Child cities | Child ports |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: |
| country | `argentine_republic` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| country | `austro_hungarian_empire` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| country | `british_empire` | NO | NO | YES | NO | CONNECTED | 3 | 1 |
| country | `country_afg` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ago` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_alb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_are` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_arm` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ata` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_atf` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_aus` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_aze` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bdi` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bel` | NO | NO | NO | NO | AMBIGUOUS | 5 | 0 |
| country | `country_ben` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bfa` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bgd` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bgr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bhs` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bih` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_blr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_blz` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bol` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bra` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_brn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_btn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_bwa` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_caf` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_can` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_che` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_chl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_civ` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cmr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cod` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cog` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_col` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cri` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cub` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cyn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cyp` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_cze` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_dji` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_dnk` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_dom` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_dza` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ecu` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_egy` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_eri` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_esp` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_est` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_eth` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_fin` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_fji` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_flk` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_fra` | YES | YES | YES | YES | CONNECTED | 11 | 5 |
| country | `country_gab` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_geo` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_gha` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_gin` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_gmb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_gnb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_gnq` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_grc` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_grl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_gtm` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_guy` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_hnd` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_hrv` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_hti` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_hun` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_idn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ind` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_irl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_irn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_irq` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_isl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_isr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ita` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_jam` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_jor` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_kaz` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ken` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_kgz` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_khm` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_kor` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_kos` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_kwt` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lao` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lbn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lbr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lby` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lka` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lso` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ltu` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lux` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_lva` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mar` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mda` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mdg` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mex` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mkd` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mli` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mmr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mne` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mng` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_moz` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mrt` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mwi` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_mys` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_nam` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ncl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ner` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_nga` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_nic` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_nld` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_nor` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_npl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_nzl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_omn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_pak` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_pan` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_per` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_phl` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_png` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_pol` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_pri` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_prk` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_prt` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_pry` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_psx` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_qat` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_rou` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_rwa` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sah` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sau` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sdn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sds` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sen` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_slb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sle` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_slv` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sol` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_som` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_srb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_sur` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_svk` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_svn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_swe` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_swz` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_syr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tcd` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tgo` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tha` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tjk` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tkm` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tls` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tto` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tun` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_twn` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_tza` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_uga` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ukr` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ury` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_uzb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_ven` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_vnm` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_vut` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_yem` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_zaf` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_zmb` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `country_zwe` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| country | `german_empire` | YES | NO | NO | NO | CONNECTED | 3 | 0 |
| country | `japanese_empire` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| country | `ottoman_empire` | NO | NO | YES | NO | CONNECTED | 2 | 1 |
| country | `qing_empire` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| country | `russian_empire` | NO | NO | NO | NO | AMBIGUOUS | 2 | 0 |
| country | `united_states` | NO | NO | YES | NO | CONNECTED | 2 | 1 |
| region | `aquitaine` | NO | YES | NO | NO | CONNECTED | 2 | 1 |
| region | `brittany` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 1 |
| region | `loire_valley` | NO | YES | NO | NO | CONNECTED | 1 | 0 |
| region | `massif_central` | NO | NO | NO | NO | EXPECTED_ISOLATION | 0 | 0 |
| region | `mediterranean_coast` | NO | YES | YES | YES | CONNECTED | 1 | 1 |
| region | `normandy` | YES | YES | YES | YES | CONNECTED | 2 | 1 |
| region | `northern_industrial_belt` | YES | YES | NO | YES | CONNECTED | 2 | 1 |
| region | `paris_basin` | YES | YES | NO | YES | CONNECTED | 1 | 0 |
| region | `rhone_valley` | YES | YES | NO | YES | CONNECTED | 1 | 0 |
| city | `alexandria` | NO | NO | YES | NO | CONNECTED | 1 | 0 |
| city | `antwerp` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `beijing` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `berlin` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `bordeaux` | NO | YES | NO | NO | CONNECTED | 1 | 0 |
| city | `brest` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| city | `brussels` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `buenos_aires` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `calais` | NO | YES | NO | NO | CONNECTED | 1 | 0 |
| city | `cologne` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `dover` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| city | `ghent` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `istanbul` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `kolkata` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `kortrijk` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| city | `le_havre` | NO | YES | YES | YES | CONNECTED | 1 | 0 |
| city | `lille` | YES | YES | NO | YES | CONNECTED | 1 | 0 |
| city | `london` | NO | NO | YES | NO | CONNECTED | 1 | 0 |
| city | `lyon` | YES | YES | NO | YES | CONNECTED | 1 | 0 |
| city | `marseille` | NO | YES | YES | YES | CONNECTED | 1 | 0 |
| city | `moscow` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `nantes` | NO | YES | NO | NO | CONNECTED | 1 | 0 |
| city | `new_york` | NO | NO | YES | NO | CONNECTED | 1 | 0 |
| city | `paris` | YES | YES | NO | YES | CONNECTED | 1 | 0 |
| city | `rouen` | YES | YES | NO | YES | CONNECTED | 1 | 0 |
| city | `st_petersburg` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `strasbourg` | YES | NO | NO | NO | CONNECTED | 1 | 0 |
| city | `tokyo` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `toulouse` | NO | YES | NO | NO | CONNECTED | 1 | 0 |
| city | `tournai` | NO | NO | NO | NO | AMBIGUOUS | 1 | 0 |
| city | `vienna` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| city | `washington` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 0 |
| port | `port_alexandria` | NO | NO | YES | NO | CONNECTED | 1 | 1 |
| port | `port_bordeaux` | NO | YES | NO | NO | CONNECTED | 1 | 1 |
| port | `port_brest` | NO | NO | NO | NO | SUSPICIOUS_ISOLATION | 1 | 1 |
| port | `port_calais` | NO | YES | NO | NO | CONNECTED | 1 | 1 |
| port | `port_le_havre` | NO | YES | YES | YES | CONNECTED | 1 | 1 |
| port | `port_london` | NO | NO | YES | NO | CONNECTED | 1 | 1 |
| port | `port_marseille` | NO | YES | YES | YES | CONNECTED | 1 | 1 |
| port | `port_new_york` | NO | NO | YES | NO | CONNECTED | 1 | 1 |

## Candidate fixes

Candidate output is staging-only. No authoritative transport record is modified by this audit.

No mechanically safe candidate fixes were generated from the current data.

## Tooling and tests

- Tool: `tools/world_map/world_transport_topology_audit.py`
- Focused tests: `tests/tools/test_world_transport_topology_audit.py`
- Machine-readable audit: `docs/audits/world_transport_topology_audit_batch1.json`
- Candidate staging suggestion: `data/staging/world_transport_topology_audit_batch1_candidate_fixes.json`
- This report is generated from the machine-readable artifact; rerunning with the same starting master and source tree must produce byte-identical output.
