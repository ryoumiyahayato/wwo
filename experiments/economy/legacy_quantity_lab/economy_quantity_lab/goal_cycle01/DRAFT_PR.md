# Suggested Draft PR (local text; no remote PR created)

Title: Research: bounded multi-firm price/payment controls and local quote feedback

Round6 can accept and transport goods without a price or cash commitment. This
research adds one integer cash authority and atomic stock/cash/transport-slot
reservation, locks accepted prices, pays sellers once on actual arrival, and
charges finite external sink accounts only when goods are delivered. Confirmed
cancellation releases only the undispatched value; injected failures restore all
acceptance authorities and buffered events.

N1 preserves original Round6 C1 physical behavior with nominal payments. N2
changes known-offer ranking to fixed posted price with the complete original
ordering as its tie-break, retaining date eligibility and C1 scarcity. N3 changes
only new seller quotes using one pure local seven-day completed-window rule,
with next-day activation,2% maximum steps, explicit ticks and safety bounds.
The manifest separates nonbinding money controls from finite-funding boundaries;
it preserves scale parameters and does not introduce credit, refill or WWO code.

A standard-library offline checker reconstructs both ledgers from initial state,
minimal events, recipes and ending state without importing simulator accounting.
Seven corrupted-log probes must fail. Compact/full/off observer authority equality,
unknown-information guards, future-prefix isolation, unit scaling and disabled
feedback controls are tested. Complete600-day,3600-day and bounded-degree scale
results and two independent-process replay evidence are attached in the final
report/evidence. Model degradation is retained and does not constitute a failed
accounting gate or justify adoption.

Validation: `python verify_goal_cycle01.py --output-dir .local/goal-cycle01`.
Locally completed:264 historical checks,42 new correctness tests, two independent
50-case/66000-day replays,353 economic file hashes/set identical,84 paid-case
offline audits, and seven unique corruptions rejected. Model result is MIXED:
shutdown N3 loses3 deliveries to N2, S5 totals gain8 with some sinks worse,
and normal long-run D hits its quote cap after Day609. No default adoption. Original historical fixtures and
golden outputs are unchanged. Round6's original strict source manifest detects
one authorized hook-file source delta; the new verifier explicitly checks370
unchanged economic files and the actual source delta. M0 also preserved exact-base
371-file two-replay success. No push, merge, tag or remote PR was performed.
