# vNext Strategic Military System

This slice adds strategic military state and logistics without adding a second
world map or connecting to `scripts/vnext/world_runtime.gd`.

## Map reuse

`VNextMilitaryMapAdapter` loads the existing `PrototypeV2Data` dataset:

- `data/world_map/cities.json`
- `data/world_map/countries.json`
- `data/world_map/regions.json`
- `data/world_map/ports.json`
- `data/world_map/road_segments.json`
- `data/world_map/rail_segments.json`
- `data/world_map/shipping_routes.json`

The only new map data is `data/world_map/strategic_military_overlay.json`.
It contains stable-ID military semantics: terrain profiles, transport
profiles, resource labels, strategic values, initial control, garrisons, and
city defense roles. It does not contain duplicate city geometry, borders, or
transport topology.

Cities without an existing macro-region use their existing country ID as a
strategic fallback region. This keeps foreign cities queryable while preserving
the current map data model.

## Strategic units and actions

`VNextMilitaryFormation` represents a formation rather than individual
soldiers. It stores personnel, equipment factor, training, morale,
organization, location, action state, and supply state.

`VNextMilitaryService` supports deploy, move, concentrate, defend, and attack.
Actions reserve a stable action ID at the current military-hour boundary and
complete only when the supplied military hour reaches their ETA. Routes are
Dijkstra paths over existing road, rail, and shipping links; an absent path is
unreachable, never an implicit teleport. Route personnel capacity creates
transport waves for oversized formations.

## Logistics

The service accepts fixed regional supply inputs. Economy integration can later
replace those inputs without changing military formulas. For each formation,
food, ammunition, equipment, and transport-capacity demand are delivered only
through controlled regions and existing transport links.

Route capacity is the bottleneck shared by all resources on that route. Rail is
faster, more reliable, and higher-capacity than road in the overlay; ports are
required for shipping links. A control change in an intermediate region makes
the route unavailable. Low or cut supply reduces organization, morale,
equipment readiness, and eventually personnel, with all values clamped to
finite non-negative ranges.

## Strategic combat and control

Combat is deterministic. Attacker and defender power include personnel,
equipment, training, organization, morale, supply, terrain defense, city
defense, garrisons, and defense posture. Ratio thresholds classify an attack as
attacker win, defender hold, or stalemate. Results expose an active/resolved war
status, attacker/defender casualties, bounded mobilization pressure, loss
records, and control changes. A win changes only the military state's region
controller and control history. The formal map UI and political legitimacy are
integration responsibilities.

## Persistence and verification

`VNextMilitaryState.snapshot()` stores dynamic formations, actions, controls,
garrisons, supply inputs, battle results, and control history. Restore validates
schema, formation IDs, action IDs, action time ranges, map references when a map
is provided, and finite supply/state values.

Focused verification:

```text
Godot --headless --path . --script res://tests/vnext/military_strategy_test.gd
python tools/run_vnext_validation.py --root . --godot <Godot executable>
```

The focused test covers map reuse, terrain, roads versus rail, ports and
shipping, timed movement, deployment, concentration, supply interruption,
combat outcomes, control changes, snapshot round trips, and a 240-day bounded
run.
