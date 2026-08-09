# vNext authoritative event and player knowledge boundary

## Scope

This slice introduces the first vNext-owned boundary that separates objective event truth from what the controlled player knows and has read.

The implementation is intentionally isolated. It does not connect to the formal UI, `VNextWorldRuntime`, persistence, player state, personal wallet, travel, `CommunicationService`, or the retained `KnowledgeService`.

## Migration evidence

`docs/vnext/reuse_migration_inventory.md` classifies both retained services as `REUSE_WITH_ADAPTER`:

- `KnowledgeService` retains useful person-scoped provenance, confidence, contradiction, expiry and idempotency behavior, but the inventory explicitly requires objective event truth to remain a separate owner.
- `CommunicationService` retains delayed delivery and explicit read semantics, but its current read path directly mutates retained knowledge and may also cross spatial, relationship and economic owners.

The retained `tests/v2_3/v2_3_knowledge_test.gd` and `tests/v2_3/v2_3_communication_test.gd` are therefore behavioral references only. This vNext slice does not reuse their mutable dictionaries or wire either service into the new authority.

## Owner and initialization

`VNextEventKnowledgeState` owns exactly four pieces of runtime state:

- one internal `player_id`;
- authoritative event records indexed internally by event ID;
- known event IDs;
- read event IDs.

A live authority must be created with `VNextEventKnowledgeState.create(player_id)`. The factory accepts only a valid `person:<local_id>` stable ID and returns no authority for an invalid owner. `player_id` remains an internal field and has no direct business setter.

`VNextEventKnowledgeState.new()` intentionally creates an ownerless empty shell. This exists only so a snapshot can be validated and restored transactionally. Until a valid person owner has been established by `create()` or a successful `restore()`, event recording, reveal, read and visibility queries fail closed and cannot mutate state. Runtime correctness therefore does not depend on `assert()` behavior in debug or release builds.

Event IDs must be valid `event:<local_id>` values accepted by `VNextStableId`.

An event record contains only:

- `event_id`;
- `occurred_at_minutes`.

No political effects, news text, AI payload, relationship effects, organization effects, communication payloads or UI state are stored here.

## Occurrence-time numeric contract

`occurred_at_minutes` remains a runtime `int`. This domain defines one explicit JSON-safe range rather than introducing a shared numeric framework:

- minimum: `0`;
- maximum: `9_007_199_254_740_991` (`2^53 - 1`).

`record_event()` rejects values outside that range. `restore()` applies the same range after JSON numeric normalization. This guarantees that every accepted occurrence minute can survive the supported JSON serialization boundary without losing integer precision.

## State transitions

`record_event(event_id, occurred_at_minutes)` adds objective truth only when the authority has a valid person owner, the event ID is valid, the occurrence minute is inside the JSON-safe non-negative integer range and the ID has not already been recorded. Duplicate IDs fail without overwriting the original record.

`reveal_event(event_id)` changes player knowledge only for a valid authority and an event that already exists in authoritative truth. It never synthesizes an event.

`mark_event_read(event_id)` succeeds only for a valid authority and an already-known event. Reading therefore cannot bypass the reveal boundary.

`knows_event(event_id)` and `has_read_event(event_id)` are read-only queries over those two player visibility sets and return `false` for an ownerless shell.

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

An ownerless restore shell may produce a snapshot with an empty `player_id`, but that shell is not a valid business authority and its snapshot cannot be restored as a valid authority until a valid person owner is present in the candidate snapshot.

The internal `Dictionary` used as the explicit event-ID map is a domain index only. It is not a generic context, service locator or arbitrary business-state bag.

## Restore contract

`restore()` validates a complete candidate before mutating live state. It rejects:

- wrong or incomplete schema;
- non-person `player_id` values;
- non-event or duplicate event IDs;
- negative, non-finite, fractional or greater-than-`9_007_199_254_740_991` occurrence minutes;
- malformed event records;
- known IDs that do not exist in authoritative event truth;
- duplicate known/read IDs;
- read IDs that are not already in the candidate known set.

JSON parsing converts integer-valued JSON numbers to floating-point values in Godot. Restore accepts finite, non-negative, integer-valued floats only when they are within the explicit JSON-safe range, then normalizes them back to runtime integers. Fractional and out-of-range values are rejected.

All validation is transactional: a rejected restore leaves the prior state unchanged. A successful restore may initialize an ownerless empty shell because the complete candidate has already established a valid person owner and valid domain state.

## Validation coverage

`tests/vnext/event_knowledge_test.gd` covers:

- valid factory creation and invalid-owner rejection;
- ownerless-shell fail-closed behavior with unchanged state;
- shared event stable-ID validation;
- duplicate event rejection;
- reveal and read transitions;
- failure to reveal an unrecorded event;
- failure to read an unknown event;
- failed-operation state isolation;
- maximum JSON-safe occurrence-minute round trip;
- record and restore rejection at maximum plus one, including unchanged prior state;
- deterministic snapshot and deterministic JSON ordering;
- snapshot/restore round trip through an empty restore shell;
- JSON round trip;
- transactional restore rejection, including player-domain and fractional-time failures.

## Deferred integration

This task deliberately stops before composition. Later slices may connect communication, event presentation, persistence and broader knowledge semantics through explicit adapters or command/query ports. Those integrations must not make UI state or retained service dictionaries the vNext authority.
