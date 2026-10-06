# Task 3 observation report

**EXPERIMENT / NON-PRODUCTION. Production integration status = NONE.**

Reproduction starts with task 2 `4c52ec37082d27c0d7b99359cfb165ae36878f15`,
stacked on task 1 `524b669214469e4b343830afef8f4ef8768ec225`. Fresh fetch and
GitHub metadata confirmed both open drafts; repository default/formal baseline
is still `canonical/current-world`, `622b260bc641036c23efbf6345a548485ac6c475`.
The sandbox PR targets the task 2 branch. Neither predecessor is merged.

## Actual automated evidence

Executable `/usr/local/bin/godot`, version **4.6.3.stable.official.7d41c59c4**.
Final Linux command (from repository root):

```sh
python3 -B experiments/war_resolver/validate.py --godot godot --regressions --output builds/sandbox-final-verified
```

**1,876 resolver + 3,762 role + 8,941 sandbox + 2,988 retained checks, zero
failures.** Import/fatal-log scans and standalone headless scene startup pass.
Sandbox checks compare every sampled state against direct resolver calls with
identical partitions: no display mutation or alternative combat/movement law.
They cover all authority-provided eligible targets, unrelated-target and early
input rejection atomicity, role input/autonomous AI equivalence, independent deep
clones, detached observation copies, pause/speed/step/reset/seed callbacks,
1280px logical layout width, bounded traces/trails, nine fixtures at seeds
**7, 71, 733**, both policies, movement ledger versus displacement, sampled
reversals, action-change bounds, suppression recovery, withdrawal termination,
reserve dependency/release, and 24-hour bottleneck mission completion.

Fresh-process replay hashes:

- Resolver: `8ca88032a57178deeded30379798dbb5e8eb8ee87ca4526e49a0de3f8d457f8a` (unchanged).
- Roles: `db9392ed36557206aa05af062e0c9a55e9565b903c7ff78051021373762f36b3` (unchanged).
- Sandbox observations/role interactions: `dff74a5d00ae2e7335d3e6ff037c0274dc07df5e7969901e0c4792f2d1094d7c`.

The probe records nine fixtures × three seeds × two policies to **7,200 game
seconds**, plus all seven role inputs at seed 71 to 3,600 seconds. It is machine
observation, not visual acceptance. The 24-hour bottleneck assertion is in tests,
not the two-hour probe records. Exact process commands, summaries, machine
observations, source hashes and original benchmark records are frozen in
[experiment evidence](../evidence/sandbox_results.json). Runtime logs and full
observation JSON are in the runner's output directory on the executing machine.

## Machine observations, seed 71 / 7,200 seconds

Casualties are fractional **both-side totals**. Positions are `attack_00` X km.
Every row has zero sampled reversals. Both policies retain contested control.

| Scenario | DETAILED / AGGREGATE casualties | DETAILED / AGGREGATE X | Mission outcome |
|---|---:|---:|---|
| open_field_attack | 38.207 / 38.431 | 2.000 / 2.000 | Six attackers complete |
| covered_defense | 10.025 / 10.037 | 2.000 / 2.000 | Six complete; uniform cover reduces losses |
| village_edge | 24.291 / 24.366 | 2.000 / 2.000 | Six complete; movement is slower |
| road_bottleneck | 17.756 / 17.756 | 1.298 / 1.296 | All six still advancing, not stationary |
| ammo_shortage | 23.817 / 23.765 | 2.000 / 2.000 | Six complete; depleted ammunition stops own fire |
| communication_delay | 37.119 / 37.266 | 2.000 / 2.000 | Six exact orders at 900s, then complete |
| suppression_recovery | 38.240 / 38.466 | 2.000 / 2.000 | attack_00 initially stalls, recovers, completes |
| cohesion_withdrawal | 36.004 / 36.150 | 0.000 / 0.000 | attack_00 withdraws; other five complete |
| dependent_reserve | 37.885 / 38.092 | 2.000 / 2.000 | attack_00 waits for time and prerequisite, completes |

No new resolver algorithm defect was established by these checks. Core resolver
and BattleState sources are unchanged; no assertions or tolerance bounds were
weakened. Slow bottleneck movement at two hours is explicitly retained in the
display/evidence. All six eventually complete in both policies by 24 hours at
all three seeds. Default no-input fixtures have at most four action transitions
per unit; the separate sampled reversal count and distance ledger reveal loops.
This finite fixture set does not prove globally plausible war behavior.

## Performance and retained validation

The sandbox is not a performance benchmark. Fresh original headless one-hour
benchmark counters remain unchanged:

| Case | Segments / areas | Unit reads | Directed contacts | Due events |
|---|---:|---:|---:|---:|
| DETAILED, 10 active squads | 126 / 126 | 33,516 | 6,048 | 0 |
| AGGREGATE, same input | 36 / 36 | 9,576 | 1,728 | 0 |
| DETAILED + 10,000 sleeping areas / 30,000 squads | 126 / 126 | 33,516 | 6,048 | 0 |
| AGGREGATE + sleeping population | 36 / 36 | 9,576 | 1,728 | 0 |
| Four / forty active squads, DETAILED | 120 / 120 each | 7,200 / 417,600 | 960 / 96,000 | 0 |
| Communication delay, AGGREGATE | 37 / 37 | 9,848 | 1,776 | 6 |

