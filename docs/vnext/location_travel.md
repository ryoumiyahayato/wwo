# vNext location and travel boundary

## Fixed base and scope

- `FIXED_BASE`: `b2584cdf6cfc5579f20a792826f6acb284164dfb`.
- Branch: `feat/vnext-location-travel-20260808`.
- This change introduces the first vNext authoritative player location and the smallest travel execution boundary.
- It does not modify `scripts/vnext/world_runtime.gd`, `PersonalWallet`, map UI, or `FormalWorldSimulation`.

## Migration evidence

The reuse/migration inventory classifies `SpatialLocationService`, `RoutePlannerService`, and `TravelExecutionService` as `REUSE_WITH_ADAPTER`. Their existing source and retained tests were reviewed before this implementation.

The old services deliberately own more than this vNext slice:

- `SpatialLocationService` owns a location catalog, per-person positions, discovery/known-location state, transit/wait/interruption state, and persistence.
- `RoutePlannerService` owns graph search, fastest/cheapest preference handling, affordability filtering, cognition limits, path tie-breaking, and route caching.
- `TravelExecutionService` owns travel plans, scheduling integration, segment settlement, payment, fatigue/stress effects, idempotency, interruption, and bounded history.

Those responsibilities are not copied into vNext. In particular, this change does not copy the old route-planning algorithm.

Useful retained tests reviewed for behavior boundaries include:

- `tests/v2_3/v2_3_location_test.gd`;
- `tests/v2_3/v2_3_route_planner_test.gd`;
- `tests/v2_3/v2_3_travel_execution_test.gd`.

## Ownership

### `VNextLocationState`

`VNextLocationState` owns exactly two business facts:

- `player_id`: a valid `person:*` vNext stable ID;
- `place_id`: a valid `place:*` vNext stable ID.

Its snapshot schema is `vnext_location_state_v1` and contains only `schema_id`, `player_id`, and `place_id`.

Restore is transactional. Schema, field presence, string types, and stable-ID kinds are validated before either owned fact is committed.

### `VNextTravelQuote`

`VNextTravelQuote` represents only an already-determined travel plan:

- `origin_place_id`;
- `destination_place_id`;
- `duration_minutes`;
- `cost_minor`.

A quote is valid only when both IDs are valid `place:*` stable IDs, origin and destination differ, duration is a positive integer, and cost is a non-negative integer. Float money and float duration are rejected at the quote boundary.

The quote does not calculate a path. `cost_minor` is descriptive in this PR and is not deducted from a wallet.

### `VNextTravelService`

`VNextTravelService` owns no independent clock, route graph, wallet, or player position. It executes a validated quote against two authorities supplied by the caller:

1. `VNextWorldRuntime` for time;
2. `VNextLocationState` for player position.

Before committing state it validates:

- runtime, location, and quote exist;
- location state is valid;
- quote is valid;
- current `place_id` equals the quote origin.

On success it advances `VNextWorldRuntime` by `duration_minutes`, then moves the location to the quote destination. The service keeps pre-execution snapshots so an unexpected post-time location commit failure can restore both authorities to their prior state.

## Explicit exclusions

This boundary does not:

- create a second clock or time field;
- use UI selection as player position;
- create map UI;
- copy or rewrite complex pathfinding;
- deduct `cost_minor` from `PersonalWallet`;
- modify `PersonalWallet`;
- modify `scripts/vnext/world_runtime.gd`;
- integrate with `FormalWorldSimulation`;
- import V2.3 transit, waiting, schedule, condition, payment, or route-cache state.

Wallet charging belongs to the later core integration after the independent player, personal-economy, travel, and related vNext boundaries are combined.

## Validation contract

`tests/vnext/location_travel_test.gd` covers:

- legal location initialization;
- invalid person/place stable IDs;
- quote field and integer validation;
- successful quote execution;
- exact runtime minute advancement;
- destination update;
- origin mismatch rejection;
- zero/negative duration rejection;
- negative cost rejection;
- float money rejection;
- failure atomicity for location and time;
- location snapshot/restore;
- JSON snapshot round trip.

The repository-wide vNext validation entry point remains `tools/run_vnext_validation.py`; no separate runner is introduced.
