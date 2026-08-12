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

Batch 3 adds two low-risk derived records under `tests/provenance/`:

- `provenance_regression_corpus.json` pins a compact, deterministic copy of
  manifest records and the manifest hash for regression checks.
- `provenance_review_backlog.json` ranks only evidence-backed review candidates
  from the manifest and reference matrix. It is not an instruction to modify
  authoritative data, infer licenses, or regenerate assets.

The reference matrix deliberately excludes JSON audit outputs under tests/provenance/ from its runtime producer/consumer scope. Those records are validated separately; excluding them prevents the audit from treating its own serialized evidence as game data references or stale runtime artifacts.
