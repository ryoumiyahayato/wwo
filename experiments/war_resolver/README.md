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
