extends SceneTree
const Host = preload("res://modules/infantry_ai/infantry_host.gd")
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func settle():
 await physics_frame
 await physics_frame
func run():
 var world := Node3D.new()
 world.set_script(load("res://modules/infantry_ai/loot_fixture.gd"))
 root.add_child(world)
 var host := Node.new()
 host.set_script(Host)
 world.add_child(host)
 host.setup(world)
 var tank := Node3D.new()
 world.add_child(tank)
 host.register_player(tank,"player","blue")
 var observer = host.spawn_actor("observer","blue",Vector3.ZERO,[],[],"")
 var enemy = host.spawn_actor("enemy","red",Vector3(0,0,-20),[],[],"")
 observer.set_physics_process(false)
 enemy.set_physics_process(false)
 await settle()
 check(host.minimap_visible_enemy_ids()==["enemy"],"clear visible enemy only")
 var wall := StaticBody3D.new()
 wall.collision_layer = 1
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = Vector3(5,4,1)
 shape.shape = box
 wall.add_child(shape)
 world.add_child(wall)
 wall.position = Vector3(0,1,-10)
 await settle()
 check(host.minimap_visible_enemy_ids().is_empty(),"physical wall blocks contact")
 wall.collision_layer = 0
 await settle()
 world.weather_index = 2
 check(host.minimap_visible_enemy_ids().is_empty(),"fog excludes enemy beyond 12m")
 world.weather_index = 0
 world.smoke_root = Node3D.new()
 world.add_child(world.smoke_root)
 world.smoke_root.position = Vector3(0,0,-10)
 world.combat.smoke_remaining = 3.0
 check(host.minimap_visible_enemy_ids().is_empty(),"smoke excludes line through cloud")
 world.combat.smoke_remaining = 0.0
 enemy.brain.hp = 0.0
 check(host.minimap_visible_enemy_ids().is_empty(),"dead enemy excluded")
 enemy.brain.hp = 10.0
 enemy.set_embarked(true)
 check(host.minimap_visible_enemy_ids().is_empty(),"embarked enemy excluded")
 enemy.set_embarked(false)
 enemy.set_physics_process(false)
 await settle()
 observer.brain.hp = 0.0
 check(host.minimap_visible_enemy_ids().is_empty(),"dead observer and empty tank reveal nothing")
 observer.brain.hp = 10.0
 observer.set_meta("crew_role","driver")
 observer.set_embarked(true)
 await settle()
 check(host.minimap_visible_enemy_ids()==["enemy"],"live embarked crew allows tank observation")
 observer.brain.hp = 0.0
 check(host.minimap_visible_enemy_ids().is_empty(),"tank with only dead crew reveals nothing")
 observer.brain.hp = 10.0
 enemy.position.z = -65.0
 await settle()
 check(host.minimap_visible_enemy_ids().is_empty(),"clear visibility bounded at 60m")
 observer.set_embarked(false)
 observer.set_physics_process(false)
 observer.position = Vector3(100,0,0)
 enemy.position = Vector3(0,0,-20)
 await settle()
 check(host.minimap_visible_enemy_ids().is_empty(),"empty tank cannot observe for distant dismounted crew")
 print("MINIMAP_VISIBILITY_FAILURES=",failures)
 world.queue_free()
 quit(1 if failures else 0)
