# WWO 1900 World Data Source Pack

This directory is an isolated historical-data staging area. It records facts,
provenance, crosswalk decisions, uncertainty, and validation results for the
1900 starting-world pipeline. It is not loaded by the runtime and must not be
treated as gameplay balance data.

## Files

- `pack_manifest.json` — snapshot, input inventory, and isolation policy.
- `source_record.schema.json` / `source_records.schema.json` - strict nested source-record contracts.
- `source_manifest.json` - reusable sources and their limits.
- `canonical_crosswalk.json` / `canonical_crosswalk.schema.json` - conservative code-resolution mappings from the existing 1900
  historical aggregate entities to current repository IDs, with identity and successor evidence kept separate.
- `source_records.json` - the first provenance-backed staging batch.
- `conflict_register.json` — explicit source-conflict protocol and current
  conflict set.
- `priority_backlog.json` — the next 50 data-entry targets.

## Status rules

`EXACT` in the crosswalk is named `EXACT_CODE`: the supplied member code
resolves to one current repository ID. It is not proof that the 1900 historical
entity is identical to that current entity and it is not a successor relation.
`LIKELY_COMPOSITE` means that all member codes resolve but the historical entity
is a composite whose canonical representation is a set, not one ID.
`AMBIGUOUS` means that collapsing the record would erase a union, fragmented
polity, or contested control distinction. `NO_MATCH` is reserved for records
with no defensible current ID.

Code resolution, historical identity, successor relation, and authoritative
promotion are separate decisions. The current 61 records keep
`historical_identity_status=UNVERIFIED`, retain no identity/successor evidence,
and set `automatic_authoritative_candidate=false`. Future promotion requires a
tracked source reference, date scope, target entity, and an allowed explicit
evidence type. Every record remains `STAGED_NOT_RUNTIME`.

The first batch uses the repository's isolated CShapes 2.0 snapshot for
political-unit names, validity intervals, capital names/coordinates, and
explicit controller relationships. It does not add GDP, production
coefficients, legitimacy, ideology, military effectiveness, or resource
yields.
