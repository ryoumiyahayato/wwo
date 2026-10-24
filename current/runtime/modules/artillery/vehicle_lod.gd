extends Node
# One authoritative node hierarchy. Only visual mesh resources switch.
var model:Node3D
var mesh_sets:Array=[]
var current:=-1
var timer:=0.0
const PATHS=["Root/Hull","Root/TracksLeft","Root/TracksRight","Root/Turret","Root/Turret/Barrel"]
func setup(root:Node3D):
 model=root
 for level in range(3):
  var source:Node=load("res://assets/artillery_open/artillery_open_lod%d.glb"%level).instantiate()
  var meshes:Dictionary={}
  for path in PATHS:
   var part=source.get_node_or_null(path)
   if part is MeshInstance3D:meshes[path]=part.mesh
  mesh_sets.append(meshes);source.free()
 set_level(0)
func set_level(level:int):
 if level==current or not is_instance_valid(model):return
 for path in mesh_sets[level]:
  var part=model.get_node_or_null(path)
  if part is MeshInstance3D:part.mesh=mesh_sets[level][path]
 current=level
func _process(delta:float):
 timer+=delta
 if timer<.25:return
 timer=0
 var camera:=get_viewport().get_camera_3d()
 if camera==null:return
 var distance:=camera.global_position.distance_to(model.global_position)
 set_level(2 if distance>160 else 1 if distance>60 else 0)
