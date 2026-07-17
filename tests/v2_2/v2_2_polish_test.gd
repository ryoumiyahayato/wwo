extends SceneTree
## V2.2.1 regression for data-driven contacts, blocking-panel pause feedback,
## polished scene wiring, and edge-scroll configuration.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V2LifeLoopSimulationPolish.new()
	test.expect(simulation.initialize(), "V2.2.1 simulation initializes")
	if not simulation.initialized:
		test.finish(self, "V2.2.1 polish")
		return

	var pierre_contacts: Array[Dictionary] = simulation.relationships.contact_candidates(
		V2LifeLoopSimulation.PIERRE_ID
	)
	test.equal(pierre_contacts.size(), 1, "Pierre sees only configured relationship contacts")
	test.equal(
		str(pierre_contacts[0].get("target_display_name_zh", "")),
		"让娜·勒鲁瓦",
		"contact display name comes from relationship data"
	)
	test.equal(
		simulation.relationships.contact_candidates(
			V2LifeLoopSimulation.ALBERT_ID
		).size(),
		0,
		"Albert is not offered a relationship he does not know"
	)
	var pierre_proposal: V2LifeLoopResult = simulation.suggest_contact_activity(
		V2LifeLoopSimulation.PIERRE_ID, "jeanne"
	)
	test.expect(pierre_proposal.success, "configured contact receives a schedule proposal")
	test.equal(
		str(pierre_proposal.data.get("related_entity_name", "")),
		"让娜·勒鲁瓦",
		"proposal carries the selected contact name"
	)
	var albert_proposal: V2LifeLoopResult = simulation.suggest_contact_activity(
		V2LifeLoopSimulation.ALBERT_ID
	)
	test.expect(
		not albert_proposal.success
		and albert_proposal.error_code == "no_contact_candidates",
		"person without contacts receives an explicit unavailable result"
	)

	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load(
		"res://scenes/v2_2/v2_2_life_loop_main.tscn"
	) as PackedScene
	test.expect(packed != null, "polished V2.2 scene loads")
	var view: V2LifeLoopMain = packed.instantiate() as V2LifeLoopMain
	test.expect(view != null, "polished V2.2 scene instantiates")
	if view == null:
		test.finish(self, "V2.2.1 polish")
		return
	root.add_child(view)
	current_scene = view
	await process_frame
	await process_frame
	test.expect(
		view.interface is V2LifeLoopInterface,
		"scene uses the V2.2.1 interface subclass"
	)
	test.expect(
		view.life_binding is V2LifeLoopUiBindingPolish,
		"scene uses the data-driven UI binding"
	)
	test.expect(
		view.life_simulation is V2LifeLoopSimulationPolish,
		"scene uses the data-driven contact simulation"
	)
	view.life_simulation.clock.set_speed(8)
	view.life_simulation.clock.set_paused(false)
	view.interface.open_panel_named("schedule", false)
	test.expect(
		view.life_simulation.clock.is_paused,
		"opening schedule panel pauses authoritative time"
	)
	view.interface.close_panel(false)
	test.expect(
		not view.life_simulation.clock.is_paused
		and view.life_simulation.clock.speed_multiplier == 8,
		"closing schedule panel restores previous pause and speed"
	)
	view.interface.set_review_mode(true)
	view.interface.set_identity("official")
	var official_binding: V2LifeLoopUiBindingPolish = (
		view.life_binding as V2LifeLoopUiBindingPolish
	)
	test.equal(
		official_binding.contact_options().size(), 0,
		"official UI has no hard-coded Jeanne contact"
	)
	var state: Dictionary = view.debug_state()
	test.expect(bool(state.get("edge_scroll_enabled", false)), "edge scrolling is enabled")
	test.equal(float(state.get("edge_scroll_margin", 0.0)), 20.0, "edge scroll margin is stable")
	view.queue_free()
	await process_frame
	test.finish(self, "V2.2.1 polish")
