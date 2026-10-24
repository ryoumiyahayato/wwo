extends SceneTree
const Host=preload("res://modules/infantry_ai/skirmish_host.gd")
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var world=load("res://modules/infantry_ai/loot_fixture.gd").new()
 root.add_child(world)
 var host=Host.new()
 world.add_child(host)
 host.setup(world)
 var person:={"hp":10.0,"alive":true,"ammo":2,"reserve_ammo":7,"parts":{}}
 var actor=host.register_bound_crew("crew_boundary",person,Vector3.ZERO,"driver")
 host.infantry_apply_hit({"hit_actor_id":"crew_boundary","actor_id":"enemy","team_id":"red","position":Vector3(0,1.1,0),"weapon":"rifle"})
 host.apply_actor_damage("crew_boundary",100,"enemy")
 host.handle_player_projectile({"collider":actor,"position":Vector3(0,1.1,0)},"mg","")
 host.apply_player_blast(Vector3.ZERO)
 actor.receive_damage(100)
 actor.receive_suppression(1.5,"blast")
 check(person.hp==10.0 and person.alive,"all exposed infantry callbacks protect shared seated person")
 check(actor.suppression_level==0.0 and person.ammo==2,"seated suppression and ammo remain unchanged")
 host.set_crew_embarked("crew_boundary",false,Vector3.ZERO)
 actor.receive_damage(2)
 check(person.hp==8.0,"same canonical person receives damage after legitimate exit")
 print("EMBARKED_CALLBACK_FAILURES=",failures)
 world.queue_free()
 quit(1 if failures else 0)
