# Continuous vehicle crew

This is a fixed-rule game module, with no real-world tactical model. It works with arbitrary vehicle IDs and seat layouts; this batch adds no new armored car or vehicle model.

## Included

- `crew_registry.gd`: identity, occupancy, transaction checks and versioned JSON-compatible state.
- `exit_clearance.gd`: real Godot ground-ray and capsule-obstruction query.
- `vehicle_crew_host.gd`: current game integration and compact crew dropdown plus individual/all exit/enter controls.
- `test_crew.gd`: 29 checks including 3D clearance.
- `test_host.gd`: actual infantry host integration, same actor continuity and blocked exits.

## Main integration

Create host and `setup(main)` once after HUD creation. Call `bind_player()` only after the new scene's hero, player_combat and ai_host are ready. The current player tank is bound through exact Combat.crew Dictionary references. Heavy uses commander/gunner/driver/loader/radio; light commander/gunner/driver. `on_stage_reset()` discards scene registry only; the owning stage must clear its AI actors on scene teardown. Do not call bind_player during ordinary transfers.

Use `can_fire()` for cannon and MG gating; `reload_multiplier()` gives exactly 1.5 when the heavy loader is absent or incapacitated. `onboard_indices()` supplies the actual in-vehicle people to vehicle-hit/explosion processing, including dead occupants but excluding people outside. Use actor hits for dismounted people. `can_drive()` is provided but the current demo has no free-driving gameplay, so this is a capability contract, not a claim of implemented driving.

The UI appears in skirmish outside the garage. Exits try six points, each grounded and capsule-checked against the live physics world. Entry requires the same living person, their correct empty seat and at most six metres from the vehicle. All-crew operations are per-person transactions: blocked/dead people remain where they are; successful transfers are counted. No teleport from a distant patrol position is allowed.

## Identity and actor lifetime

`person_id` is permanent and distinct from vehicle and seat identity. The host initially assigns scene-stable IDs `player_vehicle:person:N`; migrations retain that ID even in another vehicle. The registry holds the original person Dictionary. Never replace it with a fresh person on entry/exit. `person_ref(id)` returns this live record; `person(id)` returns an inspection copy. Existing `hp`, `alive`, `parts`, scalar `ammo`, state and extra fields persist.

The infantry host owns exactly one actor for every ID, created once with `register_bound_crew`. Transfers use `set_crew_embarked`, hiding and suspending that same actor and removing its collision while seated. No new actor or healing/reset happens on transfers. The infantry adapter reads updated onboard combat injuries before reactivating its actor.

## Portable API

- `bind_vehicle(id, roles:Array, crew:Array, config:Dictionary)` binds existing person references atomically after identity checks. Seats are indexed string IDs.
- `register_vehicle(id, seats:Dictionary, config)` handles arbitrary vehicle layouts.
- `register_person(person)` registers an existing record in world space.
- `embark(person_id, vehicle_id, seat_id, boarding_allowed:Callable, state_patch={})` validates all preconditions before mutation. Callback arguments are person, vehicle, seat IDs.
- `disembark(person_id, position:Vector3, safe_exit:Callable)` validates before mutation. Callback arguments are person ID, vehicle ID, position.
- `transferred(person_id, location)` is emitted only after success.
- `functional_status()` yields can_drive/can_fire/can_reload/reload_multiplier. Dead or incapacitated personnel do not operate roles. Both disabled arms prevent gunner/loader work; both disabled legs prevent driver work. Loader policy can instead explicitly be `block`; callers must then honor can_reload.

Validation callbacks must be synchronous and read-only; they must not reenter the registry or change scene occupancy. The host calls scene actor transition immediately after successful validation/commit, on the same main thread.

## WWO save/load boundary

`host.snapshot()` captures actual world actor positions and canonical records. `registry.serialize()` captures logical location and all person fields. Both return schema_version=1 with people/vehicles maps; Vector3 is represented by coordinate arrays. Preserve IDs and do not allocate replacements on transfer.

