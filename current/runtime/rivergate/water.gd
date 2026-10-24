extends Node3D
## Display-only surface over the actual carved riverbed. Nothing in the water draws can
## change damage, supply, time, identities, terrain collision, or gunfire.
const WaterShader = preload("res://rivergate/water.gdshader")
var mesh_count := 0

func build(field) -> void:
	name = "RivergateRiverSurface"
	var mat := ShaderMaterial.new()
	mat.shader = WaterShader
	for section in range(25):
		var low := -2500.0 + section*200.0
		var high := minf(low+200.0,2500.0)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uv := PackedVector2Array()
		var indices := PackedInt32Array()
		var nr := 26
		for k in range(nr):
			var z := lerpf(low,high,float(k)/float(nr-1))
			var p: Dictionary = field.profile_at(z)
			for side in [-1.0,-0.67,-0.33,0.0,0.33,0.67,1.0]:
				vertices.append(Vector3(float(p.x)+side*float(p.half_width)*0.985,float(p.water_y)+0.035,z))
				normals.append(Vector3.UP)
				colors.append(Color(1.0 if absf(side)>0.75 else 0.0,0.0,0.0,1.0))
				uv.append(Vector2(side,z*0.012))
		for k in range(nr-1):
			for j in range(6):
				var a := k*7+j
				indices.append_array(PackedInt32Array([a,a+7,a+1,a+1,a+7,a+8]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var visual := MeshInstance3D.new()
		visual.name = "WaterSegment_%02d" % section
		visual.mesh = mesh
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		mesh_count += 1
