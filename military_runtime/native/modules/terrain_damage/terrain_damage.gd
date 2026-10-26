extends Node3D
## Bounded, static-world heightfield deformation for tagged game terrain only.
signal terrain_changed(event: Dictionary)
const PRESETS = {"dig": {"radius": 1.8, "depth": 1.1}, "crater": {"radius": 2.4, "depth": 1.1}}
const MAX_COMMANDS = 128
const MAX_DEPTH = 3.0
const GRID_EDGE = 0.65
var source: MeshInstance3D
var visual: MeshInstance3D
var body: StaticBody3D
var collision: CollisionShape3D
var base_surfaces: Array = []
var current_surfaces: Array = []
var materials: Array = []
var commands: Array = []
var bounds := AABB()
var dirty := false
var rebuild_count := 0
var ready_surface := false
var source_id := ""
var replaying := false

func configure_from_mesh(mesh_node: MeshInstance3D, layer: String = "terrain") -> Dictionary:
	if ready_surface: return {"ok": false, "error": "already_configured"}
	if layer != "terrain" or mesh_node == null or mesh_node.mesh == null:
		return {"ok": false, "error": "invalid_layer_or_mesh"}
	# Explicit metadata or asset naming is required; props/arches cannot opt in accidentally.
	if not mesh_node.get_meta("deformable_terrain", false) and not "Terrain" in str(mesh_node.name):
		return {"ok": false, "error": "untagged_surface"}
	if not mesh_node.mesh is ArrayMesh:
		return {"ok": false, "error": "only_array_mesh_supported"}
	var mesh: ArrayMesh = mesh_node.mesh
	if mesh.get_surface_count() != 1:
		return {"ok": false, "error": "only_single_surface_grid_supported"}
	var result: Array = []
	var mats: Array = []
	var first := true
	var xz_heights: Dictionary = {}
	for si in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			return {"ok": false, "error": "non_triangle_surface"}
		var arrays: Array = mesh.surface_get_arrays(si)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var out_v := PackedVector3Array()
		var out_c := PackedColorArray()
		var out_uv := PackedVector2Array()
		if indices.is_empty():
			for j in vertices.size(): indices.append(j)
		var world := PackedVector3Array()
		for v in vertices:
			var p: Vector3 = mesh_node.global_transform * v
			var key := Vector2i(roundi(p.x * 10000), roundi(p.z * 10000))
			if xz_heights.has(key) and absf(xz_heights[key] - p.y) > 0.002:
				return {"ok": false, "error": "non_heightfield_surface"}
			xz_heights[key] = p.y
			world.append(p)
			if first: bounds = AABB(p, Vector3.ZERO); first = false
			else: bounds = bounds.expand(p)
		if not _is_rectangular_grid(world, indices):
			return {"ok": false, "error": "unsupported_non_rectangular_heightfield"}
		# Uniform subdivisions across every triangle avoid boundary T-junctions.
		var longest := 0.0
		for k in range(0, indices.size(), 3):
			var a: Vector3 = world[indices[k]]
			var b: Vector3 = world[indices[k + 1]]
			var c: Vector3 = world[indices[k + 2]]
			if absf((b-a).cross(c-a).y) < 0.00001:
				return {"ok": false, "error": "vertical_or_degenerate_surface"}
			longest = maxf(longest, maxf(a.distance_to(b), maxf(a.distance_to(c), b.distance_to(c))))
		var subdivisions := maxi(1, ceili(longest / GRID_EDGE))
		if subdivisions > 16 or indices.size() * subdivisions * subdivisions > 250000:
			return {"ok": false, "error": "mesh_budget_exceeded"}
		for k in range(0, indices.size(), 3):
			var ids := [indices[k], indices[k+1], indices[k+2]]
			for i in subdivisions:
				for j in range(subdivisions-i):
					var points := [Vector2(i,j), Vector2(i+1,j), Vector2(i,j+1)]
					if j < subdivisions-i-1:
						points.append_array([Vector2(i+1,j),Vector2(i+1,j+1),Vector2(i,j+1)])
					for pt in points:
						var w := Vector3(1.0-(pt.x+pt.y)/subdivisions,pt.x/subdivisions,pt.y/subdivisions)
						out_v.append(world[ids[0]]*w.x+world[ids[1]]*w.y+world[ids[2]]*w.z)
						out_c.append(colors[ids[0]]*w.x+colors[ids[1]]*w.y+colors[ids[2]]*w.z if not colors.is_empty() else Color.WHITE)
						out_uv.append(uvs[ids[0]]*w.x+uvs[ids[1]]*w.y+uvs[ids[2]]*w.z if not uvs.is_empty() else Vector2.ZERO)
		var out: Array = []; out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = out_v; out[Mesh.ARRAY_COLOR] = out_c; out[Mesh.ARRAY_TEX_UV] = out_uv
		result.append(out)
		mats.append(mesh_node.get_active_material(si))
	source = mesh_node
	source_id = str(mesh_node.name) + ":" + str(mesh.get_aabb()) + ":" + str(mesh_node.global_transform)
	base_surfaces = result; materials = mats
	visual = MeshInstance3D.new(); add_child(visual)
	body = StaticBody3D.new(); body.collision_layer = 8; body.collision_mask = 0; add_child(body)
	collision = CollisionShape3D.new(); body.add_child(collision)
	# Geometry is world baked. Attach this controller at identity world transform.
	global_transform = Transform3D.IDENTITY
	source.visible = false
	_disable_source_collision(source)
	ready_surface = true
	_recalculate()
	flush_updates()
	return {"ok": true, "bounds": bounds, "vertices": _vertex_count()}

