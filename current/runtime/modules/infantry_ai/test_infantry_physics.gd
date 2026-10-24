extends SceneTree
const Actor = preload("res://modules/infantry_ai/infantry_actor.gd")
var shots: Array = []
var source: CharacterBody3D
var enemy: StaticBody3D
var wall: StaticBody3D
var world: Node3D
var failures := 0
func infantry_candidates(_id: String) -> Array:
 return [{"actor_id":"enemy","team_id":"enemy","alive":true,"position":Vector3(0,1.1,-5)}]
func infantry_visibility(_a: String,_b: String) -> float: return 1.0
func infantry_apply_hit(event: Dictionary) -> void: shots.append(event)
func _init() -> void: call_deferred("run")
func body(parent: Node, pos: Vector3,size: Vector3, layer: int) -> StaticBody3D:
 var node := StaticBody3D.new()
 node.position = pos
 node.collision_layer = layer
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = size
 shape.shape = box
 node.add_child(shape)
 parent.add_child(node)
 return node
func check(ok: bool,label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func run() -> void:
 world = Node3D.new()
 root.add_child(world)
 body(world,Vector3(0,-0.5,0),Vector3(30,1,30),8)
 enemy = body(world,Vector3(0,1,-5),Vector3(1,2,1),128)
 enemy.set_meta("actor_id","enemy")
 wall = body(world,Vector3(0,1,-2),Vector3(20,2,0.5),8)
 source = CharacterBody3D.new()
 source.set_script(Actor)
 var bridge := Node.new()
 bridge.set_script(load("res://modules/infantry_ai/test_physics_bridge.gd"))
 bridge.test = self
 world.add_child(bridge)
 source.configure("friendly","friendly",bridge)
 world.add_child(source)
 var visual = load("res://assets/user_derived/models/user_rifleman_armed.glb").instantiate()
 source.add_child(visual)
 visual.name="InfantryVisual"
 source.bind_weapon_geometry(visual.find_child("Rifle",true,false),visual.find_child("Muzzle",true,false))
 for i in 10: await physics_frame
 check(source._observations().is_empty(),"real wall blocks observation")
 source.brain.patrol_points = [Vector3(0,0,-6)]
 for i in 90: await physics_frame
 check(source.global_position.z > -1.6,"CharacterBody cannot cross solid wall")
 check(shots.is_empty(),"no damage through wall")
 source.brain.patrol_points.clear()
 source.position = Vector3.ZERO # Fixture reset only, never runtime movement.
 wall.queue_free()
 for i in 120: await physics_frame
 check(not shots.is_empty(),"unobstructed autonomous shot reaches actual actor")
 if not shots.is_empty():
  check(shots[0].hit_actor_id=="enemy" and shots[0].hit.collider==enemy,"damage event contains collider and actor ID")
  check(shots[-1].origin.distance_to(source.muzzle.global_position)<0.001,"shot origin is actual authored Rifle Muzzle")
  check(shots[-1].direction.dot(-source.muzzle.global_basis.z.normalized())>0.999,"shot direction is actual muzzle minus-Z axis")
 check(source.body_part_at(source.to_global(Vector3(0,1.5,0)))=="head","head derived from collision position")
 check(source.body_part_at(source.to_global(Vector3(0,1.0,0)))=="torso","torso derived from collision position")
 check(source.body_part_at(source.to_global(Vector3(-0.24,1,0)))=="left_arm","left arm derived from collision position")
 check(source.body_part_at(source.to_global(Vector3(0.24,1,0)))=="right_arm","right arm derived from collision position")
 check(source.body_part_at(source.to_global(Vector3(-0.1,0.3,0)))=="left_leg","left leg derived from collision position")
 check(source.body_part_at(source.to_global(Vector3(0.1,0.3,0)))=="right_leg","right leg derived from collision position")
 var at_visual = load("res://assets/reused_combat/panzerfaust.glb").instantiate()
 source.add_child(at_visual)
 at_visual.position=Vector3(0.25,1.05,-0.2)
 var at_muzzle := Marker3D.new()
 at_muzzle.position=Vector3(0,0,-0.55)
 at_visual.add_child(at_muzzle)
 source.bind_weapon_geometry(at_visual,at_muzzle)
 source.aim_visible_weapon(enemy.global_position)
 source._shoot("enemy",enemy.global_position)
 check(shots[-1].origin.distance_to(at_muzzle.global_position)<0.001,"AT shot uses actual attached weapon muzzle")
 check(shots[-1].direction.dot(-at_muzzle.global_basis.z.normalized())>0.999,"AT shot uses attached minus-Z axis")
 source.receive_damage(100)
 source.update_visual_pose(0.6)
 check(visual.rotation.z>1.0 and visual.scale.y<0.8,"disabled visual visibly slumps without changing actor transform")
 var count := shots.size()
 for i in 90: await physics_frame
 check(shots.size()==count,"disabled actor stops shot events")
 var high := PhysicsRayQueryParameters3D.create(source.global_position+Vector3(0,1.1,1),source.global_position+Vector3(0,1.1,-1),128)
 var low := PhysicsRayQueryParameters3D.create(source.global_position+Vector3(0,0.28,1),source.global_position+Vector3(0,0.28,-1),128)
 check(world.get_world_3d().direct_space_state.intersect_ray(high).is_empty(),"ray passes above downed body proxy")
 var low_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(low)
 check(not low_hit.is_empty() and low_hit.collider==source,"downed body still blocks low ray")
 print("INFANTRY_PHYSICS_FAILURES=",failures)
 world.queue_free()
 quit(1 if failures else 0)
