extends SceneTree
const Registry = preload("res://modules/vehicle_crew/crew_registry.gd")
const Clearance = preload("res://modules/vehicle_crew/exit_clearance.gd")
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		push_error("FAIL: " + label)
		quit(1)
		assert(value, label)
func yes(_p, _v, _s) -> bool: return true
func no(_p, _v, _s) -> bool: return false
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var r = Registry.new()
	var crew: Array = []
	for i in 5: crew.append({"hp": 10.0, "alive": true, "parts": {"left_arm": "injured"}, "ammo": {"rifle": 7}, "state": {"order": "guard"}})
	check(r.bind_vehicle("tank-a", ["commander", "gunner", "driver", "loader", "radio"], crew, {"requires_loader": true}).ok, "bind five crew")
	var pid: String = crew[1].person_id
	check(r.can_fire("tank-a") and r.can_drive("tank-a"), "full crew functions")
	crew[1].hp = 4.0
	check(r.person_ref(pid).hp == 4.0, "exact shared combat dictionary")
	check(not r.disembark(pid, Vector3.ZERO, no).ok, "unsafe exit rejected")
	check(r.occupied_person("tank-a", "1").person_id == pid, "blocked exit preserves seat")
	check(r.disembark(pid, Vector3(2, 0, 0), yes).ok, "disembark")
	check(not r.can_fire("tank-a"), "no gunner no fire")
	check(not r.disembark(pid, Vector3.ZERO, yes).ok, "double exit rejected")
	check(not r.embark(pid, "tank-a", "0", yes).ok, "occupied seat rejected")
	check(not r.embark(pid, "tank-a", "1", no).ok, "boarding denied")
	check(r.embark(pid, "tank-a", "1", yes).ok, "reembark")
	check(crew[1].hp == 4.0 and crew[1].parts.left_arm == "injured" and crew[1].ammo.rifle == 7 and crew[1].state.order == "guard", "injuries ammo and state preserved")
	check(not r.embark(pid, "tank-a", "2", yes).ok, "person cannot board twice")
	check(r.disembark(crew[3].person_id, Vector3.ZERO, yes).ok and r.reload_multiplier("tank-a") == 1.5, "loader absent fixed 1.5x")
	check(r.disembark(crew[2].person_id, Vector3.ZERO, yes).ok and not r.can_drive("tank-a"), "driver absent disables drive capability")
	crew[0].alive = false
	check(not r.disembark(crew[0].person_id, Vector3.ZERO, yes).ok, "dead cannot transfer")
	check(not r.register_person({"person_id": pid}).ok, "duplicate identity rejected")
	var restored = Registry.new()
	var json_snapshot: Dictionary = JSON.parse_string(JSON.stringify(r.serialize()))
	check(restored.restore(json_snapshot).ok and restored.person(pid).hp == 4.0, "portable JSON roundtrip")
	var bad: Dictionary = r.serialize()
	bad.vehicles["tank-a"].seats["2"].person_id = pid
	var corrupt = Registry.new()
	check(not corrupt.restore(bad).ok, "duplicate occupancy snapshot rejected")
	check(not restored.restore(json_snapshot).ok, "live restore refused to prevent stale actor references")
	check(restored.person(pid).hp == 4.0, "failed restore atomic")
	check(r.register_vehicle("car-b", {"driver": "driver", "weapon": "gunner"}).ok, "generic future vehicle slots")
	check(r.disembark(pid, Vector3.ZERO, yes).ok and r.embark(pid, "car-b", "weapon", yes).ok, "cross vehicle same identity")
	check(not r.can_fire("tank-a") and r.can_fire("car-b"), "old vehicle loses gunner")
	var invalid = Registry.new()
	check(not invalid.bind_vehicle("bad", ["driver", "gunner"], [{"person_id": "same"}, {"person_id": "same"}]).ok and invalid.vehicle("bad").is_empty(), "duplicate bind fully rejected")
	crew[1].parts["left_arm"] = "disabled"
	crew[1].parts["right_arm"] = "disabled"
	check(not r.can_fire("car-b"), "incapacitated gunner cannot fire")
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.2, 10)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.1
	world.add_child(ground)
	await physics_frame
	await physics_frame
	check(Clearance.is_safe(world.get_world_3d().direct_space_state, Vector3.ZERO), "3D clear exit accepted")
	check(not Clearance.is_safe(world.get_world_3d().direct_space_state, Vector3(20, 0, 0)), "3D no ground rejected")
	var obstacle := StaticBody3D.new()
	var obstruction := CollisionShape3D.new()
	var obstruction_box := BoxShape3D.new()
	obstruction_box.size = Vector3(1, 2, 1)
	obstruction.shape = obstruction_box
	obstacle.add_child(obstruction)
	obstacle.position.y = 1.0
	world.add_child(obstacle)
	await physics_frame
	await physics_frame
	check(not Clearance.is_safe(world.get_world_3d().direct_space_state, Vector3.ZERO), "3D blocked exit rejected")
	print("PASS vehicle crew: %d checks, including real 3D ground/obstruction queries" % checks)
	world.queue_free()
	quit(0)
