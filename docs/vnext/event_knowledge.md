# vNext authoritative event and player knowledge boundary

## Scope

This slice introduces the first vNext-owned boundary that separates objective event truth from what the controlled player knows and has read.

The implementation is intentionally isolated. It does not connect to the formal UI, `VNextWorldRuntime`, persistence, player state, personal wallet, travel, `CommunicationService`, or the retained `KnowledgeService`.

## Migration evidence

`docs/vnext/reuse_migration_inventory.md` classifies both retained services as `REUSE_WITH_ADAPTER`:

- `KnowledgeService` retains useful person-scoped provenance, confidence, contradiction, expiry and idempotency behavior, but the inventory explicitly requires objective event truth to remain a separate owner.
- `CommunicationService` retains delayed delivery and explicit read semantics, but its current read path directly mutates retained knowledge and may also cross spatial, relationship and economic owners.

The retained `tests/v2_3/v2_3_knowledge_test.gd` and `tests/v2_3/v2_3_communication_test.gd` are therefore behavioral references only. This vNext slice does not reuse their mutable dictionaries or wire either service into the new authority.

## Owner

`VNextEventKnowledgeState` owns exactly four pieces of runtime state:

- one `player_id`;
- authoritative event records indexed internally by event ID;
- known event IDs;
- read event IDs.

The constructor requires a valid `person:<local_id>` stable ID. Event IDs must be valid `event:<local_id>` values accepted by `VNextStableId`.

An event record contains only:

- `event_id`;
- `occurred_at_minutes`.

No political effects, news text, AI payload, relationship effects, organization effects, communication payloads or UI state are stored here.

## State transitions

`record_event(event_id, occurred_at_minutes)` adds objective truth only when the event ID is valid, the occurrence minute is non-negative and the ID has not already been recorded. Duplicate IDs fail without overwriting the original record.

`reveal_event(event_id)` changes player knowledge only for an event that already exists in authoritative truth. It never synthesizes an event.

`mark_event_read(event_id)` succeeds only for an already-known event. Reading therefore cannot bypass the reveal boundary.

`knows_event(event_id)` and `has_read_event(event_id)` are read-only queries over those two player visibility sets.

Repeated reveal/read calls are idempotent after the required preconditions have been satisfied.

## Snapshot contract

Schema ID: `vnext_event_knowledge_v1`.

The snapshot contains exactly:

- `schema_id`;
- `player_id`;
- `event_records`;
- `known_event_ids`;
- `read_event_ids`.

`event_records` is emitted as an array sorted by `event_id`. Known and read ID arrays are also sorted. This makes the snapshot deterministic even when equivalent states were constructed through different insertion orders.

The internal `Dictionary` used as the explicit event-ID map is a domain index only. It is not a generic context, service locator or arbitrary business-state bag.

## Restore contract

`restore()` validates a complete candidate before mutating live state. It rejects:

- wrong or incomplete schema;
- non-person `player_id` values;
- non-event or duplicate event IDs;
- negative, non-finite or fractional occurrence minutes;
- malformed event records;
- known IDs that do not exist in authoritative event truth;
- duplicate known/read IDs;
- read IDs that are not already in the candidate known set.

JSON parsing converts integer-valued JSON numbers to floating-point values in Godot. Restore accepts finite, non-negative, integer-valued floats and normalizes them back to runtime integers. Fractional values are rejected.

All validation is transactional: a rejected restore leaves the prior state unchanged.

## Validation coverage

`tests/vnext/event_knowledge_test.gd` covers:

- shared event stable-ID validation;
- duplicate event rejection;
- reveal and read transitions;
- failure to reveal an unrecorded event;
- failure to read an unknown event;
- failed-operation state isolation;
- deterministic snapshot and deterministic JSON ordering;
- snapshot/restore round trip;
- JSON round trip;
- transactional restore rejection, including player-domain and fractional-time failures.

## Deferred integration

This task deliberately stops before composition. Later slices may connect communication, event presentation, persistence and broader knowledge semantics through explicit adapters or command/query ports. Those integrations must not make UI state or retained service dictionaries the vNext authority.
