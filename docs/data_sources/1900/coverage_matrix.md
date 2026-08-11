# WWO 1900 existing-data coverage matrix

Snapshot: `1900-03-12` data view, audited from starting master
`4b738ab8b0a21e8685aae95381717e9efd2327a` on 2026-08-12.

This matrix distinguishes historical evidence from current prototype content.
An existing JSON record is not automatically a historical fact: several files
explicitly describe themselves as prototype, estimate, fallback, or gameplay
fixtures.

## Repository inventory

| Area | Existing records | Current evidence | 1900 coverage and gap | Crosswalk / geometry state |
| --- | ---: | --- | --- | --- |
| Political entities | 61 aggregate entities; 4 event/geometry overlays | `data/world_map/historical_political_entities_1900.json` | Broad named coverage, but the file is `prototype_only` and warns that modern polygons were aggregated or used as fallback. | 40 `EXACT`, 16 `LIKELY`, 5 `AMBIGUOUS`, 0 `NO_MATCH` against current country IDs. Composite entities do not receive a single forced ID. |
| Dated political units | 151 units | `data/world_map/historical/political_units_1900.json` | Strongest existing dated political-unit layer; includes names, validity intervals, status, relationship, controller, and capital. | 151 corresponding CShapes geometry features; unit-level identity is not the same as a current country ID. |
| Historical geometry | 151 features | `data/world_map/historical/cshapes_1900_snapshot.json` | Global dated geometry snapshot for the provider units. | The 61 aggregate entities have no guaranteed one-to-one geometry. Composite, fragmented, and contested records require composed or neutral rendering. |
| Capitals | 151 provider capital fields | `political_units_1900.json` | Capital names and coordinates exist for provider units. | Only a small subset overlaps the current 32-city prototype; no global historical city crosswalk is complete. |
| Sovereignty/dependency | 98 units with a controller; 53 independent units | `political_units_1900.json` | Explicit status/relationship vocabulary exists: controlled territory, protectorate, occupation, condominium, dominion, and independent state. | Controller IDs are historical IDs; legal sovereignty and effective control are not yet separate normalized facts. |
| Administrative regions | 9 France gameplay macro regions; 98 France administrative units; 15 historical admin1 country groups | `data/world_map/regions.json`, `historical_admin1_1900.json` | France has broad modern-boundary placeholders; global 1900 admin1 coverage is missing. | France geometry is documented as a modern Natural Earth placeholder; other historical admin1 groups need source-backed geometry. |
| Major cities | 32 | `data/world_map/cities.json` | Mostly France plus selected European, U.S., Qing, Ottoman, Russian, Japanese, Indian, and Argentine cities. No historical population/date fields. | Historical capital names are not automatically mapped to these IDs. |
| Major ports | 8 | `data/world_map/ports.json` | Prototype points only; no source-backed 1900 status, throughput, facilities, or ownership record. | Five are French, one British, one U.S., one Ottoman; global coverage is absent. |
| Rail connections | 9 map segments; 50 domestic rows in Alpha transport estimates | `data/world_map/rail_segments.json`, `data/alpha/historical_transport_network_1900/transport_compact.json` | Topology exists for a prototype, but historical opening dates, operators, and route evidence are incomplete. | No authoritative historical rail crosswalk; Alpha rows remain estimated and isolated. |
| Maritime connections | 3 map routes; 30 maritime rows in Alpha transport estimates | `data/world_map/shipping_routes.json`, Alpha transport compact table | Corridor placeholders exist, not source-backed 1900 services or volumes. | No strategic route/base evidence set. |
| Population totals | 50 compact economy rows plus 8 residual aggregates | `data/alpha/historical_world_economy_1900/**` | Estimates and method metadata exist, but source dates, political-unit overlap, and confidence vary. | Not promoted into this batch; no gameplay coefficients inferred. |
| Regional population | 8 France macro regions in economy integration; 15 historical admin1 groups | Alpha economy files and `historical_admin1_1900.json` | Partial and uneven; no global region-level population staging. | Modern administrative boundaries are not silently treated as 1900 boundaries. |
| Urbanization | Listed as an economy coverage dimension; no global verified table | `data/alpha/historical_economy_coverage_1900.json` | Source-required for most entities; no normalized city/urban definition layer. | Requires source-specific urban definitions before comparison. |
| Industries / commodities | 67 commodities; 49 production sites | `data/alpha/commodity_market_1900.json` | Model estimates and production sites exist, but factual provenance and regional source dates are incomplete. | Explicitly excluded from authoritative staging and gameplay balancing. |
| Government / regime | 7 fictional force records; 6 policies | `data/vnext/politics/state_politics_1900.json` | vNext politics is a fictional fixture, not a world-history baseline. | No historical regime fact is promoted from it. |
| Organizations / institutions | 11 organizations; 7 institutions | `data/world_map/organizations.json`, `institutions.json` | France-centered prototype social structures; no source-backed global 1900 institution catalog. | Current IDs are not treated as historical institutions. |
| Characters / leaders | 2 prototype character identities; 0 historical leaders | `data/world_map/characters.json` | Demo characters are fictional/prototype; no dated historical office-holder records. | No leader crosswalk is staged. |
| Military formations / force totals | 7 fictional politics force entries | `state_politics_1900.json` | No source-backed global 1900 formation/force catalog. | Must remain raw historical counts, never combat effectiveness. |
| Strategic naval bases | 0 | No dedicated source-backed file | Missing. | Add only named bases with dated evidence; do not infer from ports. |
| Diplomatic / colonial relationships | 98 dated controller links; 4 event overlays | Historical political-unit files | Colonial/control backbone is the best existing relational layer, but legal and effective control are conflated. | First batch records provider relationship labels without changing runtime. |

