# EXPERIMENT: real unit split, merge and temporary attachment v0 (task 5)

**EXPERIMENTAL / NON-PRODUCTION / DRAFT. Production integration status = NONE.**
Frozen base: Task 4 `f80cc6ce0752a53f6a6dabc7913db45a7735046c`.
This is real experimental military structure change. Task 4 coalescing remains a
temporary numerical representation of identities, never an organizational merge.
No formal Organization, Economy, Geography, save schema or visual tool is changed.

## Minimal contract and choice

`Service` owns the experiment's admitted military relations, not combat or time.
It holds permanent parent, one optional operational attachment interval, stable
unit-to-node identity, provenance and retired historical records. Incremental
child/descendant indexes serve existing role scopes. One-time admission uses the
existing role snapshot validation. No general graph, staff AI or succession system
is added. `Commands` binds one concrete person; requests cannot select an actor,
rank, side, resource bonus or combat result. Company-and-higher officers can submit
structural requests within their current effective ancestry. Creating a peer
company requires its superior's scope, not the source company's commander.

A generic mutable organization graph would add rules and migration obligations
without evidence. Rebuilding every role tree after each change would be simple but
scan unrelated formations. Permanent parent plus one effective-parent override
and changed ancestor paths is enough for these constrained behaviors. The cost is
limited support for rank-skipping, multi-parent command, dynamic appointments and
arbitrary reorganization; none is claimed here.

## Split and merge

Leaf split retains the source ID and creates a genuine new resource-bearing
detachment ID/node, with `from/event/time` provenance and a separate mission
record. A company split retains its source company and clones its current platoon
branches into one peer company, proportionally splitting their combat records.
All seven resource/ledger allocations must be explicit, finite and proportional
to the current stocks. Zero/all transfers and sub-micro-person remainders are
rejected. Independent arbitrary equipment/ammo ratios are not admitted in v0.
The company identity is a structural unit whose resources reside in its leaves;
no additional combat proxy or second copy of its stocks is created.

Readiness, mobility, position, displacement, fatigue, suppression, cohesion,
action and mission status are inherited unchanged. Split uses the already-settled
current macro allocation proposal, then materializes only the affected leaves.
Future allocations are revalidated against due-time stocks; a stale allocation
is rejected rather than silently rescaled. Split/merge reject pending unit events,
mission dependencies, cross-cell missions and tactical/coordination inputs whose
migration is not defined. Directly attached leaves and companies cannot split;
ordinary leaves within an attached ancestor may split and follow that ancestor.

Merge is constrained to two compatible real combat records with the same permanent
and effective parent, exact same cell/position/capabilities and equivalent missions.
The requested survivor retains its stable ID; the donor is retired with an explicit
historical resource image and `into/event/time` relation. Retired IDs cannot be
resurrected by another split or reinforcement. Stock sums enter the survivor
without another `add_unit` ledger injection. Fatigue/suppression/displacement use
the worse maximum, cohesion the worse minimum, and readiness/mobility must match.
No state is refreshed. Generic whole-company merger or arbitrary rendezvous is
not implemented; the 0-time round-trip contract is tested for the supported leaf
split/merge pair, not claimed for every organizational echelon.

An inherited `tactical_weight` is split proportionally and combined additively.
It preserves the predecessor's tactical-target share and denominator floors;
creating another ID does not create another full tactical-group allowance. It is
not combat power, a new weapon or a bonus. In structure-bound battles only, the
effective-personnel numerical sleep/contact epsilon scales by that same measure
(aggregate uses its total measure). Thus an extremely small detachment is not
made untargetable by an unscaled whole-group epsilon. Intensive suppression
thresholds and weapon/terrain/fire laws remain unchanged. Unbound predecessor
and Task 4 behavior stays exact, verified by its unchanged replay hashes.

## Attachment and authority

Attachments require same side, the existing adjacent-echelon relation, an
authorized common superior, a finite future end and no overlapping interval on
the target. Permanent parent is never overwritten. Operational command scope,
perfect reporting scope and later coalescing eligibility follow the effective
relation. A subordinate keeps its own position and authority over its descendants;
the old operational superior loses the transferred subtree, while the recipient
acquires it. Previously valid standing missions persist until valid new inputs;
attachment does not create a combat bonus, move units or refill stores.

