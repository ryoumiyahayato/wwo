# Production Territory Evidence Contract / Source Registry

Status: `PRODUCTION_GEOGRAPHY_AVAILABLE=NO`

This contract defines the machine-verifiable evidence boundary for future production territory identity. It is evidence authority only: not a Spatial runtime, TerritoryUnitCatalog, controller ledger, Population authority, geometry store, renderer, or historical inference engine.

## Stable source identity

Registered evidence uses deterministic IDs of the form `territory_source:<lowercase_stable_local_id>`. Source identity is separate from future `territory_unit:*` identity. A future `VNextTerritoryUnit.source_snapshot_ref` may refer to one registered source snapshot, but the source snapshot itself is not a territory unit.

IDs and registry ordering are independent of runtime order, filesystem enumeration order, checkout path, clock, UI/camera state, and randomness.

## Record contract

Every record exposes the normalized fields required by the production gate: dataset/provider/version provenance, source and download pages, local resource binding, SHA-256, snapshot and validity dates, geometry scope/granularity/count/CRS, derivation kind/parents/method/parameters, historical target and fit, normalized license/distribution facts, prototype status, and explicit admission status/reason.

Repository-backed records bind existing resource paths and verify their hashes. The registry does not duplicate polygon payloads.

## Admission status model

`REFERENCE_ONLY` is useful evidence that is not consumable as production authority.

`CANDIDATE` has no known failed production gate but still has one or more unresolved required facts.

`ADMITTED` requires every production gate to pass and uses reason `ALL_GATES_PASSED`.

`REJECTED` has at least one known failed production gate.

Not-yet-evaluated and known-ineligible states are therefore distinct.

## Multi-axis production gate

Each required axis is evaluated as `PASS`, `FAIL`, or `UNRESOLVED`:

- `PROVENANCE_VALID`
- `SOURCE_HASH_VERIFIED`
- `TEMPORAL_SCOPE_VALID`
- `HISTORICAL_FIT_VALID`
- `GEOMETRY_SCOPE_VALID`
- `LICENSE_IDENTIFIED`
- `REDISTRIBUTION_ALLOWED`
- `DERIVATIVE_WORK_ALLOWED`
- `COMMERCIAL_USE_ALLOWED`
- `DERIVATION_TRACEABLE`
- `PROTOTYPE_ONLY_FALSE`

Production geography is admitted only if every required gate is `PASS`. Missing evidence never implies permission.

Commercial-capable distribution is mandatory for production admission. The registry records explicit normalized license facts; it is not a runtime legal-text parser. CShapes remains registered as historical/reference evidence, while its declared non-commercial condition keeps it out of production distribution. Natural Earth-derived repository geometry is not promoted merely because its license is permissive: the current France Admin-1 and country resources remain modern/prototype historical mismatches.

## Derivation lineage

Every derived snapshot must name registered parent snapshot IDs plus a non-empty deterministic derivation method. Duplicate parents, unknown parents, and parent cycles are rejected. Parameters and result resource hash are fingerprinted.

An admitted parent does not automatically admit a child. The child must independently pass all production gates.

`political_units_1900.json` is registered as a political evidence projection over CShapes geometry references, not as independent raw geometry authority.

## Immutability and fingerprint

A registry instance configures once. Runtime systems cannot mutate provenance, source hashes, license facts, historical fit, lineage, or admission. Public queries return detached copies.

The deterministic registry fingerprint is SHA-256 over source-ID-sorted, recursively canonicalized source records. It changes when production-relevant evidence metadata changes and excludes runtime/UI/clock/absolute-checkout-path state.

## Current registered evidence

The current registry contains seven source identities:

1. CShapes 2.0 upstream — `REFERENCE_ONLY`.
2. Repository CShapes 1900-03-12 snapshot — `REFERENCE_ONLY`.
3. Repository 1900 political evidence projection — `REFERENCE_ONLY`.
4. Unpinned Natural Earth Admin-1 upstream — `CANDIDATE`.
5. Unpinned Natural Earth Admin-0 upstream — `CANDIDATE`.
6. Repository France Admin-1 modern/prototype projection — `REJECTED`.
7. Repository countries modern/prototype projection — `REJECTED`.

Current machine-readable result:

```text
REGISTERED_SOURCE_COUNT=7
REFERENCE_ONLY_SOURCE_COUNT=3
CANDIDATE_SOURCE_COUNT=2
ADMITTED_SOURCE_COUNT=0
REJECTED_SOURCE_COUNT=2
PROTOTYPE_SOURCE_COUNT=2
LICENSE_RESTRICTED_SOURCE_COUNT=2
COMMERCIAL_INELIGIBLE_SOURCE_COUNT=2
UNRESOLVED_LICENSE_SOURCE_COUNT=1
UNRESOLVED_HISTORICAL_FIT_COUNT=2
DERIVED_SOURCE_COUNT=4
UNTRACEABLE_DERIVATION_COUNT=0
PRODUCTION_GEOGRAPHY_AVAILABLE=NO
```

A zero-admitted registry is valid.

## Preserved architecture

```text
PRODUCTION_TERRITORY_CATALOG_READY=NO
FORMAL_TERRITORY_CATALOG_COMPOSED=NO
TERRITORIAL_CONTROL_OWNER=VNextSpatialWorld
TERRITORIAL_CONTROL_LEDGER_PRODUCTION_COMPOSED=NO
POPULATION_PRODUCTION_COMPOSED=NO
FORMAL_SCHEMA=formal_world_simulation_v10
FABRICATED_GEOGRAPHY=0
```

The next gate is production source acquisition/admission. This contract intentionally does not construct TerritoryUnitCatalog, Population, or TerritorialControlLedger.
