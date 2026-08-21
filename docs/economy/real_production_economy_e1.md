# WWO Real Production Economy E1

This document is the handoff baseline for the isolated Phase E1 candidate
subsystem.  Fixture values in this document and in the focused test are
synthetic algorithm fixtures.  They are not historical calibration.

## Source and scope

- Baseline: `origin/master` at `85c073649e1ed17594f2a41d4f2081feceeabe8b`.
- Implementation branch: `codex/real-production-e1`.
- Isolated worktree: `C:\Users\agcrf\wwo-e1-production`.
- Current product entry and `FormalWorldEconomyService` are unchanged.
- The E1 service is not registered in the current product runtime.

## Canonical E1 architecture map

```text
Spatial authoritative region IDs
        ↓ referenced, never copied as geography
EconomicRegionDefinition (E1 static projection)
        ↓
RegionalMarketState (E1 mutable inventory, prices, demand metrics)
        ↕
IndustryState (E1 mutable buffers and daily production state)
        ↓ ProductionRecipe (E1 static coefficients)
Physical production: capacity + inputs + labor + resource
        ↓
Local market inventory
        ↓ deterministic external/producer-input demand allocation
TransportRequest (Economy request only)
        ↓ external Spatial allocation
Shipment (Economy in-transit lifecycle)
        ↓ duration-based arrival
Destination market inventory
```

| Node | Owner | Static/mutable | Persisted | Writes | Other systems may only read |
|---|---|---|---|---|---|
| Spatial region ID and geometry | Spatial/world | authoritative external fact | Spatial-owned | Spatial | Economy reads IDs only |
| `EconomicRegionDefinition` | E1 catalog | static | represented by catalog identity/hash, not copied geography | `configure` candidate build | Spatial reads references if orchestrating |
| `ProductionRecipe` | E1 catalog | static | catalog identity/hash | `configure` candidate build | Industry settlement reads |
| Producer definition/capacity | E1 catalog | static | catalog identity/hash | `configure` candidate build | Industry settlement reads |
| `RegionalMarketState` | E1 service | mutable | yes | E1 settlement only | snapshots/getters/UI candidates read |
| `IndustryState` | E1 service | mutable | yes | E1 settlement only | snapshots/getters read |
| Demand snapshot | external provider | transient injected input | no | Population/system caller | E1 reads frozen day snapshot |
| Labor snapshot | external provider | transient injected input | no | labor/population caller | E1 reads frozen day snapshot |
| `TransportRequest` | E1 service | derived day-settlement output | no; request IDs are remembered | E1 prepares/emits | Spatial allocator and other demand collectors read |
| `TransportAllocation` | external allocator | external result | no | Spatial/orchestrator/test harness | E1 validates and reads |
| `Shipment` | E1 service | mutable | active and delivered history yes | E1 only after allocation | Spatial may read route facts |
| Political controller/sovereignty | political system | external fact | outside E1 | political system | E1 does not consume it as ownership |
| Population total | Population system | external fact | outside E1 | Population system | E1 consumes snapshots only |

The only writable E1 owners for the E1 path are one regional-market state
store, one producer-state store, and one shipment store.

## Public API and settlement state machine

The public methods actually introduced by
`scripts/economy_e1/real_production_economy_e1.gd` are:

| Method | Input | Output | Mutates | Allowed order |
|---|---|---|---|---|
| `configure(configuration: Dictionary) -> bool` | validated static catalog/config candidate | success boolean; `initialization_error` explains failure | yes, only on successful candidate | initial or explicit reconfiguration boundary |
| `prepare_day(day_index: int, demand_snapshot: Array[Dictionary], labor_snapshot: Array[Dictionary], transport_intents: Array[Dictionary] = []) -> Dictionary` | frozen external snapshots and optional explicit transport intents | phase plus requests and pre-allocation summary | yes | `READY → WAITING_FOR_TRANSPORT` |
| `get_transport_requests() -> Dictionary` | none | sorted request set | no | `WAITING_FOR_TRANSPORT` only |
| `apply_transport_allocations(allocations: Array[Dictionary]) -> Dictionary` | externally supplied allocations only | accepted allocations and phase | yes; dispatches goods and creates shipments | `WAITING_FOR_TRANSPORT → ALLOCATED` |
| `finalize_day() -> Dictionary` | none | summary and next phase | yes; closes flow, validates, records history | `ALLOCATED → READY` |
| `get_region_summary(region_id: String) -> Dictionary` | E1 region ID | market, industry IDs, incoming/outgoing transit | no | any configured phase |
| `get_market_state(region_id: String) -> Dictionary` | E1 region ID | defensive copy of market state | no | any configured phase |
| `get_industry_state(producer_id: String) -> Dictionary` | producer ID | defensive copy of industry state | no | any configured phase |
| `get_persistent_state() -> Dictionary` | none | canonical mutable state candidate | no | `READY` only; otherwise empty result and error |
| `restore_persistent_state(candidate: Dictionary) -> bool` | parsed candidate state | success boolean; error remains available | yes only after full candidate validation | `READY` only |
| `validate_state() -> Dictionary` | none | diagnostics and invariant result | no | any configured phase |
| `get_authoritative_state_summary() -> Dictionary` | none | canonical state summary | no | any phase |
| `get_authoritative_state_hash() -> String` | none | SHA-256 of canonical summary | no | any phase |
| `get_phase() -> String` | none | current phase | no | any phase |
| `get_last_summary() -> Dictionary` | none | defensive copy of last finalized summary | no | any phase |
| `get_history() -> Array[Dictionary]` | none | defensive copy of bounded daily history | no | any phase |

