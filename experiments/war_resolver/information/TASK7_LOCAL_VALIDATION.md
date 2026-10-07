# TASK7 LOCAL VALIDATION — Windows 2026-10-07

**A. MILITARY INFORMATION / COMMUNICATION CONTRACT ROUTE SUPPORTED** within
the admitted isolated experiment. Full frozen validation PASS; no final contract
blocker observed. This is a supported research route, not a completed formal system.
DRAFT / EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.

Base: `15f9f652ba9c2016f3851ff03379684c13c6ba6f`.
Validated code commit: `a03d9f129f80d2cb3e1cb634a3e96c5f9efd3c3a`.
Branch: `experiment/military-information-communication-v0-20261007`.
Worktree: `C:\Users\agcrf\wwo-war-lab-local`.
Godot: `4.6.3.stable.official.7d41c59c4` at
`D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe`.

Formal worktree `D:\WWO\wwo`: **agent writes NONE**. Its branch, HEAD and index
were unchanged at the protection check. Its status, tracked diff and untracked
file hashes changed during this task; this is recorded, not reverted or attributed
to a particular concurrent actor. Thus complete before/after byte equality is
**NO**. All 225 historical untracked lab files remain byte-identical and excluded
from Task 7 commits. Full protection snapshots stay outside the repository.

## Frozen automated validation

| Layer | Checks | Failures |
|---|---:|---:|
| #103 resolver | 1876 | 0 |
| #104 roles | 3762 | 0 |
| #105 sandbox automated | 8941 | 0 |
| Task 4 aggregation | 17329 | 0 |
| Task 5 structure | 788 | 0 |
| Task 6 logistics | 5703 | 0 |
| Task 7 information A–T/V | 1341 | 0 |
| Original five regressions | 2988 | 0 |

Experimental subtotal: **39740 checks, 0 failures**.
Experiment plus retained regressions: **42728 checks, 0 failures**. Unchanged
unified validation: **4178 Godot checks / 46 Python tests**, exit 0. Codex audit:
**31 checks**, exit 0. All fatal script/load/parse scans passed. The unchanged
official unified suite permits its existing fixture shutdown diagnostic:
`ERROR: 41 resources still in use at exit` appeared three times and remains in the
raw log; no fixture or matcher was weakened for this task.

A separate **12-check** nonempty received-status probe also passed after the full
suite: player and autonomous adapters receive the same stale status claim and
retain it when hidden physical actions differ. Its source is retained as
`evidence/knowledge-parity-probe.txt` and its source hash/result are in the machine
evidence. It is additional evidence, separate from the 42728 core/regression checks.
No UI, rendered sandbox, screenshots, visual acceptance or release export run;
the Task 7 request explicitly excludes those activities.

| Replay | Fresh-process SHA256 |
|---|---|
| Resolver | `3c369000cbf20ed19fb53d20dde0f47fea9f025a5c1ee32a010cc332b0d92904` |
| Roles | `60d41290019b0efeaa7e21bee3201461a912cff8bfb838642cfe8ae6ef83b3e3` |
| Sandbox | `a079c498616d72209811861d72fad70ccab5dd6ea3c13bceedcaed3ad8882390` |
| Task 4 | `73c47a49ca73e026227324581975b1315b9386183a21da022827d30e37a646f3` |
| Task 5 | `c2da3bc13475afb8540ccae93d49b7ce8a5ba072f7c2c4e768ad6f0f7cded664` |
| Task 6 | `0245979431dca576e2194e884011572d632a1bcdc7c22cc3cd2eea4fb99698f1` |
| Task 7 | `3528e2eafc4a4945750cb21451a1855db0fd4200ec76809970414c7d8ba9b17e` |

All six predecessor hashes are unchanged. Task 7's two fresh processes match
across six seeds and both policies. Source fingerprints were captured before the
full run; final unchanged-source verification **passed**, and the committed code tree
was checked against those frozen sources (normalizing only Git line endings).

