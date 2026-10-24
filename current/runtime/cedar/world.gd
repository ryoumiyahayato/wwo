extends Node3D
## Static scenery is a separate view/obstacle set, never a second battle simulation.
## Geometry is batched by 100 m cell and asset. Colliders are retained when art culls.
var manifest: Dictionary = {}
var scene_cache: Dictionary = {}
var geometry_cache: Dictionary = {}
var collider_count := 0
var batch_count := 0
var placement_count := 0
var field: RefCounted
var material: StandardMaterial3D

func build(terrain: Node3D) -> void:
	name = "CedarScenery"
	field = terrain.cedar_field
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://cedar/assets/map.json"))
	if not parsed is Dictionary or parsed.get("schema", "") != "cedar-valley-v1":
		push_error("Cedar map manifest rejected")
		return
	manifest = parsed
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.91
	material.metallic_specular = 0.24
	var batches: Dictionary = {}
	for row in manifest.placements:
		var p: Array = row.position
		var point := Vector3(p[0], terrain.sample_height(p[0], p[2]), p[2])
		if not point.is_finite(): continue
		var basis := Basis(Vector3.UP, float(row.yaw)).scaled(Vector3.ONE * float(row.scale))
		var transform := Transform3D(basis, point)
		var key := "%s_%d_%d" % [row.kind, floori(point.x / 100.0), floori(point.z / 100.0)]
		if not batches.has(key): batches[key] = {"kind": row.kind, "transforms": []}
		batches[key].transforms.append(transform)
		_add_collider(row, transform)
		placement_count += 1
	for key in batches:
		var batch: Dictionary = batches[key]
		var mesh: Mesh = _mesh_for(batch.kind)
		if mesh == null: continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = batch.transforms.size()
		var bounds := AABB()
		var anchor: Vector3 = batch.transforms[0].origin
		for i in range(batch.transforms.size()):
			var local: Transform3D = batch.transforms[i]
			local.origin -= anchor
			multi.set_instance_transform(i, local)
			var transformed: AABB = local * mesh.get_aabb()
			bounds = transformed if i == 0 else bounds.merge(transformed)
		multi.custom_aabb = bounds.grow(0.1)
		var visual := MultiMeshInstance3D.new()
		visual.name = "CedarBatch_" + key
		visual.position = anchor
		visual.multimesh = multi
		visual.material_override = material
		visual.visibility_range_end = 1100.0 if str(batch.kind).begins_with("tree") else 1400.0
		visual.visibility_range_end_margin = 50.0
		add_child(visual)
		batch_count += 1

func _mesh_for(kind: String) -> Mesh:
	if geometry_cache.has(kind): return geometry_cache[kind]
	var packed: PackedScene = load("res://cedar/assets/" + kind + ".glb")
	if packed == null: return null
	var instance: Node = packed.instantiate()
	var mesh_node := _first_mesh(instance)
	var mesh: Mesh = mesh_node.mesh if mesh_node != null else null
	if mesh != null: geometry_cache[kind] = mesh
	instance.free()
	return mesh

func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null: return found
	return null

func _add_collider(row: Dictionary, pose: Transform3D) -> void:
	if not manifest.colliders.has(row.kind): return
	var spec: Dictionary = manifest.colliders[row.kind]
	var body := StaticBody3D.new()
	body.name = "CedarObstacle_" + str(row.id)
	body.collision_layer = 8
	body.collision_mask = 0
	body.set_meta("cedar_object_id", str(row.id))
	body.set_meta("cedar_static_not_destructible", true)
	body.set_meta("surface", "wood" if str(row.kind).begins_with("tree") else "stone")
	add_child(body)
	body.transform = pose
	if spec.shape == "compound":
		for box in spec.boxes: _box_shape(body, box)
		for vertex_list in spec.get("convex", []):
			var points := PackedVector3Array()
			for v in vertex_list: points.append(Vector3(v[0], v[1], v[2]))
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			var node := CollisionShape3D.new()
			node.shape = shape
			body.add_child(node)
	elif spec.shape == "box":
		_box_shape(body, spec)
	elif spec.shape == "cylinder":
		var shape := CylinderShape3D.new()
		shape.radius = float(spec.radius)
		shape.height = float(spec.height)
		var node := CollisionShape3D.new()
		node.shape = shape
		node.position = Vector3(spec.center[0], spec.center[1], spec.center[2])
		if spec.get("axis", "y") == "x": node.rotation.z = PI * 0.5
		body.add_child(node)
	elif spec.shape == "convex_visual":
		var mesh: Mesh = _mesh_for(row.kind)
		if mesh != null:
			var node := CollisionShape3D.new()
			node.shape = mesh.create_convex_shape()
			body.add_child(node)
	collider_count += 1

func _box_shape(body: StaticBody3D, spec: Dictionary) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(spec.size[0], spec.size[1], spec.size[2])
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = Vector3(spec.center[0], spec.center[1], spec.center[2])
	body.add_child(node)

func snapshot() -> Dictionary:
	return {"map_profile": "cedar-valley-v1", "placements": placement_count, "batches": batch_count,
		"static_obstacles": collider_count, "actors_created": 0, "static_damage": false}
