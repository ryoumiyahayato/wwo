# vNext player authority and WAIT action

VNextPlayerState owns one authoritative person:* player identity. It has no location, money, event, action-history or time fields.

VNextWorldRuntime v2 composes that player owner with the wallet, location and event-knowledge owners. The runtime verifies that all four person references remain consistent before allowing gameplay commands.

## WAIT

VNextPlayerActionService supports two typed calls:

    wait(runtime, player, minutes)
    wait_current_player(runtime, minutes)

wait(runtime, player, minutes) validates the initialized runtime and matching person identity. wait_current_player(runtime, minutes) obtains runtime.player() and calls the typed entry point. Both forms call only VNextWorldRuntime.advance_minutes(minutes); no Variant overload or -1 sentinel is used.

WAIT has no independent clock. Its per-call elapsed_minutes result is a result DTO, not persistent time state. A successful WAIT and a successful paid travel therefore advance the same runtime total_minutes value exactly once.

Invalid runtime, player, identity mismatch and non-positive minutes fail without mutating the runtime.

## Persistence and migration

The player owner continues to use vnext_player_state_v1 as its nested owner schema. The composed runtime uses vnext_world_runtime_v2; a v1 runtime snapshot is rejected rather than guessed into the new composition.

This work remains isolated from GameSessionService, formal UI, social, communication, organization, career, politics, law and AI systems.
