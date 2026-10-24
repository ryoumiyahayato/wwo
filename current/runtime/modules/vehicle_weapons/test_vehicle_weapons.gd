extends SceneTree

const Rocket = preload("res://modules/vehicle_weapons/short_rocket.gd")
const Presets = preload("res://modules/vehicle_weapons/weapon_presets.gd")
var failures: int = 0
var checks: int = 0
var world: Node3D
var impacts: Array[Dictionary] = []

func _init() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func new_world() -> void:
	impacts.clear()
	world = Node3D.new()
	root.add_child(world)

func clear_world() -> void:
	world.queue_free()
	await ticks(2)

func body(position: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.position = position
	node.collision_layer = layer
	node.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	node.add_child(collision)
	world.add_child(node)
	return node

func launch(muzzle_transform: Transform3D, exclusions: Array[RID] = [], before_tree: bool = false):
	var rocket = Rocket.new()
	rocket.impacted.connect(func(event: Dictionary) -> void: impacts.append(event))
	if before_tree:
		rocket.setup(muzzle_transform, exclusions, "fixture")
		world.add_child(rocket)
	else:
		world.add_child(rocket)
		rocket.setup(muzzle_transform, exclusions, "fixture")
	return rocket

func test_presets() -> void:
	var armor: Dictionary = Presets.armor_profile()
	check(armor.front == 40 and armor.left == 25 and armor.right == 25 and armor.rear == 20 and armor.top == 15 and armor.bottom == 15, "fixed car hull armor 40/25/20/15/15")
	check(armor.turret_front == 35 and armor.turret_left == 25 and armor.turret_right == 25 and armor.turret_rear == 20 and armor.turret_top == 15 and armor.turret_bottom == 15, "fixed car turret armor 35/25/20/15/15")
	check(armor.track_left == 12 and armor.track_right == 12, "external wheel groups use compatible mobility keys at 12")
	check(Presets.MG_AMMO.tracer.penetration == 5 and Presets.MG_AMMO.ap.penetration == 15 and Presets.MG_AMMO.incendiary.penetration == 5 and Presets.MG_INTERVAL == 0.2, "MG 5/15/5 with 0.2-second interval")
	check(Presets.CANNON_AP_PENETRATION == 90 and Presets.CANNON_RELOAD == 2.5 and Presets.weapon_preset("cannon").reload_seconds == 2.5, "cannon AP 90 with 2.5-second reload")
	check(Presets.ROCKET_ROUNDS == 3 and Presets.ROCKET_SALVO_GAP == 0.18 and Presets.ROCKET_RELOAD == 7.0, "host salvo preset 3 rounds, 0.18 gap, 7-second reload")
	check(Presets.ROCKET_HE_GRAMS == 100.0 and Presets.ROCKET_HE_RADIUS == 10.0, "rocket HE 100g and radius 10 retain existing Combat rule")
	check(Presets.weapon_preset("mg").turret_degrees_per_second == 75.0 and Presets.weapon_preset("cannon").turret_degrees_per_second == 50.0 and Presets.weapon_preset("short_rocket").turret_degrees_per_second == 30.0, "fixed turret rates MG 75, cannon 50, rocket 30 degrees per second")
	armor.front = 999
	var config: Dictionary = Presets.weapon_preset("mg")
	config.ammo.ap.penetration = 999
	check(Presets.armor_profile().front == 40 and Presets.weapon_preset("mg").ammo.ap.penetration == 15, "preset accessors isolate mutations with deep copies")
	check(Presets.weapon_preset("short_rocket").rounds == 3 and Presets.weapon_preset("unknown").is_empty(), "short_rocket manifest key resolves and unknown preset stays empty")

func test_muzzle_and_camera() -> void:
	new_world()
	var mount := Node3D.new()
	world.add_child(mount)
	mount.position = Vector3(3.25, 4.5, 8.75)
	mount.rotation = Vector3(-0.14, 0.63, 0.04)
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.4, 1.2, -1.6)
	mount.add_child(muzzle)
	var expected: Transform3D = muzzle.global_transform
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(-15, 20, 10)
	camera.look_at(Vector3(20, 0, 20))
	camera.current = true
	var rocket = Rocket.new()
	rocket.setup(expected, [], "muzzle_test")
	rocket.impacted.connect(func(event: Dictionary) -> void: impacts.append(event))
	mount.add_child(rocket)
	check(rocket.global_transform.is_equal_approx(expected), "setup-before-tree launches at exact authored Muzzle global transform")
	check(rocket.get_launch_origin().is_equal_approx(expected.origin), "launch origin remains the real Muzzle position")
	check(rocket.get_launch_direction().is_equal_approx(-expected.basis.z.normalized()), "launch axis is normalized Muzzle minus-Z")
	check(rocket.source_id == "muzzle_test", "source identity is retained without target identity")
	mount.position += Vector3(80, 20, -30)
	mount.rotation.y += 1.3
	camera.position = Vector3(50, 8, -30)
	camera.look_at(Vector3(3, 4, 8))
	await ticks(12)
	var travel: Vector3 = rocket.global_position - expected.origin
	var direction: Vector3 = -expected.basis.z.normalized()
	check(travel.cross(direction).length() < 0.0001 and travel.dot(direction) > 0.0, "parent and camera movement cannot steer projectile")
	check(absf(travel.length() - rocket.get_age_seconds() * 18.0) < 0.0001, "actual physics flight advances at 18 fictional units per second")
	check(impacts.is_empty(), "moving the camera does not fabricate a hit")
	check(is_equal_approx(rocket.get_node("WarmTip").mesh.radius, 0.055) and is_equal_approx(rocket.get_node("ShortTrail").mesh.height, 0.36), "visual uses compact tip and short trail")
	rocket.setup(Transform3D(Basis.IDENTITY, Vector3(99, 99, 99)))
	check(rocket.get_launch_origin().is_equal_approx(expected.origin), "a launched instance cannot be retargeted by setup")
	await clear_world()

