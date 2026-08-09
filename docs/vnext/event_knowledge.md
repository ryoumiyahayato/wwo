# vNext authoritative event and player knowledge boundary

VNextEventKnowledgeState separates objective event truth from what the controlled player knows and has read. It owns one internal person owner, event occurrence records, known event IDs and read event IDs.

The owner remains responsible only for event truth and visibility state. It does not own communication payloads, news text, political effects, relationship effects, organization effects or UI state.

## Runtime integration

VNextWorldRuntime v2 composes this owner with the player, wallet and location owners. runtime.record_event(event_id) supplies the occurrence minute from runtime.total_minutes(); callers cannot create a second occurrence clock or provide a guessed time. runtime.reveal_event() and runtime.mark_event_read() delegate the visibility transitions to the same owner.

The runtime requires the event-knowledge person ID to equal the authoritative player person ID. A complete v2 restore validates this relationship before committing any owner.

## Owner contract

The nested schema remains vnext_event_knowledge_v1. Occurrence minutes are runtime integers in the JSON-safe range 0 .. 9,007,199,254,740,991. Snapshot and restore remain deterministic, JSON-round-trippable and transactional. Known IDs must refer to recorded events, and read IDs must refer to known events.

## Explicit exclusions

This integration does not connect CommunicationService, retained KnowledgeService, formal UI, social, organization, career, politics, law or AI systems. No v1 runtime migration or legacy event dictionary is introduced.

See tests/vnext/event_knowledge_test.gd for the independent owner contract and tests/vnext/core_loop_integration_test.gd for runtime-derived occurrence time.
