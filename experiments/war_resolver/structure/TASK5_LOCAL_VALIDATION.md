# TASK5 LOCAL VALIDATION — Windows 2026-10-07

**A. UNIT STRUCTURE / ATTACHMENT ROUTE SUPPORTED** within the constrained experimental contract. No final Task 5 blocker observed. EXPERIMENTAL / NON-PRODUCTION / DRAFT. Production integration status = NONE.

Branch: `experiment/unit-structure-attachment-v0-20261007`.
Base: `f80cc6ce0752a53f6a6dabc7913db45a7735046c` (Task 4 final local HEAD).
Validated code HEAD: `c18ba00c7ca9e865f2d814c5fb348bae8abd35dc`. The next commit contains documentation/evidence only; final branch HEAD and complete commit list are recorded externally in `PUBLICATION_PENDING.md` / `publication.json`.
Godot: `4.6.3.stable.official.7d41c59c4` at `D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe`.
Worktree: `C:\Users\agcrf\wwo-war-lab-local`.

## Verification and replay

- #103/#104/#105 and retained regressions: **17,567 checks, 0 failures**, all 18 steps passed.
- Task 4: **17,329 checks, 0 failures**, all tests, replay pairs and ten benchmarks rerun; original tolerances unchanged.
- Task 5 A–P and additional boundary checks: **788 checks, 0 failures**; 20 zero-time split/merge cycles, 12 attach/revoke cycles, company split, extreme/malformed requests, current-mission preflight, stale-adapter denial, expiry/re-coalescing and sleeping-world comparisons.
- Unified validation: exit 0; **4,178 Godot checks and 46 Python tests**; configured fatal scan passed. Its three pre-existing `41 resources still in use at exit` diagnostics are allowed by that script's existing rule; retained logs preserved and no cleanup fix made.
- Codex audit: **31 checks passed**.
- Fresh-process Task 5 replay ×2, six seeds and both temporal policies: `c2da3bc13475afb8540ccae93d49b7ce8a5ba072f7c2c4e768ad6f0f7cded664`.
- Task 4 replay unchanged: `73c47a49ca73e026227324581975b1315b9386183a21da022827d30e37a646f3`.
- Resolver unchanged: `3c369000cbf20ed19fb53d20dde0f47fea9f025a5c1ee32a010cc332b0d92904`.
- Roles unchanged: `60d41290019b0efeaa7e21bee3201461a912cff8bfb838642cfe8ae6ef83b3e3`.
- Sandbox unchanged: `a079c498616d72209811861d72fad70ccab5dd6ea3c13bceedcaed3ad8882390`.

Final suite ran all predecessor validation first, then Task 5 tests/probes/benchmarks against a frozen full experimental GDScript/Python fingerprint. Those fingerprints were verified again after the code commit. Earlier development/intermediate logs remain external; only `frozen` is final evidence. The unified suite covers unchanged formal sources; final frozen retained regressions also rerun formal military and persistence checks.

## Local structure-operation counters

Each case starts after 120 game seconds of settled combat. Work below includes request preflight, execution, materialization and affected-cell stock refresh, excluding admission/setup and output serialization. Instantaneous cases have zero new combat segments. Expiry includes the final 156→157 second combat interval, explicitly not an event-only timing. Wall times are observations, never gates. Proxy-membership edits may touch the same residual aggregate more than once when multiple members are extracted.

| Case | Leaves materialized | Structure reads | Proxy membership edits | Scope indexes updated | Contacts | Segments | Spatial nodes | Parent writes | Wall ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| detailed_company_split | 0 | 515 | 0 | 180 | 0 | 0 | 3 | 2 | 4.126 |
| aggregate_leaf_detachment | 1 | 9 | 1 | 5 | 0 | 0 | 3 | 2 | 0.455 |
| 40_aggregate_one_attachment | 1 | 42 | 1 | 6 | 0 | 0 | 3 | 2 | 0.371 |
| 100_aggregate_one_attachment | 1 | 42 | 1 | 6 | 0 | 0 | 0 | 0 | 0.475 |
| 40_aggregate_sleeping_attachment | 1 | 42 | 1 | 6 | 0 | 0 | 3 | 2 | 0.387 |
| attachment_expiry | 0 | 18 | 0 | 6 | 12 | 1 | 3 | 2 | 1.143 |

