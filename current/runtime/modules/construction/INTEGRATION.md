# Portable construction module (fictional game mechanics)

This folder is independent of main.gd/combat.gd and WWO. Copy the folder into a Godot 4 project; preserve `res://modules/construction/` paths or rewrite the single view preload. No autoload, UI singleton, network, assets, real engineering specifications, or paid dependencies.

## Files
- `construction_system.gd`: RefCounted pure-data command/state machine. Arrays of numeric world coordinates, string IDs, integer timing, serializable snapshots, monotonic sequenced events.
- `construction_view.gd`: optional procedural Node3D presentation and primitive collisions. `sync(state)` updates partially-built appearance, progress beam/tool, finished cover, weapon props, barricade, mine development markers and anchors.
- `excavation_patch.gd`: optional isolated 12x12 training platform with a genuinely lowered floor and four surrounding solid slabs. Not a painted black circle. Host terrain integration can replace it.
- `demo.tscn`: standalone visual catalog/test host, launch with `godot --path . res://modules/construction/demo.tscn`.
- `tests/construction/test_construction.gd`: headless independent executable tests.

## Fixed preset IDs
`foxhole`, `breastwork`, `mg`, `mortar`, `at`, `tower`, `barricade`, `mine_vehicle`, `mine_person`, `mine_any`.

Times 2.5–9 seconds, costs 1–4 abstract tokens, initial budget 24. These are fictional demonstration balance, not construction or weapons guidance. The user does not configure them.

## Minimal integration
```gdscript
const Construction = preload("res://modules/construction/construction_system.gd")
const ConstructionView = preload("res://modules/construction/construction_view.gd")
var construction = Construction.new()
var construction_views = {}

# Host verifies distance to infantry, ground support, obstacle clearance, slope,
# site bounds and real excavation permission BEFORE submitting this command.
var event = construction.command({
 "op":"place", "worker_id":"infantry_1", "preset":"mg",
 "position":[4.0,0.0,8.0], "yaw":0.0,
 "site_valid":true, "slope_degrees":0.0
})
if event.kind == "placed":
 var id = event.id
 var view = ConstructionView.new()
 world.add_child(view)
 construction_views[id] = view
 construction.command({"op":"start", "id":id})

# Each frame; advance(integer_ms) preferred for deterministic fixed-step simulation.
construction.tick(delta)
for id in construction.structures:
 construction_views[id].sync(construction.structures[id])

# Finished -> occupied -> use_requested -> finished.
construction.command({"op":"enter", "id":id})
construction.command({"op":"use", "id":id})
construction.command({"op":"exit", "id":id})
```

`command` returns the event and queues it. Consume with `drain_events()` OR connect `event_emitted`; do not process the same event twice through both. Never mutate returned live `structures` from adapters. `serialize()` is a deep copy; `restore()` validates schema and worker references and resets the transient event queue. Save/restore the host terrain state alongside it. Snapshot import is for trusted own-game saves, not a security boundary for hostile multiplayer data.

Placement -> building -> finished -> occupied -> finished. Mines finish as armed -> consumed, once only. One worker means one build/occupancy at a time; entering incomplete structures, simultaneous placements, unknown worker, overlap, slope >12, invalid site/coordinates and insufficient tokens are refused with machine-readable reason. Pending/in-progress cancellation fully refunds the demo cost and requests terrain restoration. Reset clears all and emits `restore_terrain:true`; host removes views, restores terrain and puts infantry back at safe ground. Reset deliberately does not rewind event sequence.

## Physical excavation contract
For foxhole, use `excavation_reserved:true` when the host has approved a physically carveable surface. On completion the state becomes `awaiting_excavation`, with an `excavation_requested` event. Perform the real mesh/collision carve, then send `{op:"confirm_excavation",id:id,success:true}` to transition to finished. Failure leaves it non-enterable and cancellable. Use `excavation_ready:true` only when the actual opening already exists. An opaque circle is not acceptable. Either:
1. Reserve a standalone `ExcavationPatch` at its world center before place. During build call `patch.set_progress(elapsed_ms / 4000.0)`. Its center floor descends to -0.9 with updated collisions; the center has no ground lid. Place outside the main terrain footprint so a second uncut collider cannot seal the hole. At cancel/reset call `reset_patch()`.
2. Use the terrain-damage worker adapter on a supported height surface, passing its actual approved dig location. Apply real deformation before allowing enter. Match the use anchor to actual floor height. The construction module never edits somebody else's terrain mesh.

If the model refuses placement after reserving terrain, release the reservation. Persist terrain changes separately. On load, rehydrate terrain before exposing occupied structures. The optional isolated patch should be labeled “可挖训练区”, not offered as arbitrary GLB excavation.

