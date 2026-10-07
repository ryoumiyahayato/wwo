# EXPERIMENT: formation and spatial aggregation resolver v0 (task 4)

**LOCAL EXPERIMENT / NON-PRODUCTION. Production integration = NONE.** Base is
Task 3 / PR #105 at `3e80a827f457cf0b3bf146ca765fb6adeb41b57a`, containing the
unmodified history of #103 and #104. This is simulation coalescing, not an
organizational merger. It introduces no formal world, geography, economy,
organization, save contract, named-person combat or presentation system.

## One authority and one time

`Authority.configure(BattleState)` takes ownership of that one state. The private
settlement capability prevents an independent `Resolver.resolve_until` from
settling its interval again. Live `BattleState.units` contains either a leaf or
its aggregate representation, never both. All cells use `BattleState.time`.
Materialization does not advance time or rerun past contacts.

An aggregate holds structured weapon rate/lethality/range, suppression capability,
mobility, exposure through the existing terrain/posture kernel, stock ledgers,
readiness/fatigue/cohesion/suppression, mission and source-formation metadata.
There is no CombatPower or new combat kernel. `IndexedResolver` subclasses the
predecessor and replaces only candidate discovery. The shared kernel distributes
fire by represented tactical-target multiplicity and scales its existing unit
denominator floors by the same multiplicity. This preserves the per-group rules
even when personnel is below one. With no aggregate metadata, the predecessor's
equations, replay and original operation counters remain unchanged.

An admitted cohort has one side, cell, weapon, type and mobility, equivalent
mission semantics, compatible resource intensities and condition values. A
member may deviate by at most 20m from the admission anchor only if its weapon
covers the entire uniform cell; otherwise positions must match. Conditions and
stock intensities have a 2% admission envelope. Disabled, suppressed and cohesion
threshold decisions must agree. Heterogeneous/out-of-ammunition profiles, existing
coordination/dependency ownership, tactical inputs and cross-cell destinations
retain detailed representation. Rejecting admission is not a permission to
average away their causal differences. These envelopes are research admission
constraints, not relaxed correctness-test tolerances.

Leaf IDs and organization memberships persist in composition references. Their
frozen images are explicitly **unresolved**, not current detailed truth. Current
stock facts reside only in live representations and the conserved world ledger.
Snapshot current missions are filtered to live representations; standing/shared
mission templates are separately labeled non-current.

## Macro current, micro lazy

Coalescing scans the admitted members once. Subsequent resolution touches the
aggregate proxies, not every suspended squad. Each aggregate retains an explicit
unresolved distribution interval. On materialization, casualty/equipment/ammo
deltas are allocated proportionally to admitted available stocks, deterministically
and without randomness. Bounded condition changes and displacement are carried
forward; immutable readiness/mobility are preserved. No individual contact/death
history is invented. `unresolved_history` explains this limitation.

`read_leaf` is a causal materialization query. `preview_leaf` is a detached
allocation proposal used for input preflight/scoped macro reporting; it is not
an independently settled leaf or an individual historical report. Only requested
leaves are extracted, leaving the residual aggregate and its stocks current.
Materialized missions own their status without overwriting shared templates.
An off-grid order materializes its target exactly when due, before the original
event handler; retiring the last aggregate member updates the current delta.

Roles are admitted once against their original static membership snapshot, then
bound to the owning coordinator with `Roles.bind_lod`. Original role/value/scope,
ID and cooldown checks run before materialization. Accepted mission/coordination/
tactical inputs extract only their existing eligible leaves. Ordinary-soldier
personal records confer no new squad authority or combat effects. Role reports
identify unresolved projections; reports do not settle combat. Role lifecycle,
attachment and dynamic admission are not implemented.

## Independent spatial and formation axes

The synthetic hierarchy has one 50km logical root, four 25km parents and 100 5km
cells. It is a logical envelope, not a high-resolution global RTS map. The
predecessor's one-axis, uniform-cell combat remains. Legacy `field` fixtures are
formation-only inputs outside this addressed hierarchy; `cell_000`–`cell_099`
fixtures exercise spatial propagation. There are no cross-edge contacts.

