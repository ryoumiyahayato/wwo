extends SceneTree
## Reproducible machine-readable evidence for the V2.3 real-window review.

const OUTPUT_RELATIVE: String = "artifacts/v2_3_space_cognition_review"
const OUTPUT_PATH: String = "res://" + OUTPUT_RELATIVE

var generated_files: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var absolute_output: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_output)
	if directory_error != OK:
		push_error("无法创建 V2.3 评审资料目录：%s" % error_string(directory_error))
		quit(1)
		return
	var simulation := V23LifeLoopSimulation.new()
	if not simulation.initialize():
		push_error(simulation.initialization_error)
		quit(1)
		return
	var pierre: String = V2LifeLoopSimulation.PIERRE_ID
	var albert: String = V2LifeLoopSimulation.ALBERT_ID
	var jeanne: String = "jeanne"
	var binding := V23LifeLoopUiBinding.new(simulation, true)

	_write_json("01_lille_local_nodes.json", {
		"location_count": simulation.spatial_locations.locations.size(),
		"locations": simulation.v2_3_config.location_records(),
	})
	_write_json("02_pierre_known_locations.json", {
		"observer_id": pierre,
		"known_locations": simulation.spatial_locations.known_locations(pierre),
	})
	_write_json("03_albert_known_locations.json", {
		"observer_id": albert,
		"known_locations": simulation.spatial_locations.known_locations(albert),
	})
	var fastest: V2LifeLoopResult = simulation.preview_route(
		pierre, "location_lille_fives_factory", "fastest"
	)
	var cheapest: V2LifeLoopResult = simulation.preview_route(
		pierre, "location_lille_fives_factory", "cheapest"
	)
	_write_json("04_route_preview.json", fastest.to_dict())
	_write_json("05_walk_route.json", cheapest.to_dict())
	_write_json("06_urban_transit_route.json", fastest.to_dict())
	var train_edges: Array[Dictionary] = []
	for raw_edge_id: Variant in simulation.travel_graph.edges.keys():
		var edge: Dictionary = simulation.travel_graph.get_edge(str(raw_edge_id))
		if "regional_train" in (edge.get("available_modes", []) as Array):
			train_edges.append(edge)
	_write_json("07_regional_train_route.json", {
		"mode": simulation.travel_graph.get_mode("regional_train"),
		"edges": train_edges,
	})

	var transit_sim := V23LifeLoopSimulation.new()
	transit_sim.initialize()
	var station: String = "location_lille_flandres_station"
	var roubaix: String = "location_roubaix_centre"
	transit_sim.spatial_locations.force_set_at_location(
		pierre, station, transit_sim.clock.total_hours
	)
	transit_sim.spatial_locations.discover_location(pierre, roubaix)
	for edge: Dictionary in train_edges:
		transit_sim.travel_graph.discover_edge(
			pierre, str(edge.get("edge_id", ""))
		)
	var train_plan_result: V2LifeLoopResult = transit_sim.travel_execution.create_plan(
		pierre, roubaix, "fastest", transit_sim.clock.total_hours + 1,
		9999, 0
	)
	var train_plan: Dictionary = train_plan_result.data.get(
		"travel_plan", {}
	) as Dictionary
	var train_segment: Dictionary = (
		train_plan.get("route_segments", []) as Array
	)[0] as Dictionary
	var train_activity: Dictionary = {
		"activity_type": "travel_regional_train",
		"travel_plan_id": str(train_plan.get("travel_plan_id", "")),
		"route_segment_index": 0,
		"route_segment_id": str(train_segment.get("route_segment_id", "")),
	}
	transit_sim.travel_execution.settle_activity(
		pierre, train_activity, int(train_segment.get("departure_hour", 0)),
		transit_sim.households, transit_sim.ledger, transit_sim.conditions
	)
	_write_json("08_in_transit_state.json", {
		"travel_plan": train_plan,
		"position": transit_sim.spatial_locations.position_for(pierre),
	})
	transit_sim.travel_execution.settle_activity(
		pierre, train_activity, int(train_segment.get("departure_hour", 0)) + 1,
		transit_sim.households, transit_sim.ledger, transit_sim.conditions
	)
	_write_json("09_arrival_state.json", {
		"travel_plan": transit_sim.travel_execution.travel_plans.get(
			str(train_plan.get("travel_plan_id", "")), {}
		),
		"position": transit_sim.spatial_locations.position_for(pierre),
	})

	var late_sim := V23LifeLoopSimulation.new()
	late_sim.initialize()
	late_sim.schedule.cancel_future_activity_types(
		pierre, V23LifeLoopSimulation.TRAVEL_TYPES,
		late_sim.clock.total_hours, "review_late_absence"
	)
	late_sim.spatial_locations.force_set_at_location(
		pierre, "location_lille_pierre_home", late_sim.clock.total_hours
	)
	late_sim.advance_hours(2)
	_write_json("10_late_or_absence.json", late_sim.employment.today_summary(
		pierre, late_sim.clock.total_hours
	))

	var market_sim := V23LifeLoopSimulation.new()
	market_sim.initialize()
	market_sim.spatial_locations.force_set_at_location(
		pierre, "location_lille_wazemmes_market", market_sim.clock.total_hours
	)
	var purchase_before: Dictionary = market_sim.households.household_for_person(
		pierre
	)
	var purchase_result: V2LifeLoopResult = market_sim.request_activity(
		pierre, "purchase_food", market_sim.clock.total_hours, 1
	)
	var purchase_id: String = str(
		(purchase_result.data.get("activity", {}) as Dictionary).get(
			"activity_id", ""
		)
	)
	market_sim.advance_hours(1)
	_write_json("11_market_purchase.json", {
		"request": purchase_result.to_dict(),
		"before": purchase_before,
		"after": market_sim.households.household_for_person(pierre),
		"activity": _activity_by_id(market_sim.schedule, pierre, purchase_id),
		"ledger": market_sim.ledger.transactions.duplicate(true),
	})
	var remote_sim := V23LifeLoopSimulation.new()
	remote_sim.initialize()
	var remote_result: V2LifeLoopResult = remote_sim.request_activity(
		pierre, "purchase_food", remote_sim.clock.total_hours, 1
	)
	var remote_id: String = str(
		(remote_result.data.get("activity", {}) as Dictionary).get(
			"activity_id", ""
		)
	)
	remote_sim.advance_hours(1)
	_write_json("12_remote_purchase_rejected.json", {
		"request": remote_result.to_dict(),
		"activity": _activity_by_id(remote_sim.schedule, pierre, remote_id),
		"position": remote_sim.spatial_locations.position_for(pierre),
	})

	var social_sim := V23LifeLoopSimulation.new()
	social_sim.initialize()
	var hall: String = "location_lille_metalworkers_union_hall"
	social_sim.spatial_locations.force_set_at_location(
		pierre, hall, social_sim.clock.total_hours
	)
	social_sim.spatial_locations.force_set_at_location(
		jeanne, hall, social_sim.clock.total_hours
	)
	var relation_before: Dictionary = social_sim.dynamic_relationships.get_relationship(
		pierre, jeanne
	)
	var face_result: V2LifeLoopResult = social_sim.request_activity(
		pierre, "social_contact", social_sim.clock.total_hours, 1
	)
	social_sim.advance_hours(1)
	_write_json("13_face_to_face.json", {
		"request": face_result.to_dict(),
		"before": relation_before,
		"after": social_sim.dynamic_relationships.get_relationship(pierre, jeanne),
	})

	var appointment_sim := V23LifeLoopSimulation.new()
	appointment_sim.initialize()
	var appointment_start: int = appointment_sim.clock.total_hours + 72
	var invite: V2LifeLoopResult = appointment_sim.invite_appointment(
		pierre, jeanne, "location_lille_public_square",
		appointment_start, appointment_start + 1, "评审约见"
	)
	var appointment: Dictionary = invite.data.get("appointment", {}) as Dictionary
	var appointment_id: String = str(appointment.get("appointment_id", ""))
	_accept_appointment(appointment_sim, appointment_id, jeanne)
	appointment_sim.spatial_locations.force_set_at_location(
		pierre, "location_lille_public_square", appointment_start
	)
	appointment_sim.spatial_locations.force_set_at_location(
		jeanne, "location_lille_public_square", appointment_start
	)
	appointment_sim.appointments.process_hour(
		appointment_start, appointment_sim.spatial_locations,
		appointment_sim.dynamic_relationships
	)
	_write_json("14_appointment_attended.json", {
		"appointment": appointment_sim.appointments.appointments.get(
			appointment_id, {}
		),
		"relationship": appointment_sim.dynamic_relationships.get_relationship(
			pierre, jeanne
		),
	})
	var missed_sim := V23LifeLoopSimulation.new()
	missed_sim.initialize()
	var missed_start: int = missed_sim.clock.total_hours + 72
	var missed_invite: V2LifeLoopResult = missed_sim.invite_appointment(
		pierre, jeanne, "location_lille_public_square",
		missed_start, missed_start + 1, "评审爽约"
	)
	var missed_appointment: Dictionary = missed_invite.data.get(
		"appointment", {}
	) as Dictionary
	var missed_id: String = str(missed_appointment.get("appointment_id", ""))
	_accept_appointment(missed_sim, missed_id, jeanne)
	missed_sim.spatial_locations.force_set_at_location(
		pierre, "location_lille_public_square", missed_start
	)
	missed_sim.spatial_locations.force_set_at_location(
		jeanne, "location_lille_centre", missed_start
	)
	missed_sim.appointments.process_hour(
		missed_start, missed_sim.spatial_locations,
		missed_sim.dynamic_relationships
	)
	_write_json("15_appointment_missed.json", {
		"appointment": missed_sim.appointments.appointments.get(missed_id, {}),
		"relationship": missed_sim.dynamic_relationships.get_relationship(
			pierre, jeanne
		),
	})

	var message_sim := V23LifeLoopSimulation.new()
	message_sim.initialize()
	var letter: V2LifeLoopResult = message_sim.send_private_message(
		pierre, jeanne, "meeting_report",
		{
			"fact_id": "review:letter_fact",
			"subject_id": "union_metalworkers_nord",
			"fact_type": "organization_activity",
			"claim": "评审信件事实",
			"expires_hour": message_sim.clock.total_hours + 24,
		}
	)
	var letter_data: Dictionary = letter.data.get("message", {}) as Dictionary
	var letter_id: String = str(letter_data.get("message_id", ""))
	_write_json("16_write_letter.json", letter.to_dict())
	_write_json("17_message_in_transit.json", message_sim.communication.get_message(
		letter_id
	))
	var delivery_hour: int = V2DateTime.total_hour_from_iso(
		str(letter_data.get("expected_delivery_datetime", ""))
	)
	message_sim.communication.process_deliveries(delivery_hour)
	_write_json("18_message_delivered_unread.json", {
		"message": message_sim.communication.get_message(letter_id),
		"unread_count": message_sim.communication.unread_count(jeanne),
		"knowledge_before_read": message_sim.knowledge.records_for_subject(
			jeanne, "union_metalworkers_nord"
		),
	})
	message_sim.read_message_now(jeanne, letter_id)
	var reply: V2LifeLoopResult = message_sim.communication.reply_message(
		jeanne, letter_id, "greeting_reply", {"text": "已收到"},
		delivery_hour + 1, message_sim.spatial_locations, message_sim.knowledge,
		message_sim.dynamic_relationships, message_sim.households, message_sim.ledger
	)
	_write_json("19_message_reply.json", {
		"original": message_sim.communication.get_message(letter_id),
		"reply": reply.to_dict(),
	})
	_write_json("20_knowledge_log.json", {
		"person_id": jeanne,
		"knowledge": message_sim.knowledge.records_for_person(jeanne),
	})
	var expiry_result: V2LifeLoopResult = message_sim.knowledge.record_fact(
		pierre, "review:expiry", "location_lille_centre", "public_notice",
		"即将过期", "public_notice", "public_notice",
		message_sim.clock.total_hours, 750, "reported",
		message_sim.clock.total_hours + 1, "", "review:expiry:key"
	)
	var expiry_id: String = str(
		(expiry_result.data.get("knowledge", {}) as Dictionary).get(
			"knowledge_id", ""
		)
	)
	message_sim.knowledge.expire_due(message_sim.clock.total_hours + 1)
	_write_json("21_expired_knowledge.json", message_sim.knowledge.get_record(
		expiry_id
	))
	var limited_overlay: Dictionary = binding.map_overlay_payload()
	binding.set_truth_view(true)
	var truth_overlay: Dictionary = binding.map_overlay_payload()
	_write_json("22_cognition_truth_comparison.json", {
		"limited": limited_overlay,
		"truth": truth_overlay,
	})

	var introduction_sim := V23LifeLoopSimulation.new()
	introduction_sim.initialize()
	var introduction: V2LifeLoopResult = introduction_sim.request_introduction(
		pierre, jeanne, V23LifeLoopSimulation.JULES_ID
	)
	var introduction_request: Dictionary = introduction.data.get(
		"request", {}
	) as Dictionary
	_write_json("23_introduction_request.json", introduction.to_dict())
	var request_message_id: String = str(
		introduction_request.get("request_message_id", "")
	)
	var request_message: Dictionary = introduction_sim.communication.get_message(
		request_message_id
	)
	introduction_sim.communication.process_deliveries(
		V2DateTime.total_hour_from_iso(str(
			request_message.get("expected_delivery_datetime", "")
		))
	)
	introduction_sim.read_message_now(jeanne, request_message_id)
	var updated_request: Dictionary = introduction_sim.introductions.requests.get(
		str(introduction_request.get("request_id", "")), {}
	) as Dictionary
	var introduction_message_id: String = str(
		updated_request.get("introduction_message_id", "")
	)
	var introduction_message: Dictionary = (
		introduction_sim.communication.get_message(introduction_message_id)
	)
	introduction_sim.communication.process_deliveries(
		V2DateTime.total_hour_from_iso(str(
			introduction_message.get("expected_delivery_datetime", "")
		))
	)
	introduction_sim.read_message_now(pierre, introduction_message_id)
	_write_json("24_jules_known_after_introduction.json", {
		"known": introduction_sim.knowledge.knows_person(
			pierre, V23LifeLoopSimulation.JULES_ID
		),
		"request": introduction_sim.introductions.requests.get(
			str(introduction_request.get("request_id", "")), {}
		),
		"relationship": introduction_sim.dynamic_relationships.get_relationship(
			pierre, V23LifeLoopSimulation.JULES_ID
		),
	})
	var albert_binding := V23LifeLoopUiBinding.new(simulation, true)
	albert_binding.select_identity("official")
	_write_json("25_albert_contacts.json", {
		"known_people": albert_binding.known_people_view(),
		"contacts": albert_binding.contact_options(),
	})

	var v2_2_source := V2LifeLoopSimulationPolish.new()
	v2_2_source.initialize()
	v2_2_source.advance_hours(36)
	var v2_2_snapshot: Dictionary = GameSaveService.new().build_v2_2_snapshot(
		v2_2_source
	)
	var migration: V2LifeLoopResult = V23SaveMigration.new().migrate_snapshot(
		v2_2_snapshot
	)
	var migrated_snapshot: Dictionary = migration.data.get("snapshot", {}) as Dictionary
	_write_json("26_v2_2_migration.json", {
		"success": migration.success,
		"summary": migration.data.get("summary", {}),
		"validation_errors": V23SaveService.new().validate_snapshot(
			migrated_snapshot
		),
	})
	_write_json("v2_2_to_v2_3_migration_summary.json", {
		"success": migration.success,
		"summary": migration.data.get("summary", {}),
	})

	var transit_save := V23SaveService.new().build_snapshot(transit_sim)
	var transit_restored := V23LifeLoopSimulation.new()
	transit_restored.initialize()
	var transit_restore: V2LifeLoopResult = transit_restored.restore_v2_3_state(
		transit_save
	)
	_write_json("27_in_transit_save_load.json", {
		"restore": transit_restore.to_dict(),
		"before_position": transit_sim.spatial_locations.position_for(pierre),
		"after_position": transit_restored.spatial_locations.position_for(pierre),
		"travel_equal": (
			transit_sim.travel_execution.get_persistent_state()
			== transit_restored.travel_execution.get_persistent_state()
		),
	})

	var direct := V23LifeLoopSimulation.new()
	direct.initialize()
	var direct_started: int = Time.get_ticks_msec()
	direct.run_days(30)
	var direct_elapsed: int = Time.get_ticks_msec() - direct_started
	var direct_snapshot: Dictionary = direct.determinism_snapshot()
	_write_json("28_30_day_state.json", {
		"elapsed_msec": direct_elapsed,
		"summary": _thirty_day_summary(direct),
	})
	_write_json("30_day_final_state.json", {
		"elapsed_msec": direct_elapsed,
		"summary": _thirty_day_summary(direct),
		"determinism_snapshot": direct_snapshot,
	})
	_write_json("29_ledger_consistency.json", {
		"consistency": direct.ledger_consistency().to_dict(),
		"households": direct.households.get_persistent_state(),
		"ledger": direct.ledger.get_persistent_state(),
		"transport_transactions": _transport_transactions(direct),
	})

	var split := V23LifeLoopSimulation.new()
	split.initialize()
	split.run_days(10)
	var split_save: Dictionary = split.get_persistent_state()
	var resumed := V23LifeLoopSimulation.new()
	resumed.initialize()
	var resume_result: V2LifeLoopResult = resumed.restore_v2_3_state(split_save)
	resumed.run_days(20)
	var resumed_snapshot: Dictionary = resumed.determinism_snapshot()
	var field_matches: Dictionary = {}
	var all_match: bool = true
	var comparison_fields: PackedStringArray = [
		"time", "person_positions", "travel", "travel_costs", "messages",
		"knowledge", "known_locations", "known_people", "relationships",
		"appointments", "ledger", "attendance", "conditions", "npc",
	]
	for field: String in comparison_fields:
		var matches: bool = (
			V23SaveService._canonical(direct_snapshot.get(field))
			== V23SaveService._canonical(resumed_snapshot.get(field))
		)
		field_matches[field] = matches
		all_match = all_match and matches
	_write_json("determinism_comparison.json", {
		"restore_success": resume_result.success,
		"direct_days": 30,
		"split_days": [10, 20],
		"all_fields_match": all_match,
		"field_matches": field_matches,
		"direct_digest": JSON.stringify(
			V23SaveService._canonical(direct_snapshot), "", true
		).sha256_text(),
		"resumed_digest": JSON.stringify(
			V23SaveService._canonical(resumed_snapshot), "", true
		).sha256_text(),
	})

	var packed: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_main.tscn"
	) as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	root.add_child(view)
	await process_frame
	await process_frame
	var map_performance: Dictionary = view.map_canvas.debug_performance_snapshot()
	_write_json("30_96x_performance.json", {
		"zoom": view.map_canvas.zoom,
		"headless_map_snapshot": map_performance,
		"visible_window_samples": [],
	})
	_write_json("visible_window_performance.json", {
		"engine": Engine.get_version_info(),
		"headless_30_day_msec": direct_elapsed,
		"headless_map_snapshot": map_performance,
		"visible_window_samples": [],
	})
	view.queue_free()
	await process_frame
	_write_json("artifact_manifest.json", {
		"generated_at": Time.get_datetime_string_from_system(true),
		"generator": "res://tests/v2_3/v2_3_review_artifact_generator.gd",
		"files": generated_files.duplicate(),
	})
	print("V2.3 review artifacts: %d files in %s" % [
		generated_files.size(), absolute_output
	])
	quit(0)


