# vNext Observation Contract Foundation

This stage defines the read boundary shared by future Player, AI, UI, and
external observers. It adds only transport-safe DTOs, a query port, an injected
visibility resolver, a small invalidation DTO, and a deterministic synthetic
provider. It does not connect any formal UI, AI service, `KnowledgeService`,
`EventKnowledgeState`, or historical provenance owner.

## Request

`VNextObservationRequest` keeps the observer and the subjects as separate
fields:

- `observer_actor_id` is a required `person:<local-id>` stable ID;
- `scope` identifies the query scope;
- `subject_ids` is a non-empty sorted list of stable IDs;
- `expected_world_revision` is either `-1` for no expectation or a concrete
  non-negative revision;
- `requested_fields` and `requested_capabilities` are sorted, duplicate-free
  token lists. An empty requested-field list means all fields offered by the
  provider, never unrestricted truth.

Malformed IDs, duplicate values, invalid tokens, and invalid revision values
are rejected before a provider query runs.

## Response and observed field

`VNextObservationResponse` is an envelope with:

- `schema_id`, deterministic `observation_id`, and `status`;
- `world_revision`, `observer_actor_id`, and logical `observed_at`;
- `stale` and `revision_mismatch` status markers;
- filtered `records`.

Each `VNextObservationRecord` identifies one subject and one captured world
revision. Every `VNextObservedField` carries `perceived_value`, normalized
`confidence` (`0..1`), independent `acquired_at` and `observed_state_at`
logical times, sorted provenance references, freshness, and a detachable
extension dictionary. Provenance is reference-only; this contract does not own
historical evidence.

An observation may carry review metadata such as `EVIDENCE_LINKED` or
`BOUNDED_ESTIMATE` as detached source metadata, but neither status means
`VERIFIED`. Observation code never creates or promotes a verification status;
source registration, evidence cataloging, and provenance admission remain owned
by the historical provenance boundary.

All DTO getters and serialized dictionaries return deep detached copies.
Returned data cannot mutate provider truth or another consumer's result.
Fields that fail visibility are omitted before DTO creation, so a hidden field
does not leak through field IDs, metadata, or perceived values.

## Visibility and truth

Authorization remains outside the contract behind
`VNextObservationVisibilityResolver`. A missing resolver fails closed. The
provider first validates the observer, then requires the resolver to approve
each subject/field. Sensitive fields also require their capability to be
explicitly present in the request. The synthetic QA observer can read hidden
truth only with `observation.truth.read`; a request string cannot mint that
capability. There is no long-lived `truth_view` boolean.

## Revision consistency

The provider captures one `world_revision`, one `observed_at`, and a deep copy
of its source truth before materializing records. Every returned record must
match the envelope revision. If a capture hook advances the live revision, the
response retains the captured revision and marks itself stale. An
`expected_world_revision` mismatch returns `revision_mismatch` with no newer
records. `VNextObservationInvalidation` contains only the new revision, sorted
changed scopes, and a cause ID; it never carries replacement truth.

## Ownership and non-goals

The query port exposes no runtime snapshot, owner object, mutable authoritative
dictionary, economy/polity/organization/military owner, or save API. The
synthetic provider exists only to prove the contract and detached behavior.
Formal World, Player, AI, UI, Economy, Market, Territory, Military, Politics,
Organization, Knowledge, media propagation, rumor systems, fog of war, and save
schema integration remain future work.
