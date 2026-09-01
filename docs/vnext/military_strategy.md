# vNext Strategic Military Domain

This slice provides deterministic strategic formations, logistics attribution,
and battle calculation. It does not add Military gameplay to
`scripts/vnext/world_runtime.gd`, a second world map, diplomacy simulation, an
Organization system, production, or manpower recruitment.

## Authority graph

Military owns formation operational identity (`formation:*`), readiness,
requested/received/consumed supply, movement and battle actions, battle results,
garrisons, and non-authoritative `VNextMilitaryControlClaim` evidence.

Military references, but does not own:

- Political state identity or war state. `VNextPoliticalWarAuthorization` is a
  bounded permission supplied by Political; it cannot create or end a war or
  modify sovereignty.
- Organization identity, hierarchy, membership, positions, or capabilities.
  Every formation references one `organization:*` owner, and an attack requires
  a `VNextMilitaryOrderAuthorization` for that exact formation and organization.
- territorial ownership or current control. `VNextSpatialWorld` remains the sole
  owner of sovereign owner, administrative parent, and military controller.
- regional production, Economy inventory, population pools, or transport-network
  capacity. These are external inputs or queries, never Military state.

The formation's `country_id` is an operational affiliation reference used to
validate Political permission and Spatial access. It is not state identity,
sovereignty, or authority to change either fact.

## Map and control boundary

`VNextMilitaryMapAdapter` reuses `PrototypeV2Data` cities, countries, regions,
ports, and road/rail/shipping topology. It requires an authoritative
`VNextSpatialWorld` and reads current `military_controller_id` directly from it.

`data/world_map/strategic_military_overlay.json` contains only Military semantics:
terrain and movement profiles, supply/readiness rules, battle rules, strategic
values, garrison fixtures, and city defense roles. Regional resource lists and
initial controller facts are deliberately absent.

An attacker victory updates formation presence and creates a
`VNextMilitaryControlClaim` containing:

- location;
- military presence;
- battle result;
- candidate control outcome;
- timestamp.

The battle does not mutate territory. Spatial independently validates the claim,
checks the expected current controller, and may commit the candidate controller.
Applying that claim never changes sovereign owner or administrative parent.

## Actions and authorization

`VNextMilitaryService` supports the existing deploy, move, concentrate, defend,
attack, supply, and deterministic battle calculations. Routes are Dijkstra paths
over existing transport links; absent paths remain unreachable.

Attack additionally requires two external contracts at the action boundary:

1. a valid `VNextPoliticalWarAuthorization` matching attacker, opponent, and
   hour;
2. a valid `VNextMilitaryOrderAuthorization` matching formation, organization,
   capability, and hour.

Military stores only authorization provenance IDs on the action. It does not
persist either external contract or infer war state from a battle.

## Supply and transport

Military may own requested, received, and consumed supply plus the resulting
readiness effects. A caller may inject an external supply allocation for the
current runtime, but that allocation is not Economy production or stock and is
not saved. Restore callers must obtain and inject a fresh allocation.

`VNextSpatialWorld` is the sole authority for infrastructure status, nominal and
effective capacity, and the active shared allocation window. Military submits
demand, applies Spatial's final allocation, and keeps only action-level
attribution needed to explain progress. Derived queue and aggregate attribution
are rebuilt after restore and are excluded from the Military snapshot.

## Persistence

`VNextMilitaryState.snapshot()` uses the strict `vnext_military_state_v3`
schema. It contains formations, garrisons, actions, completed actions, battle
results, control claims, the Military clock/action sequence, and the last
attribution window identifier.

It contains no territorial-control truth, Economy stock or allocation truth,
population truth, transport-network capacity truth, or external authorization
snapshots. Restore rejects unknown root fields and applies candidate-first, so a
polluted or malformed snapshot cannot partially modify live Military state.

Focused verification:

```text
Godot --headless --path . --script res://tests/vnext/military_domain_boundary_closure_test.gd
Godot --headless --path . --script res://tests/vnext/military_strategy_test.gd
Godot --headless --path . --script res://tests/vnext/military_spatial_capacity_integration_test.gd
Godot --headless --path . --script res://tests/vnext/military_r3_findings_test.gd
python tools/run_vnext_validation.py --root . --godot <Godot executable>
```

The boundary test covers authorization rejection, Organization identity seams,
Military inability to create territorial ownership, Spatial's sole controller
authority, snapshot pollution rejection, deterministic restore, and unchanged
deterministic battle outputs.

## Remaining limitations

This is a foundation seam, not a complete Military domain. Political still needs
a real diplomacy/war-authority issuer and revocation policy. Organization still
needs to own unit organizations, command appointments, hierarchy, and capability
evaluation. Economy/Population/Transport integrations still need boundary-time
allocation contracts and orchestration. Claim acceptance policy beyond Spatial's
minimal structural/current-controller validation is also future integration work.
