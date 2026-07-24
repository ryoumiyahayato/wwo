extends Node3D

const LAT_SEGMENTS := 32
const LON_SEGMENTS := 64
const RADIUS := 1.0

@onready var _surface: MeshInstance3D = $Surface
var _angle: float = 0.0
var _tilt: float = -0.24

func _ready() -> void:
	_surface.mesh = _build_front_hemisphere_mesh()
	var shader := load("res://shaders/ui_spikes/holographic_workspace/hemisphere_surface.gdshader") as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	_surface.material_override = material
	_apply_rotation()

func set_orbit(angle: float, tilt: float) -> void:
	_angle = angle
	_tilt = tilt
	_apply_rotation()

func _apply_rotation() -> void:
	rotation = Vector3(_tilt, _angle, 0.0)

func _build_front_hemisphere_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for lat_index in range(LAT_SEGMENTS + 1):
		var lat_ratio := float(lat_index) / float(LAT_SEGMENTS)
		var lat := lerpf(-PI * 0.5, PI * 0.5, lat_ratio)
		for lon_index in range(LON_SEGMENTS + 1):
			var lon_ratio := float(lon_index) / float(LON_SEGMENTS)
			var lon := lerpf(-PI * 0.5, PI * 0.5, lon_ratio)
			var point := Vector3(
				sin(lon) * cos(lat),
				sin(lat),
				cos(lon) * cos(lat)
			) * RADIUS
			vertices.append(point)
			normals.append(point.normalized())
			uvs.append(Vector2(lon_ratio, 1.0 - lat_ratio))
	for lat_index in range(LAT_SEGMENTS):
		for lon_index in range(LON_SEGMENTS):
			var a := lat_index * (LON_SEGMENTS + 1) + lon_index
			var b := a + 1
			var c := a + (LON_SEGMENTS + 1)
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