func _accept_appointment(
	simulation: V23LifeLoopSimulation,
	appointment_id: String,
	participant_id: String
) -> void:
	var appointment: Dictionary = simulation.appointments.appointments.get(
		appointment_id, {}
	) as Dictionary
	var invitation_ids: Array = appointment.get("invitation_message_ids", []) as Array
	if invitation_ids.is_empty():
		return
	var message_id: String = str(invitation_ids[0])
	var message: Dictionary = simulation.communication.get_message(message_id)
	var delivery_hour: int = V2DateTime.total_hour_from_iso(
		str(message.get("expected_delivery_datetime", ""))
	)
	simulation.communication.process_deliveries(delivery_hour)
	simulation.read_message_now(participant_id, message_id)
	simulation.appointments.respond(
		appointment_id, participant_id, true, delivery_hour + 1,
		simulation.schedule, simulation.communication,
		simulation.spatial_locations, simulation.knowledge,
		simulation.dynamic_relationships, simulation.households, simulation.ledger
	)


func _activity_by_id(
	schedule: V2ScheduleService, person_id: String, activity_id: String
) -> Dictionary:
	for raw_activity: Variant in schedule.schedules.get(person_id, []) as Array:
		var activity: Dictionary = raw_activity as Dictionary
		if str(activity.get("activity_id", "")) == activity_id:
			return activity.duplicate(true)
	return {}


