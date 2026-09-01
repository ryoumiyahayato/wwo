# Shared Physical Transport Allocation Core

This is the Parallel C Spatial infrastructure slice. It is a standalone
deterministic allocator and is not connected to the current product runtime,
E1, Economy, or Military.

## Ownership

`VNextSpatialTransportAllocator` owns the physical transport batch:

- transport edges and their effective capacity;
- route validation and deterministic physical routing;
- request-set freezing;
- priority, weighted sharing and bottleneck allocation;
- the immutable `VNextSharedTransportAllocationResult`.

Requesting systems own only demand. They may submit a generic
`VNextSharedTransportRequest`, then read the final result after Spatial has
allocated the complete frozen batch. There is no direct per-request allocation
API.

The lifecycle is:

```text
submit every request -> freeze_request_set() -> allocate(time) -> apply result
```

## Request contract

`VNextSharedTransportRequest` contains:

```text
request_id
requester_system
origin_region_id
destination_region_id
quantity
cargo_class
priority_class       # integer ordinal; larger value has higher priority
weight               # positive fair-share weight
earliest_time
latest_time          # optional inclusive bound
accepted_route       # optional ordered edge IDs
route_constraints    # optional allowed/disallowed links or modes and limits
```

Requests are configured once and are immutable after construction. Duplicate
request IDs are rejected before they can enter the frozen set. `Economy` and
`Military` use the same generic fields; neither domain is referenced by the
core scripts.

## Edge and topology contract

`VNextSharedTransportEdge` contains:

```text
edge_id
from
to
mode
capacity_per_period
travel_time
enabled
disruption_multiplier   # [0, 1]
directional             # false means both directions share one capacity
base_transport_cost     # physical, congestion-independent routing cost
```

The effective capacity is always:

```text
0                                  if enabled is false
capacity_per_period * disruption_multiplier otherwise
```

`VNextSpatialSharedTransportTopology.from_spatial_world()` adapts the existing
`VNextSpatialCatalog` links and the existing `VNextSpatialWorld` infrastructure
state. It does not create a second map database or copy dynamic state into a
new authority. The core can also accept synthetic generic edge records for
isolated tests.

## Routing

An accepted route must be a contiguous path between the request endpoints and
must satisfy its route constraints. Unknown links, discontinuities, repeated
links, disallowed modes/links, and malformed constraints fail closed during
the freeze boundary.

Without an accepted route, Spatial runs a deterministic physical route search.
The search uses travel duration and congestion-independent base transport
cost, then breaks equal-cost ties by duration, base cost, and lexicographically
ordered edge IDs. Disabled or zero-effective-capacity edges are not selected
for an automatically routed request. Commodity prices and market state never
enter Spatial routing truth.

## Allocation algorithm

1. Requests are collected without provisional capacity.
2. The complete request set is canonicalized by request ID and frozen.
3. Priority classes are processed from highest to lowest. Higher classes use
   the remaining physical capacities before lower classes.
4. Within one priority class, each active request receives a weighted
   fair-share increment. For a request using several edges, its increment is
   limited by the smallest share available on any edge in its path.
5. Saturated demand and bottlenecked routes are removed, and the remaining
   capacity is redistributed iteratively.
6. Every increment is applied to every edge in the route. Stable request-ID
   order is used for deterministic rounding/remainder application.

The result contains one request record per frozen request, route metadata,
allocation status, effective edge capacities, edge usage, and remaining edge
capacity. Consumers receive copies from the result getters and cannot mutate
the authoritative result.

## Invariants

For every request and edge:

```text
0 <= allocated_request <= requested_quantity
sum(route allocations using edge) == edge allocated usage
0 <= edge allocated usage <= effective edge capacity
```

The result object validates these invariants before it becomes visible. A
request outside its time window or without a physically available automatic
route is returned as explicitly unfulfilled; malformed accepted routes prevent
the batch from freezing and cannot receive capacity.

## Integration boundary

No current product behavior is changed. A future E1 adapter must:

1. translate E1 shipment demand into generic requests with stable IDs;
2. submit all Economy and other-domain demand before the freeze boundary;
3. provide or query a Spatial-owned mapping from region demand endpoints to
   authoritative physical topology nodes;
4. call Spatial allocation once for the shared time period;
5. apply only the immutable result to E1 shipment progress;
6. never maintain a second physical capacity ledger or call a requester-side
   allocation method.

Military requires the same adapter shape. This branch intentionally does not
   implement either adapter.