Parents only maintain additive stock and control histograms. A changed cell folds
a delta into its two ancestors; no parent fights again or scans all children.
Cross-cell transfers update both necessary paths, including a source whose
control did not change. Input admission initializes hierarchy summaries once.
Changing a hierarchy view never selects combat rules or automatically expands
details. Formation level labels platoon/company/battalion are independent of
the cell/view scale and of the existing 30/120-second accuracy policies.

`zoom_in("cell_037")` uses the cell-to-aggregate index. It expands that branch's
members only, not all 100 cells. A mixed state can retain detailed leaves alongside
other formation proxies on the same clock. `Spatial.view` returns a detached copy.

## Contact query and instrumentation

The position-sorted index uses binary lower/upper bounds, then visits in-range
candidates in stable-ID order. Candidates include allies/self before the kernel
filters actual opposing contacts. Sparse queries avoid all-pairs discovery;
genuinely dense opposing contact remains quadratic in live representations.
Formation coalescing reduces those representations; it does not claim every
dense problem becomes linear.

Counters record input admission, coalescing, live leaf/formation record visits,
index records and binary probes, candidates, actual contacts, materialized leaves,
segments/events and spatial ancestor writes. Repeated property reads within a
record visit are not byte-level counters. Index/weight stock accesses are counted;
construction and transition work are reported separately from resolution.
Explicit full snapshots, evidence serialization and macro diagnostic reports are
not the benchmark's core-resolution interval. Input memory still scales with
retained identities; materialization is deterministic redistribution, not lossless
reconstruction of microscopic history.

## Real local validation

From this worktree, using the pinned executable and a writable external output:

```powershell
& '<python executable>' -B experiments/war_resolver/aggregation/validate.py `
  --godot 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --output 'C:\Users\agcrf\wwo-war-lab-results\task4\verification'
```

The default runner first performs the complete predecessor `validate.py
--regressions`, then import/fatal scans, Task 4 tests, fresh-process replay twice
and all ten benchmark records. An explicit `--retained-evidence` can reuse a
just-completed 18-step retained run only when predecessor source fingerprints
match and no other predecessor runtime/test/data changes exist. Task 4 tests,
import, both probes and benchmark still run. The complete Task 4 source set is
checked for changes during execution. Timings are observations, never CI gates.

Tests cover A–P: conservation/absolute drift bounds; eight repeated round trips;
exclusive settlement; detailed/formation/mixed and 120s policy comparisons at
six seeds; resource/cover/suppression/low-personnel structure; dense/sparse contacts;
40/100 squads; sleeping population; one-cell ancestors; bounded zoom; exact
orders/reinforcements/terrain/reserves; full-cohort event retirement; role
scope/atomicity; fresh processes; insertion/faction symmetry and independent LOD
labels/views. The model version pin is the recorded Task 4 source digest plus
Git code commit, not just the inherited legacy BattleState label.

See `TASK4_LOCAL_VALIDATION.md` and `evidence/windows-20261007.json` for actual
machine results, limits and pending publication. Comparison fixtures are separate
counterfactual test inputs, not competing authorities inside one running battle.

## Limits retained

Compatible cohorts only; no dependency migration, contact-footprint terrain
integration, heterogeneous capability mixture, cross-edge contact or high-fidelity
formation movement. Distribution loses micro history and approximates bounded
condition differences. Input leaves and templates are retained; command IDs and
mission clones are not bounded for production persistence. No broad tactical
plausibility, arbitrary partition or cross-platform bit-identical guarantee.
Finite seed/fixture invariance supports research, not a proof for all conditions.

Contested control, post-completion/withdrawal combat/action semantics, fractional
casualties, perfect reports, static hierarchy, limited higher-role verbs and
ordinary-soldier gameplay gaps remain. The #105 sandbox is unchanged and remains
an observer of its predecessor resolver; it does not present Task 4 LOD. Its known
readability issue is reserved for a separate experiment. No new rendered/manual
acceptance or exported build is claimed here.
