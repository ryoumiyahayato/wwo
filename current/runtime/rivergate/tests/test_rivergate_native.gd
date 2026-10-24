extends SceneTree
## Must be run in Godot4.6.3 AFTER project --import, not as an external parser.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func require(valid: bool, label: String) -> void:
	if not valid:
		failures.append(label)
		push_error(label)
func _run() -> void:
	var field = load("res://rivergate/heightfield.gd").new()
	require(field.valid,"rivergate height and hydro files")
	if not field.valid:
		quit(1)
		return
	require(is_finite(field.sample(-6.0,-7.0)),"spawn land exists")
	require(is_finite(field.sample(-1100.0,450.0)),"far ridge exists")
	var ford: Dictionary = field.profile_at(-790.0)
	var bridge: Dictionary = field.hydro.bridge
	var bridge_z := float(bridge.center_z)
	var bridge_x := float(bridge.center_x)
	var ford_bed: float = field.sample(float(ford.x),-790.0)
	require(float(ford.water_y) > ford_bed,"ford has water above real bed")
	require(float(ford.water_y)-ford_bed < 0.75,"ford not deep water")
	var regular: Dictionary = field.profile_at(800.0)
	require(float(regular.water_y)-field.sample(float(regular.x),800.0)>2.5,"deep channel carved in physical terrain")
	var terrain = load("res://rivergate/terrain.gd").new()
	root.add_child(terrain)
	var loaded: Dictionary = terrain.configure(Vector3.ZERO,null)
	require(bool(loaded.get("ok",false)),"real collision streaming terrain configured")
	require(terrain.source_id == "rivergate_5km_b1_20261020","unique map source id")
	require(terrain.chunks.size()>=9,"initial 3x3 physical terrain chunks")
	require(absf(terrain.sample_height(bridge_x,bridge_z)-float(bridge.deck_top_y))<0.05,"support on bridge deck")
	var world = load("res://rivergate/world.gd").new()
	root.add_child(world)
	world.build(terrain)
	require(world.placement_count>150,"bank scenery placed")
	require(world.get_node_or_null("RivergateBridge_Deck_Collision") is StaticBody3D,"drivable bridge collision exists")
	require(world.get_node_or_null("RivergateRiverSurface") != null,"water mesh created")
	require(int(world.get_node("RivergateRiverSurface").get("mesh_count"))==25,"water segments all 5km")
	for road in world.manifest.roads:
		require(world.get_node_or_null("RivergateRoad_"+str(road.id)) != null,"road mesh exists " + str(road.id))
	# Physics queries run against the actual Godot StaticBody3D and terrain collision.
	await physics_frame
	var bridge_hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(bridge_x,float(bridge.deck_top_y)+6.0,bridge_z),Vector3(bridge_x,float(bridge.deck_top_y)-12.0,bridge_z),8))
	require(bridge_hit.get("collider", null) == world.get_node_or_null("RivergateBridge_Deck_Collision"),"bridge physically supports a ray")
	var ford_x := float(ford.x)
	terrain.set_focus(Vector3(ford_x,0,-790.0))
	for i in range(30): await process_frame
	require(terrain.is_position_loaded(Vector3(ford_x,0,-790.0)),"ford terrain collision chunk loaded")
	var ford_hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(ford_x,float(ford.water_y)+10.0,-790.0),Vector3(ford_x,float(ford.water_y)-10.0,-790.0),8))
	require(not ford_hit.is_empty(),"real terrain physics under ford water")
	if not ford_hit.is_empty():
		require(absf(float(ford_hit.position.y)-ford_bed) < 0.25,"ford collision and height sample align")
	print(JSON.stringify({"test":"rivergate_native_smoke","ok":failures.is_empty(),"failures":failures,"source_id":terrain.source_id,"water_sections":int(world.get_node("RivergateRiverSurface").get("mesh_count")),"bridge":bridge,"ford_depth":float(ford.water_y)-ford_bed,"obstacles":world.collider_count,"note":"This does not substitute for GUI driving, Android testing, or mobile FPS."}))
	quit(0 if failures.is_empty() else 1)