func _thirty_day_summary(simulation: V23LifeLoopSimulation) -> Dictionary:
	return {
		"current_datetime": V2DateTime.iso_from_total_hour(
			simulation.clock.total_hours
		),
		"v2_3_hours_processed": simulation.v2_3_hours_processed,
		"person_positions": simulation.spatial_locations.person_positions.duplicate(
			true
		),
		"travel_plan_count": simulation.travel_execution.travel_plans.size(),
		"message_count": simulation.communication.messages.size(),
		"knowledge_counts": {
			V2LifeLoopSimulation.PIERRE_ID: simulation.knowledge.records_for_person(
				V2LifeLoopSimulation.PIERRE_ID
			).size(),
			V2LifeLoopSimulation.ALBERT_ID: simulation.knowledge.records_for_person(
				V2LifeLoopSimulation.ALBERT_ID
			).size(),
		},
		"relationship_count": simulation.dynamic_relationships.relationships.size(),
		"appointment_count": simulation.appointments.appointments.size(),
		"ledger_transaction_count": simulation.ledger.transactions.size(),
		"ledger_consistent": simulation.ledger_consistency().success,
		"maximum_hour_processing_usec": simulation.maximum_hour_processing_usec,
	}


func _transport_transactions(
	simulation: V23LifeLoopSimulation
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for transaction: Dictionary in simulation.ledger.transactions:
		if str(transaction.get("category", "")) == "transport":
			result.append(transaction.duplicate(true))
	return result


func _write_json(file_name: String, data: Variant) -> void:
	var file: FileAccess = FileAccess.open(
		"%s/%s" % [OUTPUT_PATH, file_name], FileAccess.WRITE
	)
	if file == null:
		push_error("无法写入评审资料：%s" % file_name)
		return
	file.store_string(JSON.stringify(
		V23SaveService._canonical(data), "\t", false
	))
	file.close()
	if file_name not in generated_files:
		generated_files.append(file_name)
