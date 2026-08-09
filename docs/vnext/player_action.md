# vNext player authority and first action

## Boundary

This change introduces the first vNext player-owned runtime state and the first formal player action. It does not introduce a second session, command bus, UI flow, legacy service dependency, or another time owner.

`VNextWorldRuntime` remains the only owner of cumulative simulation time. `VNextPlayerState` owns only the authoritative player identity for this boundary.

## Player state

`VNextPlayerState` has one business identity fact. It is stored internally as:

- `_player_id`

Normal callers may only query it through:

```text
player_id()
```

There is no public writable `player_id` member.

A valid player ID must be a canonical `person:<local_id>` accepted by `VNextStableId`. The player layer does not copy or relax stable-ID validation.

Construction is fail-closed. `VNextPlayerState.new("person:<local_id>")` stores the supplied value only when it is a valid person stable ID. A non-person stable ID or malformed ID is not stored; the object remains an invalid empty shell with `player_id() == ""`. `VNextPlayerState.new()` intentionally produces the same empty shell so persistence code can restore a validated snapshot into it later.

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

`restore()` validates the complete candidate before assigning `_player_id`, so an invalid schema, missing field, non-string ID, malformed stable ID, or non-person stable ID leaves the existing player state unchanged. A valid restore commits the candidate ID only after all validation passes. The schema is JSON round-trippable.

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
- `player.player_id()` must expose a non-empty authoritative identity;
- `player.is_valid()` must confirm that identity is a valid canonical person ID;
- `minutes` must be greater than zero.

The action service reads player identity only through the public player API. It does not access `_player_id` directly.

Validation failures return an explicit result and do not call the runtime mutation API. A successful WAIT calls exactly the existing public time mutation boundary:

```text
VNextWorldRuntime.advance_minutes(minutes)
```

No player or action service stores another cumulative time field. `elapsed_minutes` exists only in the one-operation result DTO and does not become a clock.

## Legacy migration boundary

The migration inventory classifies legacy `ActionService` as `REUSE_WITH_ADAPTER`: useful action lifecycle ideas may be reused later, but its mutable catch-all context and direct cross-owner effects are not vNext contracts.

Legacy `GameSessionService` is `REFERENCE_ONLY`. vNext player/action code must not read or write its static player, action, clock, map, autosave, or session members. `VNextPlayerState` is the new explicit player authority for vNext rather than a wrapper around the old process-global session.

## Validation

`tests/vnext/player_action_test.gd` covers valid person construction, fail-closed non-person and malformed construction, empty restore shells, transactional player restore, JSON round trip, successful WAIT advancement, zero/negative WAIT rejection, invalid/null player rejection, null runtime rejection, unchanged runtime after failures, public getter use, absence of a public writable `player_id` member, and guards against a second player-time/session owner.

The unified vNext runner discovers this test automatically under `tests/vnext/**/*_test.gd`.
