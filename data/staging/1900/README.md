# WWO 1900 World Data Source Pack

This directory is an isolated historical-data staging area. It records facts,
provenance, crosswalk decisions, uncertainty, and validation results for the
1900 starting-world pipeline. It is not loaded by the runtime and must not be
treated as gameplay balance data.

## Files

- `pack_manifest.json` — snapshot, input inventory, and isolation policy.
- `source_record.schema.json` — normalized source-record contract.
- `source_manifest.json` — reusable sources and their limits.
- `canonical_crosswalk.json` — conservative mappings from the existing 1900
  historical aggregate entities to current repository IDs.
- `source_records.json` — the first high-confidence candidate batch.
- `conflict_register.json` — explicit source-conflict protocol and current
  conflict set.
- `priority_backlog.json` — the next 50 data-entry targets.

## Status rules

`EXACT` means that the supplied member code resolves to one current repository
ID. `LIKELY` means that all member codes resolve but the historical entity is a
composite whose canonical representation is a set, not one ID. `AMBIGUOUS`
means that collapsing the record would erase a union, fragmented polity, or
contested control distinction. `NO_MATCH` is reserved for records with no
defensible current ID.

Only `EXACT` mappings may be considered for a later authoritative candidate
pipeline. Even those records remain `STAGED_NOT_RUNTIME` in this batch because
the existing runtime data and the CShapes-derived snapshot have different
provenance and geometry policies.

The first batch uses the repository's isolated CShapes 2.0 snapshot for
political-unit names, validity intervals, capital names/coordinates, and
explicit controller relationships. It does not add GDP, production
coefficients, legitimacy, ideology, military effectiveness, or resource
yields.
