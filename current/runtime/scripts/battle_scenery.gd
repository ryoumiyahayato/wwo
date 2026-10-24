extends Node3D
## Non-playable distant landscape closes the horizon; the battle remains bounded.
func build(main:Node3D):
	if not is_instance_valid(main.terrain_damage):return
	var b:AABB=main.terrain_damage.bounds
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges:=[Vector2(b.position.x,b.position.z),Vector2(b.end.x,b.position.z),Vector2(b.end.x,b.end.z),Vector2(b.position.x,b.end.z)]
	var center:=Vector2(b.get_center().x,b.get_center().z)
	for edge in range(4):
		for i in range(28):
			var a:Vector2=edges[edge].lerp(edges[(edge+1)%4],float(i)/28)
			var c:Vector2=edges[edge].lerp(edges[(edge+1)%4],float(i+1)/28)
			var pa:=Vector3(a.x,main.terrain_damage.terrain_height(Vector3(a.x,0,a.y))-.035,a.y)
			var pc:=Vector3(c.x,main.terrain_damage.terrain_height(Vector3(c.x,0,c.y))-.035,c.y)
			if not pa.is_finite() or not pc.is_finite():continue
			var oa:=center+(a-center)*5;var oc:=center+(c-center)*5
			var qa:=Vector3(oa.x,-2.0+sin(oa.x*.1)*cos(oa.y*.08)*2,oa.y)
			var qc:=Vector3(oc.x,-2.0+sin(oc.x*.1)*cos(oc.y*.08)*2,oc.y)
			for p in [pa,qa,pc,pc,qa,qc]:
				st.set_color(Color(.37,.43,.25) if p==pa or p==pc else Color(.29,.36,.25));st.add_vertex(p)
	st.generate_normals()
	var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mat.roughness=1
	st.set_material(mat)
	var mesh:=MeshInstance3D.new();mesh.mesh=st.commit();add_child(mesh)
	# Readable perimeter markers prevent an invisible edge. They are scenery, not a new map.
	for edge in range(4):
		for i in range(9):
			var p:Vector2=edges[edge].lerp(edges[(edge+1)%4],(i+.5)/9.0)
			p=p.lerp(center,.035)
			var height:float=main.terrain_damage.terrain_height(Vector3(p.x,0,p.y))
			if is_nan(height):continue
			var post:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=.055;cylinder.bottom_radius=.065;cylinder.height=1.0;post.mesh=cylinder;post.material_override=main.material(Color("655c48"));post.position=Vector3(p.x,height+.5,p.y);add_child(post)
			var flag:=MeshInstance3D.new();var plate:=BoxMesh.new();plate.size=Vector3(.28,.22,.025);flag.mesh=plate;flag.position=Vector3(p.x,height+.87,p.y);flag.material_override=main.material(Color("c7ac71"));add_child(flag)
	for i in range(14):
		var angle:=TAU*i/14.0
		var hill:=MeshInstance3D.new();var cone:=CylinderMesh.new();cone.top_radius=1.0;cone.bottom_radius=14;cone.height=10+float(i%4)*3;cone.radial_segments=9
		hill.mesh=cone;hill.position=Vector3(center.x+sin(angle)*90,cone.height*.5-4,center.y+cos(angle)*90);hill.material_override=main.material(Color(.29,.36,.33));add_child(hill)