func _disable_source_collision(node: Node):
	for child in node.get_children():
		if child is CollisionShape3D: child.disabled = true
		if child is CollisionObject3D: child.collision_layer = 0; child.collision_mask = 0
		_disable_source_collision(child)

func _vertex_count() -> int:
	var n := 0
	for a in base_surfaces: n += a[Mesh.ARRAY_VERTEX].size()
	return n

func apply_command(center: Vector3, preset: String = "dig", layer: String = "terrain") -> Dictionary:
	if not ready_surface or layer != "terrain" or not PRESETS.has(preset) or not center.is_finite():
		return {"ok": false, "error": "invalid_command_or_layer"}
	if commands.size() >= MAX_COMMANDS: return {"ok": false, "error": "command_budget_exceeded"}
	var radius: float = PRESETS[preset].radius
	if center.x-radius < bounds.position.x or center.z-radius < bounds.position.z or center.x+radius > bounds.end.x or center.z+radius > bounds.end.z:
		return {"ok": false, "error": "out_of_bounds"}
	var height := terrain_height(center)
	if is_nan(height) or absf(center.y-height) > 1.5:
		return {"ok": false, "error": "wrong_surface_height"}
	var command := {"center": [center.x, height, center.z], "preset": preset}
	commands.append(command)
	_recalculate()
	var event := {"ok": true, "kind": preset, "center": Vector3(center.x,height,center.z), "radius": radius, "depth": PRESETS[preset].depth, "index": commands.size()-1, "collision_pending": true}
	if not replaying: terrain_changed.emit(event)
	return event

func _recalculate():
	current_surfaces = base_surfaces.duplicate(true)
	for si in current_surfaces.size():
		var vertices: PackedVector3Array = base_surfaces[si][Mesh.ARRAY_VERTEX].duplicate()
		for i in vertices.size():
			var drop := 0.0
			for command in commands:
				var p: Array = command.center
				var spec: Dictionary = PRESETS[command.preset]
				var distance := Vector2(vertices[i].x-p[0],vertices[i].z-p[2]).length()
				if distance < spec.radius:
					var t: float = 1.0-distance*distance/(spec.radius*spec.radius)
					drop += spec.depth*t*t
			vertices[i].y -= minf(drop,MAX_DEPTH)
		current_surfaces[si][Mesh.ARRAY_VERTEX] = vertices
	dirty = true

