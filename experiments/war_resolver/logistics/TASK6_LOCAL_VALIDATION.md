# TASK6 LOCAL VALIDATION — Windows 2026-10-07

**A. MILITARY LOGISTICS / READINESS CONTRACT ROUTE SUPPORTED** within the tested,
admitted experimental contract. **DRAFT / EXPERIMENTAL / NON-PRODUCTION.**
Production integration status = NONE. No final contract blocker observed.

Base: `1373c5b8d8255d860a08d6c778d1ec91fedad4a7` (Task 5 exact final head).
Validated code HEAD: `85bec6e3c84bed8db5054b4c0bfc2aeeca67fd57`.
Branch: `experiment/military-supply-readiness-v0-20261007`.
Worktree: `C:\Users\agcrf\wwo-war-lab-local`.
Godot: `4.6.3.stable.official.7d41c59c4` at `D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe`.
Formal worktree `D:\WWO\wwo`: agent writes **NONE**. Before/after independent
changed fields: `[]`. Branch/HEAD comparison and raw user changes remain
in external protection snapshots. All 225 historical untracked lab files
are byte-identical and excluded from commits. Shared Git objects/new experiment
refs are distinct from the formal worktree's files, index and current branch.

## Frozen validation

| Sequential layer | Checks | Failures |
|---|---:|---:|
| #103 resolver | 1876 | 0 |
| #104 roles | 3762 | 0 |
| #105 sandbox automated | 8941 | 0 |
| Task 4 | 17329 | 0 |
| Task 5 | 788 | 0 |
| Task 6 A–P/R | 5703 | 0 |
| Original five repository regressions | 2988 | 0 |

Experiment subtotal: **38399 checks, zero failures**. Unified validation:
**4178 Godot checks / 46 Python tests**, exit 0,
configured fatal scans passed. Codex audit: **31 checks**, exit 0.
The unchanged official suite's retained resource-shutdown diagnostic occurred
3 times and is explicitly permitted by its existing matcher; no fixture fix was made.
All earlier correctness test files, tolerances and production paths were protected.

The first foreground run stopped before the final formal/unified/audit steps and
has no completed evidence manifest. It is not final acceptance. The complete
background run finished every Godot/unified step with exit 0, including 31 audit
passes, but the new orchestration wrapper expected the wrong audit summary format.
Only `logistics/validate.py` was corrected. `verified-complete` rescanned the full
raw logs, required identical runtime/test/benchmark/predecessor Python fingerprints,
ran fresh version/audit checks and completed with exit 0. Both validator fingerprints
and actual original command/wall times are retained; no simulation rerun is claimed
for rescanned steps. No final-run Godot freeze/crash observed.
Final branch head/commit list/remote status are saved externally in `publication.json`
to avoid self-referential document commit hashes.

## Replay

Fresh process ×2, same pinned platform. Tasks 4–6 include six seeds and both
temporal policies. Tasks 1–5 match the frozen predecessor hashes exactly.

| Probe | SHA256 |
|---|---|
| resolver | `3c369000cbf20ed19fb53d20dde0f47fea9f025a5c1ee32a010cc332b0d92904` |
| roles | `60d41290019b0efeaa7e21bee3201461a912cff8bfb838642cfe8ae6ef83b3e3` |
| sandbox | `a079c498616d72209811861d72fad70ccab5dd6ea3c13bceedcaed3ad8882390` |
| task4 | `73c47a49ca73e026227324581975b1315b9386183a21da022827d30e37a646f3` |
| task5 | `c2da3bc13475afb8540ccae93d49b7ce8a5ba072f7c2c4e768ad6f0f7cded664` |
| task6 | `0245979431dca576e2194e884011572d632a1bcdc7c22cc3cd2eea4fb99698f1` |


## Nine local benchmarks

Counters cover resolution through 120 game seconds, including due events and
affected-cell refresh. Allocation/admission and construction are separately
recorded in machine evidence. Diagnostic audit/JSON export are outside timing.
Inventory reads include admitted capability/activity reads on live proxies.
Structural materialization is shown separately from logistics materialization.
Wall milliseconds are observations, never pass gates.

| Case | Inventory reads | Due delivery | Heap compares | Logistics leaves | Proxy edits | Structure leaves | Contacts | Segments | Resolve ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| detailed_unit | 161 | 1 | 0 | 0 | 0 | 0 | 3200 | 4 | 68.208 |
| 40_formation | 18 | 1 | 0 | 0 | 2 | 0 | 32 | 4 | 2.051 |
| 100_formation | 45 | 1 | 0 | 0 | 5 | 0 | 200 | 4 | 7.604 |
| 100_specific_leaf | 43 | 1 | 0 | 1 | 0 | 0 | 220 | 4 | 7.455 |
| 40_attachment | 19 | 1 | 2 | 0 | 0 | 1 | 40 | 4 | 2.624 |
| split_delivery | 25 | 1 | 0 | 0 | 0 | 1 | 64 | 4 | 3.492 |
| retired_delivery | 20 | 1 | 0 | 0 | 0 | 2 | 48 | 4 | 2.920 |
| 1000_future | 22 | 3 | 54 | 0 | 6 | 0 | 32 | 4 | 2.319 |
| 40_formation_sleeping | 18 | 1 | 0 | 0 | 2 | 0 | 32 | 4 | 2.399 |

