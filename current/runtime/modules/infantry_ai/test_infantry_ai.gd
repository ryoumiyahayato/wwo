extends SceneTree
const Brain = preload("res://modules/infantry_ai/infantry_brain.gd")
const Actor = preload("res://modules/infantry_ai/infantry_actor.gd")
const Host = preload("res://modules/infantry_ai/infantry_host.gd")
var failures := 0
func check(value: bool, label: String) -> void:
 if not value:
  failures += 1
  push_error(label)
 else: print("PASS ",label)
func _init() -> void:
 var b = Brain.new()
 b.setup("friend","friendly")
 var hidden := [{"actor_id":"enemy","team_id":"enemy","alive":true,"position":Vector3(6,0,0),"visible":false}]
 check(not b.tick(0.1,Vector3.ZERO,hidden).fire and b.target_id == "", "hidden targets never acquired")
 var seen := hidden.duplicate(true)
 seen[0].visible = true
 check(not b.tick(0.1,Vector3.ZERO,seen).fire and b.state == "see_target", "reaction state before firing")
 b.tick(0.25,Vector3.ZERO,seen)
 check(not b.tick(0.1,Vector3.ZERO,seen).fire,"reaction window cannot finish early")
 check(b.tick(0.25,Vector3.ZERO,seen).fire,"visible target fires after reaction")
 check(not b.tick(0.1,Vector3.ZERO,seen).fire,"cooldown prevents next-frame fire")
 var old: Vector3 = b.last_known
 hidden[0].position = Vector3(99,0,0)
 var search: Dictionary = b.tick(0.1,Vector3.ZERO,hidden)
 check(b.state == "search" and search.destination == old and not search.fire,"lost LOS searches last known, not hidden position")
 for i in 30: b.tick(0.1,Vector3.ZERO,hidden)
 check(b.target_id == "" and b.state == "idle","search memory expires")
 b.receive_damage(2)
 check(b.state == "wounded" and not b.tick(0.1,Vector3.ZERO,seen).fire,"wounded temporarily stops")
 b.receive_damage(100)
 var dead: Dictionary = b.tick(0.25,Vector3.ZERO,seen)
 check(b.state == "disabled" and not dead.fire and not dead.move,"disabled never moves or fires")
 check(not b.order_build(Vector3.ZERO,"foxhole",true),"dead cannot build")
 var reloader = Brain.new()
 reloader.setup("reload_test","friendly")
 reloader.ammo = 0
 reloader.tick(0.1,Vector3.ZERO,seen)
 check(reloader.state=="reload","empty magazine enters reload")
 for i in 8: reloader.tick(0.25,Vector3.ZERO,seen)
 check(reloader.ammo==0,"reload cannot finish early")
 reloader.tick(0.2,Vector3.ZERO,seen)
 check(reloader.ammo==4,"reload restores bounded magazine")
 var c = Brain.new()
 c.setup("worker","friendly")
 check(not c.order_build(Vector3(3,0,0),"foxhole",false),"unapproved build rejected")
 c.target_id="old_enemy"
 c.memory_remaining=2.0
 check(c.order_build(Vector3(3,0,0),"foxhole",true),"approved build accepted")
 check(c.target_id=="" and c.memory_remaining==0.0,"build order clears old target pursuit")
 check(c.tick(0.1,Vector3.ZERO,[]).move,"builder walks to site")
 check(c.tick(0.1,Vector3(3,0,0),[]).build,"builder requests build only on arrival")
 check(not c.tick(0.1,Vector3(3,0,0),[]).build,"build request emitted once")
 var patrol = Brain.new()
 patrol.setup("walker","friendly")
 patrol.patrol_points = [Vector3(0,3,0),Vector3(5,3,0)]
 var moving: Dictionary = patrol.tick(0.1,Vector3(0,0,0),[])
 check(moving.move and moving.destination==Vector3(5,3,0),"patrol advances immediately despite terrain height difference")
 patrol.patrol_points = [Vector3(5,3,0)]
 var resting: Dictionary = patrol.tick(0.1,Vector3(5,0,0),[])
 check(not resting.move,"single arrived waypoint stops instead of tiny endless steps")
 var save: Dictionary = c.snapshot()
 check(c.restore(save),"brain snapshot restores")
 var actor := CharacterBody3D.new()
 actor.set_script(Actor)
 actor.configure("body_1","friendly",null)
 var limb := StaticBody3D.new()
 actor.add_child(limb)
 check(actor._collision_actor_id(limb)=="body_1","child collider resolves exact actor ID")
 var person := {"person_id":"body_1","hp":7.0,"ammo":2,"alive":true}
 actor.bind_person_state(person)
 actor.set_embarked(true)
 actor.receive_damage(2.0)
 person.hp = 4.0 # External vehicle damage while suspended.
 actor.set_embarked(false)
 check(actor.brain.hp==4.0 and person.hp==4.0 and actor.brain.ammo==2,"same person state persists across embark damage exit")
 check(not actor.embarked and actor.collision_layer==128,"exit restores actor collision")
 actor.free()
 print("INFANTRY_AI_FAILURES=",failures)
 quit(1 if failures else 0)
