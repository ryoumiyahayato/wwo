# Organization information required by the military role experiment

**EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.**
This document concerns only task 2's military decision inputs. It proposes no
universal Organization model and changes no formal organization authority.
Dependency: task 1, draft PR [#103](https://github.com/ryoumiyahayato/wwo/pull/103),
`experiment/land-war-resolver-v0-20261006` at
`524b669214469e4b343830afef8f4ef8768ec225`. Formal baseline:
`canonical/current-world` at `622b260bc641036c23efbf6345a548485ac6c475`.

## Implemented control and evidence

One adapter binds one stable person ID and their admitted position. Commands
contain no selectable actor, rank, side, resolution, spawn instruction or global
control permission. A higher position owns a broader mission/coordination input;
it does not inherit the soldier or squad leader's local input. Accepted commands
apply at the current game-time boundary, without retroactive combat. All references,
values, scope and generated IDs are checked before changing records, events,
command IDs or input clocks. The tests include a collision on the last affected
squad to detect partial application.

| Person's role | Input they can replace | Target scope | Minimum seconds between accepted inputs | Report |
|---|---|---|---:|---|
| Ordinary soldier | Own wait, take cover, bounded step forward/back | Bound person only | 30 | Own action and position |
| Squad leader | Hold, advance or support tactical intent | Own squad only; assigned objective stays intact | 60 | Own squad aggregate |
| Platoon leader | Squad mission and reserve/coordination posture | Direct subordinate squads | 120 | Squads in own platoon |
| Company commander | Platoon missions/reserves; company's main direction | Own company mission/coordination or direct platoons | 300 | Direct platoon aggregates |
| Battalion commander | Company missions and coordination | Own battalion or direct companies | 600 | Direct company aggregates |
| Regiment commander | Battalion missions and coordination | Own regiment or direct battalions | 1,200 | Direct battalion aggregates |
| Division commander | Regiment missions and coordination | Own division or direct regiments | 1,800 | Direct regiment aggregates |

These intervals are experimental input limits, not historically calibrated rates.
Input frequency is enforced; report aggregation is enforced, but report reads can
be requested at any time. Reports are perfect scope-limited snapshot reads, with
no global totals or enemy units. This establishes authority scope, not realistic
information availability. It does not prove these rates make enjoyable gameplay.

Higher mission inputs inherit through the indexed command tree into existing
squad mission records; nearer mission inputs retain precedence. Coordination
uses the nearest posture and the latest superior reserve-release time. Existing
task 1 mission dependencies still gate lower tactical intent. Squad intentions
never rewrite mission objectives; higher mission commands do not clear those
intentions. Mission replacement of an indexed prerequisite is explicitly rejected
for the entire command, preserving autonomous reserve release; dependency
migration/cancellation semantics remain unimplemented. Mission inputs have
posture, a bounded abstract objective, and advance
axis direction. There is no order to move a named soldier from a higher position.

The resolver continues to decide contacts, fire, suppression, withdrawal,
mission completion and movement autonomously. With no player command, every role
has exactly the same result as the original AI resolver. Standing AI missions and
coordination come from trusted scenario inputs; this is an inherited mission
translation policy, not a new operational mission generator or full soldier AI.

The ordinary soldier record is deliberately narrow: a named person's action and
at most a 20 m offset from their squad, moved by 5 m per accepted step. Take cover
is recorded but does not independently change exposure, survival, squad casualties,
ammunition or squad movement. No individual combat record is instantiated for
all soldiers. The soldier's report follows the squad when the war advances.

## Information actually required now

| Information | Implemented use and evidence | Boundary of the claim |
|---|---|---|
| Membership | Stable person → formation ID; squad formation → existing squad record, side; unique squad membership | Only named test people are represented. No formal population/person import or full membership roster. |
| Position | Role and formation binding; compatible echelon; one admitted holder of each command position | Static during a run. Not rank promotion, social status or office appointment. |
| Command scope | Own formation / direct child whitelist, role layer whitelist, input clock | Every role/target/layer combination is tested, including unrelated battalion and skipped echelons. High role cannot spawn combat entities or request resolution. |
| Subordinate relation | Parent ID with exact ascending echelon and same side; child and descendant squad indexes built once | Admission rejects cycles, duplicate squad membership, side mismatch and invalid position. Scope expansion runs on a command, never every frame or idle tick. |
| Reporting relation | Direct subordinate aggregate reports; soldier own record; scoped read-only access | Perfect information. Reporting visibility, reliability and delayed knowledge are not modeled. |
| Communication relation | Only current-boundary role submissions and task 1's existing indexed reserve wake events | No separate messenger/radio network. Task 1 communication-delay fixture remains a standing-order event regression, not evidence of implemented role-command transmission latency. |

The adapter is one per isolated battle and is configured once. The command tree
is experiment-owned input, never a competing source of formal membership or
organization truth. Production facts would have to be admitted from formal
authority in a later integration, which is outside this task.

## Evidence-backed future needs, not implemented

- **Temporary attachment:** a squad attached to another platoon would need an
  explicit effective interval and command-scope relation distinct from permanent
  membership. Current parent/scope tests show why changing only a display label
  would be insufficient. The experiment does not yet exercise attachments.
- **Delegation:** lower input ownership is preserved now. Delegating a subset of
  mission or coordination authority would require the delegator, recipient,
  allowed layer, subordinate scope, expiry and revocation boundary. There is no
  evidence that blanket rank-based delegation is needed, and no delegation API.
- **Succession:** if the controlled person dies, leaves office or loses command,
  a successor and authority boundary would be required. Static role admission
  cannot validate live succession, revoke future deliveries or model survival.
  This is required only when those lifecycle events enter the experiment.
- **Communication and reporting:** existing delayed orders and exact wake tests
  justify retaining issue/delivery times on future commands. Person-specific
  reporting paths, delayed observations and authority revalidation at delivery
  would be needed before using imperfect information or succession. No routing,
  historical radio capability, courier planner or reporting cadence is chosen.

## Speculative ideas and gameplay gaps

Supply institutions, staff offices, multi-parent organizations, national command,
formal organization composition, political appointment and a universal hierarchy
schema are speculative here. Nothing in this experiment proves they are needed
for its current permissions; they must not be implemented from this document.

Ordinary soldier control currently lacks individual tactical consequences and
cannot establish sufficient gameplay. Squad leader intent does change scoped
squad behavior, but offers only three intents. Platoon and company roles add
mission and reserve choices; their tactical variety and meaningful input rates
still need observation and playtesting. Battalion, regiment and division currently
share the same mission/coordination vocabulary at increasingly broad scopes; a
small ten-squad fixture cannot prove distinct operational gameplay for them.
Unit tests prove permission boundaries and simulation effects, never enjoyment.

The evidence supports task 3's **isolated visual observation sandbox** for inspecting
these limitations. It does not establish production readiness. Keep the known
longer-interval AGGREGATE policy (no formation coalescing), quadratic local contact
search, abstract one-axis objectives, trusted snapshots and unresolved baseline
economy golden failures visible. Air/sea combat, formal UI, maps, saves, Economy
and Organization integration remain out of scope.
