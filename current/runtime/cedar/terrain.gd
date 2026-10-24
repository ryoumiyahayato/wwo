extends "res://modules/terrain_damage/streamed_battle_terrain.gd"
## Retains the original edit/stream/collision owner. Only base field and materials differ.
const CedarField := preload("res://cedar/heightfield.gd")
const GroundShader := preload("res://cedar/shaders/ground.gdshader")
var cedar_field = CedarField.new()
var close_material: ShaderMaterial
var far_material: ShaderMaterial
var coverage_image: Image
var coverage_texture: ImageTexture

func _init() -> void:
	source_id = "cedar_valley_20261019_v1"
	bounds = AABB(Vector3(-2500, -200, -2500), Vector3(5000, 600, 5000))
	coverage_image = Image.create(100, 100, false, Image.FORMAT_R8)
	coverage_image.fill(Color.BLACK)
	coverage_texture = ImageTexture.create_from_image(coverage_image)
	close_material = _cedar_material(false)
	far_material = _cedar_material(true)

func _cedar_material(is_far: bool) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = GroundShader
	for name in ["land_color", "land_control", "grass_detail", "soil_detail", "stone_detail"]:
		result.set_shader_parameter(name, load("res://cedar/assets/" + name + ".png"))
	result.set_shader_parameter("detail_coverage", coverage_texture)
	result.set_shader_parameter("far_mesh", is_far)
	return result

func configure(focus: Vector3 = Vector3.ZERO, _original_mesh: MeshInstance3D = null) -> Dictionary:
	if not cedar_field.valid: return {"ok": false, "error": "cedar_heightfield_invalid"}
	# Never capture the old decorative plinth into the new authored map.
	return super.configure(focus, null)

func _procedural_base(x: float, z: float) -> float:
	return cedar_field.sample(x, z)

func _make_mesh(ox: float, oz: float, cells: int, step: float, detailed: bool) -> ArrayMesh:
	if detailed:
		var mesh := super._make_mesh(ox, oz, cells, step, true)
		mesh.surface_set_material(0, close_material)
		return mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := (cells + 1) * (cells + 1)
	vertices.resize(count); normals.resize(count); colors.resize(count)
	for z in range(cells + 1):
		for x in range(cells + 1):
			var wx := ox + x * step
			var wz := oz + z * step
			var index := z * (cells + 1) + x
			vertices[index] = Vector3(wx, cedar_field.sample(wx, wz), wz)
			normals[index] = cedar_field.normal_at(wx, wz)
			colors[index] = Color.WHITE
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _mesh_indices(cells)
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.surface_set_material(0, far_material)
	return result

func _build_horizon() -> void:
	horizon = MeshInstance3D.new()
	horizon.name = "CedarDistantLand"
	# Authored whole-world silhouette; masked where real fine chunks exist.
	horizon.mesh = _make_mesh(-2500, -2500, 250, 20.0, false)
	horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(horizon)

func _build_chunk(key: Vector2i) -> void:
	super._build_chunk(key)
	_refresh_coverage()

func _refresh_stream_targets() -> void:
	super._refresh_stream_targets()
	_refresh_coverage()

func _refresh_coverage() -> void:
	if coverage_texture == null: return
	coverage_image.fill(Color.BLACK)
	for key in chunks:
		coverage_image.set_pixel(key.x + 50, key.y + 50, Color.WHITE)
	coverage_texture.update(coverage_image)
