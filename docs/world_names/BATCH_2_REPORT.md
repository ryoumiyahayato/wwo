# WWO WORLD NAMES & ALIASES - BATCH 2 REPORT

Starting master: 4b738ab

## Batch 2 coverage expansion

- Repository data JSON files scanned: 224
- Generated data/staging/world_names sources excluded from the scan: yes
- Files with configured name fields: 192
- Files with any name-like fields: 198
- Configured name-field occurrences: 279096
- Unconfigured name-like-field occurrences: 1077
- Parse errors: 0
- Status counts: 13 staged, 158 modern-reference scanned-only, 13 world-map scanned-only, 40 non-world-map scanned-only

## Remaining gaps

- Excluded name-bearing source files: 185
- Excluded configured-name occurrences: 277042
- Excluded unconfigured name-like occurrences: 509
- Field groups requiring semantic review: 21
- No excluded source was promoted to an authoritative entity.
- No machine translation or unsourced historical alias was added.

## Batch 1 regression

- Entities: 923, including 502 authoritative Stable IDs
- Aliases: 2232
- Normalized search keys: 941
- Normalized collision groups: 138
- Search index one-to-many mappings: 133
- Validator: PASS

## Tooling and QA

- Fixed the package lazy-import recursion exposed by package-level imports.
- Added coverage manifest replay validation.
- Added remaining-gaps replay validation.
- Added deterministic corpus with 224 source hashes, 4 artifact hashes, and 8 normalizer fixtures.
- Batch 2 builder: PASS.
- Focused tests: 6/6 passed.
- git diff --check: PASS.

## Authority and delivery

- Authoritative IDs changed: NO
- Production entity catalogs rewritten: NO
- Checkpoint: 339f66e (implementation)
- Push: BLOCKED - network unavailable
- Draft PR: none
- No merge performed by this task.