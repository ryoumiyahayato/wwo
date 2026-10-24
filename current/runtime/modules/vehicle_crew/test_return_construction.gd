extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)
func run():
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.unit = 0
	main.garage = false
	main.game_mode = "skirmish"
	main.load_display()
	for i in range(6): await physics_frame
	# Isolate the task arbitration, preserving all actual actors and live host integration.
	for id in main.ai_host.actors: main.ai_host.actors[id].set_physics_process(false)
	var pid: String = main.crew_host.person_ids[0]
	var result: Dictionary = main.crew_host.disembark_person(pid)
	check(result.get("ok",false), "living crew disembarks in actual game")
	var actor = main.ai_host.actors[pid]
	actor.global_position = main.hero.global_position + Vector3(12,0,0)
	actor.global_position.y = main.terrain_height(actor.global_position.x,actor.global_position.z)
	var request: Dictionary = main.crew_host.request_embark(pid)
	check(request.get("pending",false), "actual crew starts return order")
	var host = main.construction_host
	check(host._choose_ai_builder() == null, "construction selector excludes only available returning crew")
	var funds: int = host.model.resources
	host.selected_position = Vector3(-7,main.terrain_height(-7,1),1)
	host.site_selected = true
	host.presets.select(host.preset_ids.find("barricade"))
	host._build()
	check(host.ai_build.is_empty() and host.model.resources==funds, "construction rejected without reservation or charge")
	check(main.crew_host.pending_returns.has(pid) and not actor.get_meta("crew_return_order",{}).is_empty() and actor.brain.order.is_empty(), "return order remains owned by same crew host")
	check(not actor.get_meta("construction_order",false), "no construction actor lock acquired")
	main.crew_host.on_stage_reset()
	check(not actor.has_meta("crew_return_order"), "scene reset clears actual actor return metadata")
	print("CREW RETURN CONSTRUCTION RESULT failures=%d" % failures)
	main.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
