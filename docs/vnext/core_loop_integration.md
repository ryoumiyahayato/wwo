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

Restore is strict and transactional. It validates all six top-level fields and all nested owner snapshots on fresh candidates before committing anything. The runtime accepts only the v2 schema; it does not guess or migrate a v1 runtime payload.

## Core commands

WAIT accepts either an explicit matching player owner or the runtime's current player owner. Both forms advance only runtime.total_minutes().

Paid travel validates the actual origin and wallet balance, then commits wallet debit, runtime time and location arrival as one transaction. A failure restores the complete v2 snapshot, including the prior wallet balance.

runtime.record_event(event_id) uses runtime.total_minutes() as the authoritative occurrence minute. Event reveal and read remain explicit owner transitions.

## Validation

The end-to-end behavior is covered by tests/vnext/core_loop_integration_test.gd. The independent owner and boundary tests remain in tests/vnext, and tools/run_vnext_validation.py discovers all files ending in _test.gd.
