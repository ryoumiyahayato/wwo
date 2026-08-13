# WWO World Data Foundation — Batch 1 Audit

This report is generated from `data/world_map/**/*.json` by the read-only validator.

## Inventory

- Files: 184
- Countries: 177
- Regions: 9
- Curated cities: 32
- Ports: 8
- Roads / rails / shipping: 3 / 9 / 3
- Historical political entities: 61
- Organizations / institutions / characters: 11 / 7 / 2
- Geometry-bearing catalog objects: 5015
- Modern city-detail records: 88927

## Findings

- Total: 110
- ERROR / WARNING / INFO: 104 / 6 / 0

| Severity | Code | Location | Message |
|---|---|---|---|
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1026].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[103].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1055].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1219].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1236].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1236].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1252].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1257].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1268].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1290].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[129].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1335].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1337].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1339].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1392].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1410].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1417].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1599].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1613].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[161].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[162].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[163].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1734].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1747].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1748].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1750].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1753].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[175].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1762].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1773].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1788].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1819].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1830].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1861].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1888].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1920].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1981].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[1982].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2016].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2025].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2026].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2037].polygons[3]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2077].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2081].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2083].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2085].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2096].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2115].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2118].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2145].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2166].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2172].polygons[1]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2172].polygons[4]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2174].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2178].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2180].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2215].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2236].polygons[1]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2250].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2345].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2346].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2354].polygons[3]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2363].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2367].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2398].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2410].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2411].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2412].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2430].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2437].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2440].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2542].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2543].polygons[1]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2547].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2548].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2559].polygons[4]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2624].polygons[1]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[267].polygons[1]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2757].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2829].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2889].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2894].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2987].polygons[1]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2989].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2995].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2995].polygons[3]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[2].polygons[3]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[3082].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[3110].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[3111].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[335].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[3806].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[3828].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[3].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[408].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[4349].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[438].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[531].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[574].polygons[2]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[620].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[621].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[847].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[953].polygons[0]` | polygon ring self-intersects |
| ERROR | SELF_INTERSECTING_RING | `world_admin1.json:regions[977].polygons[0]` | polygon ring self-intersects |
| WARNING | PLACEHOLDER_FOREIGN_KEY | `institutions.json:institutions[0].parent_institution_id` | parent institution reference 'interior_ministry_placeholder' does not resolve |
| WARNING | PLACEHOLDER_FOREIGN_KEY | `institutions.json:institutions[3].parent_institution_id` | parent institution reference 'labor_ministry_placeholder' does not resolve |
| WARNING | PLACEHOLDER_FOREIGN_KEY | `institutions.json:institutions[4].administrative_unit_id` | admin unit or country reference 'departement_seine_inferieure_placeholder' does not resolve |
| WARNING | PLACEHOLDER_FOREIGN_KEY | `institutions.json:institutions[4].parent_institution_id` | parent institution reference 'interior_ministry_placeholder' does not resolve |
| WARNING | PLACEHOLDER_FOREIGN_KEY | `institutions.json:institutions[5].administrative_unit_id` | admin unit or country reference 'commune_marseille_placeholder' does not resolve |
| WARNING | PLACEHOLDER_FOREIGN_KEY | `institutions.json:institutions[5].parent_institution_id` | parent institution reference 'commerce_ministry_placeholder' does not resolve |

## Staging

Derived reverse indexes and geometry metadata are written only to `staging_candidates.json` when an output directory is requested.

## Authoritative data

Production authoritative data modified: NO.
