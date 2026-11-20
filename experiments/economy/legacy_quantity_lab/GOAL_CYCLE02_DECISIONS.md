# Goal Cycle 02 decisions and failures

2026-10-08T02:43Z M0 SOURCE_CONTINUITY_GATE PASS. Exact package checks pass.
Original base restored with authenticated GitHub read connector, validating every
Git object SHA. Git commit exact author/committer timezone +0800; base is a shallow
boundary whose old parent history is not fetched. Bundle restores original93633b4.
Two direct git read paths did not authenticate/accept namespace; ENVIRONMENT_BLOCKER
for those paths resolved by the supported connector. No source regeneration.
Correctness42 and original seven negative log checks pass; all12 source digests
match Cycle01 GOAL_STATE. Full historical/frozen verifier running independently.

M1 design: new read-only subclass observes the inherited single runtime. It never
calls procurement on shadow offers, never asks an unknown supplier for a quote,
never feeds diagnostic world ATP back into decisions, and leaves step order intact.
T release semantics are both timely and release-due, so default current offers
execute at exact need-by==conservativeETA. A cheaper timely offer for a later date
is not necessarily an executable alternative today. Shadow reports are explicitly
same-state, not predictions of long-run counterfactuals. Fungible inventories allow
DAG/date/order linkage, not unique attribution of each coal unit to a final machine.

2026-10-08T02:53Z EXPERIMENT_DESIGN_DEFECT: initial new correctness test ran
20-day prefixes of both planned v1 holdout families. Source and tests_v1.log
preserved. These prefixes are development exposure, not blind held-out evidence.
No candidate parameters were tuned on them. The test now checks structure only.
Separate v2 holdout parameters reserve new dates/budgets without inspecting v2
outcomes; their hashes are frozen before the first simulation. Formal replay waits
for candidate gate before running any v2 holdout. No formal result was overwritten.

2026-10-08T02:57Z IMPLEMENTATION_DEFECT (research statistics, no economic
runtime defect): naive shadow-price-selected attempt count included14 weak
observations on R_LEGACY later rounds. Preserved v1 developmental evidence.
Strong metric now requires actual R_PRICE_FIRST, first round, strict same-date
positive current resources, a rank difference, and positive accepted dated line;
actual linked arrivals and separately executed pair differences are distinct.
Independent review confirms R_LEGACY strong count0 and price-first197/194
accepted-needs/linked-arrivals on60-day equal-date development evidence.

2026-10-08T02:58Z Independent recorded-fact audit now reconstructs original7-day
signals from requests and shipments/stock facts, calculates tick/clamp/formula,
and checks next-day actual quotes. It imports no simulation/runtime decision
module. Accepted quantities and direction/tick/clamp blockage are additionally
recorded locally. Old N3 algorithm and its historical result remain untouched.

2026-10-08T02:59Z Storage boundary: a normal3600 expanded causal log was633MiB.
New causal traces use deterministic gzip (mtime0, empty filename, level1) while
original events/daily authority and accounting audit are unchanged. This is an
archive format control, not a new policy; two fresh process byte hashes will
verify compressed-file determinism. Existing developmental logs are retained.

2026-10-08T03:03Z IMPLEMENTATION_DEFECT (offline causal audit only): first
formal process stopped after15 complete cases; the16th, coal-scarcity N3 binding,
finished600 physical days but audit raised KeyError(56) because a legitimate day
had no monetary/material events. Event reconstruction now carries unchanged state
through empty days, with zero shipments. No policy, fixture, source behavior,
manifest configuration or golden result changes. Failed process/files/log preserved.
A fresh full replay uses the corrected auditor; both successful formal process
source digests will match.12 controls finished before this audit-only repair;
their physical runs need no repetition and fixed auditor rechecks their facts.

2026-10-08T03:14Z EXPERIMENT_DESIGN_DEFECT (static, no holdout result): H2/v2
fixtures increased T1 demand from5 to6 after original monetary construction but
retained5/day terminal funds. All H2/v2 remain unrun. Independent reviewer found
the bound before execution. Preserve original manifest/hash; standalone funding
revision raises only external:T1 from6000000 to7200000 by600*6*2000. Demand,
prices, limits, physical fixture and all original39 non-holdout cases stay frozen.
Final N2/N3/N4 holdouts use exactly the same corrected terminal balances.

2026-10-08T03:21Z NEW_PRICE_CANDIDATE_GATE PASS after39 actual pre-candidate
configurations/59400days, including all12 long cases and4 scale cases. Seven
conditions and before-holdout proposal hash recorded independently. Do not select
Gate values for runner convenience: old runner deliberately stopped at its
incorrect pre-assumption that only FAIL/INSUFFICIENT could precede holdout. Its39
complete cases and full exit/error remain in pre_candidate_39. No H2 was run.

Exactly one N4 selected: local-zero-accept-refusal-bound-v1. A seller learns from
zero actual accepted quantity despite positive actual PRICE refusals, positive
own free stock and zero CASH refusals. No direct buyer limit enters the function.
No-new-information holds first; remembered ceiling is a target approached under
old tick/floor/cap/2% step, not authority for an abrupt step. The candidate uses
one integer/seller-good and own acceptance counter independent of trace settings.
An existing PaymentPolicy view is wrapped without constructing another CashAccounts.
Original N3 and all Cycle01 source files remain untouched.

2026-10-08T04:08Z ENVIRONMENT_BLOCKER: native execution lifecycle interrupted
both final processes at03:47:05; each52/59 cases and85200days finished, S10 N4
was only partially recorded at553/599 days. Both session probes returned unknown,
no final execution/hash manifests or exit codes existed. Old files retained as
interrupted_replay_*_v3; no partial run claimed as600days or complete replay.
Two new unchanged-source complete59 processes launched04:11; budget never reset.

2026-10-08T04:33Z Both recovery processes reached terminal PASS:59 cases and
89400days each; complete deterministic file/hash sets match. Original interrupted
runs remain excluded from successful replay count. Postprocessing-only defect
fixed after both terminal states: analyze() overwrote its case cache with day links.
Rename to day_cache, preserving original execution version at710dac3 and immutable
runtime result hashes. This repair never reruns or changes economic experiments.

2026-10-08T04:43Z IMPLEMENTATION_DEFECT (offline coverage, not runtime): independent
review reproduced a GHOST_NEED accepted-line map with conserved total that v3
accepted. Final v4 checks exact request/accepted need keys, integer/nonnegative
per-line bounds, stable date/commodity/source-bucket association, and committed
FIFO line allocation. A second cross-log association hole allowed swapping two
same-day/same-price/same-quantity order IDs between actual buyers; v4 also matches
buyer/seller/commodity/route to the actual dated request. Original v3 checker and
both old-accept/new-reject negative traces preserved. Formal archives were scanned
independently with677487 requests/625257 accepted events and no actual mismatch.
Only post-execution audit changed. Two completed simulation/file hashes remain
immutable; all118 formal archives and all10 negative logs receive final v4 review.

Frozen candidate Gate evidence path mapping: its original replay_a/39-case source
was moved to .local/cycle02/pre_candidate_39. The Gate file/hash remains frozen;
this mapping resolves it without rewriting the decision or using later holdout.

2026-10-08T04:59:53Z final v4 re-audit exit0:118 accounting/118 causal archives and10 precise negative logs PASS. Economic execution source remains710dac3; final analyzer/checker are explicitly post-execution revisions. Source PASS, causal PASS, model MIXED. M0—M5 research acceptance DONE; final verified handoff is the sole remaining activity. No user decision or new authority is needed, no Cycle03 starts.
