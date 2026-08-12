# vNext Economy / Spatial Compatibility Boundary

This note records the post-PR62 reconciliation for the isolated vNext market-economy candidate. It does not wire Economy into `VNextSpatialWorld`; gameplay integration remains a later PR.

## Authority after PR #62

`VNextSpatialWorld` is the authority for physical topology and connectivity, link existence/type, infrastructure operational state and condition, nominal/effective/used/remaining physical capacity, and the current shared per-link/per-hour allocation window.

Economy owns commodity supply/demand, inventories, production, economic shipment intent, trade policy/quota, commercial routing cost/modifiers, shipment lifecycle and economic attribution. Economy must not publish or persist a competing authoritative physical-capacity ledger.

## Current Alpha route fixture

`VNextMarketRouteNetwork` remains only as a **non-authoritative Economy fixture / derived commercial network** for the existing eight-region Alpha regression. Its source rows come from `data/alpha/economy_integration_1900.json`; they are not the authoritative world-map geometry used by Spatial.

The legacy source field `capacity_units_per_day` is interpreted inside this isolated fixture as a per-day **commercial fixture budget**. The production-facing Economy API therefore exposes `set_fixture_route_budget()` rather than a physical-capacity mutation. The fixture budget can make an isolated Economy test path unavailable, but it does not change Spatial link status, condition, topology, nominal/effective capacity, or shared reservations.

The fixture exists to preserve already-reviewed Economy behavior until integration. It must not become the permanent physical transport API.

## Route fact classification

| Economy route fact | Classification now | Post-integration authority |
|---|---|---|
| source/destination connectivity | E — Alpha fixture-only | A — Spatial topology |
| route identity / edge IDs | E — Alpha fixture identity | Spatial IDs/reference projected into Economy |
| travel duration | E — Alpha fixture calibration | derived from authoritative Spatial/world-map route data |
| physical capacity | not Economy-owned | A — Spatial only |
| fixture daily throughput budget | E — isolated Economy fixture | removed/replaced by Spatial allocation |
| trade quota / embargo | B — economic policy/trade constraint | Economy |
| freight/commercial transport cost | C — economic derived cost | Economy, derived from Spatial inputs plus commercial modifiers |
| distance used for economic cost | C/E — fixture-derived observation | derived from Spatial/world-map truth; no Economy geometry authority |
| risk/reliability commercial modifier | C — economic modifier | Economy unless a physical component is supplied by Spatial |
| physical operational availability | not Economy-owned | A — Spatial only |
| shipment queue and lifecycle | D — shipment domain state | Economy |
| reservation/allocation | fixture budget only in isolated tests | Spatial allocates; Economy stores reservation/reference and shipment outcome |

## Deferred shared-capacity integration contract

A later integration adapter should follow this direction:

1. Economy produces transport demand: source, destination, cargo, physical load and requested timing.
2. The adapter resolves authoritative Spatial/world-map links and submits capacity requests to `VNextSpatialWorld` / `VNextSpatialCapacityWindow`.
3. Spatial decides physical feasibility and full/partial/unfulfilled shared allocation for the current hour window.
4. Economy decides whether the resulting shipment is economically desirable and records shipment state plus the Spatial reservation/reference.
5. Economy never writes Spatial topology, infrastructure status/condition or capacity dictionaries.

No `world_runtime.gd` wiring, service locator, Military dependency or cross-domain scheduler is introduced by this reconciliation.

## Persistence boundary

Economy snapshots continue to own region market state, production sites, active shipments, shipment history, cumulative physical flows, shocks, trade quotas, sequence and the isolated fixture route-budget state needed for deterministic Alpha replay. They do not copy `VNextSpatialWorld` state.

When future Spatial integration replaces the fixture budget, Economy should persist only the Economy-owned shipment/reference information required to validate or resume its relationship to the authoritative Spatial reservation.

## In-transit observation

`in_transit_import_units` means the **current outstanding active shipment quantity** for the queried destination/commodity. It is derived from Economy's authoritative active shipment queue at snapshot/query time; it is not a resettable daily metric and is not duplicated in persisted region commodity state.