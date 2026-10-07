# Task 7 — military information / communication contract experiment v0

DRAFT / EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.
Base: Task 6 final `15f9f652ba9c2016f3851ff03379684c13c6ba6f`.
This extends the isolated war causal algorithm. It does not establish a formal
Information System or Military System. No production scene, save, world,
Organization, Economy, map or sandbox is connected.

## Contract and ownership

`BattleState` remains the single physical authority. The service admits sources,
channels and existing person-bound role interfaces once. Only a source producer
can obtain a scoped observation reference. An observation selectively reads a
bounded current representation; it is not a copied world snapshot. The reader's
observation result contains the reference, not a hidden truth projection.

Reports contain immutable claims. Actual receipt appends entries to a person's
knowledge. Each entry retains subject kind/ID, fact kind, claimed value,
`observed_at`, `created_at`, `sent_at`, `received_at`, source, reliability,
precision and message ID. Incorrect, stale and conflicting claims stay in the
history; quality never edits world facts or silently corrects a claim.
Reliability is admitted source quality multiplied by admitted channel quality;
it is metadata, not a simulated probability of truth or combat modifier.

Position is a coarse area/band. Status is a bounded set of existing actions.
Ammunition, fuel and readiness are LOW/AVAILABLE/UNKNOWN claims, not inventory
transfers. Direct producers observe the current world time. Explicit EXTERNAL
source input can describe a past time and can be wrong. Unknown provenance,
future timestamps and non-finite or malformed values are rejected.

Source scope is an admitted experimental observation capability, not a radius,
visibility simulator or inferred entitlement from rank. DIRECT,
SUBORDINATE_REPORT, HQ_REPORT and EXTERNAL are supported origins. The fixtures
give ordinary soldiers a local source and officers larger/coarser sources.
No person automatically receives all facts in that source scope. Sources,
channels and registry wiring belong to the trusted experiment host; underscore
fields and GDScript objects are not a hostile-code security boundary.

## One clock, two due-event queues

Both queues use `BattleState.time`. Commands are physical causal deadlines in the
existing resolver heap. Pure reports use a separate deterministic min-heap keyed
by `(delivery_time, message_id)`. They do not add integration boundaries to the
combat resolver: doing so would change existing numerical settlement merely
because a person was informed.

At resolver boundaries, the host folds reports due through the actual current
world time. Each receipt is stamped with its exact logical ETA, even if a long
resolve folds it at a later boundary. An explicit advance to T makes it available
at T; at T-epsilon it is absent. Knowledge queries never drain queues or advance
the clock. The drain refuses a supplied time different from the world clock.
There is no independent communication clock or periodic future-message scan.
There is also no autonomous decision tick at every pure report arrival. A future
agent that acts on an arrival would need to admit its own real causal deadline.

When enabled, same-time ordering preserves the earlier relative phases:
attachment expiry, structure, stock receipt, maintenance, pure report folding,
delayed command, ordinary order, reinforcement, area change, coordination release.
Combat then consumes those boundary inputs. Report payloads were fixed at
observation/send time; they are not recomputed from same-time structure or stock
changes. Unbound Tasks 1–6 keep their original ordering and hashes.

## Delayed command path

`Reader.issue_command` validates the existing Role interface in a mutation-free
preflight and creates a fixed actor, target, channel and ETA. Issuance does not
replace the old mission. Issuance and execution cooldowns both apply. At delivery,
the service checks the exact pending ticket, live target, available channel and
current person-bound Role authority/values/IDs/cooldown again. Only then does the
existing Role implementation change mission/tactical/coordination inputs.

Information-aware mode gates direct `Role.apply`, preventing an immediate bypass.
Delayed personal `local_action` is intentionally not admitted. Task 7 does not
add soldier gameplay or new combat decisions. The unbound #104 path is unchanged.

Attachment that invalidates the old issuing scope produces REJECTED. A merged or
retired target produces REJECTED / retired_recipient. No survivor redirection or
command migration occurs. Reports target stable person IDs, not offices;
attachment changes do not transfer a person's private mailbox to a successor.

## LOD policy

Formation facts use Task 6's maintained effective-node-to-current-proxy index,
without inspecting the sleeping world. A macro observation requires wholly
covered current proxies, at most 64 records, and one area for a position claim.
Partial proxies, unavailable facts or multi-area position summaries are explicitly
rejected; a trusted external report is a separate admitted alternative.

A named leaf still represented by a proxy receives an explicitly annotated
`proxy_derived_estimate`, not invented exact microscopic history. It examines one
current representation and materializes **zero** leaves. Exact leaf reconstruction
for intelligence is not implemented. A delivered physical command can materialize
the causally affected scope through existing Task 4/5 Role interfaces; that work
is separately counted as `leaves_materialized_for_commands`.

## Person-facing ports and future presentation

`reader.gd` binds one person. Knowledge queries return copied received claims,
at most 64, with indexed subject/fact lookup and an older-history cursor. The
underlying append-only history retains provenance beyond a page. Inbox queries
return at most 64 received reports and their structured claims/unread flags.
Outbox queries expose at most 64 of that sender's message metadata/status, without
claim values or command payloads. Pending, delivered/failed reports and
pending/executed/rejected commands remain distinguishable. Command recipients
are existing structural targets; no new subordinate-person inbox is invented.
Unread acknowledgment, inbox pagination, message retention limits, durable
delivery/save migration and natural-language text are not implemented.

With an information port, `Role.report` uses only those person-facing records and
own role metadata; without it the old experimental debug truth report remains.
`decision.gd` gives player and autonomous test paths the same received-status
capability and UNKNOWN behavior. It is not a strategic AI. Diagnostic
`Service.snapshot` is for test/evidence hosts and is absent from the decision port.

## Reproduce

From this dedicated Task 7 branch, using the pinned engine and an unused external
output directory:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -B `
  'C:\Users\agcrf\wwo-war-lab-local\experiments\war_resolver\information\validate.py' `
  --godot 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' `
  --output 'C:\Users\agcrf\wwo-war-lab-results\task7\rerun-unique'
```

The runner checks ancestry/protected paths/version, runs all original Tasks 1–6
tests and hashes, Task 7 A–T/V tests and two fresh-process replay probes (U),
all predecessor benchmarks, ten Task 7 benchmarks, the five retained regressions,
the unchanged unified validation and Codex audit. Fatal script/load/parse errors
are scanned even if Godot exits zero. Sources are fingerprinted before and after.
No earlier test or tolerance is weakened. See `TASK7_LOCAL_VALIDATION.md` and
`evidence/windows-20261007.json` for measured results and limitations.

Counters separate admission, due delivery, knowledge reads, fact reads, report
heap work, causal materialization and shared causal heap comparisons. The latter
counts every existing State heap comparison while information is bound, including
structure/logistics tickets; it is not a count of command-only comparisons.
`future_messages_examined = 0` means no future-table scan; heap root checks and
logarithmic comparisons still exist. Wall times are this machine's observations.
