extends "res://modules/artillery/artillery_shell.gd"
## Uses existing game trajectory and swept collision. No homing or real rocket data.
var exhaust:MeshInstance3D
func _ready():
 set_physics_process(false)
 visual=Node3D.new();add_child(visual)
 visual_mesh=MeshInstance3D.new();visual_mesh.name="RocketBody";visual.add_child(visual_mesh)
 for segments in [12,6]:
  var mesh:=CylinderMesh.new();mesh.top_radius=0.025;mesh.bottom_radius=.09;mesh.height=.85;mesh.radial_segments=segments;mesh.rings=1;visual_lods.append(mesh)
 visual_mesh.rotation.x=PI/2
 var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.45,.46,.3);mat.roughness=.75;visual_mesh.material_override=mat
 exhaust=MeshInstance3D.new();var cone:=CylinderMesh.new();cone.top_radius=.05;cone.bottom_radius=0;cone.height=.4;cone.radial_segments=6;exhaust.mesh=cone;exhaust.rotation.x=PI/2;exhaust.position.z=.6
 var glow:=StandardMaterial3D.new();glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;glow.albedo_color=Color(1,.5,.15);exhaust.material_override=glow;visual.add_child(exhaust)
 update_visual()
func update_visual():
 super.update_visual()
 if is_instance_valid(exhaust):exhaust.visible=age<.7
