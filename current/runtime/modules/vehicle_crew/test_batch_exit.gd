extends SceneTree
const CrewHost = preload("res://modules/vehicle_crew/vehicle_crew_host.gd")
const InfantryHost = preload("res://modules/infantry_ai/infantry_host.gd")
const Combat = preload("res://scripts/combat.gd")
class TestMain extends Node3D:
	var armor_host: Node = null # Legal scene with no armored AI units.
	var hero := Node3D.new()
	var hud := CanvasLayer.new()
	var stage := Node3D.new()
	var player_combat = Combat.new()
	var ai_host: Node
	var unit := 0
	var game_mode := "skirmish"
	var garage := false
	var message := ""
	func terrain_height(x:float, z:float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x,30,z),Vector3(x,-30,z),1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		return float(hit.position.y) if not hit.is_empty() else 0.0
var failures := 0
var checks := 0
func check(value:bool, label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize(): call_deferred("run")
func run():
	var cases: Array = []
	for count in [2,3,5]:
		var viewport := SubViewport.new()
		viewport.own_world_3d = true
		root.add_child(viewport)
		var main := TestMain.new()
		viewport.add_child(main)
		main.add_child(main.stage)
		main.add_child(main.hero)
		main.add_child(main.hud)
		main.player_combat.configure_tank("heavy" if count==5 else "light")
		if count==2:
			main.player_combat.crew[2].hp = 0
			main.player_combat.crew[2].alive = false
		main.ai_host = InfantryHost.new()
		main.add_child(main.ai_host)
		main.ai_host.setup(main)
		var slope := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(60,0.2,60)
		shape.shape = box
		slope.add_child(shape)
		slope.position.y = -0.1
		slope.rotation.z = deg_to_rad(15.0 if count==5 else 8.0)
		main.add_child(slope)
		var host = CrewHost.new()
		main.add_child(host)
		host.setup(main)
		cases.append({"count":count,"viewport":viewport,"main":main,"host":host,"identities":{},"health":{}})
	await physics_frame
	await physics_frame
	for test in cases:
		var host = test.host
		host.bind_player()
		for i in test.count:
			var pid: String = host.person_ids[i]
			var p: Dictionary = host.registry.person_ref(pid)
			p.hp = 4.0 + i
			p.ammo = 2
			p.parts.left_arm = "injured"
			test.identities[pid] = test.main.ai_host.actors[pid].get_instance_id()
			test.health[pid] = p.hp
		host._transfer_pressed(false,true) # All transfers occur before a physics sync.
		check(host.last_batch.success == test.count, "%d-person same-frame exit succeeds" % test.count)
		for i in test.count:
			var a = test.main.ai_host.actors[host.person_ids[i]]
			for j in range(i+1,test.count):
				var b = test.main.ai_host.actors[host.person_ids[j]]
				check(Vector2(a.position.x-b.position.x,a.position.z-b.position.z).length()>=0.8, "%d-person exits reserve distinct capsules immediately" % test.count)
	# Thirty simulated seconds at normal 60Hz physics. No transforms changed by test.
	for frame in 1800:
		await physics_frame
		if frame % 60 != 0: continue
		for test in cases:
			for pid in test.identities:
				var actor = test.main.ai_host.actors[pid]
				var ground: float = test.main.terrain_height(actor.position.x,actor.position.z)
				check(absf(actor.position.y-ground)<1.0, "sloped ground remains bounded, no capsule stacking ascent or fall")
	for test in cases:
		var host = test.host
		host._transfer_pressed(true,true)
		for frame in 360:
			if host.pending_returns.is_empty(): break
			await physics_frame
		check(host.last_batch.success==test.count and host.last_batch.pending==0, "%d nearby living crew genuinely reboard after 30s" % test.count)
		for pid in test.identities:
			var actor = test.main.ai_host.actors[pid]
			var p: Dictionary = host.registry.person_ref(pid)
			check(actor.embarked and actor.get_instance_id()==test.identities[pid] and p.hp==test.health[pid] and p.ammo==2 and p.parts.left_arm=="injured", "same actor injury and ammo survive same-frame batch and reboarding")
		if test.count==2: check(host.last_batch.failures.get("dead_person",0)==1, "dead occupant remains dead and is counted")
		test.viewport.queue_free()
	await process_frame
	print("CREW BATCH EXIT RESULT %d checks, %d failures; 2/3/5 same-frame exits, 8/15 degree slopes, 30 seconds" % [checks,failures])
	quit(0 if failures==0 else 1)
