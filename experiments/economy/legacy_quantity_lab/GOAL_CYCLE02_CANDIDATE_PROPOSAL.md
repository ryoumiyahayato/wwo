# Candidate proposal before any v2 holdout execution

Status: proposal only. No candidate code or N4 simulation before M4 and final Gate.
One proposed version: local-zero-sales-refusal-bound-v1, N4_EXPERIMENTAL.
Original N3/local-window-v1 remains unmodified.

Hypothesis: a windowed seller that discards its earlier observed PRICE refusals
can repeatedly raise through a fixed willingness boundary even after learning
that this posted price stops all its actual sales. This predicts cyclic idle
stock/price refusals and reduced material service, separable from the same
physical coal capacity under N2.

Local state: one remembered refusal ceiling per seller/commodity, initially the
same existing4x initial-price upper boundary. No buyer private max-price value,
other firm plan, terminal backlog, future event, or world aggregate enters it.

Pure function inputs: current/initial/tick; original completed7-day LocalWindow;
actual accepted quantity during that same window; previous remembered ceiling.

Learning condition, all required:
- Actual PRICE refusal quantity >0
- Accepted quantity ==0
- Seller current uncommitted physical stock >0
- Actual CASH refusal quantity ==0

On that condition, remember min(previous ceiling, current posted price minus one
configured tick), floored at the original initial/4 tick-rounded lower boundary.
A refusal by one low-limit customer cannot learn a bound while another actual
customer has a positive accepted quantity in that window.

Compute original local-window-v1 proposal first, then bound its next price by the
remembered ceiling, original floor/cap, and current +/- original tick-rounded2%
step. A zero original step still prevents movement. Effective date remains next
day; accepted orders retain their original locked price. Learning can narrow a
ceiling without an immediate price move. No parameter scan or tuning.

Counterfactual: frozen normal/coal-scarcity/recovery N3 versus N4, both limit groups,
600 and3600 days; S5/S10; both still-unrun v2 holdouts. Same original physical
inputs, funding, limits, initial quotations. Primary discriminator is cyclic
PRICE-refusal/zero-sales windows and actual goods/sink distribution, not quotation
smoothness alone. Original N2 stays the physical/fixed-price reference.

Negative cases: some accepted sales despite PRICE refusals must not learn a bound;
CASH-only or physical-only refusals must not learn; no new information holds;
tick/floor/step remain bounded; nominal unit scaling must preserve decisions.
Mixed limits may still leave low-limit buyers starved while high-limit buyers
trade. A permanent memory may respond poorly to a future willingness increase or
new customer. These are explicit limitations; holdout failure will not be tuned
away. No adaptive buyer bid, elasticity, credit, or global information is added.

Specification clarification before implementation/freeze:
- If information_count==0, retain current quotation and prior memory first.
- Otherwise ceiling is a target, not permission to violate the2% rate limit:
  new_price = max(original_low, current-step,
                  min(original_high, current+step, v1_price, new_ceiling)).
  If memory lies below current-step, approach gradually; do not claim the quote
  instantaneously satisfies memory. All quantities/tick remain integer-aligned.
These clarify safety priorities, without changing any tested candidate parameter.