## The nineteen required answers

| # | Answer and actual evidence |
|---|---|
| 1 | **YES**, physical BattleState and received person claims are separate. No filtered truth snapshot constructs knowledge. |
| 2 | **YES**, physical position changes without a new report leave knowledge entries exactly unchanged (A). |
| 3 | **YES**, observed_at=0 remains 0 when received_at=47; a later receipt does not masquerade as a current fact (B/C). |
| 4 | **YES**, conflicting and wrong claims retain distinct source, observed/received times and quality; history is append-only and older pages remain available (D/E). |
| 5 | **YES** for world authority: 100 repeated queries preserve complete BattleState, time/random state, LOD materialization and combat counters. Copied outputs cannot mutate stored claims. Only information diagnostic read counters increase (F). |
| 6 | **YES**, 100 aggregate squads' formation fact examines 5 current proxies; zero leaves materialized (G/benchmark). |
| 7 | **0**: one current proxy is read and the leaf claim is explicitly proxy_derived_estimate. Exact microscopic reconstruction is not implemented (H). |
| 8 | **YES**, old mission before 47; the existing Role mission path changes only at delivery=47. Direct immediate Role.apply bypass is rejected in opt-in mode (I/K). |
| 9 | **YES**, issue preflight and delivered-time authority checks both run. Attachment outside the original platoon's scope rejects the old command (J). |
| 10 | **Explicit REJECTED / retired_recipient** after donor merge; no command is silently redirected to the survivor (L). |
| 11 | **YES**, duplicate IDs reject admission; repeated delivery neither appends duplicate knowledge nor executes a command again (N/U). |
| 12 | **YES**, 1000 pending reports, 3 due: exactly 3 processed, 997 remain; 54 report-heap comparisons and zero future-table records examined (O). This stress fixture uses reports; commands reuse the existing causal heap. |
| 13 | **YES**, +10000 sleeping areas/+30000 squads preserves active information, LOD and combat counters and active results (P/benchmark). Construction/storage costs grow. |
| 14 | **YES**, player and autonomous test adapters receive the same knowledge capability; changing hidden truth does not alter the decision input. No strategic AI is implemented (Q). |
| 15 | **YES**, a pure report due at off-grid 47 seconds leaves the complete BattleState and LOD counters exactly identical to an unobserved long resolve to 600 (R). |
| 16 | **YES**, knowledge history survives split, merge and attachment; retired IDs remain historical, new split subjects have their own ID, and retired live observations reject (M/S). |
| 17 | **YES**, ammo/fuel/readiness reports are claims only. An AVAILABLE ammo claim does not change actual inventory (T). |
| 18 | **YES** for all predecessor replay hashes, operation counters and deterministic benchmark records/results. Wall time and allocator memory are recorded observations, not unchanged-value guarantees. Original tests/tolerances and production paths are protected. |
| 19 | Evidence supports distinct fact/receipt times, stable person/subject identity, traceable conflicting claims, bounded selective producers/readers, due-only transmission, separate noncausal versus physical deadlines, delivered-time authority and resource-report neutrality. Future save/retention, office routing and cross-domain typed producers need more contracts; full radio/AI/universal-information designs remain speculative. See MILITARY_INFORMATION_REQUIREMENTS.md. |

## Ten Task 7 benchmark cases

Each resolves to 120 game seconds. Admission work is measured separately from
resolution. Info leaves are zero in every case. No absolute milliseconds gate.

