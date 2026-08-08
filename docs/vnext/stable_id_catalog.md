# vNext stable ID and catalog contract

This document defines the identity boundary for the first static vNext catalogs. It does not migrate product data and it does not implement any gameplay system.

## Stable identity

`VNextStableId` defines a persistent identity string with the canonical form:

```text
<kind>:<local_id>
```

The only supported kinds are:

- `person`
- `place`
- `organization`
- `event`
- `economy`

`local_id` is non-empty and may contain only lowercase `a-z`, digits `0-9`, underscore `_`, and hyphen `-`.

Examples:

```text
person:alice_example
place:country_fra
organization:parliament_france
event:election_france_1900
economy:country_fra
```

Stable ID is persistent identity. It is not a UI selection, display name, array position, transient object address, or a per-system alias. The same entity must not gain a second writable identity maintained in parallel.

The contract does not normalize or repair malformed IDs. Uppercase text, spaces, empty local IDs, multiple colons, unsupported kinds, and other symbols are rejected. `compose()` returns an empty string for invalid inputs; parse helpers return an empty string for an invalid canonical ID.

## Static catalog boundary

`VNextCatalogContract` does not own a global writable registry. Callers pass a batch of static records to validation or lookup.

Each record is represented by a `Dictionary` and must contain at least an `id` field. At this boundary, `Dictionary` is only a representation for static catalog records; it is not a universal runtime state bag.

A valid catalog has these properties:

- every `id` is a valid canonical stable ID;
- no canonical ID appears more than once;
- lookup is by exact canonical ID;
- input IDs are not rewritten;
- `display_name` is never substituted for `id`;
- record order does not determine identity.

`record_by_id()` first validates the requested canonical ID and the supplied catalog. It returns the matching record when one exists. Invalid catalogs, invalid query IDs, and unknown IDs return `null`; they do not synthesize a default entity.

Catalog records should be treated as static data by consumers. Runtime ownership and mutable business state belong in later, explicit system boundaries rather than in this catalog contract.

## Migration boundary

This change does not decide whether any legacy identifier is reusable. Reuse, adaptation, or replacement of old IDs must be decided by the separate migration inventory from evidence in the existing systems and data.

No real person, place, organization, event, economy, save, or other product data is migrated by this contract.

This contract also does not define the complete future field schema for any entity kind. Fields beyond the required `id` remain intentionally unspecified until their owning systems are designed.

## Explicit non-goals

This work does not add an `IdManager`, global ID registry, UUID service, autoload, singleton, player system, travel system, economy gameplay, social system, politics system, event gameplay, or AI system.