`restore(snapshot)` accepts only an empty registry, validates all seat/person cross-links before changing anything, and never spawns actors. Rejecting live-registry restore prevents stale bound dictionaries or ghost actors. A future WWO scene loader must restore into an empty registry, then bind one actor per saved ID to `person_ref`, apply world position and embarked status. Repeated loads must reconcile/clear their previous scene actors explicitly. This module is reusable code and tested serialization, not an already integrated WWO save menu.

## Run

Set XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME to writable directories, then:

    godot --headless --path PROJECT --script res://modules/vehicle_crew/test_crew.gd
    godot --headless --path PROJECT --script res://modules/vehicle_crew/test_host.gd

## Walking return orders (GUI reboarding fix)

The host now distinguishes immediate boarding from a requested walk back. `request_embark(person_id, batch_id=-1)` first attempts the same strict six-metre registry transaction. If a living dismounted actor is farther away, it returns `{ok:false,pending:true,reason:"returning"}` and adds a host-owned `crew_return_order` metadata request to that same actor. The minimal infantry actor bridge moves through its existing collision-aware `move_and_slide` routine, suspending autonomous pursuit/fire for this order. The registry changes occupancy only after the actor physically reaches within 5.9m of the vehicle (six-metre validation remains authoritative). There is no return teleport, new actor or health/ammo reset.

An actor with a construction metadata lock, a brain build order, disabled physics, zero movement speed or both legs disabled cannot be assigned return movement. The construction host's candidate selector also excludes returning actors. A newly assigned construction order, additional injury, death, replaced actor/vehicle, stage reset, or non-progress for 12 seconds cancels the return without modifying a construction order or reviving anyone. Cancellation on injury permits the surviving wounded person to receive a fresh explicit order later. The prototype uses its existing short obstacle detours, not a general navigation/pathfinding system; blocked routes are reported rather than teleported through.

Batch UI results count every reason separately. Immediate successes, pending walks, dead personnel, already seated personnel and construction-busy personnel remain visible together. When a walk finishes or is cancelled, that batch's pending count and summary update without discarding its earlier failure reasons. The selector marks travelling crew `回车中`.

Additional regression tests:

    godot --headless --path PROJECT --script res://modules/vehicle_crew/test_return.gd
    godot --headless --path PROJECT --script res://modules/vehicle_crew/test_return_construction.gd

The first runs a wounded actor through more than 200 actual physics frames back from twelve metres, verifies bounded per-frame motion, unchanged identity/HP/ammo/injury and all cancellation paths. The second uses the real game scene and construction host to prove that a returning crew member is not commandeered and a rejected construction request charges no resources.

## Same-frame batch exit correction

The real default rocket-car battle revealed a physics synchronization gap: two successful disembarks in one UI callback could both choose the first exit because the physics space had not yet registered the first actor's reactivated collider. Overlapping CharacterBody capsules treated one another as moving floors and rapidly pushed each other hundreds of metres upward. This caused invisible crew and apparently blocked return orders; it was not a pathfinding failure.

Exit checks now also compare the live positions of all already-dismounted actors synchronously (0.8m horizontal spacing with overlapping vertical extents), so each committed transfer immediately reserves its occupied space before the next physics tick. The final spawn point starts 0.12m above the sampled surface, and the exact actor BodyCollision shape is checked at that final transform in addition to the conservative generic clearance query. Physics settles the actor naturally; no post-exit position correction or return teleport is used. Existing damage, visibility, patrol and return behavior remains unchanged.

`diagnose_live_return.gd` reproduces the actual default rocket-car battle, waits 25 seconds, exits all living crew in one callback, waits 30 seconds and requests all crew to reboard, recording ground/position/collision/identity state. `test_batch_exit.gd` covers two, three and five simultaneous exits on 8/15-degree slopes with 30 seconds of live physics and injury/ammo continuity through reboarding.