Role scaling also remains 36 segments / 9,576 reads / 1,728 contacts with and
without sleeping population. UI snapshots are bounded to the tiny fixtures and
read on controlled refreshes; no core scan or per-person Nodes were added.

PowerShell is unavailable: literal `tools/run_validation.ps1` is **NOT RUN**.
The inherited Linux Python equivalent was rerun with
`python3 -B /tmp/wwo_sandbox_broad_validation.py`: **48/49 steps pass**, with
**4,178 Godot checks / 2 failures**, **46 Python tests / zero failures**, and four
matching fresh-process formal probe pairs. Adapter source/results are preserved
in the frozen evidence. The only failures are the existing formal economy
goldens; fresh pristine baseline reproduction gives the same hashes:

- Day 30: `24519f5dc2d191d7d5bac67437e35e6d4c4e734700f5c9915ee1df620abdfdcf`.
- Day 365: `241451cb8ce5a69d62a5105c0b0808fe16fbdc4ca1f0cb79ade3ffde780c56fd`.

No formal economy code or expected hashes changed. Reproduce after editor import
with `godot --headless --path . --script res://tests/formal/formal_world_economy_golden_test.gd`.
Supported Windows broad command remains
`powershell -ExecutionPolicy Bypass -File tools/run_validation.ps1`.
The inherited experimental workflow only targets `canonical/current-world`, so
this stacked base does **not** trigger it. No task 3 Windows acceptance is claimed.

## Rendered/manual status and local checklist

**NOT RUN — RENDERED VISUAL / HUMAN ACCEPTANCE.** This environment has no DISPLAY,
Xvfb or desktop capture facility. Godot advertises only the dummy renderer for
its headless display driver. No screenshots were produced. Scene smoke and
logical UI callback/layout tests are headless and cannot establish glyph
legibility, click usability, animation plausibility or actual visual behavior.
No exported build or real Windows execution was run for this task.

Launch using [the exact standalone commands](README.md), at 1280×720. Start
paused, select the named fixture, type the seed, Reset, then use +120s or Run.
Pause near interesting boundaries; inspect attack_00 and scroll causal traces.
Each manual row below is **NOT RUN** here; its automated evidence is separate.

| Concern | Local reproduction and what to inspect | Automated evidence |
|---|---|---|
| Movement loops / formation jitter | open_field_attack, seeds 7/71/733; run to 7,200s. Compare X, total movement and trails; rows must stay fixed | No excess path distance or sampled reversals; real formation jitter is outside the one-axis model |
| Permanent waits / mission deadlock | communication_delay, seed 71: pause before/after 900s. dependent_reserve: inspect at 600s and after mission_attack_01 completes | Exact orders and dependency gates tested; reserve eventually completes |
| Congestion | road_bottleneck, seed 71: inspect at 7,200s, then run to 86,400s | Slow two-hour progress retained; all six complete by 24h at three seeds |
| Unreasonable retreat / charge | cohesion_withdrawal, seed 71: inspect attack_00 retreat to X=0 and withdrawn event. Compare ordinary open-field advance | Cohesion withdrawal terminates; no wider tactical plausibility claim |
| Repeated command flipping | Default fixtures: watch action-change counts. Squad leader: submit hold, immediately submit advance, then step 120s and submit advance | Default transition bound; early input rejected atomically; no input disables the AI |
| No terrain / suppression effect | Compare open_field_attack, covered_defense, village_edge and road_bottleneck at seed 71. suppression_recovery: inspect first step, then recovery | Distinct loss/movement outcomes; initial suppression stalls and later recovers |
| Unconditional numerical domination | Inspect original benchmark's four/forty active-group results, then vary inputs in a new reproducible fixture before asserting a defect | Existing symmetry/frontage/resource tests only; systematic balance acceptance NOT RUN |
| Input disabling AI / role bypass | All seven roles, seed 71; choose an eligible target, submit, Run. Probe foreign rejection; submit twice. dependent_reserve + platoon leader + mission squad_attack_01 shows mission_has_dependents | Direct authority/resolver equivalence, eligible selection and rejection checks |
| UI usability | Check both columns, reset/seed/role fields, pause/speeds, disabled irrelevant fields, inspector and trace scrolling at 1280×720 | Scene load, callbacks and logical width only; rendered readability NOT RUN |

## Known anomalies and unanswered gameplay questions

- There is one axis and uniform area terrain. Squads initially overlap logically;
  fixed visual rows separate records without inventing Y, lane occupancy or
  formation behavior. Road congestion is frontage sharing, not collision/pathfinding.
- Presence keeps control contested even after attackers complete their objectives.
  Completed/withdrawn missions transition to hold and may continue firing while
  enemy records remain in the same area. Is that sensible objective/disengagement
  behavior? No disappearance or fake victory is drawn to conceal it.
- Casualties are fractional ledgers, not named-person deaths. A soldier's cover/
  step is a personal record without independent survival/fire consequences.
- AGGREGATE uses longer intervals without coalescing. Local pair discovery is
  quadratic. Higher ranks have a narrow mission/coordination vocabulary, static
  membership, perfect reports and no realistic communication/operational planning.
- The trace is bounded and loss events are counted separately; 120s position
  samples can alias short turns. Total movement, action events and headless tests
  complement the projection. Arbitrary partition and cross-platform replay remain
  limited by the predecessor's contracts.
- Input replay is independently applied to each mode; it is not a fair automatic
  strategy evaluator. The prototype has no production saves, dependencies,
  historical world composition, formal military authority or integration adapter.
