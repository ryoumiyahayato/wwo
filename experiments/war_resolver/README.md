# EXPERIMENT: deterministic event-driven land war resolver v0

**NON-PRODUCTION. Production integration status = NONE.** Research: can missions
→ coordination → local contacts explain automatic land combat, can two accuracies
preserve outcome direction, and can a 5×5 km abstract battle advance substantial
time while idle areas sleep? WWO's player remains one person. This experiment
does not complete its military system.

Remote HEAD and GitHub metadata independently verified on 2026-10-06:
`canonical/current-world`, `622b260bc641036c23efbf6345a548485ac6c475`.
The older branch-cleanup document's `master` reference is stale.
Godot verified: `4.6.3.stable.official.7d41c59c4`.

## Model and API

Plain unit/area/mission dictionaries and a RefCounted BattleState hold an isolated
snapshot, one game-second clock, coordination/dependency indexes, local contacts,
explicit keyed random state and a stable-ID event heap. Call
`Resolver.new().resolve_until(state, target_seconds, Resolver.DETAILED)` for
StateDelta, events, summary and counters. `scenarios.gd` supplies six abstract inputs.

Orders, reinforcements, terrain changes, reserve releases, objectives, arrivals
and ammo exhaustion define boundaries. All sides plan from the same starting
state before simultaneous effects/control changes. Effective equipped personnel,
readiness, fatigue/cohesion, suppression, proportional frontage, detection/range,
cover/exposure and actual ammunition constrain fire and movement. Suppression
stalls exposed advances; cohesion can trigger withdrawal; dependencies release
reserves. Events explain decisions. Fractional personnel losses, ammunition and
equipment have conserved ledgers. Keyed randomness is only ±4%. No CombatPower
comparison, nodes, frame loops, physics, projectiles or soldier planner is used.

DETAILED evaluates tactical groups at maximum 30-second intervals; AGGREGATE uses
the same rules at maximum 120-second intervals, without formation coalescing yet.
Observation summaries are pure reads. Quiet holds/reserves sleep; due events or
indexed dependencies wake affected areas. Idle time jumps to the next event or
horizon. Heap work is O(log events); contact discovery is O(n²) per active area.
Counters count preparations, core indexed unit reads, directed detected contacts
and due events. Input construction/diagnostic snapshots are excluded. Per-call
output scope prevents formerly active sleeping areas accumulating output scans.

## Verification

From the repository root (`python` on Windows; supply the pinned engine path):

```sh
python3 -B experiments/war_resolver/validate.py --godot godot --regressions
```

The runner verifies version, imports, scans fatal logs, runs tests, compares two
fresh-process replays and benchmarks; JSON/traces go to `builds/war-resolver/`.
It supplies writable XDG paths on sandboxed Linux. Direct commands after import:

```sh
godot --headless --path . --script res://experiments/war_resolver/tests.gd
godot --headless --path . --script res://experiments/war_resolver/benchmark.gd
```

Actual Linux: **1,876 checks, 0 failures**, identical fresh-process replay.
Retained military/R3/capacity/DEFEND/persistence: **2,988 checks, 0 failures**.
Coverage includes conservation, idle and formerly active sleeping areas, hour/chunk
comparisons, terrain/ammo/suppression, event/arrival boundaries, reserves and
faction/insertion/geometric symmetry. Resolution tolerances: 20% loss/ammo (scale
floor 1), 0.20 km movement, equal mission/control direction; hourly/off-grid
partition tolerances 1%/2%. These accommodate coarse frozen rates/thresholds and
were not loosened to conceal algorithm failures. Split/merge is absent.

PowerShell is unavailable, so its unified script was not run literally. All 49
equivalent engine/audit/test/probe/startup steps ran via Python: **48 passed**.
The economy golden step reports 3 checks/2 failures, reproduced with identical
30-/365-day hashes on a pristine baseline. Cause remains unresolved; formal code
and expected hashes are unchanged. Reproduce with `godot --headless --path .
--script res://tests/formal/formal_world_economy_golden_test.gd`, or on Windows
`powershell -ExecutionPolicy Bypass -File tools/run_validation.ps1`.

One game hour, ten active squads; wall times are observations, never CI gates:

| Policy | Sleeping areas / units | Areas | Unit reads | Contacts | Wall ms |
|---|---:|---:|---:|---:|---:|
| DETAILED | 0 / 0 | 126 | 33,516 | 6,048 | 65.649 |
| DETAILED | 10,000 / 30,000 | 126 | 33,516 | 6,048 | 67.679 |
| AGGREGATE | 0 / 0 | 36 | 9,576 | 1,728 | 19.735 |
| AGGREGATE | 10,000 / 30,000 | 36 | 9,576 | 1,728 | 19.162 |

Sleeping comparisons have identical counters and active outcomes. DETAILED versus
AGGREGATE: 126/36 segments, 23.166/23.364 casualties, 4,237.715/4,264.007 ammunition;
all six advances complete and control stays contested. Four/forty active groups
produce 960/96,000 contacts, exposing local pair cost. Communication delay processes
six orders. Net static memory changes about 1.09/0.34 MB; input memory scales with
snapshot size. [Frozen machine evidence](evidence/results.json) includes full
summaries, changes, movement, missions, event counts, memory, commands and failures.

## Limits and next research

One movement axis, uniform cover, presence-based control, no cross-edge contacts,
finite initial supply, no fatigue recovery, trusted builders, per-group advancement
missions, quadratic local contact discovery and no production persistence contract.
Pinned-engine replay passes; arbitrary partitions/cross-platform math are not
bit-identical contracts. StateDelta remains a proposal with no formal application
adapter. No formal population/equipment/inventory/geography/organization authority,
FormalWorldSimulation, formal UI/maps, economy structures or save schema changed.