## Enter/use and combat hooks
`view.use_position`, `view.muzzle`, `view.observation` are Marker3D references recreated on visual rebuild; read current properties, don't cache an old marker. Their global transforms are valid after parenting. On enter, save the infantry's outside transform and move to use_position; on exit return to a validated safe spot outside collision. Towers raise use position and observation origin. No climb simulation is claimed.

`use_requested.weapon` is `mg_direct`, `mortar_arc`, `at_direct`, or empty for cover/observation. Host invokes existing combat rules from the muzzle transform, applies cooldown/ammunition/actor-state restrictions and renders the fictional mortar arc. Module does not duplicate damage/penetration models. View props are stylized game representations.

Firing does not require a visible target: `use_requested.requires_line_of_sight=false`, while identification requires LOS. Enter aligns once only when the target is visible; subsequent Use preserves manual aim and permits blind fire along the actual visible barrel. Damage disclosure still respects visibility.

Tower observation MUST go through the same distance/weather/terrain/structure/smoke LOS filtering as any observer. Never directly set every enemy visible. Sight line queries should use layer 1 (environment/cover) and ignore the observer's own collider as appropriate. Sandbags and tower sides are actual StaticBody3D shapes.

Barricade has a solid broad layer-1 collision envelope in addition to visible beams. Both infantry and vehicle controllers MUST use collisions (`CharacterBody3D.move_and_slide` or equivalent sweep); directly assigning coordinates bypasses all physical barriers.

Mines expose an Area3D named GameTrigger (mask layers 16|32, no collision layer). Host identifies entered actors and calls:
```gdscript
construction.command({"op":"trigger", "id":id,
 "actor_kind":"vehicle", "target_id":"vehicle_7"})
```
Use `person`/`vehicle` actor categories. These are trusted host-authoritative proximity commands; the pure model does not infer distance. Configure actual actor bodies to layers 16 (infantry test actor), 32 (vehicle test actor), or implement equivalent host distance checking. `mine_vehicle` filters persons; `mine_person` filters vehicles; `mine_any` accepts both. A successful `mine_triggered` carries position, target_id, game_damage=4 and terrain_preset=`crater`. Apply your existing fictional explosion damage once and call terrain.apply_command(position,"crater") once. Sync the consumed state to remove trigger/prop. Game damage value is an abstract demo value only. Main's visibility system controls mine/enemy presentation; bright mine tops here are deliberate development markers.

## Tests
```
XDG_DATA_HOME=/tmp/construction-godot/data XDG_CONFIG_HOME=/tmp/construction-godot/config XDG_CACHE_HOME=/tmp/construction-godot/cache godot --headless --path . --script tests/construction/test_construction.gd
```
The tests cover deterministic JSON continuation, refusal/overlap/slope, one worker, cancel/refund, all ten finished mesh builds, raised observation, mine filters/one-shot consumption, invalid snapshot rejection, and physics rays proving a lower center surface and unchanged surroundings. They do not certify final mobile controls, Android exports, main-game weapons, visibility, or the separate terrain deformation module.

## Prototype host adapter and scope guards
`construction_host.gd` extends Node. Main adds it and calls `setup(main)`, then `on_stage_reset()` before replacing the stage. It supplies compact touchscreen-friendly preset/site/build/enter/use/exit controls, single-worker relocation, progressive visual work, completion-time real excavation, raised observation, weapon dispatch, and actual CharacterBody3D test actors traversing mine or barricade sites. All mutating UI handlers reject garage/vehicle modes. Tests are in `tests/construction/test_host.gd`; these run against the actual main scene.

Movement to a selected build point is immediate demo relocation, not a pathfinding or locomotion system. Main infantry and vehicles themselves remain main's responsibility for collision-aware movement. The module's test actors use collision-aware motion and terrain height sampling. Test actor layers 16/32 deliberately avoid main's crew-internal layer 2. A mine test applies one abstract damage event to its test actor; it does not claim that the main player vehicle drives around or that production actor health integration is complete.

Adapter dependencies: `stage`, `hero`, `target`, `camera`, `hud`, `font`, `garage`, `unit`, `scoped`, `weapon_override`, `terrain_damage`; `terrain_height`, `damage_terrain`, `toggle_scope`, `target_is_visible`, `update_visibility`, `fire_mg`, `fire_cannon`, `fire_mortar`, `refresh_hud`, and string `message`. Core module has none of these dependencies. `view.aim_at(target)` rotates actual visible weapon group with muzzle; mortar preserves the tube's upward axis and only changes azimuth.

### GUI verification fixes
Occupied structures hide the own infantry mesh to avoid first-person camera occlusion; exit/reset restores it. Enter collapses the engineering panel and leaves a compact Use/Exit toolbar. Mine testers preflight four approach directions to avoid the builder and targets, then move with ordinary collision. Their whole footprint follows terrain-only height rays; prop tops cannot act as ground and barricades remain solid. Exhausting the 24 demonstration tokens produces a Chinese reset instruction. Host regression includes the GUI-reported mine site (0.8, -2), scope visibility, compact toolbar, and barricade collider identity.

