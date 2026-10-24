extends "res://modules/terrain_damage/streamed_battle_terrain.gd"
## This is the old collision/stream/edit owner with a baked river valley source.
## Water itself never provides ground collision; bridge deck is a separate real StaticBody3D.
const RiverField = preload("res://rivergate/heightfield.gd")
const GroundShader = preload("res://cedar/shaders/ground.gdshader")
var river_field = RiverField.new()
var close_material: ShaderMaterial
var far_material: ShaderMaterial
var coverage_image: Image
var coverage_texture: ImageTexture

func _init() -> void:
	source_id = "rivergate_5km_b1_20261020"
	bounds = AABB(Vector3(-2500,-60,-2500),Vector3(5000,390,5000))
	coverage_image = Image.create(100,100,false,Image.FORMAT_R8)
	coverage_image.fill(Color.BLACK)
	coverage_texture = ImageTexture.create_from_image(coverage_image)
	close_material = _river_material(false)
	far_material = _river_material(true)

func _river_material(is_far: bool) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = GroundShader
	for name in ["land_color","land_control"]:
		result.set_shader_parameter(name, load("res://rivergate/assets/" + name + ".png"))
	for name in ["grass_detail","soil_detail","stone_detail"]:
		result.set_shader_parameter(name, load("res://cedar/assets/" + name + ".png"))
	result.set_shader_parameter("detail_coverage",coverage_texture)
	result.set_shader_parameter("far_mesh",is_far)
	return result

func configure(focus: Vector3 = Vector3.ZERO, _original_mesh: MeshInstance3D = null) -> Dictionary:
	if not river_field.valid: return {"ok":false,"error":"rivergate_source_invalid"}
	return super.configure(focus, null)

func _procedural_base(x: float,z: float) -> float:
	return river_field.sample(x,z)

func sample_height(x: float,z: float) -> float:
	var ground := super.sample_height(x,z)
	if not is_finite(ground): return ground
	# Support queries must see the same drivable bridge deck that physics raycasts hit.
	return maxf(ground, river_field.bridge_surface_height(x,z))

func _make_mesh(ox: float,oz: float,cells: int,step: float,detailed: bool) -> ArrayMesh:
	if detailed:
		var fine: ArrayMesh = super._make_mesh(ox,oz,cells,step,true)
		fine.surface_set_material(0,close_material)
		return fine
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := (cells + 1)*(cells + 1)
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	for j in range(cells+1):
		for i in range(cells+1):
			var x := ox + i * step
			var z := oz + j * step
			var idx := j*(cells+1)+i
			vertices[idx] = Vector3(x,river_field.sample(x,z),z)
			normals[idx] = river_field.normal_at(x,z)
			colors[idx] = Color.WHITE
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _mesh_indices(cells)
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.surface_set_material(0,far_material)
	return result

func _build_horizon() -> void:
	horizon = MeshInstance3D.new()
	horizon.name = "RivergateDistantLand"
	horizon.mesh = _make_mesh(-2500,-2500,250,20.0,false)
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
		coverage_image.set_pixel(key.x+50,key.y+50,Color.WHITE)
	coverage_texture.update(coverage_image)
