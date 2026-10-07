# Military → future Information requirements, Task 7 evidence

DRAFT / EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.
This document extracts military requirements. It does not prescribe a
UniversalInformationSystem or claim integration with WWO's formal domains.

## IMPLEMENTED in the isolated military contract

| Requirement | Evidence |
|---|---|
| One physical truth; independently received person knowledge | A/F/R: world movement does not refresh knowledge; copied queries and pure reports leave physical state/counters unchanged |
| Fact time differs from knowledge acquisition time | B/C: observed at 0, received at 47; absent at 46.999; segmented knowledge equal |
| Claims preserve provenance, quality and contradictions | D/E: differing old/incorrect values and source qualities retained, never corrected from truth |
| Stable person-private receipt independent of effective office relations | M: attachment moves the office's effective hierarchy; the original person gets the private report, another person does not |
| Due-only report transmission with stable identity/idempotence | N/O: duplicate admission and delivery do not duplicate knowledge; 1000 pending, 3 delivered, 997 pending, no future-table scan |
| LOD-compatible bounded producer/query ports | F/G/H/P: aggregate/leaf estimates materialize zero; +10000 areas/+30000 sleeping squads do not change active information or combat counters |
| Command issue differs from command effect | I/K: mutation-free issue preflight, old mission until exact delivery; one-shot/segmented causal state equal |
| Authority is revalidated against delivered-time structure | J/L/V: moved target and retired donor rejected, no implicit successor redirect; common-time structure/logistics precede commands |
| Same information capability for player and autonomous adapters | Q: the received-status test adapter has no world-state port; changing hidden truth leaves its input unchanged |
| Historical military subjects are not live entity aliases | S: reports survive split/merge/retirement; new subjects use new stable identities |
| Resource reports cannot settle inventories | T: ammunition/fuel/readiness claims only update knowledge, stocks unchanged |
| Deterministic record and delivery replay | U: six seeds, both policies, fresh-process hash pair; no random communication loss |
| Structured future message presentation | Personal inbox/unread/claim metadata; sender outbox pending/success/failure; no UI or natural-language rendering |

## EVIDENCE-BACKED FUTURE NEED

- A shared information kernel would need separate fact time, report formation/send
  time and person receipt time. Collapsing these loses the tested stale-report
  distinction.
- Cross-domain messages need stable subject and person references, provenance and
  a typed bounded payload admission contract. A retired military subject remains
  meaningful in history without becoming a live authority target.
- Cross-domain observation producers must selectively read admitted facts from
  each domain's authority. Received claims must not serve as competing physical
  truth or as hidden full-snapshot refreshes.
- Any future agent acting automatically on receipt needs an explicit decision
  deadline. Pure presentation/knowledge receipt must not perturb physical
  integration; Task 7's separate noncausal queue demonstrates why these categories
  need different settlement semantics despite sharing a clock.
- A future Organization connection must supply current actor/office/scope binding
  and delivered-time authority checks. Private person mail and office mail need
  different explicit routing policies; only person mail exists here.
- Long campaigns need retention/pagination, save/restore and replayable pending
  delivery admission without losing conflict provenance. Current knowledge pages
  are bounded but retained storage grows with received reports.
- Future message presentation needs unread acknowledgment and queries for reports
  and command outcomes. This experiment exposes structured records but does not
  implement that lifecycle or a graphical message center.
- Large multi-area formations need a bounded regional-summary producer policy
  rather than a reason to materialize all leaves; this experiment explicitly
  rejects an unavailable one-area position claim.

These needs are supported by military tests and current explicit limits. Political,
economic, diplomatic and personal domains must provide their own evidence before
selecting a common schema or kernel implementation.

## SPECULATIVE / NOT IMPLEMENTED

Radio propagation, frequencies, courier routes, infrastructure topology, encrypted
communication, deception planning, probabilistic signal loss, full reconnaissance
visibility, semantic belief fusion, automatic fact correction, public news/media,
cross-domain forwarding, office-successor mailbox routing, command migration,
strategic AI, player learning UI and durable formal saves remain out of scope.
Rank does not automatically imply exact information; the admitted source model
can express larger/coarser officer scope without prescribing full gameplay.

The task preserves ordinary-soldier combat-consequence and higher-command
vocabulary limitations from earlier research. Information does not supply missing
combat behavior or turn this experimental chain into a finished game system.
