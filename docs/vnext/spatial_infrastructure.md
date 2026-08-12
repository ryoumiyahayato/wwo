# VNext Spatial / Infrastructure Foundation

This document defines the ownership boundary for the first Spatial fact layer.
It is a backend contract and a debug/test projection contract; it is not a
rewrite of the formal Hemisphere UI and it does not integrate Economy, Politics
or Military.

## Ownership

`VNextSpatialWorld` is the authority for:

- physical place and link queries exposed by the catalog;
- physical topology and connectivity;
- link existence and route type (`road`, `rail`, `shipping`);
- dynamic infrastructure status and bounded physical condition;
- nominal capacity, effective capacity, used capacity and remaining capacity;
- the current hour-level shared-capacity window and deterministic allocation;
- sovereign owner, administrative parent and military controller facts for
  catalog regions, cities and ports.

`VNextSpatialCatalog` is the read-only normalized skeleton. It reuses the
existing files under `data/world_map/` and keeps their lower-case IDs as
map-owned identifiers. The vNext boundary derives `place:<map_id>` queries
using the existing `place` stable-ID kind. No new `spatial_cell`, `rail_link`
or `infrastructure` stable-ID kind is introduced.

Spatial does not own:

- commodity, shipment, market or household economics;
- military formations, war resolution or political legitimacy;
- player/person/organization state;
- the formal Hemisphere scene, map camera or UI selection state;
- a global clock, service locator, singleton or universal event bus;
- a second world-map JSON or a global spatial-cell grid.

Economy does **not** own total transport capacity. Military does **not** own
total transport capacity. Hemisphere does **not** own spatial truth. Future
integration callers may submit transport demand to Spatial and query the
resulting allocation; they may not write Spatial dictionaries directly.

This PR does not modify Economy, Politics, Military, `world_runtime.gd`, or
formal Hemisphere UI code. Integration is reserved for a later PR.

## Legacy map reuse

`VNextSpatialCatalog.load_legacy_world_map()` reads these existing assets:

- `data/world_map/countries.json` for valid owner/controller IDs;
- `data/world_map/regions.json`;
- `data/world_map/cities.json`;
- `data/world_map/ports.json`;
- `data/world_map/road_segments.json`;
- `data/world_map/rail_segments.json`;
- `data/world_map/shipping_routes.json`.

The loader validates IDs and cross-file references, copies records into a
read-only normalized query boundary, and sorts every returned collection by the
map-owned ID. It does not rewrite the source files or build a parallel
geometry dataset. Regions, cities and ports are the first spatial units;
geography remains static while territorial facts are mutable.

## Dynamic infrastructure

`VNextInfrastructureLinkState` stores one dynamic record per catalog link:

```text
link_id
link_type
status
nominal_capacity
condition
```

Supported statuses are `operational`, `construction`, `damaged`,
`interrupted`, `destroyed`, `repairing` and `restored`. Status is semantic;
`condition` is only a bounded `[0, 1]` physical multiplier. It is not a
universal health field.

Effective capacity is derived deterministically:

```text
nominal_capacity * status_factor * condition
```

Unavailable states have a zero factor. Damaged and repairing links use the
central factors in `infrastructure_link_state.gd`; callers cannot replace
status semantics with arbitrary health writes. Mutations go through explicit
methods such as `set_infrastructure_status()`, `set_nominal_capacity()` and
`restore_infrastructure()`.

## Shared capacity contract

`VNextSpatialCapacityWindow` owns the active hour-level capacity window. The
world receives either an absolute hour (`advance_to_hour`) or an elapsed-hour
delta (`advance_hours`); it does not read system time or create a second world
clock.

Each request contains a caller-supplied request ID, map-owned link ID, window
hour and positive demand. Requests are queued and reallocated after every
mutation. For each link, request IDs are sorted lexicographically before
allocation. This makes equal-capacity contention independent of insertion
order. Allocation is bounded by effective capacity and can be full, partial or
unfulfilled. Zero effective capacity produces zero allocation and zero
remaining capacity.

At a boundary, the active request set is cleared and a new window begins.
There is no unbounded reservation history. `capacity_summary()` exposes
authoritative nominal, effective, used and remaining capacity plus the sorted
current reservations. Future Economy/Military adapters should submit demand to
this contract instead of implementing a second capacity ledger.

## Territorial facts

`VNextSpatialWorld` exposes explicit mutations:

- `set_sovereign_owner()`;
- `set_administrative_parent()`;
- `set_military_controller()`;
- `set_territorial_facts()` for an atomic combined update.

Owner and controller IDs must exist in the reused country catalog. An
administrative parent is empty, a known country, or a known region. Self
parents and cycles are rejected. Query methods return copies, so callers do
not receive a writable reference to authoritative dictionaries.

## Projection

`VNextSpatialMapProjection` is a read-only debug/test projection. Each call
reads the current world and returns sorted region facts, infrastructure status
and capacity, derived port status, important nodes and important links. It is
deliberately not connected to or substituted for the formal Hemisphere UI.

For a rail link changed to `interrupted`, a new projection reports
`status = "interrupted"` and `effective_capacity = 0`. Port status is a
derived summary of connected shipping links (`operational`, `degraded`,
`unavailable` or `unconnected`); no second port-state authority is created.

## Snapshot / restore

`VNextSpatialWorld.snapshot()` persists the schema ID, current hour, one
infrastructure record per link, one territorial record per place and the
bounded active capacity window. Reservations include their demand and the
derived allocation; link usage includes nominal, effective, used and remaining
capacity so malformed persisted values are detectable.

Restore is transactional:

```text
raw shape/type/reference validation
-> candidate infrastructure and territorial state
-> candidate capacity allocation and usage validation
-> complete candidate validation
-> assignment to live state
```

Unknown places or links, duplicate or orphan reservations, wrong windows,
invalid owners/controllers/statuses, negative or non-finite capacities,
`used > effective`, malformed collection items, and administrative cycles are
rejected. A failed restore leaves the live world byte-for-byte equivalent at
the snapshot boundary.

## Determinism and time

All result-affecting collections are canonicalized by stable map ID or request
ID before iteration. No system time, unseeded RNG or dictionary insertion order
is used for topology, allocation, projection or persistence. A 24-hour jump is
implemented as explicit hour boundaries and is equivalent to 24 one-hour
advances.

## Validation

The focused contract is in
`tests/vnext/spatial_infrastructure_test.gd`. It covers legacy reuse, topology
queries, status mutation, capacity formula/contention/zero-capacity behavior,
interruption and restoration, ownership/controller changes, projection,
transactional malformed restore, JSON round-trip, snapshot/resume,
time-partition equivalence, deterministic insertion permutations and bounded
persistent state.

Run the focused test directly when iterating, then run the repository's unified
vNext validation and the full `tools/run_validation.ps1` before review. Godot
generated `.uid` files, logs, caches and builds are not part of this change.
