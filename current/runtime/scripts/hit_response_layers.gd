extends RefCounted
const MARK=preload("res://scripts/hit_mark.gdshader")
const COUNT:=6
static func warm(parent:Node3D)->Dictionary:
 var mark:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2.ONE;mark.mesh=quad
 var material:=ShaderMaterial.new();material.shader=MARK;mark.material_override=material
 parent.add_child(mark);mark.hide();mark.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var sparks:Array[MeshInstance3D]=[];var mesh:=BoxMesh.new();mesh.size=Vector3(.025,.025,.18)
 for i in range(COUNT):
  var node:=MeshInstance3D.new();node.mesh=mesh;var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;node.material_override=mat
  parent.add_child(node);node.hide();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;sparks.append(node)
 return {"mark":mark,"jets":sparks}
static func axes(normal:Vector3)->Basis:
 var z:=normal.normalized();var helper:=Vector3.UP if absf(z.dot(Vector3.UP))<.95 else Vector3.RIGHT
 var x:=helper.cross(z).normalized();return Basis(x,z.cross(x).normalized(),z)
static func update(e:Dictionary,load_count:int=0)->void:
 var info:Dictionary=e.get("feedback",{});var normal:Vector3=info.get("normal",Vector3.ZERO)
 var camera:Camera3D=e.root.get_viewport().get_camera_3d()
 var distance:float=0.0 if camera==null else camera.global_position.distance_to(e.end)
 var visual:Dictionary=e.get("visual",{})
 var budget:int=2 if bool(visual.get("low",false)) or distance>65 or load_count>12 else COUNT
 var t:float=e.impact_age;var active:bool=e.contact and e.impact_started and normal.length_squared()>.01
 var basis:=axes(normal) if active else Basis.IDENTITY
 var surface:=str(info.get("surface",e.surface));var metal:=surface=="metal"
 var outcome:=str(info.get("outcome","unknown"))
 var sensor:Callable=e.get("point_visibility",Callable())
 var mark:MeshInstance3D=e.response.mark
 mark.visible=active and distance<80 and load_count<16 and t>.025 and t<2.5
 if mark.visible:
  var point:Vector3=e.end+normal*.018
  var collider=info.get("collider")
  if is_instance_valid(collider) and collider is Node3D:
   point=collider.to_global(info.local_point);normal=(collider.global_basis.inverse().transposed()*info.local_normal).normalized();basis=axes(normal);point+=normal*.018
  elif info.has("local_point"):mark.hide()
  mark.global_transform=Transform3D(basis,point)
  mark.scale=Vector3.ONE*(.10 if e.mg else .22 if outcome=="penetrated" else .4)
  mark.material_override.set_shader_parameter("confirmed_penetration",outcome=="penetrated")
  mark.material_override.set_shader_parameter("opacity",1.0-smoothstep(1.7,2.5,t))
  if sensor.is_valid():mark.visible=mark.visible and bool(sensor.call(point))
 var direction:Vector3=info.get("direction",e.direction)
 for i in range(COUNT):
  var node:MeshInstance3D=e.response.jets[i]
  node.visible=active and t<(.18 if e.mg else .32) and i<mini(budget,6 if metal else 3)
  if not node.visible:continue
  var a:=float(i)*2.399963;var radial:Vector3=basis.x*cos(a)+basis.y*sin(a)
  var jet:Vector3=(normal*(2.5 if metal else 1.5)+radial*(2.2 if outcome=="stopped" else 1.2))
  node.global_position=e.end+normal*.025+jet*t+Vector3.DOWN*t*t*2.0
  node.scale=Vector3(1,1,1.0+3.0*(1.0-t/.32))*(.6 if e.mg else 1.0)
  if jet.length_squared()>.001:node.global_basis=axes(jet)
  var mat:StandardMaterial3D=node.material_override
  mat.albedo_color=Color(1,.67,.18) if metal else Color(.48,.39,.27) if surface in ["ground","wood"] else Color(.58,.57,.53)
  mat.emission_enabled=metal;mat.emission=Color(1,.37,.04)
  if sensor.is_valid():node.visible=bool(sensor.call(node.global_position))