## Modern-only records without historical member mapping

The current country inventory has 177 records. Historical aggregate member codes
resolve to 168 current IDs. Nine current records have no member-code mapping in
the existing 1900 aggregate file:

`country_prk`, `country_sds`, `country_ata`, `country_sol`, `country_tto`,
`country_atf`, `country_cyn`, `country_kos`, and `country_lux`.

This is a crosswalk gap, not evidence that those places did not exist in a
1900 historical dataset. Each requires a separately sourced historical polity
or territory decision.

## Existing historical entities without a safe one-ID mapping

The five `AMBIGUOUS` records are Austria-Hungary, the Congo Free State,
Arabian polities, Somali territories, and the South Africa war-zone overlay.
They are kept in the crosswalk with their candidate current IDs and an explicit
reason not to collapse them. The 16 `LIKELY` records also retain a set of
candidate IDs because a composite empire, union, or colonial aggregate is not
one current country.

## First safe staging boundary

`data/staging/1900/source_records.json` contains 28 records:

- 20 dated political-unit identity snapshots with source-provided capitals;
- 8 dated status/controller relationships for dominion, condominium,
  dependency, and protectorate examples.

All 28 remain `STAGED_NOT_RUNTIME`. The pack stores no GDP, industry output,
legitimacy, ideology, combat strength, organization capability, or resource
yield. The crosswalk covers all 61 existing aggregate historical entities, but
only `EXACT` mappings are marked eligible for a future authoritative candidate
export.

## Source coverage

The pack uses the ETH Zürich CShapes 2.0 page and publication as the primary
political-unit provenance, the existing repository snapshot for inventory and
crosswalk evidence, and catalogs the 1900 *Statesman's Year-book*, the U.S.
1900 Census report, the Maddison Project, and Clio Infra as later source paths.
The source manifest stores citations and limits, not copied books or large
copyrighted text.

## Isolation checks

- No file under `scripts/vnext/**` or `.github/workflows/**` is part of the pack.
- Existing authoritative world-map JSON remains read-only.
- Staging is not loaded by runtime code.
- The validator checks required fields, dates, canonical IDs, duplicate facts,
  overlapping contradictory ranges, source completeness, conflict semantics,
  and deterministic JSON digests.
