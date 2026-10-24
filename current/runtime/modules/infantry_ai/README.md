# Reusable fictional infantry AI (Godot 4.6)

## Shipped boundary
- `infantry_brain.gd`: deterministic state machine, no scene/global access. Idle, patrol, target reaction, move to a host-approved generic cover point, fire, reload, search last-seen location, wounded, disabled; optional walk-to-approved-build-site request.
- `infantry_actor.gd`: CharacterBody3D gravity/floor/collision movement and fixed left/right local wall avoidance. Real raycast detection and shot authority; no runtime teleport/pathfinding or omniscient hidden target pursuit. Actor collision layer 128; obstacle/shot mask 1|8|16|32|128 excludes internal crew layer 2 and heightfield-only 64.
- `infantry_host.gd`: host-scoped actor/person registry and observer-local weather/smoke bridge. Events carry stable IDs. No autoload or WWO modifications.
- `skirmish_host.gd`: bounded friendly rifle + enemy rifle + enemy AT demo. AT uses verified reused Panzerfaust asset; if missing, an explicit pending-equipment label appears. Fictional fixed penetration values rifle 5 / AT 110; target choice is stable ID order, not weak-point optimization. AT interval 4.5s and one-round magazine; rifle 1.1s and four rounds.

## Main integration
Create a Node with `skirmish_host.gd`, call `setup(main)`, then `spawn(main.stage)` after terrain and hero/target exist; spawn automatically registers `main.hero` as actor `player`, team `blue`. Friendly AI team blue, enemy red. `on_stage_reset()` before removing stage actors. Each player collider must resolve ancestor metadata actor_id=player.

Host expects main.stage, main.hero, main.target, main.camera, main.weather_index, main.smoke_root, main.combat.smoke_remaining and main.terrain_height(x,z). Main owns separate player armor/crew state and implements `apply_ai_hit(event)` and optional `spawn_ai_shot(origin,impact,weapon)`. Actual shot event fields: actor_id, team_id, intended_actor_id, hit_actor_id, origin, direction, position, weapon, penetration, damage, hit (actual collider/position/normal dictionary), seq. Main must use the real hit and module intersection; AI does not name a hit module or damage the static practice target.

Player hit route: `handle_player_projectile(hit,kind,ammo,part)->String`; blast route `apply_player_blast(origin)`. `is_identified(actor_id)` applies player-camera weather/smoke/terrain ray before selection/labels; this is independent of the AI observer's perception. These methods do not promise navigation around arbitrary maps.

## Continuous crew identity
`person_id == actor_id`. Bind exact canonical Dictionary by `actor.bind_person_state(person_ref)`; values hp/ammo/alive/ai_state update in place. `actor.set_embarked(true)` disables physics, visibility and collision without deleting actor or resetting HP/ammo. Exit uses same node via `set_embarked(false)`; external seat registry owns validated exit position and seat transaction. Body injury dictionary key is `parts`, matching shared Combat. `persons[id]` and crew registry must retain the same reference. No crew clone on entry or exit.

## Construction and portability
`actor.order_build(site,preset,approved)` rejects unapproved/dead orders, walks physically, then emits one build_requested event. Main `apply_ai_build_request(event)` optionally validates and starts existing construction. This does not independently excavate terrain or build instantly; integration is optional.

Brain `snapshot`/`restore` preserve identity, HP/ammo, target memory and timers. Actor/host snapshots expose position and event sequence. These are current-state snapshots, not a complete saved game (patrol/cover configuration and pending build orders need host restoration). Portable WWO integration should implement the three host callbacks (`infantry_candidates`, `infantry_visibility`, `infantry_apply_hit`); event dictionary `hit` has runtime Objects and should be projected to IDs/coordinates for network serialization.

## Verification
Run with writable HOME/XDG directories:
- `godot --headless --path . --script modules/infantry_ai/test_infantry_ai.gd`
- `godot --headless --path . --script modules/infantry_ai/test_infantry_physics.gd`

Tests exercise deterministic state, hidden observation filtering, lost-LOS last-known memory, cooldown, wounded/dead stops, authorized build arrival, stable collider ID, snapshot, crew state continuity, real wall occlusion/collision and autonomous ray hit routing. Whole-scene visual QA and mobile performance remain separate acceptance steps. Visual AT attachment is a prototype socket; source weapon is real reused asset with Z long axis and muzzle toward -Z.

## Damage consistency
Player bullets and AI infantry hits use shared `Combat.hit_person` on the canonical dictionary (head/torso disable; limbs damage 3). Player blast uses shared `Combat.explode` at 100g and within 10m, with real obstruction ray. No numerical personnel HP is emitted in gameplay status strings. `register_bound_crew`/`set_crew_embarked` bridge the seat registry and retain exact actor/person references. No extra personnel health model is introduced by the adapter.

## Actual weapon geometry correction
AI now binds the reused Rifle's authored Muzzle to a visible aim pivot; AT binds a marker at the verified Panzerfaust -Z endpoint (z=-0.55). It turns the actor and the visible weapon before emitting a ray from the actual muzzle along -global_basis.z. Eye rays are perception only. A blocked barrel segment cancels the shot rather than shooting through scenery. Missing muzzle fails closed.

Six abstract body regions are resolved from actual collision position in actor-local coordinates. Player and AI hits use that region; target text no longer dictates AI body-part damage. If the actor is unidentifiable, the player only gets generic shot feedback. The demo refreshes model plus team-marker visibility every 0.15s from player-camera LOS/weather/smoke.

The demo starts with a six-second patrol grace period and a fixed three-shot aim-offset pattern. These offsets visibly rotate the weapon and retain real-ray authority. This is bounded prototype tuning, not a claim of fun or finished balance. test_infantry_physics now uses actual reused rifle and Panzerfaust GLBs and checks muzzle origin/axis and all six regions; 16 physics/geometry checks pass.

## Actual-scene verification and visual status
`diagnose_main_ai.gd` loads the real main.tscn, enters default skirmish, runs 1,200 physics frames, records observer rays and actual shot events, and asserts enemy AT hits the player, friendly AI hits enemies, and the player's front module integrity falls. Fixed scenario pairings apply only to already-visible candidates; no hidden actor is acquired. A prior genuine integration issue was actor-ID sorting directing all enemies at the friendly rifleman, leaving the player's armor untouched; fixed visible-target preferences and a non-obstructed preset AT spawn resolve it. Current diagnostic shows three actual AT hits and front integrity 100 to 55 over 20 simulated seconds.

The marker uses main.font and displays team plus injured/disabled words, never HP. Damaged visuals lean/crouch and disabled visuals slump without gore. Disabled body collider becomes a real low capsule (height .56, centerY .28) rather than retaining an invisible standing blocker. Regression rays pass overhead and still hit the low body. Construction-order metadata suppresses autonomous observations while the worker travels, and accepting the build order clears old pursuit memory; the construction host remains authoritative for cancellation, resources and completion.
