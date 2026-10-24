extends Node3D
## Static scenery is a separate view/obstacle set, never a second battle simulation.
## Geometry is batched by 100 m cell and asset. Colliders are retained when art culls.
var manifest: Dictionary = {}
var scene_cache: Dictionary = {}
var geometry_cache: Dictionary = {}
var collider_count := 0
var batch_count := 0
var placement_count := 0
var field
var material: StandardMaterial3D

func build(terrain) -> void:
	name = "RivergateScenery"
	field = terrain.river_field
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://rivergate/assets/map.json"))
	if not parsed is Dictionary or parsed.get("schema", "") != "rivergate-map-v1":
		push_error("Rivergate map manifest rejected")
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
		visual.name = "RivergateBatch_" + key
		visual.position = anchor
		visual.multimesh = multi
		visual.material_override = material
		visual.visibility_range_end = 1100.0 if str(batch.kind).begins_with("tree") else 1400.0
		visual.visibility_range_end_margin = 50.0
		add_child(visual)
		batch_count += 1
	_build_roads(terrain)
	_build_bridge()
	var water := preload("res://rivergate/water.gd").new()
	add_child(water)
	water.build(field)

func _stone_material() -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color("918775")
	result.roughness = 0.98
	return result

func _road_material(kind: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("938a75") if kind == "stone" else Color("877c5c") if kind == "gravel" else Color("786c4d")
	mat.roughness = 0.99
	return mat

func _build_roads(terrain) -> void:
	# Roads are terrain-conforming visual surfaces. Underlying heightfield owns collision;
	# the elevated bridge has its OWN collision and the road rides that surface.
	for road in manifest.roads:
		var points: Array = road.points
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		var indices := PackedInt32Array()
		var width: float = float(road.width_m)
		var length := 0.0
		var samples: Array = []
		for k in range(points.size()-1):
			var a := Vector2(float(points[k][0]),float(points[k][1]))
			var b := Vector2(float(points[k+1][0]),float(points[k+1][1]))
			var dist := a.distance_to(b)
			var count := maxi(1,ceili(dist / 4.0))
			for j in range(count):
				var t := float(j)/float(count)
				var middle := a.lerp(b,t)
				var forward := (b-a).normalized()
				var sideways := Vector2(-forward.y,forward.x)
				var left := middle - sideways*width*0.5
				var right := middle + sideways*width*0.5
				var hleft: float = terrain.sample_height(left.x,left.y)
				var hright: float = terrain.sample_height(right.x,right.y)
				if not is_finite(hleft) or not is_finite(hright): continue
				samples.append([Vector3(left.x,hleft+0.065,left.y),Vector3(right.x,hright+0.065,right.y),length])
				length += dist/float(count)
		var endpt := Vector2(float(points[-1][0]),float(points[-1][1]))
		if samples.is_empty():continue
		var last: Array = samples[-1]
		var middle_last: Vector3 = (last[0] + last[1]) * 0.5
		var delta := Vector2(endpt.x-middle_last.x,endpt.y-middle_last.z)
		var final_left := Vector2(last[0].x,last[0].z)+delta
		var final_right := Vector2(last[1].x,last[1].z)+delta
		samples.append([Vector3(final_left.x,terrain.sample_height(final_left.x,final_left.y)+0.065,final_left.y),Vector3(final_right.x,terrain.sample_height(final_right.x,final_right.y)+0.065,final_right.y),length])
		for i in range(samples.size()):
			var row: Array = samples[i]
			vertices.append(row[0]);vertices.append(row[1])
			normals.append(Vector3.UP);normals.append(Vector3.UP)
			uv.append(Vector2(0,row[2]*0.22));uv.append(Vector2(1,row[2]*0.22))
			if i>0:
				var a := (i-1)*2
				indices.append_array(PackedInt32Array([a,a+1,a+2,a+1,a+3,a+2]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual := MeshInstance3D.new()
		visual.name = "RivergateRoad_" + str(road.id)
		visual.mesh = mesh
		visual.material_override = _road_material(str(road.type))
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)

func _solid_box(parent: Node3D, name: String, point: Vector3, size: Vector3, color: Color, collidable: bool = true) -> void:
	var root: Node3D
	if collidable:
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		root = body
	else:root = Node3D.new()
	root.name = name
	root.position = point
	parent.add_child(root)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.96
	visual.material_override = mat
	root.add_child(visual)

func _build_bridge() -> void:
	var data: Dictionary = field.hydro.bridge
	var cx := float(data.center_x)
	var z := float(data.center_z)
	var deck_y := float(data.deck_top_y)
	var half_span := float(data.half_span_m)
	var span := half_span*2.0
	var width := float(data.width_m)
	var road_body := StaticBody3D.new()
	road_body.name = "RivergateBridge_Deck_Collision"
	road_body.position = Vector3(cx,deck_y-0.4,z)
	road_body.collision_layer = 8
	road_body.collision_mask = 0
	road_body.set_meta("road_id", "bridge_crossing")
	road_body.set_meta("source_id","rivergate_bridge_road_01")
	road_body.add_to_group("drivable_ground")
	add_child(road_body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(span,0.8,width)
	collider.shape = shape
	road_body.add_child(collider)
	var decking := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = shape.size
	decking.mesh = deck_mesh
	decking.material_override = _stone_material()
	road_body.add_child(decking)
	for side in [-1.0,1.0]:
		_solid_box(self,"Bridge_Rail",Vector3(cx,deck_y+0.42,z+side*(width*0.5+0.22)),Vector3(span,0.83,0.38),Color("a6a49a"))
	for offset in [-half_span*0.58,half_span*0.58]:
		var waterlevel: float = float(field.profile_at(z).water_y)
		var pier_bottom: float = waterlevel - 0.9
		var deck_bottom: float = deck_y - shape.size.y
		_solid_box(self,"BridgePier",Vector3(cx+offset,(pier_bottom+deck_bottom)*0.5,z),Vector3(2.4,deck_bottom-pier_bottom,4.5),Color("6c7270"))


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
	body.name = "RivergateObstacle_" + str(row.id)
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
	return {"map_profile": "rivergate-map-v1", "placements": placement_count, "batches": batch_count,
		"static_obstacles": collider_count, "actors_created": 0, "static_damage": false, "bridge_collision": true, "ford": true}