The 40-/100-squad attachment changes one real leaf and one residual aggregate; structure work stays bounded by that relation and ancestor paths. A stock refresh additionally reads the live representations in the affected cell, so local active density can increase those reads. No claim that every metric is independent of active density is made. The sleeping comparison has exactly equal structure/LOD/combat counters and active outcomes. Construction/storage still grows with world size.

## Fifteen answers

1. Split conserves all seven stocks/ledgers to absolute 1e-7; leaf and real company-detachment tests pass.
2. Compatible leaf merge sums resources into the named survivor without adding the ledger twice. Donor history and stable identity remain reserved, not live.
3. Twenty 0-time split/merge cycles show no resource drift or condition recovery; inherited tactical measure is conserved. This supports the tested policy, not arbitrary regrouping gameplay.
4. Attachment retains permanent parent separately from current operational parent.
5. Effective command and report scopes move from old to receiving superior. Unbound/stale legacy adapters are denied, and queued structural events revalidate authority at delivery.
6. Expiry/revoke restores permanent relation at its exact boundary. Stale expiry cannot override a new attachment; adjacent intervals use expiry-before-begin ordering.
7. Suspended leaf split or attachment materializes **one** leaf and edits **one** residual proxy; a whole-company attachment materializes its 20 affected leaves, not unrelated red units/world.
8. A one-leaf attachment does not expand the whole formation or 50km region; unrelated proxies remain live aggregates.
9. Each leaf has one live representation. Transfer removes old ownership; old-parent coalescing is rejected, new-parent coalescing and later expiry are tested.
10. No double settlement observed: structural boundaries add no elapsed combat, independent resolver access is rejected, and materialization keeps world time unchanged.
11. Split copies conditions; merge uses worse fatigue/suppression, worse cohesion and matching capabilities. Attachment changes no physical combat state or position.
12. Task 4 tests/hash/counters remain intact for unbound battles. Dynamic structure keeps the same kernel and independent formation/spatial LOD; local detail legitimately increases live contact work until explicit compatible coalescing.
13. +10,000 sleeping areas/+30,000 squads add **zero** active operation work in the compared structure and continuation cases.
14. Original Role Overrides tests/hash remain intact. Dynamic scope, reporting, ordinary-soldier rejection, recipient command and retired/stale adapter rejection pass.
15. Evidence supports separate permanent/effective relation queries; interval/revision identity; authority revalidation; identity/provenance/retirement; unique simulation ownership; bounded materialization; and a supply-responsibility lookup reference. Lifecycle/appointment and event migration are future needs. Universal Organization and actual logistics/payroll ownership policies remain speculative.

## Scope, protection and limits

Only experimental paths changed. #105 sandbox remains unchanged and a pure observer. No visual acceptance/UI design, formal Organization/Economy/Geography/save integration, air/naval, named-person deaths or command succession was added.

Split requires explicit proportional allocations. Merge supports compatible sibling combat records, not arbitrary whole-company mergers. Directly attached leaf/company splits and pending order/reserve/coordination migration are rejected; an attached ancestor can retain normal leaf splits. Exact position/capability/mission checks prevent teleporting and incompatible merges. New company offices get no invented commander. Military structure authority is the service's admitted relations; old combat `parent_id` metadata is not an operational command source.

The numerical effective threshold scales by preserved tactical measure only in structure-bound battles, preventing tiny detachments from becoming untargetable. Parent summaries never fight. Micro history remains approximate/lazy; inputs, event IDs and retirement history consume growing storage. Offices are admitted once; late adapters from old snapshots are rejected. No generalized succession, communication, event migration or persistent schema is claimed.

Original worktree agent writes: **NONE**. HEAD/branch/index remain unchanged. Full before/after status+diff identical: **NO — independent concurrent work appeared; preserved without agent writes**. Exact comparisons are external in `original-protection.json`. Historical generated UIDs/Python caches are excluded from commits.

The final frozen runs have no fatal script error, crash or timeout. Prior known contested control, post-completion action/combat semantics, one-axis/uniform terrain, fractional casualties, perfect reports, personal-combat gap and limited role vocabulary remain unchanged. Publication status and exact commands/title/body are recorded externally after the local commits.
