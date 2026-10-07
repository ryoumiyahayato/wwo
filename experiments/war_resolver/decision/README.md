# Task 8 — bounded person decision / command contract v0

DRAFT / EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.
Exact base: Task 7 final `4145a123b583a6a43c9777d24aff4288248aa924`.
This is isolated algorithm research. The deterministic policies are test providers,
not a formal AI or a final commander gameplay design. No production world,
Organization, Economy, save, map, main scene, command UI or sandbox is connected.

## Data boundary

`decision_context.gd` constructs a copied envelope containing the person's latest
at most 64 **received** claims, their own role/position, current admitted authority
target metadata, standing-order inputs, decision time, cadence and personal command
cooldowns. Each admitted target window is at most 64 IDs. Structure metadata is
identity/echelon/current scope, not combat status. The context never copies a
BattleState snapshot or reads positions, casualties, suppression, stocks or RNG.
The claim history itself is retained by Task 7; a bounded decision page is not a
claim that the provider has examined all historical knowledge.

`adapter.gd` supplies the same envelope to player and autonomous sources. A player
may supply a proposal; the autonomous test source evaluates `test_policy.gd`.
Both receive dictionaries of data only, without a reader, role, service or world
object. The provider owns only its mode/proposal. This is an engine capability
contract for trusted providers, not a hostile-GDScript security sandbox.

The test status policy prefers reliability, then observed_at, then received_at,
then stable entry ID. It returns hold for a known hold/stalled claim, otherwise
withdraw. Missing status or a command cooldown returns keep. The ammo test policy
can request 10 ammunition from a LOW claim. A separate attachment test proposal
uses admitted standing-order parameters. None is intended as final doctrine,
strategic intelligence or historical command behavior. Conflict selection never
edits the original knowledge history or refreshes it from physical truth.

## Explicit opportunity, then separate issuance and effect

The decision service binds before any causal events are pending, so opt-in phase
adoption cannot reinterpret an already queued event. Person enrollment admits one
provider and definition. `schedule(person, id, T)` creates an explicit ticket in
the existing authoritative min-heap. The service never runs each combat segment,
scans all persons, or automatically enrolls the whole world. Opportunities are
one-shot; after a decision, the next opportunity must be explicitly scheduled and
respect the admitted cadence. Cadence is an experiment parameter, not game balance.

At T the resolver folds actually received reports first, then invokes the one
person's provider and validates the proposed output. The service records
decision ACCEPTED/REJECTED separately from the issued input and, for commands,
Task 7 PENDING/EXECUTED/REJECTED. Acceptance does not mean command execution.
Creation authorization uses current metadata and existing domain validation.
Issuance validates again through the domain API. Physical command delivery retains
Task 7's delivered-time authority checks, including attachment/retirement rejection.
Authority validators may verify the domain's live admissibility; they do not
provide hidden combat facts to the policy or its context.

Supported outputs are deliberately small:

- **keep**: no input is submitted; the existing mission/coordination continues.
- **command**: a mission for officers or tactical intent for a squad leader,
  using Task 7 transmission and existing Role input semantics. Ordinary soldiers
  cannot submit these officer intents; their current envelope supports keep only.
- **logistics_request**: a bounded formation stock request through Task 6. It
  neither allocates a depot nor creates stocks. A separate authorized allocation
  and Task 6 receipt are required for supply to arrive.
- **structure_request**: an attachment request through Task 5. It must be future
  (`delay >= 1` second), with current scope validation and a later expiry. Decision
  admission does not change the relation or materialize a leaf.

No WIN_BATTLE, casualty/suppression/inventory setter or combat bonus output exists.
The service counts zero physical truth reads for decision input/provider evaluation.
It has a world-clock/heap host reference for integration; policies do not receive it.

In the tested timeline: decision and command issue at 10, command ETA 25. Mission
and leaf representation stay unchanged before 25. Only the original command path
changes the mission and materializes the causally required leaf at 25. Command
execution cooldown starts at delivery, so its ready time can differ from the
decision cadence and command-issue cooldown; the context exposes these separately.

## Scheduled and urgent policies

Reports normally update knowledge only. `admit_urgent(person, message_id)` is an
explicit host admission for a person enrolled with urgent enabled. It checks the
report's fixed recipient metadata and schedules a separate opportunity at no
earlier than ETA+5, now+5 and that person's cadence boundary. It can replace only
that person's later pending opportunity. Duplicate/non-earlier/other-person wakes
reject. It does not inspect pending claim values or provide them early.

At that deadline, an undelivered/failed report skips provider execution. Reports
are not universally urgent; there is no global message listener or automatic
mission reaction. Replaced tickets remain in the heap until due, then skip the
provider. This bounded lazy cancellation keeps deterministic queue semantics;
the obsolete ticket's eventual heap work and causal boundary are recorded.
There is no automatic recurring reschedule or restoration of a replaced regular
opportunity after failed urgent receipt. Standing missions still continue.

Opt-in same-time phase order: attachment expiry, structure, stock receipt,
maintenance, report folding, decision, communication command, ordinary orders,
reinforcement, area changes, coordination releases, then combat interval work.
Existing relative phase relations remain. Unbound Tasks 1–7 retain old behavior.
Actual opportunities are causal deadlines; preview alone creates none and cannot
change combat integration. Scheduled keep/skipped tickets still have queue/clock
work, so preview invariance is not a claim that every admitted opportunity has
zero numerical settlement cost.

## Work, LOD and limitations

Only due tickets build contexts. Preview is bounded and never schedules/settles.
It can increment existing information/structure diagnostic read counters, but
world time, RNG, BattleState, combat counters and LOD materialization remain intact.
Decision context, provider evaluation and request admission materialize zero.
Physical commands/structure/logistics events keep their existing causal LOD rules.

The 1000-person fixture admits distinct real people before Task 5 binding using
the original role/structure/logistics/information APIs; 992 additional persons are
ordinary soldiers. It does not alias one commander under 1000 IDs. Construction
and storage include existing per-role admission snapshot costs and can grow;
the active decision counter test processes only three actual due people.

Diagnostic snapshot/result records are for evidence hosts. There is no graphical
command interface, autonomous strategy, natural-language order generation,
automatic recurrent NPC brain, universal decision framework or new soldier combat
behavior. Persisting pending opportunities, provider state, canceled tickets and
decision provenance in formal saves remains future work. Large target windows,
long history summaries, urgent admission policy and cadence balance are unfinished.

## Validation

Use `decision/validate.py --godot <pinned executable> --output <unused external directory>`
on the dedicated Task 8 branch. It checks exact ancestry/protected predecessor
paths/version, runs Tasks 1–8 tests, all predecessor hash pairs/benchmarks, Task 8
fresh-process replay, ten benchmarks, five retained regressions, the unchanged
unified script and Codex audit. Frozen GDScript/Python fingerprints must match
before/after. Original test files and tolerances are unchanged. Raw timing is an
observation, never an absolute milliseconds gate.

See `TASK8_LOCAL_VALIDATION.md`, `evidence/windows-20261007.json` and
`../MILITARY_DECISION_REQUIREMENTS.md`. Human visual acceptance is explicitly not
required or run for this task. Earlier war limitations are preserved.
