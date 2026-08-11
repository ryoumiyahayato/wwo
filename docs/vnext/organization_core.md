# VNext organization core

`VNextOrganizationCore` establishes the structural grammar of organizations. It
answers three questions without executing any specialist system:

1. Which organization exists, where is its primary place, and where does it sit
   in the organization hierarchy?
2. Which people are members, and which people hold which appointments?
3. Which capabilities are granted by each position to its current appointee?

The implementation is isolated at
`scripts/vnext/organization/organization_core.gd`. It does not extend the
legacy `OrganizationService`, does not write `CharacterData`, and is not
connected to `world_runtime`, Economy, Politics, Military, Spatial, or
Population.

## Ownership boundary

The core owns:

- organization stable identity (`organization:*`), organization kind, optional
  primary place reference, and active/inactive structural status;
- the single parent reference and derived subordinate queries;
- organization membership;
- organization-owned position definitions and local appointment records;
- declared capability IDs and position-to-capability grants;
- deterministic authorization queries.

The core deliberately does not own company money or profit, wages, general
resources, military strength, political support, generic influence, generic
power, or any generic resources scalar. It also does not own employment. An
ordinary employee can therefore remain outside membership, while an
appointment can explicitly use non-membership semantics when the model permits
it.

Capability is authorization data, not an operation. For example,
`military.issue_strategic_order` may be granted to a `war_minister` position.
`has_capability(person_id, organization_id, capability_id)` only answers whether
the current appointment authorizes the capability; it never calls Military or
any other system and never checks whether the resulting action can succeed.

## IDs and hierarchy

The core reuses the existing `VNextStableId` kinds:

- `organization:<local-id>` for organizations;
- `person:<local-id>` for people;
- `place:<local-id>` for optional primary places.

Position and appointment IDs are local strings scoped by their owning
organization. They are deterministic caller-supplied IDs such as
`war_minister` and `war_minister_alice`; there is no shared `position:` or
`appointment:` stable-ID kind. A position ID can be reused in two organizations
because the organization scope is part of its identity.

Every organization has at most one parent. Registration and parent updates
reject a missing parent, self-parenting, and any cycle. Subordinate queries
iterate sorted organization IDs, so their result does not depend on Dictionary
insertion order.

## Membership, positions, and appointments

Membership is an independent fact. `add_member` does not create a position or
appointment, and `create_appointment` does not add membership when
`requires_membership` is `false`.

The first version enforces one current appointment per person within one
organization and enforces each position's `slot_count`. An appointment that
requires membership prevents that member from being removed until the
appointment is explicitly removed. A non-membership appointment does not block
membership removal. These rules prevent contradictory current state without
inventing employment or career behavior.

An inactive organization retains its validated structure for persistence and
possible later reactivation, but it grants no authorization and rejects
membership, position, capability, appointment, and hierarchy mutations. The
status is structural; it is not a time source and does not automatically alter
subordinate organizations.

## Persistence contract

`snapshot()` returns `vnext_organization_core_v1`:

```text
{
  "schema_id": "vnext_organization_core_v1",
  "organizations": [
    {
      "organization_id": "organization:...",
      "organization_kind": "...",
      "primary_place_id": "place:..." or "",
      "parent_organization_id": "organization:..." or "",
      "active": true,
      "member_ids": ["person:..."],
      "capability_ids": ["domain.capability"],
      "positions": [
        {
          "position_id": "...",
          "title": "...",
          "slot_count": 1,
          "capability_ids": ["domain.capability"]
        }
      ],
      "appointments": [
        {
          "appointment_id": "...",
          "person_id": "person:...",
          "position_id": "...",
          "requires_membership": true
        }
      ]
    }
  ]
}
```

Organizations, positions, appointments, members, and capability arrays are
canonicalized in sorted order when written. Restore accepts valid transport
ordering but rejects malformed collections, extra fields, duplicate IDs,
invalid stable references, unknown positions or capabilities, over-capacity
appointments, conflicting membership requirements, missing parents, and
hierarchy cycles. When a reference catalog is supplied, person and place IDs
must also exist in that catalog; the catalog is validation context and is not
organization state.

Restore decodes into a candidate graph, validates every invariant, and only
then replaces live state. A rejected restore leaves the previous snapshot
unchanged. The core has no second clock, timestamps, or implicit time-based
activation semantics.

## Reuse and future integration

The legacy service remains a reference for vacancy, membership, position
occupancy, and permission concepts only. Its direct writes to legacy character
fields and its organization resources/influence fields are intentionally not
copied. Future Economy, Labor, Politics, Military, Spatial, or UI work must
consume read-only organization queries or explicit integration commands at its
own boundary; the organization core must not execute those systems.
