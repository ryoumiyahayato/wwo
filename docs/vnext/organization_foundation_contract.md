# Organization Foundation Contract

`VNextOrganizationCore` is a structural domain foundation. It is not wired to
Formal gameplay and it does not execute Economy, Military, or Politics commands.

## Identity and taxonomy

Every first-class organization uses an `organization:*` stable ID. Company,
corporation, enterprise, union, party, faction, government body, guild,
association, and military institution are distinguished by the controlled
`organization_kind` catalog. They do not introduce parallel stable-ID kinds.

`formation:*` remains a Military identity. State and polity identities are not
organizations.

The kind catalog exposes a sorted ID list and a deterministic SHA-256
fingerprint. Unknown or malformed kinds are rejected during registration and
snapshot restore.

## External references

Person and Place identities remain externally owned. OrganizationCore receives
a detached reference catalog containing only known stable IDs. Any non-empty
Person or Place reference fails closed when that catalog is absent, the ID is
unknown, or its stable-ID kind is wrong. The reference catalog is not serialized
inside an Organization snapshot.

Reverse membership and appointment queries are derived from OrganizationCore's
authoritative records on every call. Their results are deterministically sorted
and deeply detached; no second membership or appointment truth is stored.

## Capability vocabulary

Capabilities are authorization facts, not gameplay commands. The controlled
registry currently contains only `organization.manage_appointments`, the one
authorization needed by this foundation. Unknown capability declarations or
grants fail closed. The registry exposes deterministic ordering and fingerprint.

## Ownership boundary

OrganizationCore owns:

- organization identity, kind, active state, parent, and primary Place reference;
- membership;
- positions and appointments;
- capability declarations and position grants.

OrganizationCore does not own:

- cash, profit, inventory, production, employment, or wages;
- political influence, support, or legitimacy;
- formations, equipment, supply, or combat state;
- generic national resources;
- Person, Place, State, or Polity identity.

## Snapshot contract

The persisted field shape remains `vnext_organization_core_v1`; no migration is
needed because this hardening changes validation rather than serialized fields.
Restore is candidate-first. Invalid kinds, references, capabilities, hierarchy,
or snapshot structure reject the entire candidate and leave live state unchanged.