Only the affected subtree is materialized. The leaf-to-proxy ownership map removes
its old membership before the relation changes. A later coalescing request must
name a currently effective containing formation; the old parent cannot reclaim
the transferred leaf. Other aggregates and sleeping areas remain suspended.

Expiry restores the permanent relation at its boundary. Explicit revoke uses
the same limited-scope transition; an old expiry becomes a recorded no-op and
cannot overwrite a later attachment. `supply_responsibility_reference` returns the
current operational parent as a future lookup reference only. It does not produce,
transport or allocate supplies. Equipment/payroll/replacement responsibility
policies are not inferred from this experiment.

Existing Roles optionally bind the same structure service once at admission.
Once a BattleState adopts dynamic relations, an unbound or differently bound
legacy adapter is explicitly denied input/report/scope access; it cannot bypass
the current relation with its old static snapshot. Late adapter admission from
historical snapshots is unsupported and rejected.
The adapter queries its current indexed scopes and effective ancestry; it retains
the original input vocabulary, permission layers, input clocks and nearer-input
precedence. A position on a retired leaf becomes inactive; no successor is invented.
Structure requests have distinct IDs and explicit boundaries, but no new gameplay
rate calibration. Repeated zero-time operations are intentionally permitted for
exploit tests, not asserted to be desirable gameplay. Ordinary soldiers and squad/
platoon leaders cannot submit these structural requests. Without explicit events,
the state is exactly equivalent to Task 4 autonomous resolution.

## One clock, event ordering and rejection

There is one BattleState, one LOD coordinator settlement capability and the same
combat kernel. Configure the structure service before queuing any events and
bind roles before executing structural changes; importing an already-pending
legacy event heap is rejected. Within a structure-bound battle, at a timestamp:

1. Combat through that timestamp uses the preceding state, once.
2. Attachment expiry/reversion runs first.
3. Other structural events run by stable event ID, revalidating current authority,
   identities, stocks and compatibility before any materialization/mutation.
4. Orders, reinforcement, terrain and coordination-release events run in that
   phase order, then stable ID within each phase.
5. Subsequent combat uses the resulting current state.

Unbound legacy heaps retain their original time/ID order. A pending unit-reference
index prevents unsupported split/merge migration without scanning the world or
entire event heap. Submission rejection changes neither authoritative state nor
request/ID clocks. A previously admitted future event may be rejected at delivery;
it is logged and consumed without partial materialization. This is not retroactive
revocation of already-settled war. Parents summarize changed local stock facts and
never resolve combat again.

## Instrumentation and verification

Input admission is separate from operation work. Structure counters record
relation/ancestor reads, events, materialized leaves, residual aggregate membership
edits, updated scope indexes and real relation changes. Combat/L0D counters are
reported separately; local stock refresh may read the other live representations
in that affected cell, never the whole sleeping world. Explicit report/snapshot
serialization can scan the requested scope and is outside core resolution work.

From the experiment worktree:

```powershell
& '<Python executable>' -B experiments/war_resolver/structure/validate.py `
  --godot 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --output 'C:\Users\agcrf\wwo-war-lab-results\task5\verification'
```

This runs all #103–#105 tests, retained regressions and Task 4 validation before
the new A–P checks, fresh-process six-seed/two-policy replay twice and six benchmark
cases. Fatal log scanning catches script errors even with engine exit 0. All
experimental GDScript/Python fingerprints are frozen for the run. Wall times are
observations, never pass/fail gates. See `TASK5_LOCAL_VALIDATION.md` and committed
machine evidence for actual outcomes and exact tested code version.

## Research boundaries

Static admitted offices, compatible leaf merges, proportional resource splits,
same-side adjacent-echelon attachments and synthetic one-axis cells only. New
offices are not appointed; newly split formations get no invented commander.
No arbitrary hierarchy-level merge, authority delegation, multi-parent command,
communication network, logistical responsibility policy, future-event migration,
cross-platform float contract, general persistence or bounded history storage.
People/roles outside the admitted experiment tree are not discovered globally.

Prior contested control, post-completion action/combat behavior, uniform terrain,
fractional casualties, perfect reports, personal combat gaps and limited higher
role vocabulary remain. Sandbox stays unchanged and observes its existing battle;
Task 5 adds no visual/manual acceptance, UI or formal integration.
