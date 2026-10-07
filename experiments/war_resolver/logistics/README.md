# Task 6 — military supply and equipment readiness contract v0

**DRAFT / EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.**
Frozen base: Task 5 `1373c5b8d8255d860a08d6c778d1ec91fedad4a7`.
This optional binding extends the existing resolver, LOD owner and real structure
service. No additional combat solver, clock, scene, Economy, Technology,
Organization, transport routing or formal save system is introduced.

## Facts and authority

`service.configure` admits a fixed, validated external snapshot once, before
coalescing and pending events. Unit material quantities exist only in live
`BattleState.units`: detailed leaves **or** aggregate proxies. The LOD's frozen
leaf images and retired donor records are historical/unresolved inputs, never
additional current inventory. Source-depot free stocks and finite maintenance
capacity are separate admitted facts in the logistics service. Exports are copies.

The three resource classes are `AMMUNITION`, `FUEL`, `SPARES`. A workshop's finite
repair capacity is an externally admitted constraint, not a produced resource.
`equipment` is currently retained assigned equipment; `serviceable_equipment +
damaged_equipment = equipment`. `equipment_lost` remains the existing loss ledger.
`fuel_spent`, `spares_spent`, `wear_damage`, `repair_restored` are extensive ledgers
that survive materialization, split and merge. Repair changes availability of
already assigned equipment, never its assigned count or the personnel count.

Unbound Tasks 1–5 preserve their existing snapshot schemas, event phases, stocks,
tests, replay hashes and tolerances. Task 6 deliberately rejects reinforcement
events while bound: admitting replacement assets/personnel needs a separate
external transfer contract. Legacy unbound reinforcement is unchanged.

## Request, allocation, delivery, receipt

`commands.gd` binds one concrete person. Payloads cannot nominate an actor, rank
or scope. The authoritative structure service supplies current effective ancestry.
Platoon leaders and higher may request within their operational scope; company
commanders and higher may allocate or schedule maintenance within scope. Soldiers
and squad leaders cannot allocate a company warehouse. A source's externally
admitted `allocation_scope` must also be inside the allocator's current scope.
Ownership (`owner_ref`) is a distinct, uninterpreted external identity.

1. `REQUESTED`: valid positive finite quantity and recipient. No stock movement.
2. `ALLOCATED` / delivery `IN_TRANSIT`: explicit source stock is debited once;
   the amount is reserved in exactly one delivery record. Recipient stock is
   unchanged. Already allocated requests and used action IDs cannot be reused.
3. `RECEIVED`: at the exact admitted ETA the in-transit amount becomes recipient
   stock once. A later combat segment can use it.
4. `REJECTED_RETURNED`: an invalid/retired recipient returns the entire reservation
   to its original source; the reason remains in history. No implicit redirect.

The immutable delivery record contains `delivery_id`, `source_ref`,
`recipient_ref`, `recipient_kind`, `resource_class`, `quantity`, `issue_time`,
`delivery_time`, `status`, allocation actor and request ID. ETA is an externally
admitted arrival fact. This experiment neither derives travel time nor invents
trucks, routes or transport capacity. No repeating replenishment exists.

Targets have distinct policies:

- **Unit**: stable unit ID. Attachment does not retarget it. A split keeps the
  source ID; the child receives no copy of a pre-existing shipment. A retired
  merged donor is rejected and returned, not redirected to its survivor.
- **Formation**: stable military-node ID, current effective live recipients at
  receipt. Distribution follows their current personnel mass. Reparented leaves
  leave the former superior's receipt index. Empty or partially covered proxies
  reject and return; use an explicit unit target for a subset.
- **Depot/supply node**: fixed admitted depot ID. Receipt stays in that depot's
  stock and does not automatically distribute to troops. Depot ownership and
  allocation scope are not overwritten by operational attachment.

Allocation authority is checked when the reservation is committed. Physical
receipt follows that immutable target policy even if the issuer subsequently
loses operational scope; a shipment is not a delayed command to a new recipient.
Maintenance authority and capacity scope are additionally rechecked at execution.
General cancellation, redirection, shared finance and transport authorization are
not implemented.

## One clock and exact boundaries

The existing binary heap owns all scheduled events. A strict prepared-ticket
check validates ID, payload, timestamp and pending status; arbitrary direct
scheduling, altered ETAs, duplicate processing and replayed completed records
cannot mint receipts.

At a common timestamp:

1. Settle elapsed combat with the interval's starting state.
2. Attachment expiry.
3. Other real structure events, sorted by stable event ID.
4. Deliveries, sorted by stable event ID.
5. Maintenance, sorted by stable event ID.
6. Existing orders, reinforcement (unbound only), area changes and coordination.
7. Plan subsequent combat from the resulting current state.

Dictionary order is not a tie-breaker. The bound system is one resolver/time owner;
no supply tick or second simulation exists. Exact off-grid ETA and aligned caller
segmentation tests compare causal snapshots. Diagnostic spatial fold reads can
depend on the number of explicit `advance` calls and are excluded from that causal
comparison; sleeping-world comparisons still require exact operation counters.

## Causal resource and equipment effects

