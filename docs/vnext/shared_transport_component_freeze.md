# Shared Transport Component Freeze Record

This record closes provenance and API-boundary review for the isolated Shared
Transport component. It does not authorize product integration.

## Provenance

The safest recoverable original artifact is:

    C:\Users\agcrf\wwo-shared-transport-c-20260823

That worktree is on `codex/shared-transport-parallel-c` at
`85c073649e1ed17594f2a41d4f2081feceeabe8b`. Its eight source files were
untracked, not committed. The committed component checkpoint audited here is
`e93ad2fb02c39054ce4b89b6d70715411fd59d12` on
`codex/shared-transport-freeze`, also descended from `85c0736`.

Original untracked files and SHA-256 hashes:

| File | SHA-256 |
| --- | --- |
| `docs/vnext/shared_transport_allocation.md` | `faba1f4f6fba0d373b0e8dda360af10b933a167870a3d9f065f2a1fb009796d2` |
| `shared_transport_allocation_result.gd` | `2d81a2c23e42c6b3555c002302e82d3dcc5d8ba63764259edfe9553975b603dc` |
| `shared_transport_edge.gd` | `d5b4ba0998db147dc6759f14f3635215caaf1a354b59e553a53c7b1abea709d3` |
| `shared_transport_request.gd` | `d523a7d6f092c3c968fc9d4ef9d5e40bb3fff12a532fdcab8e81d247d1ca5810` |
| `shared_transport_route.gd` | `916febe8c99deb47fbd1ca9f62812dc375cc6996ca213ac206c1cb91130493b1` |
| `spatial_shared_transport_topology.gd` | `9fe28685c9f5385ae974a1a4c80f347f4300ecc5cc77f4cec5fd78f9424cc327` |
| `spatial_transport_allocator.gd` | `fede2f9d52b9a9335e6c1c2a77d427ef2129e3818a3546769d37ca36e9de8924` |
| `tests/vnext/shared_transport_allocation_test.gd` | `fa915d27d1ca25c74f60fc9e4c4de37b455f5ab3fff337dcd401a37c8135a88c` |

The same files at committed checkpoint `e93ad2f` have these SHA-256 hashes:

| File | SHA-256 |
| --- | --- |
| `docs/vnext/shared_transport_allocation.md` | `806f68571afff6ad1eed445248f9b2502beac35cb74278cd6d1d000565daf701` |
| `shared_transport_allocation_result.gd` | `fcf887b5ae408a0aeb382717fd0390e99250165ab6a2da6b342576cbaa9d3826` |
| `shared_transport_edge.gd` | `d5b4ba0998db147dc6759f14f3635215caaf1a354b59e553a53c7b1abea709d3` |
| `shared_transport_request.gd` | `f86490ed0df3513cc0bd1a487b3fcf09e4fe1a194925a917932b0a6ac9884891` |
| `shared_transport_route.gd` | `916febe8c99deb47fbd1ca9f62812dc375cc6996ca213ac206c1cb91130493b1` |
| `spatial_shared_transport_topology.gd` | `1603924eafee3decc7b78c15b83e208f4a845edac02e47cb91d42c2d8e582ddf` |
| `spatial_transport_allocator.gd` | `b8c6e5faff814f0867dccc8457d7b4c42c3c83ff2c7a62779a28e17fba3fbb54` |
| `tests/vnext/shared_transport_allocation_test.gd` | `2ae5f8d66764ef46dc187892febbaba6fc6184cb4f00ef07e01ad232133c77c1` |

Godot generated six `.uid` sidecars during the repair; those sidecars and all
eight content files are committed at `e93ad2f`. The repair introduced detached
request/topology/result snapshots, explicit request and route freeze phases,
atomic local allocation, deterministic weighted progressive bottleneck
sharing, strict priority, multi-edge conservation checks, Pareto-safe
deterministic routing constraints, causal diagnostics, route caching,
adversarial tests and the architecture contract. Edge and route content files
are byte-identical to the recovered original; the other six content files were
changed by the repair.

A safe-location scan found only two copies: this committed component worktree
and the older untracked artifact above. No competing Parallel C implementation
was found. This result does not prove that no deleted or inaccessible copy ever
existed.

**ORIGINAL PARALLEL C PROVENANCE: PARTIAL / UNVERIFIED.** The file artifact and
hashes are recoverable, but its creation history is not committed.

## Canonical component line

`e93ad2f` and later explicitly approved descendants are the canonical Shared
Transport component line. An older or untracked Parallel C copy must never
replace this line merely because it appears newer.

