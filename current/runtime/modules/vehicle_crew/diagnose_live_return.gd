extends SceneTree
var main: Node3D
func _initialize(): call_deferred("run")
func record(label: String) -> void:
	var rows: Array = []
	for pid in main.crew_host.person_ids:
		var actor = main.ai_host.actors[pid]
		var ground: float = main.terrain_height(actor.global_position.x,actor.global_position.z)
		var slides: Array = []
		for i in actor.get_slide_collision_count():
			var c = actor.get_slide_collision(i)
			slides.append({"normal":str(c.get_normal()),"collider":str(c.get_collider())})
		rows.append({"id":pid,"instance_id":actor.get_instance_id(),"ammo":actor.person_state.ammo,"hp":actor.person_state.hp,"alive":actor.person_state.alive,"parts":actor.person_state.parts,"position":str(actor.global_position),"ground":ground,"floor":actor.is_on_floor(),"velocity":str(actor.velocity),"distance":actor.global_position.distance_to(main.hero.global_position),"visible":actor.visible,"identified":main.ai_host.is_identified(pid),"embarked":actor.embarked,"physics":actor.is_physics_processing(),"state":actor.brain.state,"patrol":str(actor.brain.patrol_points),"mask":actor.collision_mask,"layer":actor.collision_layer,"shape_height":actor.get_node("BodyCollision").shape.height,"shape_position":str(actor.get_node("BodyCollision").position),"slides":slides,"return":str(actor.get_meta("crew_return_order",{}))})
	print("LIVE_RETURN_DIAG ", JSON.stringify({"phase":label,"hero":str(main.hero.global_position),"basis":str(main.hero.global_basis),"camera":str(main.camera.global_position),"crew":rows,"batch":main.crew_host.last_batch,"pending":str(main.crew_host.pending_returns)}))
func run():
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.select_catalog("armored_car_rocket")
	main.switch_mode()
	for i in range(10): await physics_frame
	await create_timer(25.0).timeout
	record("after_default_battle")
	main.crew_host._transfer_pressed(false,true)
	record("immediate_exit")
	await physics_frame
	record("exit_frame1")
	await create_timer(0.2).timeout
	record("exit_0.2s")
	await create_timer(1.0).timeout
	record("exit_1.2s")
	await create_timer(3.8).timeout
	record("exit_5s")
	await create_timer(25.0).timeout
	record("exit_30s")
	main.crew_host._transfer_pressed(true,true)
	record("return_requested")
	await create_timer(2.0).timeout
	record("return_2s")
	await create_timer(13.0).timeout
	record("return_15s")
	main.queue_free()
	await process_frame
	quit(0)
