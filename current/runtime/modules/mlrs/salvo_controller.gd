extends Node
## Explicit finite queue. A host owns selected target, ammo commits and damage settlement.
signal launched(event:Dictionary)
signal impact(event:Dictionary)
signal expired(event:Dictionary)
signal cancelled(reason:String)
const Rocket=preload("res://modules/mlrs/rocket.gd")
const INTERVAL:=.22
const MAX_ACTIVE:=24
var launcher:Node3D
var world:Node3D
var muzzles:Array[Node3D]=[]
var available:Array[bool]=[]
var queue:Array[int]=[]
var active:Dictionary={}
var sequence:=0
var delay:=0.0
var speed:=55.0
var dispersion_degrees:=0.0
var rng:=RandomNumberGenerator.new()
var exclusions:Array[RID]=[]
var commit_round:Callable
var permit:Callable
var visibility:Callable
var height_sampler:Callable
var generation:=0
var audit:Array[Dictionary]=[]
func configure(owner_node:Node3D,stage:Node3D,rail_muzzles:Array[Node3D],commit:Callable,allowed:Callable,excluded:Array[RID]=[],sensor:Callable=Callable(),height:Callable=Callable())->bool:
 if not queue.is_empty() or not active.is_empty() or not is_instance_valid(owner_node) or not is_instance_valid(stage) or rail_muzzles.size()!=8:return false
 launcher=owner_node;world=stage;muzzles=rail_muzzles.duplicate();commit_round=commit;permit=allowed;exclusions=excluded.duplicate();visibility=sensor;height_sampler=height
 available.assign([true,true,true,true,true,true,true,true]);rng.seed=41021
 return true
func begin_salvo(launch_speed:float,spread:float=0)->bool:
 if not queue.is_empty() or not is_finite(launch_speed) or launch_speed<14 or launch_speed>180 or not is_finite(spread):return false
 if not permit.is_valid() or not bool(permit.call()):return false
 speed=launch_speed;dispersion_degrees=clampf(spread,0,2)
 for i in range(available.size()):
  if available[i]:queue.append(i)
 delay=0
 return not queue.is_empty()
func cancel(reason:String="cancelled"):
 queue.clear();delay=0;cancelled.emit(reason)
func reset_generation():
 cancel("stage_changed");generation+=1
 for rocket in active.values():
  if is_instance_valid(rocket):rocket.queue_free()
 active.clear()
func _physics_process(delta:float):
 if queue.is_empty():return
 if not is_instance_valid(launcher) or not is_instance_valid(world) or not permit.is_valid() or not bool(permit.call()):cancel("owner_unavailable");return
 delay-=maxf(delta,0)
 if delay>0:return
 # Never burst multiple rounds after a long frame. Backpressure leaves rounds loaded.
 if active.size()>=MAX_ACTIVE or get_tree().get_nodes_in_group("mlrs_projectile").size()>=MAX_ACTIVE:return
 var index:int=queue[0]
 var muzzle:Node3D=muzzles[index]
 if not is_instance_valid(muzzle) or not muzzle.is_inside_tree():cancel("muzzle_unavailable");return
 var pose:=muzzle.global_transform.orthonormalized()
 if not pose.origin.is_finite() or not pose.basis.is_finite() or (-pose.basis.z).length_squared()<.9:cancel("invalid_transform");return
 var base_direction:Vector3=-pose.basis.z
 var jitter:=Vector2.ZERO
 if dispersion_degrees>0:
  jitter=Vector2(rng.randf_range(-1,1),rng.randf_range(-1,1))*deg_to_rad(dispersion_degrees)
  pose.basis=pose.basis*Basis(Vector3.UP,jitter.x)*Basis(Vector3.RIGHT,jitter.y)
 if not commit_round.is_valid() or not bool(commit_round.call(index)):cancel("ammo_denied");return
 var rocket:=Rocket.new();world.add_child(rocket)
 if not rocket.setup(pose,speed,exclusions,visibility,height_sampler):
  rocket.queue_free();cancel("setup_failed");return
 sequence+=1;var shot:=sequence;var epoch:=generation
 rocket.add_to_group("mlrs_projectile");active[shot]=rocket
 rocket.impacted.connect(_settle.bind(shot,epoch,true));rocket.expired.connect(_settle.bind(shot,epoch,false))
 rocket.tree_exiting.connect(_forget.bind(shot,epoch))
 queue.pop_front();available[index]=false;delay=INTERVAL
 if launcher.has_method("set_loaded"):launcher.set_loaded(index,false)
 var event:Dictionary={"shot":shot,"rail":index,"origin":pose.origin,"base_direction":base_direction,"direction":-pose.basis.z,"jitter_radians":jitter,"speed":speed,"generation":epoch}
 audit.append(event);if audit.size()>128:audit.pop_front()
 launched.emit(event)
func _settle(event:Dictionary,shot:int,epoch:int,hit:bool):
 if epoch!=generation or not active.has(shot):return
 active.erase(shot);event["shot"]=shot;event["generation"]=epoch
 if hit:impact.emit(event)
 else:expired.emit(event)
func _forget(shot:int,epoch:int):
 if epoch==generation:active.erase(shot)
