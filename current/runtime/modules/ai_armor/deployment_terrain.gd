extends RefCounted
## Symmetric neutral scene terrain. No team/actor target or special damage immunity.
const WIDTH := 24.0
const HEIGHT := 3.6
const DEPTH := 8.0
static func spawn(main: Node3D, home: Vector3, team: String, label: String) -> Node3D:
 var center := home+Vector3(0,0,18.0 if team=="blue" else -18.0)
 center.y=main.terrain_height(center.x,center.z)
 var body:=StaticBody3D.new()
 body.name="DeploymentEarthwork_"+label
 body.collision_layer=8
 body.collision_mask=0
 body.set_meta("neutral_deployment_terrain",true)
 var points:=PackedVector3Array([
  Vector3(-12,-1,-4),Vector3(12,-1,-4),Vector3(12,-1,4),Vector3(-12,-1,4),
  Vector3(-10,3.6,-1.5),Vector3(10,3.6,-1.5),Vector3(10,3.6,1.5),Vector3(-10,3.6,1.5)])
 var collider:=CollisionShape3D.new()
 var shape:=ConvexPolygonShape3D.new()
 shape.points=points
 collider.shape=shape
 body.add_child(collider)
 var st:=SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for face in [[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7],[3,2,1,0]]:
  for index in [face[0],face[2],face[1],face[0],face[3],face[2]]:st.add_vertex(points[index])
 st.generate_normals()
 var mesh:=MeshInstance3D.new()
 mesh.mesh=st.commit()
 var material:=StandardMaterial3D.new()
 material.albedo_color=Color(.34,.29,.20)
 material.roughness=1.0
 material.cull_mode=BaseMaterial3D.CULL_DISABLED
 mesh.material_override=material
 body.add_child(mesh)
 main.stage.add_child(body)
 body.global_position=center
 return body
