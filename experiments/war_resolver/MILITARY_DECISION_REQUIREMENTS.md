# Military decision requirements — Task 8 evidence

DRAFT / EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.
This extracts causal boundaries for future military gameplay. It does not define
formal Military, AI or Organization systems, or complete any rank's gameplay.

## IMPLEMENTED in the isolated contract

| Boundary | Actual evidence |
|---|---|
| Combat information is received person knowledge, not hidden truth | A/I: hidden position, ammunition, action and seed differ; same context/policy output. Stale hold claim remains observed_at=0 at decision_time=10 while actual movement has occurred |
| Decision is an explicit one-person event | B/C: absent at 9.999, created at 10; a new received claim changes a later deadline's context |
| Reading is separate from acting | D/K/S: repeated copied queries/preview issue no command and preserve complete physical state, RNG, counters and LOD; report alone does not react |
| Output is an authorized existing-domain input | E/F/N/O: command goes through Task 7, supply through Task 6, attachment through Task 5; no bonus/casualty/stock setter |
| Decision acceptance, issuance and execution are different states | E/F: accepted at 10, pending until 25; a later attachment rejects the delivered old command without rewriting the accepted decision history |
| Input capability depends on person/role/current authority | G: ordinary keep, squad tactical, officer mission/logistics, senior attachment; admitted target windows and cadences differ |
| Player/autonomous capability is the same | H: copied context fields and full resulting physical state match for two real source paths; source is separate provenance |
| Conflicting claims need a deterministic selection rule | J: quality, observed/received times and stable ID select within a bounded page independent of array ordering; history retained |
| Urgent receipt is bounded, person-specific and separately admitted | L: report ETA47, decision52, only its recipient wakes; another scheduled person stays at200; duplicate/cross-person wake rejects; failed receipt skips |
| Standing order survives absent decision | M: units continue their original mission when no new intent is submitted |
| Future actors are not scanned each combat segment | P/Q: 1000 distinct enrolled persons, three due; 997 pending, future-person scans zero. +10000 sleeping areas/+30000 squads preserve active counters/outcomes |
| New context does not require microscopic truth | G/S and macro benchmark: no decision/context materialization; causal delivery alone performs existing local LOD work |
| Replay and predecessor contracts remain testable | R/T: fresh process pairs, protected old tests/tolerances, all existing hash/counter records rerun |

## EVIDENCE-BACKED FUTURE NEED

- A military decision opportunity needs an actor ID, explicit world-clock boundary,
  capability envelope and input/decision/source provenance. Knowledge reads must
  remain queries; provider evaluation must not be a receipt/query side effect.
- The already identified Task 7 future decision deadline requirement is now
  exercised: urgent information admission may create a real later deadline while
  pure receipt remains noncausal. A future Information connection must distinguish
  those policies and handle unavailable receipt without supplying hidden claims.
- A future Organization connection must distinguish current authority from old
  knowledge, and preserve checks at creation, issue and effect. Rank alone cannot
  imply omniscience or a complete gameplay vocabulary.
- Opportunity cadence, issue rate and command-execution cooldown are separate
  clocks/boundaries. The tested command at25 leaves execution ready_at145 even
  though the original decision cadence from10 permits another opportunity at130.
  Future presentation must explain these without granting a bypass.
- Larger campaigns need bounded knowledge summaries/selection windows, retained
  decision provenance and formal persistence of pending/canceled opportunities.
  Current admission snapshots and append-only evidence records have storage costs.
- A future gameplay layer needs explicit policy for recurring opportunities,
  urgency qualification, replacement restoration after failed messages, command
  priority and player input timing. The current one-shot policy proves a causal
  route, not those final choices.

## SPECULATIVE / UNDECIDED

Optimal doctrine, command intelligence, staff support, historical rank balance,
army/division/regiment/battalion/company/squad gameplay loops, battlefield plotting,
command UI, strategic goals, automatic planning, GOAP/behavior trees/utility
frameworks, LLM commanders, learned policies, morale bonuses and full-world NPC
brains are not implemented or justified as final designs by this experiment.

The test policy is deliberately simple and can make poor military choices.
Higher ranks largely share existing command vocabulary with wider scope and
different experimental cadence. Ordinary soldier combat consequences remain the
earlier unresolved limit. No completed rank gameplay or production readiness is
claimed. Existing information/organization requirement documents remain valid;
this document records the exercised boundary without rewriting their old evidence.
