# WWO WORLD NAMES & ALIASES — BATCH 1 REPORT

Starting master: `4b738ab`

## Inventory

- Entities inventoried: **923** (502 authoritative Stable IDs; source-record keys remain non-authoritative)
- Unique raw names: **1418**
- Normalized collisions: **138**
- High-confidence aliases: **2232**
- Historical-name candidates: **690**
- Ambiguous mappings: **133**
- Missing display names: **0**

Modern GeoNames city shards and geometry/runtime files were read for source coverage, but modern reference records are not staged as 1900 authoritative entities by default.

## Validation

- Search index: PASS — 941 normalized keys, 133 one-to-many collisions
- Validator: **PASS**
- Deterministic replay: **PASS**
- `git diff --check`: **PASS**

## Authority and delivery

- Authoritative IDs changed: **NO**
- Existing production world data rewritten: **NO**
- Commit: `not created`
- Push: `not attempted (GitHub unavailable in this environment)`
- Draft PR: `none`

## TOP 50 NAME / ALIAS CLEANUP TARGETS

1. `波多黎各` — normalized_collision / high — country_pri, cshapes_gw_6, source:data/world_map/historical/historical_admin1_1900.json#$.countries[8].units[51] — 波多黎各
2. `afghanistan` — normalized_collision / medium — country_afg, emirate_of_afghanistan — Afghanistan
3. `algeria` — normalized_collision / medium — country_dza, cshapes_gw_615 — Algeria
4. `andré` — normalized_collision / medium — source:data/world_map/name_pool_fr.json#$.family_names[25], source:data/world_map/name_pool_fr.json#$.given_names[13] — André
5. `angola` — normalized_collision / medium — country_ago, cshapes_gw_540 — Angola
6. `belgium` — normalized_collision / medium — country_bel, kingdom_of_belgium — Belgium
7. `belize` — normalized_collision / medium — country_blz, cshapes_gw_80 — Belize
8. `benin` — normalized_collision / medium — country_ben, cshapes_gw_434 — Benin
9. `bhutan` — normalized_collision / medium — country_btn, kingdom_of_bhutan — Bhutan
10. `bolivia` — normalized_collision / medium — bolivia_1900, country_bol — Bolivia
11. `botswana` — normalized_collision / medium — country_bwa, cshapes_gw_571 — Botswana
12. `brazil` — normalized_collision / medium — brazil_1900, country_bra — Brazil
13. `brunei` — normalized_collision / medium — country_brn, sultanate_of_brunei — Brunei
14. `bulgaria` — normalized_collision / medium — country_bgr, principality_of_bulgaria — Bulgaria
15. `canada` — normalized_collision / medium — country_can, dominion_of_canada — Canada
16. `chile` — normalized_collision / medium — chile_1900, country_chl — Chile
17. `colombia` — normalized_collision / medium — country_col, republic_of_colombia_1900 — Colombia
18. `costa rica` — normalized_collision / medium — costa_rica_1900, country_cri — Costa Rica
19. `cuba` — normalized_collision / medium — country_cub, cuba_occupation_1900 — Cuba
20. `denmark` — normalized_collision / medium — country_dnk, kingdom_of_denmark — Denmark
21. `djibouti` — normalized_collision / medium — country_dji, cshapes_gw_522 — Djibouti
22. `dominican republic` — normalized_collision / medium — country_dom, dominican_republic_1900 — Dominican Republic
23. `east timor` — normalized_collision / medium — country_tls, cshapes_gw_860 — East Timor
24. `ecuador` — normalized_collision / medium — country_ecu, ecuador_1900 — Ecuador
25. `egypt` — normalized_collision / medium — country_egy, khedivate_of_egypt — Egypt
26. `el salvador` — normalized_collision / medium — country_slv, el_salvador_1900 — El Salvador
27. `equatorial guinea` — normalized_collision / medium — country_gnq, cshapes_gw_411 — Equatorial Guinea
28. `eritrea` — normalized_collision / medium — country_eri, cshapes_gw_531 — Eritrea
29. `ethiopia` — normalized_collision / medium — country_eth, ethiopian_empire — Ethiopia
30. `fiji` — normalized_collision / medium — country_fji, cshapes_gw_950 — Fiji
31. `gabon` — normalized_collision / medium — country_gab, cshapes_gw_481 — Gabon
32. `ghana` — normalized_collision / medium — country_gha, cshapes_gw_452 — Ghana
33. `greece` — normalized_collision / medium — country_grc, kingdom_of_greece — Greece
34. `guatemala` — normalized_collision / medium — country_gtm, guatemala_1900 — Guatemala
35. `guinea` — normalized_collision / medium — country_gin, cshapes_gw_438 — Guinea
36. `guinea bissau` — normalized_collision / medium — country_gnb, cshapes_gw_404 — Guinea-Bissau
37. `guyana` — normalized_collision / medium — country_guy, cshapes_gw_110 — Guyana
38. `haiti` — normalized_collision / medium — country_hti, haiti_1900 — Haiti
39. `honduras` — normalized_collision / medium — country_hnd, honduras_1900 — Honduras
40. `iceland` — normalized_collision / medium — country_isl, iceland_under_denmark — Iceland
41. `india` — normalized_collision / medium — country_ind, cshapes_gw_750 — India
42. `indonesia` — normalized_collision / medium — country_idn, cshapes_gw_850 — Indonesia
43. `jamaica` — normalized_collision / medium — country_jam, cshapes_gw_51 — Jamaica
44. `kenya` — normalized_collision / medium — country_ken, cshapes_gw_501 — Kenya
45. `laos` — normalized_collision / medium — country_lao, cshapes_gw_812 — Laos
46. `lesotho` — normalized_collision / medium — country_lso, cshapes_gw_570 — Lesotho
47. `liberia` — normalized_collision / medium — country_lbr, republic_of_liberia — Liberia
48. `luxembourg` — normalized_collision / medium — country_lux, grand_duchy_of_luxembourg — Luxembourg
49. `malawi` — normalized_collision / medium — country_mwi, cshapes_gw_553 — Malawi
50. `mexico` — normalized_collision / medium — country_mex, mexican_republic — Mexico

No merge performed by this task.