func test_wall_first() -> void:
	new_world()
	var wall := body(Vector3(0, 1, -1.137), Vector3(5, 3, 0.005), 8)
	var target := body(Vector3(0, 1, -4), Vector3(1, 2, 1), 128)
	target.set_meta("actor_id", "designated_target")
	await ticks(2)
	var origin := Vector3(0, 1, 0)
	var rocket = launch(Transform3D(Basis.IDENTITY, origin))
	check(rocket.global_position.is_equal_approx(origin), "setup-after-tree starts at exact Muzzle origin")
	await ticks(20)
	check(not is_instance_valid(rocket), "thin first obstacle stops and frees the rocket")
	check(impacts.size() == 1, "impact emits exactly once")
	if impacts.size() == 1:
		var hit: Dictionary = impacts[0]
		check(hit.collider == wall and hit.collider != target, "segment ray hits wall before the farther target")
		check(absf(hit.position.z - (-1.1345)) < 0.002, "continuous segment ray cannot tunnel through a 0.005-unit wall")
		check(hit.normal.is_equal_approx(Vector3.BACK), "impact normal comes from actual physics collider")
		check(hit.origin.is_equal_approx(origin) and hit.direction.is_equal_approx(Vector3.FORWARD), "impact carries preserved launch origin and direction")
		check(hit.has_all(["position", "normal", "collider", "origin", "direction"]), "impact dictionary contains the host contract")
	await ticks(12)
	check(impacts.size() == 1, "no second impact or auto-hit beyond the wall")
	await clear_world()

