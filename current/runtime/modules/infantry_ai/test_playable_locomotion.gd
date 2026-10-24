extends SceneTree
const Actor = preload("res://modules/infantry_ai/infantry_actor.gd")
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func run():
 var world := Node3D.new()
 root.add_child(world)
 var floor_body := StaticBody3D.new()
 floor_body.collision_layer = 8
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = Vector3(30,1,30)
 shape.shape = box
 floor_body.add_child(shape)
 floor_body.position.y = -0.5
 world.add_child(floor_body)
 var actor := CharacterBody3D.new()
 actor.set_script(Actor)
 actor.configure("walking_fixture","blue",null)
 actor.brain.patrol_points = [Vector3(5,0,0),Vector3(-5,0,0)]
 world.add_child(actor)
 var visual = load("res://assets/user_derived/models/user_rifleman_armed.glb").instantiate()
 visual.name = "InfantryVisual"
 actor.add_child(visual)
 actor.bind_weapon_geometry(visual.find_child("Rifle",true,false),visual.find_child("Muzzle",true,false))
 var thigh = visual.find_child("*Thigh_L",true,false)
 var origin: Vector3 = actor.global_position
 var low := 99.0
 var high := -99.0
 for i in 120:
  await physics_frame
  low = minf(low,thigh.rotation.x)
  high = maxf(high,thigh.rotation.x)
 check(actor.global_position.distance_to(origin)>2.0,"actual capsule moves metres, not tiny in-place oscillation")
 check(high-low>0.4,"articulated leg swings while real body moves")
 check(is_instance_valid(actor.muzzle) and actor.muzzle.is_visible_in_tree(),"authored visible rifle muzzle remains bound during walk")
 actor.receive_damage(100.0)
 for i in 90: await physics_frame
 var stop: Vector3 = actor.global_position
 for i in 30: await physics_frame
 check(actor.global_position.distance_to(stop)<0.01,"disabled actor remains still")
 check(visual.rotation.z>1.0 and not actor.weapon_pivot.visible,"disabled pose settles and hides gun")
 print("PLAYABLE_LOCOMOTION_FAILURES=",failures)
 world.queue_free()
 quit(1 if failures else 0)
