extends SceneTree
const CrewHost = preload("res://modules/vehicle_crew/vehicle_crew_host.gd")
const InfantryHost = preload("res://modules/infantry_ai/infantry_host.gd")
const Combat = preload("res://scripts/combat.gd")
class TestMain extends Node3D:
	var hero := Node3D.new()
	var hud := CanvasLayer.new()
	var stage := Node3D.new()
	var player_combat = Combat.new()
	var ai_host: Node
	var armor_host: Node
	var unit := 0
	var game_mode := "skirmish"
	var garage := false
	var message := ""
	func terrain_height(_x:float, _z:float) -> float: return 0.0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		push_error(label)
		quit(1)
		assert(value, label)
func _initialize(): call_deferred("run")
func run():
	var main := TestMain.new()
	main.player_combat.configure_tank("heavy")
	root.add_child(main)
	main.add_child(main.hero)
	main.add_child(main.hud)
	main.add_child(main.stage)
	main.ai_host = InfantryHost.new()
	main.add_child(main.ai_host)
	main.ai_host.setup(main)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 8
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60,0.2,60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	main.add_child(floor_body)
	var host = CrewHost.new()
	main.add_child(host)
	host.setup(main)
	host.bind_player()
	await physics_frame
	await physics_frame
	var pid: String = host.person_ids[0]
	var actor = main.ai_host.actors[pid]
	var actor_instance: int = actor.get_instance_id()
	var p: Dictionary = host.registry.person_ref(pid)
	p.hp = 4.0
	p.ammo = 2
	p.parts.left_arm = "injured"
	check(host.disembark_person(pid).ok, "wounded actor disembarks")
	actor.global_position = Vector3(12,0,0) # Fixture starts outside boarding radius.
	var busy_id: String = host.person_ids[2]
	check(host.disembark_person(busy_id).ok, "builder fixture disembarks")
	var builder = main.ai_host.actors[busy_id]
	builder.set_meta("construction_order",true)
	builder.order_build(Vector3(20,0,5), "sandbag", true)
	var build_order: Dictionary = builder.brain.order.duplicate(true)
	var dead: Dictionary = host.registry.person_ref(host.person_ids[1])
	dead.hp = 0
	dead.alive = false
	var near_id: String = host.person_ids[4]
	check(host.disembark_person(near_id).ok, "nearby living fixture disembarks")
	host._transfer_pressed(true,true)
	check(host.last_batch.success == 1 and host.last_batch.pending == 1, "batch distinguishes immediate and walking passengers")
	check(host.last_batch.failures.get("dead_person",0)==1 and host.last_batch.failures.get("construction_busy",0)==1 and host.last_batch.failures.get("already_aboard",0)==1, "batch retains every failure reason instead of last error")
	check(main.message.contains("正在走回车旁") and main.message.contains("阵亡") and main.message.contains("工程订单"), "UI summary includes pending and all failures")
	check(not actor.embarked and actor.global_position.x == 12, "return request never teleports or boards from distance")
	check(builder.brain.order == build_order and bool(builder.get_meta("construction_order")), "return does not commandeer construction order")
	var steps := 0
	var moved := false
	var previous: Vector3 = actor.global_position
	while not actor.embarked and steps < 480:
		await physics_frame
		var displacement: float = actor.global_position.distance_to(previous)
		check(displacement < 0.15, "each real physics step bounded, no teleport")
		if displacement > 0.001: moved = true
		previous = actor.global_position
		steps += 1
	check(actor.embarked and moved and steps>30, "actor actually walks back then boards")
	check(actor.global_position.distance_to(main.hero.global_position)<=6.0, "boarding occurs only inside actual range")
	check(actor.get_instance_id()==actor_instance and p.person_id==pid and p.hp==4 and p.ammo==2 and p.parts.left_arm=="injured", "identity injuries ammo survive real walking return")
	check(host.last_batch.success==2 and host.last_batch.pending==0 and host.last_batch.failures.size()==3, "completion summary retains initial failures")
	check(not actor.has_meta("crew_return_order"), "successful return clears movement order")
	check(host.disembark_person(pid).ok, "repeat exit for injury cancellation")
	actor.global_position = Vector3(12,0,0)
	check(host.request_embark(pid).pending, "queue second return")
	p.hp = 3
	await physics_frame
	await physics_frame
	check(not host.pending_returns.has(pid) and not actor.has_meta("crew_return_order") and not actor.embarked and p.hp==3, "new injury safely cancels without healing or boarding")
	check(host.request_embark(pid).pending, "wounded survivor can request again")
	actor.set_meta("construction_order",true)
	actor.order_build(Vector3(18,0,2), "sandbag",true)
	var protected_order: Dictionary = actor.brain.order.duplicate(true)
	await physics_frame
	await physics_frame
	check(not host.pending_returns.has(pid) and not actor.has_meta("crew_return_order") and actor.brain.order==protected_order, "new construction order cancels return without clearing build")
	actor.set_meta("construction_order",false)
	actor.brain.order.clear()
	check(host.request_embark(pid).pending, "queue before death")
	p.hp = 0
	p.alive = false
	await physics_frame
	await physics_frame
	check(not host.pending_returns.has(pid) and not actor.embarked and not p.alive and p.hp==0, "death cancels and never resurrects")
	# Fresh living crew return is cancelled on stage reset, with no orphan metadata.
	builder.set_meta("construction_order",false)
	builder.brain.order.clear()
	builder.global_position = Vector3(12,0,5)
	check(host.request_embark(busy_id).pending, "queue before stage reset")
	host.on_stage_reset()
	check(host.pending_returns.is_empty() and not builder.has_meta("crew_return_order") and not builder.embarked, "stage reset cancels pending movement safely")
	print("PASS crew return: %d checks, %d real 3D movement frames, mixed-failure summary and safe cancellation" % [checks,steps])
	main.queue_free()
	quit(0)