The 40-squad sleeping comparison has exactly equal logistics, LOD, combat counters,
current active stocks and active outcomes after adding 10,000 areas/30,000 squads.
Construction/storage grows; there is no periodic sleeping inventory scan.
1000 scheduled deliveries process only 3 currently due; 997 remain pending,
future-table scan work is zero and heap comparisons show the bounded indexed cost.
Task 4's ten and Task 5's six benchmark counter records were compared to committed
predecessor evidence and are unchanged, including construction/transition work
where applicable. No historical millisecond observation is reused as a guarantee.

For the admitted active cohorts, 40→100 squads changes 4→10 live proxies:
inventory reads 18→45 and resolved contacts 32→200 (×6.25 for ×2.5 density).
**ACTIVE LOCAL CONTACT SEARCH SCALING = QUADRATIC-LIKE** remains visible.
No contact optimization was introduced. The largest Task 6 resolution observation
is the detailed-recipient case (68.208 ms); sleeping-world construction is a separate
stored cost and is not confused with periodic resolver work.

## Required 19 answers

| # | Question / observed answer |
|---|---|
| 1 | No resource creation observed. Source free + transit + recipient current + consumed mass is conserved. |
| 2 | Receipt occurs at exact ETA; before ETA stocks remain unavailable. One-shot/segmented causal states match. |
| 3 | Duplicate requests/IDs, processing, ticket smuggling and replay do not duplicate receipt. |
| 4 | Ammo scarcity acts through original actual fire/consumption, reducing suppression and casualty output. |
| 5 | Fuel scarcity stops only admitted motor movement. Walking continues; inappropriate fuel allocation rejects. |
| 6 | Assigned equipment and serviceable/damaged counts are distinct; equal assigned counts yield different usable capability. |
| 7 | No automatic repair. Explicit repair consumes actual spares and finite admitted workshop capacity, bounded by damage and authority. |
| 8 | Live detailed records or current proxies own one stock truth; frozen images/history are not current stock. |
| 9 | Formation receipt on 40/100 underlying squads materializes 0 leaves; it edits 2/5 live recipient proxies. |
| 10 | Specific receipt into a 100-squad aggregate materializes exactly 1 leaf and preserves the residual. Already detailed targets need 0. |
| 11 | All inventory, assigned/serviceable/damaged equipment and consumption histories survive 12 repeated split/merge cycles; extended company split also conserves them. |
| 12 | Attachment changes effective responsibility/request scope, keeps permanent membership and existing owned stock, and restores relation at expiry. |
| 13 | A retired merged donor rejects the shipment and returns the whole reserved amount to source, with explicit history; no implicit survivor redirect. |
| 14 | Sleeping-world active logistics/combat counters and outcomes remain exactly equal in the compared cases. |
| 15 | Future deliveries use the existing due-event heap; 1000 records with 3 due do not cause a future-table scan. |
| 16 | Tasks 4/5 tests, hashes and instrumented benchmark counters remain intact; absolute timings are rerun observations. |
| 17 | Economy needs single inventory authority, finite allocation/reservation, idempotent transfer outcomes, exact external arrival facts, spares and finite maintenance capacity. No market/production/finance model is proven. |
| 18 | Organization needs separate permanent/effective responsibility, request versus allocation/maintenance scope, ownership and stable recipient retirement/receipt policies. Full delegation/finance/transport offices remain future or speculative. |
| 19 | Technology supplies structured range/fire/suppression, mobility dependency, fuel consumption, spares demand and wear/serviceability facts. Research/tech trees/levels are not implemented or selected. |

Concrete D/E evidence: zero-ammo case spends 0 and has 0 casualties in the initial
comparison; supplied case spends 45.6 with 0.29737485504 casualties and nonzero
actual fire/suppression. Fuel-exhaustion movement is 0.00555555555555554 km in the
low-fuel fixture, then remains stopped until explicit refuel; walking advances
0.0374321546302305 km. The repair fixture restores exactly 2 equipment using 2
spares and 2 workshop capacity, with zero logistics leaf materialization.

## Limits and domain boundary

Homogeneous capability/stock profiles are required for managed coalescing.
Partially covered proxy targets reject/return; explicit leaf targeting is available.
Proportional lazy stock allocation does not reconstruct individual battle history.
Structural subtree materialization follows the unchanged Task 5 policy.
Sources and capability inputs are trusted admitted snapshots behind strict command
validation, not a hostile-code security boundary. Replacement/reinforcement,
redirection, routing, vehicle assets, wages, ownership finance and full economic
institutions are not implemented. Workshop capacity is admitted, never generated.

Known contested control, post-completion hold/fire, one-axis/uniform terrain,
fractional casualties, perfect reports, ordinary-soldier combat gap, limited high
rank vocabulary and no air/naval combat remain. No sandbox/GUI work or human visual
acceptance was performed or required. No formal Economy, Organization, Technology,
Geography, main scene or save schema was integrated.

See [contract](README.md), [machine evidence](evidence/windows-20261007.json),
[Economy requirements](../MILITARY_ECONOMY_REQUIREMENTS.md),
[Organization requirements](../MILITARY_ORGANIZATION_REQUIREMENTS.md),
[Technology requirements](../MILITARY_TECHNOLOGY_REQUIREMENTS.md).
Raw logs/protection/publication evidence: `C:\Users\agcrf\wwo-war-lab-results\task6`.
