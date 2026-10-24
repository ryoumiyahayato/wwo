extends Node
## Optional existing-game host adapter. Main retains driving, aim and map authority.
const Controller=preload("res://modules/mlrs/salvo_controller.gd")
var host
var controller
var token:=-1
var ordinal:=0
var stage_generation:=-1
var input_epoch:=-1
var last_commit:=-1
var records:Dictionary={}
func attach(main,model:Node3D,rails:Array[Node3D])->bool:
 host=main;stage_generation=int(main.stage_generation)
 controller=Controller.new();add_child(controller)
 var excluded:Array[RID]=[]
 for body in main.hero.find_children("*","CollisionObject3D",true,false):excluded.append(body.get_rid())
 if not controller.configure(model,main.stage,rails,_commit,_allowed,excluded,Callable(main,"effect_point_visible"),Callable(main,"indirect_surface_height")):return false
 controller.launched.connect(_launched);controller.impact.connect(_impact);controller.expired.connect(_expired);controller.cancelled.connect(_cancelled)
 return true
static func loadout()->Dictionary:
 return {"primary":{"kind":"burst","rounds":{"he":8},"initial":"he"}}
func begin(speed:float,spread_degrees:float=0.0)->bool:
 if not is_instance_valid(host) or not _stage_valid() or not controller.queue.is_empty():return false
 input_epoch=int(host.fire_input_epoch)
 var begun:Dictionary=host.vehicle_ammo.begin_burst(host.PLAYER_VEHICLE_ID,"primary")
 if not bool(begun.get("ok",false)):return false
 token=int(begun.token);ordinal=0
 if not controller.begin_salvo(speed,spread_degrees):_cancelled("queue_denied");return false
 return true
func _stage_valid()->bool:
 return is_instance_valid(host) and int(host.stage_generation)==stage_generation and not host.garage and not host.battle_finished
func _allowed()->bool:
 return _stage_valid() and int(host.fire_input_epoch)==input_epoch and host.player_can_fire()
func _commit(_rail:int)->bool:
 if not _allowed():return false
 var result:Dictionary=host.vehicle_ammo.commit_burst_round(host.PLAYER_VEHICLE_ID,"primary",token,ordinal,7.0,true,true)
 if not bool(result.get("ok",false)):return false
 last_commit=int(result.commit);ordinal+=1;return true
func _launched(event:Dictionary):
 host.shot_sequence+=1
 var visual_weapon:Dictionary={"weapon_id":"mlrs_prototype","game_visual_tier":"medium","mount_id":"rail_%d"%int(event.rail)}
 records[int(event.shot)]={"commit":last_commit,"shot":int(host.shot_sequence),"visual_weapon":visual_weapon.duplicate(true)}
 host.shot_audit.append({"id":host.shot_sequence,"accepted":true,"weapon":"mlrs","ammo_commit":last_commit,"rail":event.rail,"origin":event.origin,"direction":event.direction,"base_direction":event.base_direction,"jitter_radians":event.jitter_radians,"visual_weapon":visual_weapon.duplicate(true),"flight_state":"flying"})
 if host.shot_audit.size()>128:host.shot_audit.pop_front()
 host.spawn_combat_vfx("muzzle_pulse",event.origin,event.direction,visual_weapon.duplicate(true))
 host.refresh_hud()
 if controller.queue.is_empty():_cancelled("completed")
func _impact(event:Dictionary):
 if not _stage_valid() or not records.has(int(event.shot)):return
 var record:Dictionary=records[int(event.shot)];records.erase(int(event.shot))
 # Existing game's short-rocket blast rule, never pre-settle at selected point.
 if bool(event.get("terrain_sample",false)):
  var at:Vector3=event.position
  if host.effect_point_visible(at):host.spawn_combat_vfx("impact_explosion",at,Vector3.FORWARD,record.visual_weapon.duplicate(true))
  if host.game_mode=="skirmish" and is_instance_valid(host.ai_host):host.ai_host.apply_player_blast(at)
  else:host.combat.high_explosive("infantry" if host.target_infantry else "armor",at.distance_to(host.target.global_position+Vector3.UP),host.blast_occluded(at))
  host.explode_terrain(at,preload("res://scripts/ammo_profiles.gd").explosive_mass("short_rocket"))
 else:host._on_rocket_impact(event,stage_generation,int(record.commit),record.visual_weapon.duplicate(true))
 for row in host.shot_audit:
  if int(row.get("id",-1))==int(record.shot):row["flight_state"]="impacted";row["flight_seconds"]=event.flight_seconds;row["impact"]=event.position
func _expired(event:Dictionary):
 if not records.has(int(event.shot)):return
 var record:Dictionary=records[int(event.shot)];records.erase(int(event.shot))
 if not _stage_valid():return
 for row in host.shot_audit:
  if int(row.get("id",-1))==int(record.shot):row["flight_state"]="expired"
func _cancelled(_reason:String):
 if _stage_valid() and token>=0:host.vehicle_ammo.cancel_burst(host.PLAYER_VEHICLE_ID,"primary",token)
 token=-1
func _exit_tree():
 _cancelled("adapter_removed")
 if is_instance_valid(controller):controller.reset_generation()