The invalid-call behavior is explicit and returns `success: false`; it does
not advance the phase.  The state machine is:

```text
UNCONFIGURED --configure(success)--> READY
READY --prepare_day--> WAITING_FOR_TRANSPORT
WAITING_FOR_TRANSPORT --apply_transport_allocations--> ALLOCATED
ALLOCATED --finalize_day--> READY
```

`apply_transport_allocations([])` is a valid external decision meaning no
allocation.  `get_persistent_state` and restore are restricted to the READY
boundary so a partial day cannot be saved or replaced.

## Frozen-candidate, provisional, and internal contracts

### Frozen candidate

- Economic region identity is an E1 `region_id` with a sorted list of
  authoritative `spatial_region_ids` and a unique `market_id`.
- Commodity identity reuses the existing canonical IDs (`coal`, `iron_ore`,
  `steel`, and the rest of the existing catalog); no `e1_*` duplicate IDs.
- Recipe IDs, producer IDs, market IDs, transport request IDs, and shipment IDs
  are stable strings.
- `BASIS_POINTS = 10_000`.
- Stored quantity is integer `QUANTITY_SCALE = 1_000` units per canonical unit.
- Recipe coefficients are integer `RECIPE_RATIO_SCALE = 1_000_000` ratios.
- Prices are integer centimes per canonical commodity unit.
- `TransportRequest` is a request-only contract; `TransportAllocation` is an
  externally supplied result and contains request ID, allocated quantity,
  route ID, positive duration, and transport cost.
- Shipment lifecycle is origin inventory → in transit → destination inventory,
  with one stable shipment ID and one delivered history record.
- Persistent state uses `STATE_SCHEMA = real_production_economy_e1_state_v1`;
  catalog identity uses `CATALOG_SCHEMA = real_production_economy_e1_catalog_v1`,
  caller catalog revision, and a canonical static catalog hash.

### Provisional

- Demand and labor snapshot providers and their future Population integration.
- Resource-source stock integration and Spatial route/capacity allocation.
- Price gains, moving-average horizon, target-stock days, and initial prices.
- Recipe coefficient provenance and historical calibration.
- Producer utilization response, enterprise ownership, wages, and finance.
- Priority semantics when Economy, Military, and other systems submit shared
  transport demand.

### Internal

- `shipment:e1:%08d` generated shipment ID formatting.
- Daily `daily_metrics` layout and bounded history length.
- Largest-remainder allocation implementation details and private flow-key
  separator.
- Canonical SHA-256 state summary implementation details.

## Algorithms

For each producer, all quantities are integer stored units.  The exact plan is

```text
planned_output = floor(installed_capacity_per_day * utilization_bp / 10,000)
actual_output = min(
    planned_output,
    floor(buffer[input] * 1,000,000 / input_ratio[input]) for every input,
    floor(available_labor[class] * 1,000,000 / labor_ratio[class]) for every labor class,
    floor(source_extraction_capacity * 1,000,000 / resource_ratio)
    and any producer resource-capacity maximum
)
```

Required inputs are consumed with deterministic ceiling arithmetic:

```text
required_input = ceil(actual_output * input_ratio / 1,000,000)
```

`ProductionRecipe.output_quantity` is retained as a positive declared batch
quantity for catalog identity and diagnostics.  E1 does not derive today's
capacity from demand or from that metadata; `installed_capacity_per_day` is
the authoritative physical output capability.