### Engineering-only placement preview
Selecting ground displays a translucent terrain-following footprint outline sized from the fixed preset. Green/red uses the same site/clearance/slope/overlap/budget checks as Build. Hover updates are throttled; touch selection retains the outline until build or leaving engineering. Starting construction, entering a structure, closing engineering, changing mode, and reset hide it. This is not a weapon aiming reticle. Mines/barricades disable Enter/Use and finish with a testing prompt.

### Foxhole view clearance
Foxholes retain a genuinely lowered infantry position and a real rifle muzzle. Observation is 0.65 above the original surface; front/back berms are 0.16 high and side berms remain 0.4. At placement, a visible identified target determines the low opening's initial orientation; otherwise the fixed default remains. On entering unmounted cover/tower, the actual infantry weapon initially aims only at a visible target. Manual aim remains thereafter; low sideward shots are still blocked by the solid side berm. Regression checks both open forward rays and blocked side rays without raising the rifle muzzle artificially.

## High-level AI construction orders in skirmish
Skirmish exposes “命令友军施工” while the player remains in a tank. Select the same validated footprint and issue an order to an available living, non-embarked friendly actor, preferring `friendly_rifle` and falling back to a dismounted crew member with no existing order. The core reserves the fixed cost once in placement state; the AI walks with its normal CharacterBody collision to an outside work position. The host listens directly to `ai_host.event_emitted` and accepts the matching `build_requested` only after actual arrival, then rechecks placement and starts progress. No main `apply_ai_build_request` bridge is required; do not add a second event processor.

The host sets actor metadata `construction_order=true` during the task. The infantry adapter should suppress autonomous observation/combat while this flag is set, retaining actual navigation and incoming damage. During the short building phase the host pauses that actor's physics callback at its arrived position; the actor stays physically present and damageable. Completion/cancel restores the previous processing flag. Any HP loss, death, embarking, cancellation or stage reset releases the task; cancellable reservations refund once. No player hero transform, camera, or mounted weapon is commandeered by AI construction.

This closes AI build orders only. Autonomous AI occupation, tower observation, and emplacement firing are not implemented by this adapter yet. The skirmish UI hides direct Enter/Use/Exit and synthetic test-actor controls. The labeled engineering practice mode retains the prior complete isolated construction tests. Dead/missing builders are refused; blocked travel remains pending and cancellable rather than falsely completing remotely. `tests/construction/test_ai_construction.gd` uses real friendly actor physics and isolates enemy shooting solely for deterministic arrival testing, then separately checks injury/death cancellation and exact reservation accounting.

## Actual AI and dismounted-crew mine triggers
In skirmish, armed personnel/universal mines check actual living, non-embarked `ai_host.actors` positions each physics tick. Stable actor-ID order resolves simultaneous entry; the first valid entry consumes the mine immediately. Vehicle mines ignore people. This does not require synthetic test actors.

A `mine_triggered.target_id` selects either the explicit `construction_test_actor` path or the actual AI person through `ai_host.apply_actor_damage(id, 4, source)`. The latter mutates the canonical person already shared by AI, vehicle crew registry and tank combat, preserving earlier injuries and identity. It never reduces the synthetic tester's HP. Terrain crater publication occurs once per consumed mine; invisible targets receive only generic explosion feedback. No free-driving player-vehicle mine detection is claimed: vehicle mines remain covered by the existing physically moving engineering test vehicle.

`tests/construction/test_ai_mines.gd` validates real actor walking, personnel trigger, exactly one damage/crater, tester isolation, actual crew disembark/walking through a vehicle mine without triggering, universal trigger and shared crew health/history. Enemy shooting is disabled only in these deterministic fixtures; the actual actor collision movement is retained.

### Post-combat ground-probe regression
A GUI-equivalent regression now runs 20 seconds of the real default battle, maps the reported letterboxed screenshot point to the game viewport, and issues the same construction order. It verifies actual departure, arrival/progress/completion and unchanged player-tank transform. A dead-only worker pool refuses without charging; surviving dismounted crew can take over while preserving canonical identity. The assigned worker alone is ignored in initial footprint clearance because they must physically leave for an outside work position before building begins; all other actor/prop collisions remain checked.

The infantry actor's obstacle pre-probe now classifies walkable ground by contact normal and `floor_max_angle`, including a second slightly raised diagnostic sweep so a zero-distance ground contact cannot mask a wall. These probes never move the actor; `move_and_slide` remains authoritative. This fix applies globally, not only to construction. `test_ai_walkable_floor.gd` checks actual gentle-slope movement and retained wall/steep-face blocking. Combat outcomes may change as actors can now traverse previously misclassified ground.
