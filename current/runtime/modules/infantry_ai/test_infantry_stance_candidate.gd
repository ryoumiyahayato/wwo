extends SceneTree
const Actor = preload("res://reports/infantry_stance_candidate/infantry_actor.candidate.gd")
const Stance = preload("res://modules/infantry_ai/infantry_stance.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
 checks += 1
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func block(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
 var body := StaticBody3D.new()
 body.collision_layer = 8
 var collider := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = size
 collider.shape = box
 body.add_child(collider)
 parent.add_child(body)
 body.position = at
 return body
func settle(actor: Node3D, frames := 20) -> void:
 for i in frames:
  actor._advance_stance(1.0/30.0)
  actor.update_visual_pose(1.0/30.0)
  await physics_frame
func mesh_floor(visual: Node3D) -> float:
 var lowest := INF
 for node in visual.find_children("*", "MeshInstance3D",true,false):
  var box: AABB = node.get_aabb()
  for i in 8: lowest = minf(lowest,(node.global_transform*box.get_endpoint(i)).y)
 return lowest
func run() -> void:
 var world := Node3D.new()
 root.add_child(world)
 block(world,Vector3(0,-0.5,0),Vector3(30,1,30))
 var actor := CharacterBody3D.new()
 actor.set_script(Actor)
 actor.configure("stance_fixture","blue",null)
 world.add_child(actor)
 actor.set_physics_process(false)
 actor.set_process(false)
 actor.position.y = 0.002
 var visual = load("res://assets/user_derived/models/user_rifleman_armed.glb").instantiate()
 visual.name = "InfantryVisual"
 actor.add_child(visual)
 actor.bind_weapon_geometry(visual.find_child("Rifle",true,false),visual.find_child("Muzzle",true,false))
 actor.update_visual_pose(0.0)
 await physics_frame
 var original_muzzle = actor.muzzle
 var original_weapon = actor.weapon_pivot
 check(actor.request_sprint(true) and actor.locomotion_speed()>actor.move_speed,"explicit standing sprint changes speed")
 actor.request_sprint(false)
 check(not actor.request_stance("invalid"),"unknown stance rejected")
 check(actor.request_stance("crouch"),"crouch accepted in free space")
 var lowest := INF
 for i in 20:
  await settle(actor,1)
  lowest = minf(lowest,mesh_floor(visual))
 check(lowest>=-0.035,"crouch transition mesh bounds stay above ground: %.4f"%lowest)
 check(not actor.request_sprint(true),"crouch refuses sprint")
 check(actor.locomotion_speed()<actor.move_speed,"crouch changes real locomotion speed")
 check(actor.aim_height<1.1,"crouch lowers observer and target height")
 check(actor.get_node("BodyCollision").shape.size.y<1.4,"crouch changes physical body height")
 var roof := block(world,Vector3(0,1.48,0),Vector3(3,0.2,3))
 await physics_frame
 check(not actor.request_stance("stand"),"ceiling blocks standing before geometry grows")
 roof.queue_free()
 await physics_frame
 check(actor.request_stance("prone"),"prone accepted on supported flat floor")
 lowest = INF
 for i in 20:
  await settle(actor,1)
  lowest = minf(lowest,mesh_floor(visual))
 check(lowest>=-0.035,"prone transition mesh bounds stay above ground: %.4f"%lowest)
 check(actor.get_node("BodyCollision").shape.size.z>=1.8,"prone has a real fore-aft collision volume")
 check(actor.aim_height<0.6 and actor.locomotion_speed()<0.5,"prone lowers sight and crawl speed together")
 var head = visual.find_child("*Head",true,false)
 check(actor.body_part_at(head.global_position)=="head","prone head hit follows articulated head instead of standing height")
 check(actor.muzzle==original_muzzle and actor.weapon_pivot==original_weapon,"weapon and muzzle identity preserved across stances")
 check(actor.muzzle.global_position.y>0.1 and actor.muzzle.global_position.y<0.8,"real muzzle follows prone pose above floor")
 var wall := block(world,Vector3(0,0.4,-1.3),Vector3(3,0.8,0.3))
 await physics_frame
 check(actor._path_blocked(Vector3.FORWARD,0.6),"prone collision detects front wall")
 wall.queue_free()
 await physics_frame
 check(actor.request_stance("stand"),"standing accepted after removing ceiling")
 await settle(actor)
 check(actor.aim_height>=1.1 and actor.locomotion_speed()==actor.move_speed,"standing restores speed and sight")
 # Expansion is checked again if a ceiling arrives during the transition.
 check(actor.request_stance("crouch"),"repeat crouch accepted")
 await settle(actor)
 check(actor.request_stance("stand"),"start rise in clear space")
 roof = block(world,Vector3(0,1.48,0),Vector3(3,0.2,3))
 await physics_frame
 await settle(actor)
 check(actor._stance_elapsed<Stance.TRANSITION_SECONDS,"new obstacle pauses growth instead of clipping")
 roof.queue_free()
 await physics_frame
 await settle(actor)
 check(actor._stance_elapsed==Stance.TRANSITION_SECONDS,"interrupted transition resumes once clear")
 actor.position = Vector3(14.7,0.002,0)
 actor.rotation.y = PI/2
 await physics_frame
 check(not actor.request_stance("prone"),"prone refused across unsupported ledge")
 print("INFANTRY_STANCE_CHECKS=",checks," FAILURES=",failures)
 world.queue_free()
 quit(1 if failures else 0)
