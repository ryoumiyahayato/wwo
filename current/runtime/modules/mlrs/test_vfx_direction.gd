extends SceneTree
var checks:=0
var failures:=0
class FakeController extends Node:
 var queue:Array=[1]
 func reset_generation():pass
class Host extends Node:
 var stage_generation:=4
 var garage:=false
 var battle_finished:=false
 var shot_sequence:=0
 var shot_audit:Array=[]
 var effects:Array=[]
 var impacts:Array=[]
 func spawn_combat_vfx(effect,at,direction,descriptor):
  effects.append(descriptor.duplicate(true));descriptor.mount_id="mutated_by_renderer"
 func refresh_hud():pass
 func _on_rocket_impact(event,generation,commit,descriptor):impacts.append(descriptor.duplicate(true))
func check(ok:bool,label:String):
 checks+=1;print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var host:=Host.new();root.add_child(host)
 var adapter=load("res://modules/mlrs/host_adapter.gd").new();host.add_child(adapter);adapter.host=host;adapter.stage_generation=4
 adapter.controller=FakeController.new();adapter.add_child(adapter.controller)
 for i in range(8):
  adapter._launched({"shot":i,"rail":i,"origin":Vector3(i,1,0),"direction":Vector3.FORWARD,"base_direction":Vector3.FORWARD,"jitter_radians":Vector2.ZERO})
 for i in range(8):
  host.shot_audit[i].visual_weapon.mount_id="changed_later"
  adapter._impact({"shot":i,"position":Vector3.ZERO,"flight_seconds":1.0})
  check(host.impacts[i].mount_id=="rail_%d"%i,"rail %d descriptor survives renderer and audit mutation"%i)
 check(host.impacts.all(func(d):return d.weapon_id=="mlrs_prototype" and d.game_visual_tier=="medium" and not d.has("caliber_mm")),"fictional visual tier only, no invented caliber")
 var model=load("res://modules/mlrs/launcher_visual.gd").new();root.add_child(model);await process_frame
 var minimum_dot:=1.0
 for yaw in [0.0,1.2,PI]:
  model.rotation.y=yaw
  for mount_yaw in [-8.0,0.0,8.0]:
   for pitch in [20.0,35.0,65.0]:
    model.set_angles(deg_to_rad(mount_yaw),deg_to_rad(pitch))
    var drive_forward:=Vector3(-sin(yaw),0,-cos(yaw))
    var coherent:=true
    for rail in model.rails:
     var direction:Vector3=-rail.global_basis.z.normalized()
     var planar:=Vector3(direction.x,0,direction.z).normalized()
     minimum_dot=minf(minimum_dot,drive_forward.dot(planar))
     coherent=coherent and drive_forward.dot(planar)>.99 and direction.y>0
    check(coherent,"8 rail axes forward/up hull yaw %.2f rack %.0f pitch %.0f"%[yaw,mount_yaw,pitch])
 print("DIRECTION_EVIDENCE ",JSON.stringify({"sampled_rail_axes":216,"minimum_horizontal_forward_dot":minimum_dot,"drive_source":"scripts/mobile_battle.gd:379 negative sin/cos yaw","chassis_front_wheels_z":-2.55,"rear_wheels_z":2.65}))
 print("MLRS_VFX_DIRECTION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 host.queue_free();model.queue_free();await process_frame;quit(1 if failures else 0)