func flush_updates() -> void:
	# Call once after a batch, outside physics callbacks, never every frame.
	if not dirty: return
	var mesh := ArrayMesh.new()
	for si in current_surfaces.size():
		var arr: Array = current_surfaces[si]
		var vertices: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array(); normals.resize(vertices.size())
		for i in range(0,vertices.size(),3):
			var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
			for j in 3: normals[i+j] = normal
		arr[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
		mesh.surface_set_material(si, materials[si])
	visual.mesh = mesh
	collision.shape = mesh.create_trimesh_shape()
	dirty = false
	rebuild_count += 1

func terrain_height(position: Vector3) -> float:
	if not ready_surface or not position.is_finite(): return NAN
	for arr in current_surfaces:
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in range(0,vs.size(),3):
			var a := Vector2(vs[i].x,vs[i].z); var b := Vector2(vs[i+1].x,vs[i+1].z); var c := Vector2(vs[i+2].x,vs[i+2].z)
			var p := Vector2(position.x,position.z)
			var den := (b-a).cross(c-a)
			var v := (p-a).cross(c-a)/den; var w := (b-a).cross(p-a)/den; var u := 1.0-v-w
			if u >= -0.00001 and v >= -0.00001 and w >= -0.00001: return vs[i].y*u+vs[i+1].y*v+vs[i+2].y*w
	return NAN

func reset() -> void:
	commands.clear()
	if ready_surface: _recalculate(); flush_updates()

func save_state() -> Dictionary:
	return {"version": 1, "source_id": source_id, "commands": commands.duplicate(true)}

func replay_state(state: Dictionary) -> Dictionary:
	if state.get("version") != 1 or state.get("source_id") != source_id or not state.get("commands") is Array:
		return {"ok": false, "error": "invalid_state"}
	var previous := commands.duplicate(true)
	replaying = true
	commands.clear(); _recalculate()
	for cmd in state.commands:
		if not cmd is Dictionary or not cmd.get("center") is Array or cmd.center.size() != 3 or not cmd.get("preset") is String:
			replaying = false; commands = previous; _recalculate(); return {"ok": false, "error": "invalid_state_command"}
		for value in cmd.center:
			if not (value is float or value is int):
				replaying = false; commands = previous; _recalculate(); return {"ok": false, "error": "invalid_state_center"}
		var result := apply_command(Vector3(cmd.center[0],cmd.center[1],cmd.center[2]),cmd.preset)
		if not result.ok:
			replaying = false; commands = previous; _recalculate(); return result
	replaying = false
	flush_updates()
	terrain_changed.emit({"ok": true, "kind": "replay", "collision_pending": false})
	return {"ok": true}

func _is_rectangular_grid(vertices: PackedVector3Array, indices: PackedInt32Array) -> bool:
	# Explicit supported subset: a complete axis-aligned rectangular triangle grid.
	# Each grid cell has exactly two complementary triangles, excluding overlap,
	# holes, stacked layers, arbitrary bridges, arches, vertical walls and caves.
	var xs: Dictionary = {}; var zs: Dictionary = {}
	for p in vertices:
		xs[roundi(p.x * 10000)] = true; zs[roundi(p.z * 10000)] = true
	var xkeys: Array = xs.keys(); xkeys.sort()
	var zkeys: Array = zs.keys(); zkeys.sort()
	if xkeys.size()<2 or zkeys.size()<2: return false
	for i in xkeys.size(): xs[xkeys[i]] = i
	for i in zkeys.size(): zs[zkeys[i]] = i
	var cells: Dictionary = {}
	for i in range(0,indices.size(),3):
		var corners: Array = []
		for j in 3:
			var p := vertices[indices[i+j]]
			corners.append(Vector2i(xs[roundi(p.x*10000)],zs[roundi(p.z*10000)]))
		var lo: Vector2i = corners[0].min(corners[1]).min(corners[2])
		var hi: Vector2i = corners[0].max(corners[1]).max(corners[2])
		if hi-lo != Vector2i.ONE: return false
		var mask := 0
		for corner in corners:
			var offset: Vector2i = corner-lo
			mask |= 1 << (offset.x + offset.y*2)
		if not mask in [7,11,13,14]: return false
		if not cells.has(lo): cells[lo] = []
		cells[lo].append(mask)
	if cells.size() != (xkeys.size()-1)*(zkeys.size()-1): return false
	for pair in cells.values():
		if pair.size()!=2: return false
		pair.sort()
		if pair != [7,14] and pair != [11,13]: return false
	return true
