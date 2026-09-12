# Current World Population Authority Contract

`VNextPopulationAuthority` is the sole mutable Population owner for Runtime
Current World. Its authoritative key is `territory_unit_id`; its first schema
stores only an exact integer `total_population` for each initialized territory.
Territories may remain uninitialized, and duplicate initialization fails.

The authority borrows identity from a sealed `VNextTerritoryUnitCatalog`. It
does not copy territory identity and binds every candidate and snapshot to the
catalog version and fingerprint. Country/polity population is only a future
derived aggregation over a caller-supplied controlled-territory set. Controller
changes have no Population side effect.

Transfers use prepare/validate/adopt. Preparation is detached and cannot mutate
live state. Adoption checks the live revision and fingerprint, exact integer
conservation, and the Territory catalog binding, then replaces the complete
candidate state once and advances the revision exactly once. Births, deaths,
external migration, demographic simulation, and cross-domain transactions are
not part of this schema.

Snapshots use `vnext_population_authority_v1`. Restore parses the complete
snapshot into a detached candidate, validates all records and the canonical
state fingerprint, and only then adopts it. Failed restore leaves state,
fingerprint, and revision unchanged.

Legacy `VNextMacroPopulation` remains an uncomposed place-keyed simulation
component, and Formal population input remains immutable historical economic
evidence. Neither is a mutable Runtime Current World Population owner.
