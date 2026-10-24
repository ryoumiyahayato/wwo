extends Node3D
## Fictional 8-rail gameplay prototype. Not a historical BM-13 reconstruction.
var mount:Node3D
var rails:Array[Node3D]=[]
var loaded:Array[Node3D]=[]
var lods:Array[Node3D]=[]
var level:=0
func _ready():
 name="RocketLauncherPrototype"
 mount=Node3D.new();mount.name="Turret";mount.position=Vector3(0,2.2,1.5);add_child(mount)
 box(self,Vector3(1.5,.22,1.2),Vector3(0,1.35,1.5),Color(.2,.25,.15))
 for side in [-1,1]:box(self,Vector3(.15,.8,.18),Vector3(side*.7,1.75,1.5),Color(.2,.25,.15))
 var rack:=Node3D.new();rack.name="Barrel";mount.add_child(rack)
 for z in [-.8,.6]:box(rack,Vector3(1.7,.1,.12),Vector3(0,-.08,z),Color(.18,.23,.14))
 for l in range(3):
  var root:Node3D=load("res://assets/mlrs/chassis_lod%d.glb"%l).instantiate()
  root.name="VehicleLOD%d"%l;add_child(root);lods.append(root);root.visible=l==0
 for i in range(8):
  var x:float=(i%4-1.5)*.43
  var y:float=(i/4)*.28
  box(rack,Vector3(.08,.08,2.5),Vector3(x,y,0),Color(.17,.2,.14))
  var muzzle:=Node3D.new();muzzle.name="RailMuzzle%d"%i;muzzle.position=Vector3(x,y,-1.4);rack.add_child(muzzle);rails.append(muzzle)
  var round_view:=Node3D.new();round_view.name="LoadedRocket%d"%i;rack.add_child(round_view);loaded.append(round_view)
  var body:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=.025;cylinder.bottom_radius=.08;cylinder.height=1.1;cylinder.radial_segments=8;body.mesh=cylinder;body.rotation.x=PI/2;body.position=Vector3(x,y+.12,-.1)
  var paint:=StandardMaterial3D.new();paint.albedo_color=Color(.4,.43,.28);body.material_override=paint;round_view.add_child(body)
 var aim_origin:=Node3D.new();aim_origin.name="Muzzle";aim_origin.position=Vector3(0,.14,-1.4);rack.add_child(aim_origin)
 set_angles(0,deg_to_rad(35))
func box(parent:Node3D,size:Vector3,pos:Vector3,color:Color):
 var item:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;item.mesh=mesh;item.position=pos
 var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.9;item.material_override=mat;parent.add_child(item)
func set_angles(yaw:float,pitch:float):
 mount.rotation.y=clampf(yaw,deg_to_rad(-8),deg_to_rad(8))
 mount.get_node("Barrel").rotation.x=clampf(pitch,deg_to_rad(20),deg_to_rad(65))
func set_loaded(index:int,value:bool):
 if index>=0 and index<loaded.size():loaded[index].visible=value
func _process(_delta:float):
 var cam:=get_viewport().get_camera_3d()
 if cam==null:return
 var dist:=cam.global_position.distance_to(global_position)
 set_lod(0 if dist<35 else (1 if dist<90 else 2))
func set_lod(value:int):
 level=clampi(value,0,2)
 for i in range(lods.size()):lods[i].visible=i==level