No demand or price value enters the output formula.  A zero required input
buffer produces zero output and records `input:<commodity_id>`.  Labor is
claimed in producer ID order from the frozen labor snapshot.  Extractive
resource stock is reduced only after the feasible output is known; source
extraction capacity and producer resource capacity are converted from
resource units with the same ratio arithmetic.

Each producer has an input buffer.  After production and local clearing,
producer-input demand moves the buffer toward
`expected_daily_input * input_buffer_target_days`; market inventory is never
treated as an instant factory buffer.

Local clearing groups by region and commodity, sorts demand by
`stable_order_key`, then demand ID, and uses largest-remainder proportional
allocation.  Remainders are sorted descending by integer remainder with
demand ID as the tie-breaker.  Household/system allocations are consumed;
producer-input allocations move into exactly one industry buffer.

Price update is integer-only.  Shortage and stock pressure are explicitly
clamped for zero demand/zero target stock.  Default gains are 600 bp shortage
and 250 bp stock pressure; daily movement is clamped to +1000 bp / -500 bp.
There is no historical-price pullback.

Settlement order is A arrivals, B frozen snapshots, C production, D demand
collection, E local clearing, F prices, G explicit transport request
preparation, H external allocation, I dispatch, J validation/metrics.

## Synthetic reference fixture and trace

The test-only fixture uses obvious IDs: `fixture:source`, `fixture:steel`,
`fixture:coal_site`, `fixture:iron_site`, `fixture:steel_site`, and
`fixture:steel_recipe`.  It is not named after a historical region.  Coal and
iron extraction use finite synthetic resource sources; the steel recipe uses
2,000,000 iron-ratio units and 1,000,000 coal-ratio units per 1,000 output
units.  The trace interrupts the next coal delivery, then dispatches 10,000
coal from source to steel with a two-day duration.

Stored quantities below are integer E1 quantity units (1,000 units per
canonical unit):

| Day | Planned | Actual | Limit | Coal buffer | Steel inventory | Demand | Fulfilled | Unmet | Price | Requested | Allocated | In transit | Arrivals |
|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 5,000 | 5,000 | capacity | 5,000 | 2,000 | 3,000 | 3,000 | 0 | 102 | 0 | 0 | 0 | 0 |
| 1 | 5,000 | 5,000 | capacity | 0 | 4,000 | 3,000 | 3,000 | 0 | 104 | 0 | 0 | 0 | 0 |
| 2 | 5,000 | 0 | input:coal | 0 | 1,000 | 3,000 | 3,000 | 0 | 106 | 10,000 | 10,000 | 10,000 | 0 |
| 3 | 5,000 | 0 | input:coal | 0 | 0 | 3,000 | 1,000 | 2,000 | 112 | 0 | 0 | 10,000 | 0 |
| 4 | 5,000 | 0 | input:coal | 10,000 | 0 | 3,000 | 0 | 3,000 | 121 | 0 | 0 | 0 | 10,000 |
| 5 | 5,000 | 5,000 | capacity | 5,000 | 2,000 | 3,000 | 3,000 | 0 | 123 | 0 | 0 | 0 | 0 |

The buffer absorbs the interruption on days 0–1, production falls on days
2–4, and production resumes only after the externally allocated shipment
arrives on day 4.  No shipment exists before an allocation.

## Conservation evidence

The same six-day fixture reports the following totals:

```text
coal: opening 10,000
      + extracted 60,000
      - process inputs 15,000
      - household/system 0
      - dispatched 10,000
      + arrived 10,000
      = closing market + buffers + in-transit 55,000
      unexplained drift = 0

steel: opening 0
       + produced 15,000
       - process inputs 0
       - household/system 13,000
       = closing market + buffers + in-transit 2,000
       unexplained drift = 0
```

Dispatch and arrival are internal location transfers, so they cancel in the
global stock equation.  Market-to-buffer transfer is also explicitly tracked
and is neither a source nor a sink.

## Determinism and complexity evidence

The focused runner executes two identical short simulations and an equivalent
source-record reorder.  The recorded state hashes are:

```text
run A: 58eeeb0a5d7fd30055d89b0b2e2b4e3dbc863ed0e696af2aff6f55dde76cde21
run B: 58eeeb0a5d7fd30055d89b0b2e2b4e3dbc863ed0e696af2aff6f55dde76cde21
canonical reordered-test run: 77d518951ef3f47be2b2e334a4bcd093474efb88ca5276997e449097e221c774
reordered-source run: 77d518951ef3f47be2b2e334a4bcd093474efb88ca5276997e449097e221c774
```

The E1-16 test prints both the canonical and reordered hashes and asserts
equality.  All catalogs, producers, requirements, demand records, requests,
allocations, shipments, and reduction loops use stable ID ordering; state
hashing recursively canonicalizes dictionaries.

