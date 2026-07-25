extends Node3D

const LAT_SEGMENTS := 32
const LON_SEGMENTS := 64
const RADIUS := 1.0
const MOON_RADIUS := 0.145

@onready var _surface: MeshInstance3D = $Surface
@onready var _moon: MeshInstance3D = $Moon


func _ready() -> void:
	_surface.mesh = _build_front_hemisphere_mesh()
	var hemisphere_shader := load(
		"res://shaders/ui_spikes/holographic_workspace/hemisphere_surface.gdshader"
	) as Shader
	var hemisphere_material := ShaderMaterial.new()
	hemisphere_material.shader = hemisphere_shader
	_surface.material_override = hemisphere_material

	_moon.mesh = _build_moon_mesh()
	var moon_shader := load(
		"res://shaders/ui_spikes/holographic_workspace/moon_surface.gdshader"
	) as Shader
	var moon_material := ShaderMaterial.new()
	moon_material.shader = moon_shader
	_moon.material_override = moon_material


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
			# Outward-facing winding for the camera on +Z looking toward the origin.
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_moon_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = MOON_RADIUS
	mesh.height = MOON_RADIUS * 2.0
	mesh.radial_segments = 32
	mesh.rings = 18
	return mesh