func test_terrain() -> void:
	new_world()
	var terrain := body(Vector3(0, -0.25, 0), Vector3(10, 0.5, 10), 8)
	await ticks(2)
	var down_basis := Basis(Vector3.RIGHT, -PI / 2.0)
	var rocket = launch(Transform3D(down_basis, Vector3(0, 2, 0)), [], true)
	await ticks(15)
	check(not is_instance_valid(rocket) and impacts.size() == 1, "terrain collision stops downward projectile")
	if impacts.size() == 1:
		check(impacts[0].collider == terrain and absf(impacts[0].position.y) < 0.001 and impacts[0].normal.is_equal_approx(Vector3.UP), "terrain contact uses real surface position and normal")
	await clear_world()

func test_owner_exclusions_and_masks() -> void:
	new_world()
	var owner := body(Vector3(0, 1, 0), Vector3(2, 2, 2), 1)
	body(Vector3(0, 1, -1.4), Vector3(2, 2, 0.2), 2)
	var wall := body(Vector3(0, 1, -3), Vector3(2, 2, 0.2), 1)
	await ticks(2)
	var exclusions: Array[RID] = [owner.get_rid()]
	var rocket = launch(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), exclusions)
	exclusions.clear()
	exclusions.append(wall.get_rid())
	await ticks(20)
	check(not is_instance_valid(rocket) and impacts.size() == 1, "frozen owner exclusions survive host array mutation")
	if impacts.size() == 1:
		check(impacts[0].collider == wall, "owner RID excluded, layer 2 ignored, layer 1 obstacle hit")
	await clear_world()
	new_world()
	var actor := body(Vector3(0, 1, -2), Vector3(1, 2, 1), 128)
	await ticks(2)
	launch(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	await ticks(12)
	check(impacts.size() == 1 and impacts[0].collider == actor, "layer 128 actor collision is included")
	await clear_world()
	new_world()
	var overlap := body(Vector3(0, 1, 0), Vector3(1, 2, 1), 8)
	await ticks(2)
	launch(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	await ticks(3)
	check(impacts.size() == 1 and impacts[0].collider == overlap, "unexcluded obstacle at launch is a real immediate collision")
	await clear_world()

func test_lifetime_miss() -> void:
	new_world()
	var off_axis := body(Vector3(3, 1, -6), Vector3(1, 2, 1), 128)
	off_axis.set_meta("actor_id", "designated_target")
	body(Vector3(0, 1, -73), Vector3(1, 2, 0.2), 1)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1, 0)
	camera.look_at(off_axis.position)
	camera.current = true
	await ticks(2)
	var rocket = launch(Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	var terminal: Dictionary = {}
	rocket.tree_exiting.connect(func() -> void:
		terminal.distance = rocket.get_distance_travelled()
		terminal.age = rocket.get_age_seconds()
		terminal.position = rocket.global_position
	)
	await ticks(120)
	check(is_instance_valid(rocket), "no-obstacle rocket remains alive before its four-second limit")
	await ticks(130)
	check(not is_instance_valid(rocket), "unobstructed rocket is removed at lifetime limit")
	check(impacts.is_empty(), "off-axis target and obstacle beyond range receive no fabricated impact")
	check(terminal.has("distance") and absf(float(terminal.get("distance", -1)) - 72.0) < 0.001, "maximum travel distance is exactly 72 units")
	check(terminal.has("age") and absf(float(terminal.get("age", -1)) - 4.0) < 0.0001, "maximum simulated lifetime is exactly four seconds")
	if terminal.has("position"):
		check(terminal.position.distance_to(Vector3(0, 1, -72)) < 0.002, "lifetime endpoint follows Muzzle axis independently of camera target")
	await clear_world()

func run() -> void:
	test_presets()
	await test_muzzle_and_camera()
	await test_wall_first()
	await test_terrain()
	await test_owner_exclusions_and_masks()
	await test_lifetime_miss()
	print("VEHICLE_WEAPONS_CHECKS=", checks)
	print("VEHICLE_WEAPONS_FAILURES=", failures)
	quit(1 if failures > 0 else 0)
