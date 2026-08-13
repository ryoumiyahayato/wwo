# vNext Economy / Spatial Compatibility Boundary

This document records the local Economy closeout boundary. Economy models commercial intent and shipment state; `VNextSpatialWorld` remains the sole authority for physical transport topology, operational links, capacity windows and final allocation.

## Runtime authority boundary

`VNextSpatialWorld` owns physical connectivity, infrastructure state, nominal/effective/used/remaining link capacity, and shared per-link/per-hour reservations. Economy must not publish or persist a second authoritative physical-capacity ledger.

`VNextMarketRouteNetwork` remains a non-authoritative commercial fixture for isolated Alpha regression paths. Its legacy daily route budget is only a test fixture and can gate the fallback Economy-only path; it does not describe Spatial capacity and must not be used as a second allocator when Spatial is attached.

The current adapter maps Economy route-edge IDs to Spatial link IDs. The mapping is an integration reference, not a new topology authority.

## Physical transport sequence

For each Economy settlement window with Spatial attached, the shared-time coordinator must first select the matching absolute Spatial window (`day_index * 24`). Economy does not advance or privately roll that shared clock. The sequence is:

1. Build all applicable commercial transport demand deterministically.
2. Submit every demand request to Spatial for the current allocation window as one transactional batch.
3. Query the final allocation for every request only after the complete batch exists.
4. Apply only those final allocations to Economy inventories, trade quotas, exports and shipment progress.

If the shared Spatial window does not match the requested Economy day, settlement fails closed before Economy mutates market state or touches any Spatial reservation. Economy never clears Spatial reservations directly; the shared Spatial boundary owns rollover and removal. Economy does not consume sequential provisional allocations and does not maintain a competing total-capacity allocator. Partial or shared-link results are accepted exactly as returned by Spatial. The isolated fixture path remains available only when no Spatial authority is attached.

## Shipment and in-transit semantics

A shipment stores its total units, delivered/progress units and remaining units. `in_transit_import_units` is the derived sum of outstanding units in active shipments for the queried destination and commodity. It is not “units moved today,” is not reset at the daily tick, and is not duplicated as mutable region commodity state.

A shipment created today remains represented after the tick when delivery takes multiple days. It remains active until all units are delivered or the shipment is explicitly cancelled or otherwise resolved. Delivery removes the active record only after the outstanding quantity reaches zero; the completed record is retained in shipment history.

When `VNextSpatialWorld` is attached, `apply_shipment_progress()` treats the supplied Economy `day_index` only as a requested progress reference. Its canonical day-start hour (`day_index * 24`) must not be later than `Spatial.current_hour()`, and the call never advances Spatial time. A request that exhausts a shipment is additionally accepted only at or after the shipment's stored `arrival_day`, which is derived from its dispatch day and the existing route-duration contract. These checks complete before any delivery, inventory, shipment-queue, or in-transit mutation.

When no Spatial authority is attached, the explicit fixture contract remains: `day_index` must be nonnegative, must not precede Economy's last settled day, and must not precede the shipment's dispatch day. It is a caller-supplied fixture reference rather than an independently advancing physical clock. Day-zero and later partial progress remain valid after dispatch, while final delivery still follows the shipment's stored arrival boundary. This fallback is confined to the detached fixture mode and is not a second physical-time authority.

## Persistence boundary

Economy snapshots own region market state, production sites, active shipments, shipment history, cumulative flows, shocks, trade quotas, sequence and the isolated fixture state needed for deterministic Economy replay. Spatial world state and live Spatial reservations are not copied into an Economy snapshot. A resumed Spatial-integrated simulation must reattach the same authoritative Spatial world and runtime route mapping before submitting new transport demand.

Snapshot/restore canonicalizes the serialized Economy copy for deterministic replay without mutating the live simulation state. The active shipment queue and its derived in-transit index are rebuilt after restore.

## Verification

The focused Economy tests cover delayed delivery, partial progress, concurrent shipments, delivery removal, mid-transit restore and deterministic continuation. `market_economy_spatial_integration_test.gd` exercises shared Spatial-link contention and verifies that Economy applies only final Spatial allocation. The vNext validation workflow runs the focused suite and the ten-year Economy test in separate lanes; neither lane removes substantive assertions.