Player-role overrides and observation UI (tasks 2/3), air/maritime combat,
death/succession, economy integration, historical data, ballistics, animation,
models, split/merge and save migration are intentionally absent. Evidence supports
**isolated player-role command research**, with these limits visible; it establishes
no production readiness or military-system completion.

## Task 2: role-scoped decision and command overrides

Task 2 is stacked on task 1 draft [PR #103](https://github.com/ryoumiyahayato/wwo/pull/103),
base `524b669214469e4b343830afef8f4ef8768ec225`. Production integration status
remains **NONE**. No task 3 visual sandbox or formal Organization/UI is included.

`role_overrides.gd` is a data-only adapter, configured once per isolated battle:

```gdscript
var overrides = Roles.new()
assert(overrides.configure(state, formation_records, named_people, player_person_id))
var result = overrides.apply({"id": "order_001", "kind": "mission",
    "target": "platoon_blue00",
    "values": {"posture": "advance", "objective": 2.0, "direction": 1.0}})
var observation = overrides.report()
# Advance autonomously with the caller-selected resolution, with or without input.
var combat_result = Resolver.new().resolve_until(state, 3600.0, Resolver.AGGREGATE)
```

Formation records contain `echelon`, `parent`, `side`, and `unit_id` for squads.
Named people contain `role` and `formation_id`. `role_scenarios.gd` supplies
complete examples and scripted commands for all seven roles. Configure binds the
player's identity/position; command objects cannot choose their own rank or actor.
Reconfiguration is rejected. This prototype has static membership and no person
switching, attachment, delegation, succession, formal import or save contract.

Accepted input kinds: `local_action` (soldier's own person); `tactical_intent`
(squad leader's own squad); `mission` and `coordination` (platoon and higher's
direct subordinates; company and higher can also set their own formation's main
mission/coordination). Coordination values are `posture` and `release_after`
seconds. Mission values are `posture`, `objective` within every affected area,
and `direction` of +1 or -1. No destinations, entity creation, resolution policy,
low-level movement or resource editing are accepted. Unknown fields are rejected.

`apply` returns `ok`, a command StateDelta, a causal event with person/role/layer/
scope, and `next_input_at`, or a stable rejection code without partial mutation.
Command deltas must be retained alongside subsequent resolver deltas: changes
accepted before an advance are not retroactively included in that advance's delta.
Cloned squad mission IDs isolate shared mission templates; the original mission
records/dependency indexes remain. A mission command that would replace a
prerequisite with indexed dependents is atomically rejected as
`mission_has_dependents`; dependency migration/cancellation is not defined yet.
Clones and accepted command IDs accumulate in
this short experiment; there is no bounded production persistence contract.

Higher inputs translate through indexed descendants to existing squads. Local
contact rules remain autonomous. Tactical intent retains the assigned objective
and cannot bypass superior reserves/dependencies. Inputs never select resolution.
Absent input, standing AI missions and coordination proceed exactly as before.
On-demand reports aggregate by direct subordinate; no report frequency, fog,
communication latency or realistic operational mission generator is claimed.
The soldier action is only one person's bounded local record and offset, without
individual survival/fire effects or planners for all soldiers.

Role input intervals, permission evidence, reporting scope, organization needs
and gameplay gaps are in [MILITARY_ORGANIZATION_REQUIREMENTS.md](MILITARY_ORGANIZATION_REQUIREMENTS.md).
The canonical validation command above now runs `role_tests.gd` and two separate
`role_replay_probe.gd` processes as well as all unchanged resolver/performance/
consistency tests and retained regressions. Frozen task 2 evidence is recorded in
`evidence/role_results.json`; task 1's original evidence remains unchanged.

Task 2 Linux validation on Godot `4.6.3.stable.official.7d41c59c4`:

```sh
python3 -B experiments/war_resolver/validate.py --godot godot --regressions --output builds/role-final-verified
```

**3,762 role checks**, **1,876 unchanged resolver checks** and **2,988 retained
checks**, zero failures. Fresh-process role replay covers all seven roles and
both policies, plus reserve commands and rejected local micro commands at higher
roles: `db9392ed36557206aa05af062e0c9a55e9565b903c7ff78051021373762f36b3`.
Original resolver replay remains
`8ca88032a57178deeded30379798dbb5e8eb8ee87ca4526e49a0de3f8d457f8a`.
Mission/tactical inputs retain the previous 20% resolution, 1% hourly partition
and 2% off-grid resource tolerances; scoped reserve commands also pass 20%
resolution and 2% off-grid comparisons. No tolerances were changed.

Division command, AGGREGATE, one game hour, ten active squads: **36 segments /
areas, 9,576 unit reads, 1,728 contacts, zero due events**. Adding **10,000 sleeping
areas / 30,000 squads** preserves every active outcome, delta and work counter;
no combat records are created by the command. Original seven benchmark counters
also remain unchanged, including DETAILED **126 segments / 33,516 reads / 6,048
contacts** and four/forty active squads **960 / 96,000 contacts**.

The 49-step Linux equivalent of the broad validation was rerun: **48 passed**, with
**4,178 Godot checks / 2 failures**, **46 Python tests / zero failures** and all four
fresh-process formal probe pairs matching. The only failed step is the same
formal economy golden test, with exactly the two hashes recorded by task 1's
pristine-baseline reproduction. No formal economy code or golden values changed.
PowerShell remains unavailable; its literal command was not run. Task 1's three
Windows CI runs subsequently completed successfully; that does not explain the
Linux golden mismatch or constitute task 2 Windows acceptance. The inherited
experimental CI targets `canonical/current-world`, so its target filter does not
cover this stacked PR's task 1 base branch. No manual gameplay acceptance is claimed.
