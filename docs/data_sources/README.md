# WWO data and asset provenance

This directory contains the machine-readable provenance manifest for the
WWO DATA & ASSET PROVENANCE AUDIT. Batch 1 covers tracked files below:

- `data/**`
- `assets/**`
- `docs/**`

The manifest records file size and SHA-256, category, source or generated
status, explicit source locators, explicitly recorded licenses, derived-from
relationships, generators, confidence, review status, and audit issues.

Provenance policy:

- A source or license is known only when the repository contains explicit
  evidence for it.
- Otherwise the manifest uses `SOURCE_UNKNOWN`, `LICENSE_UNKNOWN`, or
  `PROVENANCE_INCOMPLETE` as appropriate.
- An online match or a dataset name without a locator is not treated as proof
  of the current file's origin.
- Unknown licenses are validator warnings, not legal conclusions.
- The dependency graph represents `source -> generator -> generated output`.
- No formal assets are regenerated or deleted by the audit.

The manifest is generated from tracked files and is intended to be rerun after
source or asset changes. Reviewers should inspect the repository evidence
listed in each entry before treating a provenance chain as complete.

Batch 2 adds `provenance_reference_matrix.json`. It statically inventories
tracked producers, consumers, repository path literals, write-site candidates,
and candidate dependency edges under `scripts/**`, `scenes/**`, `shaders/**`,
`tests/**`, and `tools/**`. Dynamic test fixtures are marked
`INTENTIONAL_TEST_FIXTURE`; candidate edges remain review-required and do not
become authoritative provenance automatically.