The salvaged Alpha catalog adapter reports revision
`alpha_commodity_market_1900_v1:df094a57ec0f4eb80e01b44884349d33910959ff61f14df84cabd02ec663b571`,
canonical catalog hash
`57ab0bbf33ed04966cb69022f9c7da1532bfba10feb0b1e96ef8872d95fda6e9`, and
67 commodity IDs.  The expanded one-day sanity fixture is 24 regions, 48
producers, 8 commodities, 96 demand records, and 0 transport requests.  The last focused
run measured 27.463 ms for one settlement and about 102,349
authoritative-summary bytes.  This is a sanity observation only, not a
performance gate and not a long-run simulation.

## Failure behavior audit

The focused runner completes 40 checks and verifies fail-closed behavior for
unknown recipe commodity, unknown producer region, duplicate producer ID,
duplicate recipe ID, negative capacity, invalid utilization, invalid call
order, unknown allocation request, allocation above request, dispatch before
earliest dispatch, duplicate allocation, duplicate shipment delivery, missing
persistence history, mismatched persistent state identity, and non-sequential
prepare.  Configuration rejects malformed authoritative records; restore
parses and validates a candidate before commit.  A wrong catalog identity and
malformed persistence candidates leave the current state hash unchanged.

## Alpha economy salvage and consolidation

### Reused

- Existing commodity IDs and metadata from
  `data/alpha/commodity_market_1900.json` through
  `scripts/economy_e1/real_production_catalog.gd`.
- Stable ID and shipment field concepts were retained where they match the
  E1 contract.
- The data source is read-only at runtime; Alpha production sites, region
  overrides, country markets, international liquidity, and historical notes
  are not imported into E1 state.

### Refactored

| Old responsibility | E1 owner | Semantic change |
|---|---|---|
| Alpha local market inventory/price/consumption | `RegionalMarketState` in `RealProductionEconomyE1` | physical integer inventory; no instant factory read; deterministic demand allocation |
| Alpha production-site output | `IndustryState` + `ProductionRecipe` in E1 | capacity/input-buffer/labor/resource minimum; demand cannot increase today's output |
| Alpha shipment fields/lifecycle | E1 `TransportRequest` → external allocation → `Shipment` | Economy cannot pick shared capacity or dispatch before allocation |
| Alpha deterministic ID indexing ideas | E1 numeric/canonical ordering helpers | all authoritative reductions use sorted IDs and integer arithmetic |

The old Alpha service files were not rewritten or removed because the current
product and retained Alpha tests still consume them.  There is no mirrored
writable Alpha state attached to the E1 service.

### Deferred for later migration

`AlphaEnterpriseService`, `AlphaLaborService`, ledger/account, asset,
contract, debt, credit, wage, ownership, and bankruptcy functionality remain
useful future migration sources.  They are intentionally not E1 authorities.
`economy_integration_1900.json` and Spatial route/capacity integration remain
future interface sources only.

### Recipe audit

The 37 Alpha recipe IDs were inspected individually as records.  Their
input/output relationships are structurally useful but their decimal batch
units, worker counts, producer semantics, resource limits, and provenance are
not an E1 frozen physical calibration.  Therefore every ID below is classified
`NEEDS PHYSICAL-RECIPE CORRECTION` before import; none is silently promoted to
E1 production truth:

```text
farm_wheat, farm_rye, farm_maize, farm_potatoes, farm_livestock, fishery,
flour_mill, bakery, meat_processing, preserving, oil_press, coal_mine,
iron_mine, copper_mine, timber_camp, sawmill, coke_works, blast_furnace,
steelworks, copper_smelter, oil_refinery, chemical_works, pulp_mill,
paper_mill, cotton_mill, wool_mill, clothing_factory, fine_clothing_workshop,
tannery, soap_works, glassworks, cement_works, machine_works, railway_works,
arms_factory, ammunition_factory, thermal_power, freight_network
```

The E1 reference fixture uses separate `fixture:*` recipes and is explicitly
synthetic.

### Obsolete

None this phase.  Existing Alpha and Formal implementations still have valid
current-product or retained-test consumers, so no deletion gate is satisfied.

### Deleted this phase

None.  No Alpha file was deleted.

### Not yet safe to delete

`AlphaCommodityMarketService`, `AlphaEconomyIntegrationService`,
`AlphaEconomyService`, `AlphaEnterpriseService`, `AlphaLaborService`,
`AlphaConfig`, `AlphaLedgerService`, and their retained data/tests.  Current
runtime reachability and save/test compatibility prevent deletion.  A future
deletion must prove responsibility replacement, runtime reachability, data
generator reachability, save migration coverage, repository-wide consumer
absence, and focused post-delete tests.