| Case | Build ms | Admission ms | Resolve ms | Info events | Command leaves | Fact reads at admission | Report heap comparisons |
|---|---:|---:|---:|---:|---:|---:|---:|
| instant_report | 16.495 | 0.084 | 2.262 | 1 | 0 | 2 | 0 |
| delayed_report | 15.990 | 0.118 | 2.639 | 1 | 0 | 2 | 0 |
| delayed_command | 17.596 | 0.344 | 6.288 | 1 | 1 | 0 | 0 |
| authority_invalidated | 23.176 | 0.690 | 6.651 | 1 | 0 | 0 | 0 |
| 100_formation_report | 45.883 | 0.110 | 7.301 | 1 | 0 | 5 | 0 |
| 100_leaf_report | 34.498 | 0.133 | 9.690 | 1 | 0 | 1 | 0 |
| 1000_pending_3_due | 19.010 | 21.229 | 2.741 | 3 | 0 | 2 | 54 |
| 40_sleeping_report | 770.362 | 0.397 | 5.286 | 1 | 0 | 2 | 0 |
| conflicting_reports | 216.668 | 0.358 | 5.889 | 2 | 0 | 0 | 0 |
| multiple_persons | 23.318 | 0.559 | 3.207 | 8 | 0 | 0 | 17 |

The 40-squad delayed-report case and its sleeping-world counterpart have exact
equal information/LOD/combat counters, stocks and active results. Both combat
counters: areas_examined=4, contacts_resolved=32, segments=4, units_examined=388,
events_processed=0. Both write one received claim. The 100-squad report cases
use areas_examined=4, contacts_resolved=200, segments=4, units_examined=1930.

A legal one-leaf delayed command materializes **one** leaf at its physical
deadline, separately from information generation. The invalidated-command case
materializes zero leaves for the rejected command; its independent Task 5
attachment still performs its own causal work. Raw machine evidence records all
knowledge reads/writes, authority checks, shared causal-heap work and counters.

All seven original resolver benchmark physical records/counters match the Task 6
baseline after excluding wall/allocator observations. Tasks 4/5/6's 10/6/9 cases
match their committed predecessor deterministic records after excluding timing.
The old 4→40 active groups still produce contacts_resolved 960→96000, units_examined
7200→417600, with areas_examined and segments both 120. Thus
**ACTIVE LOCAL CONTACT SEARCH SCALING = QUADRATIC-LIKE** remains an inherited limit.
The largest measured retained benchmark was Task 4 dense contacts at 14371.153 ms;
largest Task 7 resolve was 9.690 ms. Sleeping-world construction took 770.362 ms.
These single-run observations do not prove hardware-independent speed targets.

## Current limits and supported next boundary

Pure reports use the same world clock but their own due heap. They preserve exact
logical receipt stamps without forcing new combat integration segments. External
queries at T must first advance the authoritative host to T; queries never perform
settlement. Future autonomous action on receipt needs a genuine causal decision
deadline, not a knowledge query side effect.

No report-loss RNG, channel topology, real visibility, exact leaf intelligence,
multi-area position summary, inbox acknowledgment, bounded retained storage,
formal persistence, office-successor mailbox or command migration is implemented.
Person-facing outboxes expose statuses/metadata rather than pending claim values;
service diagnostics are only for the trusted test host. Authority wiring is an
engine contract, not a hostile GDScript security sandbox.

Existing contested control, post-completion combat semantics, one-axis/uniform
terrain, fractional casualties, ordinary-soldier combat gap, limited high-rank
vocabulary and no air/naval combat remain unchanged. Sandbox readability was not
investigated or changed. Human visual acceptance = NOT REQUIRED / NOT RUN.

External raw run: `C:\Users\agcrf\wwo-war-lab-results\task7\frozen-complete`.
Machine evidence: `evidence/windows-20261007.json`. Runtime and tests were committed
only after the full suite and supplemental probe passed. The final documentation
commit adds this report and evidence without changing frozen GDScript/Python.
Remote final HEAD / Draft PR verification is recorded in the external publication
record and task response, avoiding a self-referential final-commit hash here.

No crash or timeout occurred in these headless runs. Rendered behavior and GUI
freezes were not tested. To repeat the supplemental probe, copy its retained text
to a `.gd` file outside the repository and invoke the pinned engine with
`--headless --path C:\Users\agcrf\wwo-war-lab-local --script <absolute-probe-path>`.
