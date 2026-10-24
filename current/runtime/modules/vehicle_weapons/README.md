# Armored-car weapons

These are fixed fictional game presets. They contain no real-world ballistics or historical performance model.

## Projectile contract

`short_rocket.gd` extends `Node3D` and represents exactly one projectile. Create a new instance for every round. The host owns three-round scheduling, the 0.18-second gap, seven-second reload, crew checks, damage and impact effects.

```gdscript
const ShortRocket = preload("res://modules/vehicle_weapons/short_rocket.gd")
var exclusions: Array[RID] = owner_collision_rids
var rocket = ShortRocket.new()
rocket.impacted.connect(handle_rocket_impact)
scene.add_child(rocket)
rocket.setup(muzzle.global_transform, exclusions, "player")
```

Setup also works before adding the node to the scene. Call it once per projectile. Its launch origin is the actual provided Muzzle global position; its fixed direction is normalized minus-Z from the same transform. The projectile is top-level, so later parent movement, turret rotation and camera movement cannot move or steer it. The host's RID exclusion array is copied and made read-only at setup, so later host mutations do not change a rocket already in flight. Include all owner/friendly RIDs that should be excluded.

Every physics step casts a real segment ray over that frame's flight distance, with collision mask `1 | 8 | 128`, body collisions enabled and inside hits enabled. It moves 18 fictional world units/second. The first physical obstacle stops it and emits exactly one `impacted(event: Dictionary)` signal, then queues itself for deletion. The event contains:

- `position`, `normal`, `collider`: actual first physics collision
- `origin`, `direction`: preserved launch geometry

The source identity is available as `rocket.source_id`. No target ID is accepted, and no automatic damage or hit is produced for a designated target. Terrain and walls block the projectile. A miss expires after at most four simulated seconds or 72 world units and emits no impact. A small warm tip and 0.36-unit trailing mesh provide the flight visual; there is no billboard or launch-to-target beam.

The impact handler should pass the real collider and contact location to the existing Combat/infantry bridge and use the existing covered-infantry / sealed-armor HE rules. The projectile does not infer penetration, see through obstacles or damage an off-axis selected target.

## Fixed presets

`weapon_presets.gd` exposes `ARMOR_CAR_PROFILE`, `MG_AMMO`, `WEAPON_PRESETS` and named constants. `armor_profile()` and `weapon_preset(kind)` return deep copies so callers can change local state safely. Weapon keys match the manifest: `mg`, `short_rocket`, `cannon`.

- Hull: front 40, left/right 25, rear 20, top/bottom 15
- Turret: front 35, left/right 25, rear 20, top/bottom 15
- External wheels: 12, using existing Combat keys `track_left` and `track_right`
- MG: penetration 5 / 15 / 5 for tracer / AP / incendiary, interval 0.2 seconds
- Cannon: AP 90, reload 2.5 seconds
- Short rocket: three rounds, 0.18-second gap, reload seven seconds, HE 100 fictional grams / radius 10, resolved by the existing Combat rules
- Turret rates: MG 75, cannon 50, short rocket 30 degrees/second

Weapon dictionaries use `reload_seconds` and `turret_degrees_per_second`; MG uses `interval`, while short rocket uses `rounds`, `gap`, `he_grams`, and `he_radius`.

## Tests

```sh
modules/vehicle_weapons/run_tests.sh
```

The suite runs actual Godot physics and checks both setup orders, exact authored muzzle origin/axis, constant speed, parent/camera independence, thin-wall interception before a farther target, terrain, collision layers, immutable owner exclusions, inside-obstacle collisions, single-impact lifetime and misses expiring at four seconds / 72 units. The current report is `test_results.log` beside the module.
