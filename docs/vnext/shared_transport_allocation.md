# Shared Physical Transport Allocation Core

This is a standalone Spatial core. It is not connected to Formal runtime, E1,
Economy, Military, Population, UI, screenshots, or the product save schema.

## Ownership and policy boundary

Spatial owns edge topology, base/effective capacity, disruption, routing,
allocation, conservation checks and frozen results. Consumers own demand and
externally supplied policy. They submit generic requests and receive detached
facts, never residual-capacity dictionaries or mutable edge handles.

Priority is an external integer ordinal; larger values run first. Spatial does
not infer priority from requester, cargo, price, fee, or stable ID. Strict
priority intentionally permits starvation.

## Exact lifecycle

    COLLECT REQUESTS
    -> freeze_request_set()
    -> freeze_routes(allocation_time)
    -> allocate()
    -> PUBLISH FROZEN RESULT
    -> CONSUMERS OBSERVE/APPLY

Allocation fails closed before route freeze. Every selected route/no-route
outcome therefore exists before any residual capacity is decremented. An
earlier request cannot make a later request generate a different route.

At request freeze the allocator validates and canonicalizes by request ID,
deep-copies scalar values, route arrays and nested constraints, then drops
consumer-owned references. Later ID, quantity, priority, weight, time-window
or constraint mutation cannot affect the cycle.

Initialization deep-copies edge records and computes a deterministic SHA-256
snapshot ID from edge-ID-sorted physical records. Edge accessors return copies.
The topology-change policy is frozen snapshot/defer: source topology or
disruption changes apply only to a newly created later cycle. Reflective
corruption of the allocator snapshot changes the fingerprint and fails closed.

Route freeze first freezes effective capacities, then selects or validates all
routes in local records. Invalid accepted routes abort this phase atomically.
Invalid endpoints and disconnected automatic routes get explicit no-route
records without capacity mutation.

v1 supports exactly one selected route candidate per routable request. It does
not implement congestion rerouting, load balancing, network equilibrium, or a
global multi-commodity optimizer. Candidate counts make that scope explicit.

Allocation uses only local residual dictionaries. Nothing is published until
request bounds, edge conservation, per-priority usage and route-flow
reconciliation all pass. The allocator retains a canonical result and returns
a new detached result to every observer; getters also copy collections.

## Request contract

The generic request fields are:

    request_id
    requester_system
    origin_region_id
    destination_region_id
    quantity
    cargo_class
    priority_class
    weight
    earliest_time
    latest_time
    accepted_route
    route_constraints

Origin and destination must differ. A same-node request is an invalid no-op,
not free physical shipment.

Time windows are eligibility/deadline filters only. A request valid from 08:00
through 12:00 may join cycles in that inclusive interval. It does not reserve
10:00 capacity while the simulation is at 08:00. Unknown fields such as price
or paid fee do not enter routing or allocation.

## Edge and disruption contract

The physical edge fields are:

    edge_id
    from
    to
    mode
    capacity_per_period
    travel_time
    enabled
    disruption_multiplier
    directional
    base_transport_cost

The disruption multiplier is finite and bounded to [0, 1]. Effective capacity
is zero when disabled; otherwise it is deterministically rounded base capacity
times disruption multiplier. Disruption never mutates base capacity. A later
snapshot restored to multiplier 1 recovers base-derived capacity while keeping
the edge ID. Both directions of a bidirectional edge share one capacity.

The adapter from SpatialWorld reads authoritative link and infrastructure
state into a cycle snapshot. It does not write that world, duplicate map truth,
or persist the snapshot.

## Deterministic routing

Accepted routes must be contiguous simple edge paths between the endpoints and
satisfy every constraint. Unknown, repeated, disallowed or discontinuous edges
fail closed.

Automatic routing:

- ignores residual allocation capacity;
- rejects disabled and zero-effective-capacity edges;
- minimizes nonnegative travel time plus physical base cost;
- breaks ties by travel time, base cost and lexicographic edge path;
- sorts adjacency by stable edge ID, making input edge order irrelevant;
- prevents cycles by tracking nodes already present in a path.

With maximum travel-time or base-cost constraints, routing retains Pareto
labels at intermediate nodes. This prevents a higher-score, lower-travel or
lower-cost prefix from being discarded when it is the only prefix that can
satisfy the final constraint. This is a narrow deterministic route search, not
a global optimizer.

## Allocation algorithm

Priority classes run greatest to least. Within a class, deterministic weighted
progressive bottleneck sharing repeats:

1. Sum active request weights on each used edge.
2. Calculate every request's weight-proportional increment on every route edge.
3. Limit its end-to-end increment by the smallest edge share and demand.
4. Apply the same increment to every edge in the route.
5. Freeze satisfied/bottlenecked requests and redistribute remaining capacity.

Stable IDs only canonicalize iteration and epsilon-scale rounding. They do not
change mathematical weights or priority.

Before publication:

    0 <= allocated request <= requested quantity
    sum(route allocations using edge) == edge usage
    0 <= edge usage <= effective edge capacity
    sum(edge usage by priority) == edge usage
    every quantity is finite and nonnegative

Invalid batches leave collection unchanged. Invalid candidates, corrupt
topology snapshots and invariant failures publish no result and cannot leave a
half-mutated authoritative capacity ledger.

## Causal diagnostics

Each request result contains requested, allocated and unallocated quantity,
allocation fraction, selected route, candidate count, binding edge IDs,
higher-priority blocking, status/reason, deterministic tie rule and compact
route-edge facts.

Each route-edge fact contains base/effective capacity, disruption factor and
capacity loss, total use, use at the request priority and use by higher
priorities. Result-level edge facts also carry closure loss, remaining
capacity, saturation and usage by priority. These are copied observations, not
state handles.

Reasons distinguish outside time window, invalid endpoint, no available route,
insufficient effective capacity, shared capacity, higher-priority capacity,
and combined higher-priority/shared-capacity constraints.

## Persistence boundary

The core persists nothing and exposes no restore API. Static topology remains
an external catalog/version concern; disruption is read into a cycle snapshot;
allocation results are transient. Future in-transit state belongs to its
runtime owner and may retain stable IDs and copied facts, not allocator state.
No product save-format change is part of this work.

## Legacy API audit

The Shared Transport directory exposes no request_capacity, reserve_capacity,
cancel, cancel_capacity_request or allocate_request method. Focused tests scan
against their reintroduction.

The unused `request_capacity()` and `reserve_capacity()` admission methods were
removed from both the older VNextSpatialWorld and VNextSpatialCapacityWindow.
Their old test fixtures now use one-member batches, so no discoverable public
single-request admission path remains.

`request_capacity_batch()` remains a **LEGACY TRANSPORT COMPATIBILITY PATH**.
Economy and Military still call it and must be migrated together in an
authorized product-integration task. Military also uses the legacy
`cancel_capacity_request()` wrapper while cancelling active actions; the
implementation below SpatialWorld is internal and cancellation can only
release, never admit or increase, capacity. Focused tests require these legacy
classifications and reject any call from Shared Transport core sources.

See `shared_transport_component_freeze.md` for provenance, the canonical-line
rule and the future product orchestration seam.
