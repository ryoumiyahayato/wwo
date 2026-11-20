# Goal Cycle 01 — price/payment research

Single workspace: `/workspace/wwo-economy-lab`, local branch
`research/economy-goal-cycle-01`, Round6 BASE_SHA
`334d3f546824415604b7645a91a61196fb2bad83`. No remote publication.

Python3.12 standard library. Current complete runner is tested on Linux;
`resource.getrusage` memory measurements are Linux process high-water values.
No claim of testing this cycle on Windows or WWO integration.

```sh
# Fast correctness, observer controls and seven temporary log corruptions:
python verify_goal_cycle01.py --correctness-only --output-dir .local/goal-cycle01
# All historical economic regression plus two independent official replays:
python verify_goal_cycle01.py --output-dir .local/goal-cycle01
# Optional separately numbered experiment suite; new output directory required:
python economy_quantity_lab/goal_cycle01/run_cycle.py --suite main --output-dir .local/cycle-main-new
python economy_quantity_lab/goal_cycle01/run_cycle.py --suite long --output-dir .local/cycle-long-new
python economy_quantity_lab/goal_cycle01/run_cycle.py --suite scale --output-dir .local/cycle-scale-new
# Standalone accounting checker: no simulator imports:
python economy_quantity_lab/goal_cycle01/offline_audit.py .local/cycle-main-new/normal_S2_N3_nonbinding_600
```

`experiments_manifest.json` fixes formal fixtures, controls, days, funding and
candidate version. `GOAL_STATE.json` and `EXECUTION_PLAN.md` carry exact resume
instructions and the original non-resetting ten-hour limit. Never start a second
copy of a running verifier. Complete outputs stay in `.local`; curated summaries,
source/gate evidence and failed development probes stay in `evidence/`.

N0 uses the unmodified economic behavior of Round6 C1. N1 adds uniform nominal
payments with the original ranking; N2 ranks known current offers by posted price
then all old tie-breaks, while ReleaseBook still enforces dates. N3 changes only
new local quotes every completed seven-day window, effective the next day. Arrival
pays the locked price; dispatch does not pay; confirmed cancellation releases only
undispatched value. Terminal price is fixed per external sink. No credit or refill.

Funding upper bounds use each firm's own input capacity, initial inventory/targets
and the same23-day exposure allowance at every scale, assuming no sale revenue.
External accounts cover the declared horizon at maximum daily fixture demand.
The finite group uses20-day initial funding and never replenishes accounts.

The one candidate is documented in `pricing.py` and the frozen manifest. It uses
own free stock, actual shipments and received need identities, with distinct
physical/price/cash refusal signals. Tick rounding can stop adjustment below50
integer units; all safety boundaries and clamp hits remain reported. Model results
may be worse. No candidate tuning is performed after inspecting formal outcomes.

Compact/off replace only reporting archives with count-preserving current-day
tails and retire closed runtime order records. Active material/order indexes,
identity dedup maps and local planning semantics remain. Full/compact/off authority
hash equality and independent reconstruction are tested. Dedup identity maps still
grow with distinct dates; this is bounded-duration research, not constant-memory
infinite operation.

Historical Round6 provenance includes source hashes. The original strict entry
`verify_round6.py` remains unchanged: on the new hook source it detects the expected
manifest-only source difference. The new verifier separately checks all370 frozen
economic outputs, the same371-file set, all50 old tests, and the sole authorized
source delta against actual file bytes. Exact-base371-file two-replay verification
is also preserved. No golden fixture, output or invariant is refreshed.

The offline checker reconstructs already recorded facts, recipes and dual ledgers.
It makes no economic decisions and is not a second simulation or third-party
certification. Performance files do not enter economic result hashes. Timing
categories describe hook attribution; event streaming time overlaps its caller.
File bytes, Python GC-tracked object counts and measured process RSS high-water
are separately named; no global WWO performance claim follows.

Future CI routing is updated locally: trees containing `verify_goal_cycle01.py`
run the complete new entry; older trees retain original verification steps.
No remote CI execution is claimed. The four timing groups use orchestration
boundaries: procurement includes atomic acceptance/resource reservation, and
settlement includes arrival/cancel/production/terminal/dispatch/account work.
`off` suppresses expanded daily/quote files but keeps mandatory minimal audit
records. Both observations and the measured sample duration are explicitly scoped.
