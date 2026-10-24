extends SceneTree
const Host = preload("res://modules/infantry_ai/infantry_host.gd")
const Registry = preload("res://modules/vehicle_crew/crew_registry.gd")
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func run():
 var world := Node3D.new()
 world.set_script(load("res://modules/infantry_ai/loot_fixture.gd"))
 root.add_child(world)
 var ground := StaticBody3D.new()
 ground.collision_layer = 8
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = Vector3(40,1,40)
 shape.shape = box
 ground.add_child(shape)
 ground.position.y = -0.5
 world.add_child(ground)
 var host := Node.new()
 host.set_script(Host)
 world.add_child(host)
 host.setup(world)
 var donor = host.spawn_actor("donor","red",Vector3(0,0,-4))
 donor.weapon = "at"
 donor.brain.ammo = 1
 donor.brain.reserve_ammo = 2
 donor.brain.magazine_size = 1
 donor._sync_person_state()
 var old = donor.weapon_pivot
 old.queue_free()
 var equipment = load("res://assets/reused_combat/panzerfaust.glb").instantiate()
 donor.add_child(equipment)
 equipment.position = Vector3(0.25,1.05,-0.2)
 var marker := Marker3D.new()
 marker.name = "ATMuzzle"
 marker.position = Vector3(0,0,-0.55)
 equipment.add_child(marker)
 donor.bind_weapon_geometry(equipment,marker)
 host.infantry_weapon_tick(donor,0.0)
 var identity: String = donor.weapon_id
 var visual_id: int = donor.weapon_pivot.get_instance_id()
 donor.receive_damage(100)
 host.infantry_weapon_tick(donor,0.0)
 check(donor.weapon_id=="" and donor.weapon=="" and donor.brain.ammo==0,"dead actor relinquishes gun and ammunition")
 check(host.arsenal.records[identity].owner=="" and host.weapon_visuals[identity].get_parent()==world,"same real weapon node drops into world")
 var crew = host.register_bound_crew("crew_fixture",{"hp":10.0,"alive":true,"ammo":3,"reserve_ammo":7},Vector3.ZERO,"driver")
 var registry=Registry.new()
 check(registry.register_person(host.persons.crew_fixture).ok,"canonical crew person registers with actual registry")
 check(registry.register_vehicle("fixture_vehicle",{"driver_seat":"driver"}).ok,"real registry has driver role seat")
 check(registry.embark("crew_fixture","fixture_vehicle","driver_seat",func(_p,_v,_s):return true).ok,"registry authorizes initial boarding")
 check(not host.loot_eligible(crew),"seated crew cannot auto loot")
 check(registry.disembark("crew_fixture",Vector3.ZERO,func(_p,_v,_point):return true).ok,"real registry authorizes exit")
 crew.set_meta("crew_return_order",{"destination":Vector3.ZERO})
 host.set_crew_embarked("crew_fixture",false,Vector3.ZERO)
 check(host.loot_eligible(crew) and crew.get_meta("crew_role")=="driver","exited AI driver eligible without losing role identity")
 crew.set_meta("player_controlled",true)
 check(not host.loot_eligible(crew) and host.infantry_loot_command(crew,.1).is_empty(),"AI pickup cannot hijack player commander")
 crew.set_meta("player_controlled",false)
 crew.set_meta("construction_order",true)
 check(not host.loot_eligible(crew),"construction assignment is not hijacked")
 crew.set_meta("construction_order",false)
 for i in 190: await physics_frame
 check(crew.weapon_id==identity and crew.weapon=="at","dismounted crew physically walks to and picks up stronger weapon")
 check(is_instance_valid(crew.weapon_pivot) and crew.weapon_pivot.get_instance_id()==visual_id and crew.weapon_pivot.get_parent()==crew,"pickup transfers exact visible model, not duplicate")
 check(is_instance_valid(crew.muzzle) and crew.muzzle.name=="ATMuzzle","picked-up weapon uses transferred authored muzzle")
 var ammo_before: int = crew.brain.ammo
 var reserve_before: int = crew.brain.reserve_ammo
 host.set_crew_embarked("crew_fixture",true)
 host.set_crew_embarked("crew_fixture",false,crew.global_position)
 check(crew.weapon_id==identity and crew.brain.ammo==ammo_before and crew.brain.reserve_ammo==reserve_before,"crew reboard/exit preserves weapon identity and both ammo pools")
 crew.receive_suppression(1.0)
 check(crew.weapon_id=="" and crew.pickup_cooldown==3.0,"forced fixture suppression drops armed crew gun with cooldown")
 var count: int = host.arsenal.records.size()
 crew.receive_suppression(1.0)
 check(host.arsenal.records.size()==count,"repeated suppression cannot create duplicate weapons")
 for i in 60: await physics_frame
 check(crew.weapon_id=="","suppressed crew cannot instantly re-equip")
 print("CREW_REGISTRY_LOOT_FAILURES=",failures)
 world.queue_free()
 quit(1 if failures else 0)
