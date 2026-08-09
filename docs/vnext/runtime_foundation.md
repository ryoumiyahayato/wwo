# vNext runtime composition

VNextWorldRuntime v2 is an isolated composition root for the first vNext core gameplay loop. It is not a formal product entry point and does not replace the existing formal product.

## Ownership

The runtime owns exactly one cumulative simulation-time value, _total_minutes, plus references to four explicit domain owners:

- VNextPlayerState owns the authoritative person:* player identity;
- VNextPersonalWallet owns that person's non-negative integer balance;
- VNextLocationState owns that person's actual place:* location;
- VNextEventKnowledgeState owns objective event records and the player's known/read event sets.

The runtime does not store a second player ID. player_id() delegates to the player owner. A valid composition requires the wallet owner, location owner and event-knowledge owner to equal that one player ID.

VNextWorldRuntime.create(player_id, place_id) and initialize(player_id, place_id) construct all four owners together. An empty new() instance is a restore shell, not a valid gameplay runtime. Runtime actions fail closed until the composition is valid.

## One authoritative clock

total_minutes() is the only vNext cumulative-time query. advance_minutes() is the only vNext cumulative-time mutation boundary.

The accepted range is 0 .. 9,007,199,254,740,991 (2^53 - 1). Advancement rejects non-positive values and any operation that would exceed that JSON-safe upper bound. WAIT and paid travel both use this same runtime boundary; neither service stores a second clock.

record_event(event_id) records occurrence at the current total_minutes(). Callers cannot supply a separate occurrence time through the composed runtime command.

## v2 snapshot and restore

The exact runtime snapshot schema is vnext_world_runtime_v2:

    {
      "schema_id": "vnext_world_runtime_v2",
      "total_minutes": 0,
      "player": {},
      "wallet": {},
      "location": {},
      "event_knowledge": {}
    }

The four nested payloads use their existing owner schemas (vnext_player_state_v1, vnext_personal_wallet_v1, vnext_location_state_v1, and vnext_event_knowledge_v1). Restore requires all six top-level fields, validates every nested owner on fresh candidate objects, verifies person identity consistency, and commits the complete composition only after every check succeeds.

Numeric JSON transport values may arrive as finite integral floats. They are normalized back to runtime int values only inside the JSON-safe range. Fractional, negative, non-finite, out-of-range, malformed, incomplete and cross-owner snapshots are rejected transactionally.

A vnext_world_runtime_v1 payload is not migrated or guessed into v2. It is rejected and leaves the existing composition unchanged.

## Explicit exclusions

This foundation does not connect to FormalWorldSimulation, the current product UI, the formal save path, social systems, communication, organizations, careers, politics, law, AI or route planning. It does not introduce a universal mutable Context or a second runtime root.
