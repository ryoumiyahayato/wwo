extends SceneTree
## V2.2.1 regression for data-driven contacts, V2-only navigation,
## reviewed panel spacing, blocking-panel pause feedback, and edge scrolling.

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

	var configured_main: String = str(
		ProjectSettings.get_setting("application/run/main_scene", "")
	)
	test.equal(
		configured_main,
		"res://scenes/v2_3/v2_3_life_loop_menu.tscn",
		"project starts from the formal V2.3 world-map menu"
	)
	var v2_3_formal_menu: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_menu.tscn"
	) as PackedScene
	test.expect(
		v2_3_formal_menu != null,
		"the formal V2.3 world-map menu remains loadable"
	)
	var menu_scene: PackedScene = load(
		"res://scenes/v2_2/v2_2_life_loop_menu.tscn"
	) as PackedScene
	test.expect(menu_scene != null, "dedicated V2.2 menu scene loads")
	if menu_scene != null:
		var menu: V2LifeLoopMenu = menu_scene.instantiate() as V2LifeLoopMenu
		test.expect(menu != null, "dedicated V2.2 menu instantiates")
		if menu != null:
			root.add_child(menu)
			await process_frame
			test.equal(
				menu.LIFE_LOOP_SCENE,
				"res://scenes/v2_2/v2_2_life_loop_main.tscn",
				"new and load actions target only the V2.2 world map"
			)
			menu.queue_free()
			await process_frame

	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load(
		"res://scenes/v2_2/v2_2_life_loop_main.tscn"
	) as PackedScene
	test.expect(packed != null, "reviewed V2.2 scene loads")
	var view: V2LifeLoopMain = packed.instantiate() as V2LifeLoopMain
	test.expect(view != null, "reviewed V2.2 scene instantiates")
	if view == null:
		test.finish(self, "V2.2.1 polish")
		return
	root.add_child(view)
	current_scene = view
	await process_frame
	await process_frame
	test.expect(
		view.interface is V2LifeLoopInterfaceFinal,
		"scene uses the final reviewed V2.2 interface subclass"
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
	test.equal(
		str(state.get("v2_menu_scene", "")),
		"res://scenes/v2_2/v2_2_life_loop_menu.tscn",
		"system return points to the V2.2 menu, not the legacy menu"
	)
	test.expect(
		not bool(state.get("system_menu_heading_visible", true)),
		"gear menu omits the redundant system-tools heading"
	)
	test.expect(
		float(state.get("relationship_first_row_offset", 0.0)) >= 54.0,
		"relationship names are separated from the section heading"
	)
	test.expect(
		float(state.get("summary_heading_offset", 99.0)) <= 10.0,
		"current-status heading is raised within the overview"
	)
	view.queue_free()
	await process_frame
	test.finish(self, "V2.2.1 polish")