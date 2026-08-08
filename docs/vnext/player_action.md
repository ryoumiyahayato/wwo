# vNext player authority and first action

## Boundary

This change introduces the first vNext player-owned runtime state and the first formal player action. It does not introduce a second session, command bus, UI flow, legacy service dependency, or another time owner.

`VNextWorldRuntime` remains the only owner of cumulative simulation time. `VNextPlayerState` owns only the authoritative player identity for this boundary.

## Player state

`VNextPlayerState` has one business identity field:

- `player_id`

A valid player ID must be a canonical `person:<local_id>` accepted by `VNextStableId`. The player layer does not copy or relax stable-ID validation.

The snapshot schema is:

```text
vnext_player_state_v1
```

Its payload contains only:

```json
{
  "schema_id": "vnext_player_state_v1",
  "player_id": "person:<local_id>"
}
```

`restore()` validates the complete candidate before assigning `player_id`, so an invalid schema, missing field, non-string ID, malformed stable ID, or non-person stable ID leaves the existing player state unchanged. The schema is JSON round-trippable.

This first version intentionally does not own country selection, location, money, employment, health, relationships, politics, AI state, current action, pending action, or action history. Those facts require separate owners and later contracts.

## Action result

`VNextActionResult` is a per-call result DTO only. It contains:

- `success`
- `code`
- `message`
- `elapsed_minutes`

It is not persistent world state and it is not a shared mutable context.

## WAIT

`VNextPlayerActionService` supports one action:

```text
wait(runtime, player, minutes)
```

Validation is fail-closed:

- `runtime` must be non-null;
- `player` must be non-null;
- `player.player_id` must be a valid canonical person ID;
- `minutes` must be greater than zero.

Validation failures return an explicit result and do not call the runtime mutation API. A successful WAIT calls exactly the existing public time mutation boundary:

```text
VNextWorldRuntime.advance_minutes(minutes)
```

No player or action service stores another cumulative time field. `elapsed_minutes` exists only in the one-operation result DTO and does not become a clock.

## Legacy migration boundary

The migration inventory classifies legacy `ActionService` as `REUSE_WITH_ADAPTER`: useful action lifecycle ideas may be reused later, but its mutable catch-all context and direct cross-owner effects are not vNext contracts.

Legacy `GameSessionService` is `REFERENCE_ONLY`. vNext player/action code must not read or write its static player, action, clock, map, autosave, or session members. `VNextPlayerState` is the new explicit player authority for vNext rather than a wrapper around the old process-global session.

## Validation

`tests/vnext/player_action_test.gd` covers canonical person identity, non-person rejection, transactional player restore, JSON round trip, successful WAIT advancement, zero/negative WAIT rejection, invalid/null player rejection, null runtime rejection, unchanged runtime after validation failures, and guards against a second player-time/session owner.

The unified vNext runner discovers this test automatically under `tests/vnext/**/*_test.gd`.
