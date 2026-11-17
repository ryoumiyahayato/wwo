extends "res://military_runtime/native/modules/terrain_damage/streamed_battle_terrain.gd"
## Retains the original edit/stream/collision owner. Only base field and materials differ.
const RidgeField := preload("res://military_runtime/native/ridgevale/heightfield.gd")
const GroundShader := preload("res://military_runtime/native/cedar/shaders/ground.gdshader")
var ridge_field: RidgeField
var close_material: ShaderMaterial
var far_material: ShaderMaterial
var coverage_image: Image
var coverage_texture: ImageTexture
var prepared_horizon: Array = []

func _init(validated_samples: PackedFloat32Array = PackedFloat32Array(), prepared_field: RidgeField = null) -> void:
	ridge_field = prepared_field if prepared_field!=null else RidgeField.new(validated_samples)
	source_id = "ridgevale_5km_c1_20261020"
	bounds = AABB(Vector3(-2500, -200, -2500), Vector3(5000, 600, 5000))
	coverage_image = Image.create(100, 100, false, Image.FORMAT_R8)
	coverage_image.fill(Color.BLACK)
	coverage_texture = ImageTexture.create_from_image(coverage_image)
	close_material = _ridge_material(false)
	far_material = _ridge_material(true)

func _ridge_material(is_far: bool) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = GroundShader
	for name in ["land_color", "land_control"]:
		result.set_shader_parameter(name, load("res://assets/terrain/region_slice/ridgevale/assets/" + name + ".png"))
	for name in ["grass_detail", "soil_detail", "stone_detail"]:
		result.set_shader_parameter(name, load("res://assets/terrain/region_slice/cedar/assets/" + name + ".png"))
	result.set_shader_parameter("detail_coverage", coverage_texture)
	result.set_shader_parameter("far_mesh", is_far)
	return result

func configure(focus: Vector3 = Vector3.ZERO, _original_mesh: MeshInstance3D = null) -> Dictionary:
	if not ridge_field.valid: return {"ok": false, "error": "ridgevale_heightfield_invalid"}
	# Never capture the old decorative plinth into the new authored map.
	return super.configure(focus, null)

func _procedural_base(x: float, z: float) -> float:
	return ridge_field.sample(x, z)

func _make_mesh(ox: float, oz: float, cells: int, step: float, detailed: bool) -> ArrayMesh:
	if detailed:
		var mesh := super._make_mesh(ox, oz, cells, step, true)
		mesh.surface_set_material(0, close_material)
		return mesh
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_ridge_arrays(ridge_field,ox,oz,cells,step))
	result.surface_set_material(0, far_material)
	return result

static func prepare_horizon(samples: PackedFloat32Array) -> Dictionary:
	var field := RidgeField.new(samples)
	if not field.valid: return {}
	return {"field":field,"arrays":_ridge_arrays(field,-2500,-2500,250,20.0)}

static func _ridge_arrays(field: RidgeField, ox: float, oz: float, cells: int, step: float) -> Array:
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
			vertices[index] = Vector3(wx, field.sample(wx, wz), wz)
			normals[index] = field.normal_at(wx, wz)
			colors[index] = Color.WHITE
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _grid_indices(cells)
	return arrays

func _build_horizon() -> void:
	horizon = MeshInstance3D.new()
	horizon.name = "RidgevaleDistantLand"
	# Authored whole-world silhouette; masked where real fine chunks exist.
	if prepared_horizon.is_empty():
		horizon.mesh = _make_mesh(-2500, -2500, 250, 20.0, false)
	else:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,prepared_horizon)
		mesh.surface_set_material(0,far_material)
		horizon.mesh = mesh
		prepared_horizon = []
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
