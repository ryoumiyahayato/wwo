# vNext core gameplay loop integration

This slice composes the four previously isolated vNext owners without entering the formal product.

## Ownership model

| Owner | Mutable facts | Runtime access |
|---|---|---|
| VNextPlayerState | one authoritative person ID | runtime.player() |
| VNextPersonalWallet | owner person ID and minor-unit balance | runtime.wallet() |
| VNextLocationState | owner person ID and actual place ID | runtime.location() |
| VNextEventKnowledgeState | event records, known IDs and read IDs | runtime.event_knowledge() |
| VNextWorldRuntime | one cumulative total_minutes and the four owner references | runtime.total_minutes() |

The runtime stores no duplicate person ID. A valid composition requires all four owner IDs to equal runtime.player_id().

## Service responsibilities

VNextWorldRuntime is the composition root and the sole owner of cumulative runtime time.

VNextTravelService.execute(runtime, location, quote) owns only the already-validated runtime time advance and location movement. It does not access, validate or debit a wallet.

VNextCoreLoopService.execute_paid_travel(runtime, quote) is the narrow cross-owner application service for paid travel. It validates the composed owners and quote, performs all known preflight checks, debits the runtime wallet once when needed and delegates the actual time/location step to VNextTravelService. It does not use a manager, context, registry, locator, event bus or generic transaction abstraction.


## Runtime v2 snapshot

The exact top-level schema is vnext_world_runtime_v2:

    {
      "schema_id": "vnext_world_runtime_v2",
      "total_minutes": 0,
      "player": { "schema_id": "vnext_player_state_v1", "player_id": "person:..." },
      "wallet": { "schema_id": "vnext_personal_wallet_v1", "owner_person_id": "person:...", "balance_minor": 0 },
      "location": { "schema_id": "vnext_location_state_v1", "player_id": "person:...", "place_id": "place:..." },
      "event_knowledge": { "schema_id": "vnext_event_knowledge_v1", "player_id": "person:...", "event_records": [], "known_event_ids": [], "read_event_ids": [] }
    }

Restore is strict and transactional. It validates all six top-level fields and all nested owner snapshots on fresh candidates before committing anything. An empty runtime shell installs fresh validated owners; an initialized runtime restores validated candidate snapshots into the existing player, wallet, location and event-knowledge objects, preserving their object identities. A rejected restore leaves both state and references unchanged. The runtime accepts only the v2 schema; it does not guess or migrate a v1 runtime payload.

## Core commands

WAIT exposes the typed entry point wait(runtime, player, minutes) and the typed helper wait_current_player(runtime, minutes). Both forms advance only runtime.total_minutes(); there is no Variant overload or player sentinel.

Paid travel is composed only by VNextCoreLoopService.execute_paid_travel(runtime, quote). It validates runtime/quote/identity/origin, calls runtime.can_advance_minutes() and checks wallet.can_debit() before debiting once when cost is positive, then delegates time and movement to VNextTravelService.execute(). Known failures leave time, wallet, location and event knowledge unchanged without depending on debit-then-rollback.

runtime.record_event(event_id) uses runtime.total_minutes() as the authoritative occurrence minute. Event reveal and read remain explicit owner transitions.

## Validation

The end-to-end behavior is covered by tests/vnext/core_loop_integration_test.gd. The independent owner and boundary tests remain in tests/vnext, and tools/run_vnext_validation.py discovers all files ending in _test.gd.
