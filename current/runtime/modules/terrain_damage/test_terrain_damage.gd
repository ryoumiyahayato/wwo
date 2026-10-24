extends SceneTree
const Terrain = preload("res://modules/terrain_damage/terrain_damage.gd")
var failures := 0
func check(value: bool, label: String):
	if value: print("PASS ",label)
	else: push_error("FAIL " + label); failures += 1
func _initialize(): call_deferred("run")
func find_terrain(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and "Terrain" in str(node.name): return node
	for child in node.get_children():
		var found := find_terrain(child)
		if found: return found
	return null
func ray(world: World3D, p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p+Vector3.UP*20,p-Vector3.UP*20,8)
	return world.direct_space_state.intersect_ray(q)
func run():
	for asset in ["plains", "hills_terraces", "rock_arch"]:
		var scene: Node3D = load("res://assets/reused_terrain/"+asset+".glb").instantiate()
		root.add_child(scene); scene.scale = Vector3.ONE*5; scene.position.z = 6
		for collider in scene.find_children("*", "CollisionObject3D", true, false): collider.collision_layer = 8
		var source := find_terrain(scene)
		check(source != null,asset+" tagged mesh")
		var old_mesh: Mesh = source.mesh
		var original_colors: PackedColorArray = old_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR].duplicate()
		var untouched: Dictionary = {}
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			if node != source: untouched[node.get_instance_id()] = node.mesh
		var module := Terrain.new(); root.add_child(module)
		var setup := module.configure_from_mesh(source)
		check(setup.ok,asset+" configure "+str(setup))
		if not setup.ok: scene.free(); module.free(); continue
		var point := Vector3(15,0,20)
		point.y = module.terrain_height(point)
		var original_height := point.y
		await physics_frame; await physics_frame
		var before := ray(module.get_world_3d(),point)
		check(not before.is_empty(),asset+" collision exists")
		check(absf(before.position.y-original_height)<0.03,asset+" collision matches source")
		var count := module.rebuild_count
		check(module.apply_command(point,"dig").ok,asset+" dig accepted")
		check(module.rebuild_count == count,asset+" deferred collision budget")
		var lowered := module.terrain_height(point)
		check(lowered < original_height-0.9,asset+" real visible vertex depression")
		module.flush_updates()
		await physics_frame; await physics_frame
		var after := ray(module.get_world_3d(),point)
		check(not after.is_empty() and absf(after.position.y-lowered)<0.03,asset+" actual ray lowered; no original lid")
		check(source.mesh == old_mesh,asset+" source mesh unchanged")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(module.save_state()))
		check(not module.apply_command(Vector3(100,0,100),"dig").ok,asset+" bounds rejected")
		check(not module.apply_command(point,"dig","bridge").ok,asset+" layer rejected")
		check(not module.apply_command(point+Vector3.UP*50,"dig").ok,asset+" wrong height rejected")
		module.reset()
		await physics_frame; await physics_frame
		check(absf(ray(module.get_world_3d(),point).position.y-original_height)<0.03,asset+" reset collision")
		check(module.replay_state(saved).ok,asset+" JSON replay accepted")
		check(absf(module.terrain_height(point)-lowered)<0.0001,asset+" deterministic replay")
		var old_count: int = module.commands.size()
		check(not module.replay_state({"version":1,"source_id":module.source_id,"commands":[{"center":["x",0,0],"preset":"dig"}]}).ok,asset+" malformed replay rejected")
		check(module.commands.size()==old_count,asset+" replay atomic state rollback")
		check(module.visual.mesh.surface_get_material(0)==source.get_active_material(0),asset+" material preserved")
		check(old_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == original_colors,asset+" source vertex colors unchanged")
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			if node != source: check(node.mesh==untouched[node.get_instance_id()] and node.visible,asset+" obstacle/plinth preserved "+str(node.name))
		var count_before: int = module.rebuild_count
		point.y = module.terrain_height(point)
		check(module.apply_command(point,"crater").ok,asset+" repeat crater")
		point.y = module.terrain_height(point)
		check(module.apply_command(point,"dig").ok,asset+" repeat dig")
		module.flush_updates()
		check(module.rebuild_count == count_before+1,asset+" batch single rebuild")
		check(module.terrain_height(point)>=original_height-3.001,asset+" cumulative depth bounded")
		scene.free(); module.free()
	var invalid := MeshInstance3D.new(); invalid.name = "TerrainBad"
	var box := BoxMesh.new()
	var box_array := ArrayMesh.new(); box_array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
	invalid.mesh = box_array; root.add_child(invalid)
	var rejected := Terrain.new(); root.add_child(rejected)
	check(not rejected.configure_from_mesh(invalid).ok,"solid box/overhang refused")
	check(invalid.visible,"unsupported source left visible")
	invalid.free(); rejected.free()
	print("TERRAIN_DAMAGE_FAILURES=",failures)
	quit(1 if failures else 0)
