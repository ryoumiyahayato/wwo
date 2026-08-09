# vNext location, travel and paid core integration

## Boundary

The vNext location boundary owns one actual player location and the smallest execution boundary for an already-determined quote. It remains isolated from map UI, formal product entry points and route-planning algorithms.

VNextLocationState owns exactly:

- player_id: a valid person:* stable ID;
- place_id: a valid place:* stable ID.

VNextTravelQuote contains only an origin, destination, positive integer duration and non-negative integer cost. It does not calculate a route.

## Runtime integration

The v2 composition root supplies the authoritative runtime, location and wallet owners. VNextTravelService.execute(runtime, location, quote) owns only the runtime time advance and actual location change. VNextCoreLoopService.execute_paid_travel(runtime, quote) owns the cross-owner paid composition and is the only layer that reads or debits the wallet.

A successful paid travel transaction:

1. records the complete runtime snapshot;
2. debits the wallet once when cost is positive;
3. advances VNextWorldRuntime by the quoted duration;
4. moves the actual location to the destination.

The paid core loop preflights runtime validity, quote validity, person identity, actual origin, JSON-safe time capacity and wallet funds before debiting. Known failures therefore leave time, wallet, location and event knowledge unchanged without relying on a debit-then-rollback path. execute(runtime, location, quote) remains the explicit low-level location/time boundary and never accesses a wallet.

## Identity and time

Travel never stores its own clock, wallet, route graph or player identity. The runtime's player ID must match the location owner, and all elapsed travel minutes are applied through VNextWorldRuntime.advance_minutes().

## Explicit exclusions

This integration does not copy V2.3 transit, schedule, condition, payment, route-cache, route-planner or travel-history state. It does not create map UI, a formal product entry point, social/communication/organization/career/politics/law/AI systems or a second location authority.

## Validation

tests/vnext/location_travel_test.gd covers the independent location/time boundary and TravelService ownership guard. tests/vnext/core_loop_integration_test.gd covers paid wallet settlement, shared time, arrival, zero-cost travel, invalid origins/quotes, insufficient funds, stale-reference safety and time-overflow preflight.
