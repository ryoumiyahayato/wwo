extends SceneTree
const Brain = preload("res://modules/infantry_ai/infantry_brain.gd")
var failures := 0
func check(ok: bool, label: String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func item(id: String, kind: String, team: String, point: Vector3, visible := true) -> Dictionary:
 return {"actor_id":id,"actor_kind":kind,"team_id":team,"position":point,"alive":true,"visible":visible}
func _initialize():
 var brain := Brain.new()
 brain.setup("rocket_actor","blue")
 brain.prefer_vehicles = true
 var infantry := item("a_infantry","infantry","red",Vector3(6,0,0))
 var near_vehicle := item("z_vehicle","vehicle","red",Vector3(20,0,0))
 var remote := item("remote_vehicle","vehicle","red",Vector3(50,0,0))
 brain.tick(0.1,Vector3.ZERO,[infantry,near_vehicle])
 check(brain.target_id=="z_vehicle","visible nearby hostile vehicle takes explosive priority")
 brain.tick(0.1,Vector3.ZERO,[infantry,remote])
 check(brain.target_id=="a_infantry","remote vehicle does not prevent infantry fallback")
 near_vehicle.visible = false
 brain.tick(0.1,Vector3.ZERO,[infantry,near_vehicle])
 check(brain.target_id=="a_infantry","hidden nearby vehicle does not prevent legitimate fallback")
 var fort := item("fort_enemy","fortification","red",Vector3(10,0,0))
 var friendly := item("a_friend_fort","fortification","blue",Vector3(3,0,0))
 brain.tick(0.1,Vector3.ZERO,[fort,friendly,remote])
 check(brain.target_id=="fort_enemy","fallback can select hostile fortification, never own fort")
 fort.alive = false
 brain.memory_remaining = 0.0
 brain.tick(0.1,Vector3.ZERO,[fort,friendly])
 check(brain.target_id=="","destroyed and friendly fortifications are not targets")
 var world := Node3D.new()
 world.set_script(load("res://modules/infantry_ai/loot_fixture.gd"))
 root.add_child(world)
 var host := Node.new()
 host.set_script(load("res://modules/infantry_ai/infantry_host.gd"))
 world.add_child(host)
 host.setup(world)
 var cover := StaticBody3D.new()
 world.add_child(cover)
 var destruction := {"count":0}
 host.register_fortification("fort_fixture",cover,"red",60.0,func(_id):destruction.count+=1)
 check(host.damage_fortification("fort_fixture","rifle","blue").damage==0 and host.fortifications.fort_fixture.hp==60.0,"rifle cannot chip thick cover")
 check(host.damage_fortification("fort_fixture","cannon","blue","smoke").damage==0,"smoke causes no fortification damage")
 host.damage_fortification("fort_fixture","at","blue")
 check(host.fortifications.fort_fixture.hp==25.0,"actual explosive hit reduces registered fortification health")
 host.damage_fortification("fort_fixture","at","blue")
 host.damage_fortification("fort_fixture","at","blue")
 check(destruction.count==1 and host.fortifications.fort_fixture.hp==0.0,"destroyed fortification invokes owner callback exactly once")
 world.queue_free()
 print("TARGET_FALLBACK_FAILURES=",failures)
 quit(1 if failures else 0)