- **Ammunition** uses the original fire mechanism and exhaustion boundary. Only
  actual usable outgoing fire spends ammunition; scarcity lowers actual fire,
  suppression and casualty output through that existing mechanism.
- **Serviceability** replaces assigned equipment in the commitment ceiling.
  Range, rate and lethality remain structured weapon facts. A damaged assigned
  item cannot contribute as an operational item.
- **Fuel** constrains only an admitted fuel-dependent mobility capability.
  Segment-start operational equipment, fuel-per-equipment-km and actual travelled
  distance determine consumption. Fuel exhaustion introduces an exact boundary;
  exhausted motor movement sleeps until an explicit refuel event. Walking
  capability ignores fuel and rejects unit/formation fuel allocation.
- **Wear** is deterministic bounded damage from travelled distance and admitted
  wear-per-km. It moves serviceable to damaged; there is no per-frame random wear.
  Casualty equipment losses remove serviceable/damaged equipment proportionally.
- **Repair** requires a named event, sufficient recipient spares, actual damage,
  finite external workshop capacity and valid authority. Oversized/unsupported
  repair rejects atomically. Explicit repair consumes spares and capacity and
  moves damaged to serviceable, without manufacturing assigned equipment.

Capability facts are `fuel_dependent`, `fuel_per_equipment_km`,
`spares_per_repair`, `wear_per_km`, `suppression_per_round`, alongside the existing
weapon range/fire/lethality and mobility. No general supply scalar, CombatPower,
technology level, tech tree or research process exists.

## Macro current, micro lazy

Managed cohorts require matching capability facts and homogeneous per-person
extensive stock profiles, in addition to Task 4's existing spatial/mission/
condition compatibility. Incompatible exhaustion or readiness profiles stay
detailed; they are never averaged into invented usable capabilities.

Aggregate inventory/consumption/serviceability remains current directly on the
proxy. Positive receipts update live proxies, not frozen leaf images. A lazy
leaf receives the deterministic admitted personnel fraction of **all** current
extensive stocks and ledgers; extracting it subtracts those exact shares from
the residual proxy. This is a conservative unresolved allocation, not reconstructed
individual contact or vehicle history. Task 5 extends its proportional allocations
and compatible merges to the same stock fields. No state or damage reset occurs.

The effective-node-to-current-representation index stores membership counts,
never quantities. Coalescing, local materialization and real structure changes
update it incrementally. Formation delivery/repair reads this index and the
fully contained live proxies; no leaf expansion is required. Unit-specific
input materializes one leaf and keeps the residual proxy. Structural attachment
still follows Task 5's existing causal subtree materialization policy; it is
reported separately from logistics-driven materialization.

## Evidence and performance

`tests.gd` covers A–P and R, malformed input, person scope, depot receipts,
extended company split, strict cohort compatibility and simultaneous events.
`replay_probe.gd` covers Q in six seeds and both DETAILED/AGGREGATE interval
policies. `benchmark.gd` supplies all nine requested cases. Counters distinguish
admission/index construction, due transactions, live inventory reads, proxy
edits, logistics materialization, effective responsibility queries and heap
comparisons. `future_deliveries_examined` counts future-table scan work (zero);
heap comparisons explicitly record necessary indexed work instead.

Snapshot export and `audit()` may scan all facts **only on explicit diagnostic
request**. Timed resolver work never calls them. Construction, storage and
allocation admission costs are reported separately from resolution. Absolute
milliseconds have no pass threshold. Comparison of 40 versus 100 underlying
leaves is evidence for these admitted proxy cohorts, not a universal guarantee
for heterogeneous formations or dense local contact search.

Run the complete pinned validation into a new output directory:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -B `
  experiments/war_resolver/logistics/validate.py `
  --godot 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --output 'C:\Users\agcrf\wwo-war-lab-results\task6\new-run'
```

The runner verifies ancestry, protects predecessor tests and production paths,
freezes all experimental GDScript/Python source digests, runs retained Tasks 1–3,
then Task 4, Task 5, Task 6, the original five repository regressions, unchanged
unified validation, and Codex audit. It scans logs even when Godot returns zero.
The official unified runner's already documented `41 resources still in use at
exit` fixture diagnostic remains allowed and counted in raw evidence.

`--completed-run` with `--completed-source-digest` can rescan a just-completed full
run only when all runtime, test, replay, benchmark and predecessor Python digests
are identical. Only this new orchestration script may have changed. It requires
all 21 actual completed step records and exact commands, scans every raw log again,
retains original command/wall-time records with explicit reuse flags, and runs
version/audit fresh. It never reuses changed simulation/test results. The audit
requires the real `CODEX AUDIT REGRESSION PASSED: 31 checks` marker, 31 `[PASS]`
records, no `[FAIL]` and exit 0.

See [local report](TASK6_LOCAL_VALIDATION.md), machine evidence, and the separate
Economy/Organization/Technology requirement documents. No human visual acceptance
is required or claimed. The sandbox is unchanged. Known contested control,
post-completion combat, one-axis/uniform terrain, fractional casualties, perfect
reports, ordinary-soldier combat gap, limited high-rank vocabulary and absent
air/naval combat remain. No replacement equipment, transport, wages or economy
integration is implied by this experiment.
