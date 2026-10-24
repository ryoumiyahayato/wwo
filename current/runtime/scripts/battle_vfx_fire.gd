extends Node3D
## One persistent visual per burning prop. Freed with the prop/stage.
const Layers=preload("res://scripts/battle_vfx_layers.gd")
var pieces:Array[MeshInstance3D]=[]
var elapsed:=0.0
func _ready():
 var quad:=QuadMesh.new();quad.size=Vector2.ONE
 for i in range(7):
  var node:=MeshInstance3D.new();node.mesh=quad
  node.material_override=Layers.material(Color(.2,.21,.22,.7) if i>3 else Color(.7,.26,.04,.88),float(i)*5.7)
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(node);pieces.append(node)
func _process(delta:float):
 elapsed+=maxf(0.0,delta)
 var camera:=get_viewport().get_camera_3d()
 var far:bool=camera!=null and camera.global_position.distance_to(global_position)>70.0
 for i in range(pieces.size()):
  var node:MeshInstance3D=pieces[i]
  node.visible=not far or i%2==0
  if not node.visible:continue
  var smoke:bool=i>3
  var life:float=2.3 if smoke else .65
  var phase:float=fmod(elapsed+float(i)*.27,life)/life
  var a:float=float(i)*2.4
  node.position=Vector3(cos(a)*.25+phase*.15, .65+phase*(2.1 if smoke else .9),sin(a)*.23)
  node.scale=Vector3.ONE*((.45+phase*1.1) if smoke else (.35+sin(phase*PI)*.48))
  node.material_override.set_shader_parameter("age",elapsed+float(i))
  node.material_override.set_shader_parameter("opacity",sin(phase*PI)*(.65 if smoke else 1.0))
  node.material_override.set_shader_parameter("heat",0.0 if smoke else 1.0-phase*.5)