### Duplicate authority check

- Writable E1 regional market owners: **1**.
- Writable E1 producer-state owners: **1**.
- Writable E1 shipment-state owners: **1**.
- Current product old economy and E1 do not share a state object and E1 is not
  wired into the current product; they cannot both mutate the same production
  state in this phase.

### Legacy interaction matrix

| Component | E1 relationship | Reason |
|---|---|---|
| `FormalWorldEconomyService` | ISOLATED | remains the current product economy; not replaced or called by E1 |
| Alpha commodity catalog JSON | REUSED DATA CONTRACT ONLY | canonical commodity IDs/metadata only |
| `AlphaCommodityMarketService` | MUST NOT REUSE as-is | direct shared-market production inputs, float state, automatic balancing, and demand/price coupling violate E1 |
| `AlphaEconomyIntegrationService` | REUSE DATA CONTRACT ONLY | shipment concepts are useful; internal route-capacity scheduling is forbidden in E1 |
| `AlphaEconomyService` | MUST NOT REUSE as-is | legacy aggregate/market authority is incompatible with one physical regional writer |
| `AlphaEnterpriseService` | FUTURE MIGRATION SOURCE | ownership/enterprise concepts are outside E1 |
| `AlphaLaborService` | FUTURE MIGRATION SOURCE | E1 consumes a snapshot; no second population/employment authority |
| Alpha config inputs | REUSE DATA CONTRACT ONLY / synthetic-only input | no unreviewed Alpha production-site values enter E1 |
| `economy_integration_1900.json` | REFERENCED ONLY | route/integration data is not an E1 capacity authority |
| Alpha shipment/ledger/asset/contract/debt helpers | FUTURE MIGRATION SOURCE | preserve useful finance/domain primitives without absorbing them early |
| VNext market economy | MUST NOT COMBINE | its float and internal route/production authority cannot run beside E1 |
| Spatial catalog/world/capacity code | REFERENCED ONLY | E1 stores spatial IDs and emits requests; Spatial owns capacity |
| Population/macro population data | REFERENCED ONLY | E1 consumes injected demand/labor snapshots and owns no population total |
| Alpha economy tests | ISOLATED | retained legacy behavior tests are not E1 proof; E1 has separate focused tests |

Answers to the explicit compatibility questions:

1. E1 uses the existing canonical Alpha commodity identity catalog via a
   read-only adapter.
2. The old Alpha/Formal production algorithm remains active only on its
   current product path; it is untouched.
3. E1 and the old Formal economy currently mutate the same production state:
   **NO**.
4. E1 owns any political, population, or Spatial authoritative fact: **NO**.

## E1 → E2 HANDOFF

### Concrete prerequisites already produced

- Deterministic integer arithmetic helpers and fixed scales.
- Validated economic-region, recipe, producer, resource, market, industry,
  demand, labor, request, allocation, and shipment data contracts.
- Local inventory and producer input-buffer ownership.
- Capacity/input/labor/resource physical constraint settlement.
- Deterministic proportional local clearing and bounded price signal.
- Explicit A–J day boundary and invalid-call failures.
- External transport allocation handoff with no Economy-owned capacity.
- Shipment dispatch/arrival lifecycle and defensive restore.
- Per-region/day flow accounting plus global per-commodity conservation checks.
- Canonical state summary/hash and source-order determinism tests.
- Synthetic reference fixture, human-auditable trace, conservation totals,
  failure audit, and complexity sanity evidence.
- Alpha salvage classification and canonical commodity adapter.

### READY FOR E2

- Adding more physically reviewed E1 recipes and producer definitions using the
  frozen ID/scale contracts.
- Adding more resource-constrained regional producers using the existing
  input-buffer and flow-accounting APIs.
- Adding additional focused causal tests against the existing settlement API.

### NEEDS DESIGN BEFORE E2

- How Spatial will allocate one shared capacity window across Economy,
  Military, and other request collectors.
- How Population will produce compatible frozen demand/labor snapshots without
  duplicating ownership.
- Provenance and unit conversion policy for importing reviewed Alpha recipes.

### DEFERRED BEYOND E2

- Autonomous regional trade matching.
- Real Spatial capacity allocation.
- Real Population/labor integration.
- Weekly utilization/profit response.
- Investment/capacity expansion.
- Seasonal agriculture.
- Historical regional calibration.
- Fiscal/military integration.
- Eventual current-product migration.