This component line is based on `85c0736`; it is not based on the separately
trusted product checkpoint `c41f07f50ac355b8c85b961cd3d633fa17f37ba9`.
Freezing the component does not freeze or complete product integration. Future
integration must start from an authorized current product baseline and
deliberately reconcile the approved component without treating this branch as
the product lineage.

## Legacy capacity API caller classification

| API at the e93 checkpoint | Exact callers | Classification and closure |
| --- | --- | --- |
| `request_capacity()` | At e93: `spatial_infrastructure_test.gd` lines 107, 108, 114, 123, 124, 134-137 and 214; `market_economy_spatial_day_window_test.gd` lines 69 and 83; SpatialWorld line 276 delegated to the capacity window | **TEST-ONLY** at e93; removed. Historical `tools/pr58_spatial_capacity_integration_worker.py` contains generator text but is not a runtime caller. |
| `reserve_capacity()` | At e93: SpatialWorld alias at lines 285-288 only; no external GDScript caller | **UNUSED**; removed. A historical PR58 patch tool mentions the declaration marker but is not runtime. |
| `cancel_capacity_request()` | Military helper call at line 1590, reached from action-cancellation paths at lines 764, 815 and 1194; SpatialWorld delegates to its capacity window | **LEGACY RUNTIME**; retained only on SpatialWorld and fenced. Its lower-level implementation is `_cancel_capacity_request()`. It releases capacity and cannot submit demand. |
| `request_capacity_batch()` | Economy market settlement line 1179; Military hourly settlement line 514; legacy Spatial/integration tests; SpatialWorld delegates to the capacity window | **CURRENT PRODUCT REQUIRED / LEGACY RUNTIME**; retained as **LEGACY TRANSPORT COMPATIBILITY PATH**. It is not the Shared Transport authority. |
| `reservation_result()` | Military state invariants and legacy tests | **LEGACY RUNTIME READ-ONLY**; retained. |
| `reservation_results_batch()` | Economy and Military settlement, plus legacy tests | **CURRENT PRODUCT REQUIRED READ-ONLY**; retained with the batch compatibility path. |

New Shared Transport sources are statically guarded from calling any of the
legacy admission, cancellation or batch APIs. Coordinated Economy/Military
migration is required before the legacy batch and cancellation wrappers can be
removed.

## Future product integration seam (design only)

Spatial should own a small `TransportCycleCoordinator`; no new mega WorldState
or capacity owner is required.

1. The authorized simulation settlement scheduler asks Spatial to open exactly
   one cycle for a stable settlement/cycle ID and allocation time.
2. Spatial snapshots topology and disruption revisions when opening the cycle.
   Registered Economy, Military and future domain adapters submit only generic
   requests during collection. They never receive edge or residual-capacity
   mutation handles.
3. After every registered collector has returned, the settlement scheduler
   tells Spatial to close collection. Spatial freezes the detached request set,
   freezes every selected/no-route outcome against the opening snapshot, then
   invokes the allocator once.
4. Spatial publishes one immutable result map keyed by stable request ID.
   Domain adapters receive only their copied results and apply Economy or
   Military consequences after publication.
5. A submission after collection closes is rejected as `cycle_closed`; the
   caller may submit it to the next eligible cycle, but cannot reopen the
   published cycle.
6. Authoritative topology/disruption changes during a cycle are deferred to a
   newly opened cycle. Snapshot corruption or unexpected revision mismatch
   aborts before publication; no partial capacity ledger is committed.
7. Spatial records the settlement/cycle ID state transition
   `OPEN -> CLOSED -> ALLOCATED -> PUBLISHED`. A second allocate or publish for
   that ID fails closed, preventing one simulation settlement from allocating
   transport twice.

The scheduler orders phases but does not own transport truth. Spatial remains
the sole physical topology, disruption, routing, allocation and result
authority.

## Performance freeze

The retained representative profile is:

| Profile | Nodes | Edges | Requests | Candidates | Routing | Allocation | Approx. memory |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Small | 16 | 29 | 32 | 32 | 17.9-23.0 ms | 3.0-4.4 ms | 878.5 KiB |
| Medium | 48 | 93 | 128 | 128 | 175.3-291.9 ms | 22.1-43.8 ms | 5.28 MiB |
| Stress-local | 96 | 189 | 320 | 320 | 790-996 ms | 96.4-102 ms | 20.44 MiB |

Classification: **PRE-GLOBAL ROUTING PERFORMANCE RISK**. Per-request route
search dominates. No accidental regression found in this closure, so global
multi-commodity optimization, adaptive equilibrium and broad route optimization
remain outside the component freeze.
