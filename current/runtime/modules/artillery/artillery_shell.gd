extends Node3D
## Game-only kinematic projectile; authoritative collision occurs during elapsed flight.
signal impacted(event:Dictionary)
signal expired(event:Dictionary)
const Arc=preload("res://modules/artillery/arc_solution.gd")
const MAX_LIFETIME:=36.0
const MAX_DISTANCE:=9000.0
const MAX_STEP:=1.0/60.0
# Per-flight game settings retain the existing indirect-fire defaults.
var gravity:=Arc.GRAVITY
var lifetime_limit:=MAX_LIFETIME
var horizontal_limit:=MAX_DISTANCE
var visual_kind:="artillery"
var visual:Node3D
var visual_mesh:MeshInstance3D
var visual_lods:Array=[]
var visual_level:=-1
var velocity:=Vector3.ZERO
var origin:=Vector3.ZERO
var age:=0.0
var distance:=0.0
var configured:=false
var ended:=false
var exclusions:Array[RID]=[]
var sensor:Callable
var height_sampler:Callable
func setup(pose:Transform3D,speed:float,owner_exclusions:Array[RID],visibility:Callable=Callable(),height:Callable=Callable()) -> bool:
 if not is_finite(gravity) or gravity<0 or not is_finite(lifetime_limit) or lifetime_limit<=0 or lifetime_limit>MAX_LIFETIME or not is_finite(horizontal_limit) or horizontal_limit<=0:return false
 if configured or not pose.origin.is_finite() or not is_finite(speed) or speed<Arc.MIN_SPEED or speed>Arc.MAX_SPEED:return false
 var axis:Vector3=-pose.basis.z.normalized()
 if not axis.is_finite() or axis.length_squared()<.9:return false
 configured=true;origin=pose.origin;velocity=axis*speed
 exclusions=owner_exclusions.duplicate();sensor=visibility;height_sampler=height
 set_as_top_level(true);global_transform=pose
 add_to_group("artillery_projectile")
 set_physics_process(true)
 if sensor.is_valid():visible=bool(sensor.call(global_position))
 update_visual()
 return true
func _ready():
 set_physics_process(false)
 var path:="res://assets/artillery_shell/%s_shell_lod0.glb"%visual_kind
 if ResourceLoader.exists(path):
  visual=load(path).instantiate();add_child(visual)
  visual_mesh=visual.get_node_or_null("Projectile/ShellMesh")
  for level in range(2):
   var source:Node=load("res://assets/artillery_shell/%s_shell_lod%d.glb"%[visual_kind,level]).instantiate()
   visual_lods.append(source.get_node("Projectile/ShellMesh").mesh);source.free()
  update_visual()
func update_visual():
 if not is_instance_valid(visual):return
 if velocity.length_squared()>.001:
  var axis:=velocity.normalized()
  look_at(global_position+axis,Vector3.RIGHT if absf(axis.dot(Vector3.UP))>.99 else Vector3.UP)
 var camera:=get_viewport().get_camera_3d()
 var level:=1 if camera!=null and global_position.distance_squared_to(camera.global_position)>2500 else 0
 if level!=visual_level and is_instance_valid(visual_mesh):visual_mesh.mesh=visual_lods[level];visual_level=level
func _physics_process(delta:float):
 if not configured or ended or delta<=0:return
 var remaining:float=minf(delta,lifetime_limit-age)
 # Bounded substeps prevent high-frame-time tunnelling without tracing a full future arc.
 while remaining>.000001 and not ended:
  var step:=minf(remaining,MAX_STEP)
  var horizontal_speed:=Vector2(velocity.x,velocity.z).length()
  if horizontal_speed>.000001:
   var horizontal_left:=horizontal_limit-Vector2(global_position.x-origin.x,global_position.z-origin.z).length()
   step=minf(step,maxf(0,horizontal_left)/horizontal_speed)
  if step<=.000001:break
  var start:=global_position
  var next:=start+velocity*step+Vector3.DOWN*gravity*step*step*.5
  var hit:Dictionary=preload("res://modules/artillery/arc_collision.gd").segment(get_world_3d().direct_space_state,start,next,exclusions,height_sampler)
  if not hit.is_empty():
   var fraction:float=clampf(start.distance_to(hit.position)/maxf(start.distance_to(next),.000001),0,1)
   age+=step*fraction;distance+=start.distance_to(hit.position)
   velocity+=Vector3.DOWN*gravity*step*fraction
   global_position=hit.position;ended=true;set_physics_process(false)
   hit["origin"]=origin;hit["direction"]=velocity.normalized();hit["flight_seconds"]=age
   impacted.emit(hit);queue_free();return
  global_position=next;velocity+=Vector3.DOWN*gravity*step;age+=step;distance+=start.distance_to(next)
  remaining-=step
  if _outside_limits():break
 update_visual()
 if sensor.is_valid():visible=bool(sensor.call(global_position))
 if _outside_limits():
  ended=true;set_physics_process(false);expired.emit({"origin":origin,"position":global_position,"flight_seconds":age});queue_free()

func _outside_limits()->bool:
 return age>=lifetime_limit-.00001 or distance>=MAX_DISTANCE or Vector2(global_position.x-origin.x,global_position.z-origin.z).length()>=horizontal_limit-.0001 or absf(global_position.x)>2500 or absf(global_position.z)>2500
