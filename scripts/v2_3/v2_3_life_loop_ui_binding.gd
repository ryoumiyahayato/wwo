class_name V23LifeLoopUiBinding
extends V2LifeLoopUiBindingPolish
## Person-scoped V2.3 presentation data and authoritative UI commands.

var v2_3_simulation: V23LifeLoopSimulation
var v2_3_save_service := V23SaveService.new()
var save_migration := V23SaveMigration.new()
var route_preview: Dictionary = {}
var _view_revision: int = 1


func _init(
	life_simulation: V2LifeLoopSimulation,
	enable_developer_mode: bool = false
) -> void:
	super._init(life_simulation, enable_developer_mode)
	v2_3_simulation = life_simulation as V23LifeLoopSimulation


func person_view(person_id: String = "") -> Dictionary:
	var view: Dictionary = super.person_view(person_id)
	if v2_3_simulation == null:
		return view
	var resolved_id: String = str(view.get("person_id", selected_person_id()))
	var position: Dictionary = v2_3_simulation.spatial_locations.position_for(
		resolved_id
	)
	var active_plan: Dictionary = (
		v2_3_simulation.travel_execution.active_plan_for_person(resolved_id)
	)
	var location_id: String = str(position.get("current_location_id", ""))
	view["current_location_id"] = location_id
	view["current_location"] = v2_3_simulation.spatial_locations.location_name(
		location_id, resolved_id, v2_3_simulation.truth_view
	)
	view["location_state"] = str(position.get("location_state", "at_location"))
	view["current_route_id"] = str(position.get("current_route_id", ""))
	view["travel_destination_id"] = str(
		position.get("travel_destination_id", active_plan.get("destination_id", ""))
	)
	view["travel_destination"] = v2_3_simulation.spatial_locations.location_name(
		str(view["travel_destination_id"]), resolved_id, v2_3_simulation.truth_view
	)
	view["expected_arrival_datetime"] = str(
		position.get(
			"expected_arrival_datetime",
			active_plan.get("expected_arrival_datetime", "")
		)
	)
	view["transport_modes"] = _plan_modes(active_plan)
	view["travel_cost_centimes"] = int(active_plan.get("total_cost_centimes", 0))
	view["unread_message_count"] = v2_3_simulation.communication.unread_count(
		resolved_id
	)
	view["knowledge_count"] = v2_3_simulation.knowledge.records_for_person(
		resolved_id
	).size()
	view["truth_view"] = v2_3_simulation.truth_view
	view["relationships"] = contact_options(resolved_id)
	view["relationship"] = (
		(view["relationships"] as Array)[0]
		if not (view["relationships"] as Array).is_empty()
		else {}
	)
	return view


func contact_options(person_id: String = "") -> Array[Dictionary]:
	if v2_3_simulation == null:
		return super.contact_options(person_id)
	var resolved_id: String = (
		selected_person_id() if person_id.is_empty() else person_id
	)
	var result: Array[Dictionary] = []
	for relation: Dictionary in (
		v2_3_simulation.dynamic_relationships.contact_candidates(
			resolved_id, v2_3_simulation.knowledge
		)
	):
		result.append({
			"target_id": str(relation.get("target_id", "")),
			"display_name_zh": str(relation.get("display_name_zh", "")),
			"native_name": str(relation.get("native_name", "")),
			"familiarity": int(relation.get("familiarity", 0)),
			"trust": int(relation.get("trust", 0)),
			"affinity": int(relation.get("affinity", 0)),
			"tension": int(relation.get("tension", 0)),
			"obligation": int(relation.get("obligation", 0)),
			"reciprocity": int(relation.get("reciprocity", 0)),
			"relationship_status": str(
				relation.get("relationship_status", "")
			),
			"known_contact_channels": (
				relation.get("known_contact_channels", []) as Array
			).duplicate(),
			"last_contact_datetime": str(
				relation.get("last_contact_datetime", "")
			),
			"recent_interactions": (
				relation.get("interaction_history", []) as Array
			).duplicate(true),
		})
	return result


func contact_name(target_id: String, _person_id: String = "") -> String:
	return _person_name(target_id)


func travel_destination_options(person_id: String = "") -> Array[Dictionary]:
	if v2_3_simulation == null:
		return []
	var resolved_id: String = (
		selected_person_id() if person_id.is_empty() else person_id
	)
	var position: Dictionary = v2_3_simulation.spatial_locations.position_for(
		resolved_id
	)
	var current_id: String = str(position.get("current_location_id", ""))
	var result: Array[Dictionary] = []
	for location: Dictionary in (
		v2_3_simulation.spatial_locations.known_locations(resolved_id)
	):
		var location_id: String = str(location.get("location_id", ""))
		if location_id == current_id:
			continue
		result.append({
			"location_id": location_id,
			"display_name": str(location.get("display_name", location_id)),
			"location_type": str(location.get("location_type", "")),
			"services": (
				location.get("available_services", []) as Array
			).duplicate(),
		})
	return result


func preview_travel(
	destination_id: String, preference: String = "fastest"
) -> V2LifeLoopResult:
	if v2_3_simulation == null:
		return V2LifeLoopResult.fail("v2_3_unavailable", "V2.3 旅行服务不可用")
	var result: V2LifeLoopResult = v2_3_simulation.preview_route(
		selected_person_id(), destination_id, preference
	)
	last_command_result = result
	route_preview = result.data.duplicate(true) if result.success else {}
	_view_revision += 1
	view_changed.emit()
	return result


func submit_travel() -> V2LifeLoopResult:
	if route_preview.is_empty():
		return V2LifeLoopResult.fail("route_not_previewed", "请先预览一条路线")
	var result: V2LifeLoopResult = v2_3_simulation.request_travel(
		selected_person_id(),
		str(route_preview.get("destination_id", "")),
		str(route_preview.get("route_preference", "fastest")),
		int(route_preview.get("departure_hour", -1))
	)
	last_command_result = result
	if result.success:
		route_preview.clear()
	_view_revision += 1
	view_changed.emit()
	return result


func messages_view(person_id: String = "") -> Dictionary:
	if v2_3_simulation == null:
		return {"inbox": [], "outbox": [], "unread_count": 0}
	var resolved_id: String = (
		selected_person_id() if person_id.is_empty() else person_id
	)
	return {
		"inbox": _decorate_messages(
			v2_3_simulation.communication.inbox(resolved_id)
		),
		"outbox": _decorate_messages(
			v2_3_simulation.communication.outbox(resolved_id)
		),
		"unread_count": v2_3_simulation.communication.unread_count(resolved_id),
	}


func read_message(message_id: String) -> V2LifeLoopResult:
	last_command_result = v2_3_simulation.read_message_now(
		selected_person_id(), message_id
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func send_greeting(target_id: String) -> V2LifeLoopResult:
	last_command_result = v2_3_simulation.send_private_message(
		selected_person_id(), target_id, "greeting",
		{"text": "希望近日能与你见面交谈。"}
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func knowledge_view(person_id: String = "") -> Array[Dictionary]:
	if v2_3_simulation == null:
		return []
	var resolved_id: String = (
		selected_person_id() if person_id.is_empty() else person_id
	)
	var records: Array[Dictionary] = (
		v2_3_simulation.knowledge.records_for_person(resolved_id)
	)
	records.reverse()
	return records


func known_people_view(person_id: String = "") -> Array[Dictionary]:
	if v2_3_simulation == null:
		return []
	var resolved_id: String = (
		selected_person_id() if person_id.is_empty() else person_id
	)
	var result: Array[Dictionary] = []
	for person: Dictionary in v2_3_simulation.v2_3_config.social_people():
		var target_id: String = str(person.get("person_id", ""))
		if (
			target_id != resolved_id
			and v2_3_simulation.knowledge.knows_person(resolved_id, target_id)
		):
			result.append({
				"person_id": target_id,
				"display_name_zh": str(person.get("display_name_zh", target_id)),
				"native_name": str(person.get("native_name", "")),
			})
	return result


func introduction_options() -> Array[Dictionary]:
	if v2_3_simulation == null:
		return []
	var requester_id: String = selected_person_id()
	var result: Array[Dictionary] = []
	for intermediary: Dictionary in contact_options(requester_id):
		var intermediary_id: String = str(intermediary.get("target_id", ""))
		for person: Dictionary in v2_3_simulation.v2_3_config.social_people():
			var target_id: String = str(person.get("person_id", ""))
			if (
				target_id == requester_id
				or v2_3_simulation.knowledge.knows_person(requester_id, target_id)
				or not v2_3_simulation.knowledge.knows_person(
					intermediary_id, target_id
				)
			):
				continue
			result.append({
				"intermediary_id": intermediary_id,
				"intermediary_name": str(
					intermediary.get("display_name_zh", intermediary_id)
				),
				"target_id": target_id,
				"target_name": str(person.get("display_name_zh", target_id)),
			})
	return result


func request_first_introduction() -> V2LifeLoopResult:
	var options: Array[Dictionary] = introduction_options()
	if options.is_empty():
		return V2LifeLoopResult.fail(
			"no_introduction_option", "当前没有可通过中间人介绍的陌生人物"
		)
	var option: Dictionary = options[0]
	last_command_result = v2_3_simulation.request_introduction(
		selected_person_id(),
		str(option.get("intermediary_id", "")),
		str(option.get("target_id", ""))
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func invite_contact(target_id: String) -> V2LifeLoopResult:
	var start_hour: int = _next_evening_hour()
	last_command_result = v2_3_simulation.invite_appointment(
		selected_person_id(), target_id, "location_lille_public_square",
		start_hour, start_hour + 1, "见面交谈"
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func set_truth_view(enabled: bool) -> V2LifeLoopResult:
	if not developer_mode and not v2_3_simulation.review_mode:
		return V2LifeLoopResult.fail(
			"truth_view_forbidden", "真相视图仅供评审或开发模式使用"
		)
	last_command_result = v2_3_simulation.set_truth_view(enabled)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func sandbox_view(person_id: String = "") -> Dictionary:
	var product: V23ProductSimulation = (
		v2_3_simulation as V23ProductSimulation
	)
	if product == null:
		return {
			"available": false,
			"situations": [],
			"goals": [],
			"methods": [],
			"tasks": [],
			"events": [],
			"explanation": {},
		}
	var resolved_id: String = (
		selected_person_id() if person_id.is_empty() else person_id
	)
	var person_goals: Array[Dictionary] = product.social_sandbox.goals_for(
		resolved_id
	)
	var selected_goal_id: String = (
		""
		if person_goals.is_empty()
		else str(person_goals.front().get("goal_id", ""))
	)
	return {
		"available": true,
		"person_id": resolved_id,
		"situations": product.social_sandbox.situations_for(resolved_id),
		"goals": person_goals,
		"selected_goal_id": selected_goal_id,
		"methods": product.social_sandbox.methods_for(
			resolved_id, selected_goal_id
		),
		"tasks": product.social_sandbox.tasks_for(resolved_id, true),
		"events": product.social_sandbox.visible_events_for(
			resolved_id, product.truth_view, 12
		),
		"explanation": (
			product.social_sandbox.explanation_for(resolved_id)
			if product.truth_view
			else {}
		),
	}


func submit_sandbox_method(
	goal_id: String, method_id: String, target_id: String = ""
) -> V2LifeLoopResult:
	var product: V23ProductSimulation = (
		v2_3_simulation as V23ProductSimulation
	)
	if product == null:
		return V2LifeLoopResult.fail(
			"sandbox_unavailable", "社会沙盒行动服务不可用"
		)
	last_command_result = product.social_sandbox.submit_intent(
		selected_person_id(),
		goal_id,
		method_id,
		target_id,
		"player",
		{"current_hour": product.clock.total_hours, "preparation": 250}
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func map_overlay_payload() -> Dictionary:
	if v2_3_simulation == null:
		return {}
	var observer_id: String = selected_person_id()
	var truth: bool = v2_3_simulation.truth_view
	var locations: Array[Dictionary] = []
	var location_ids: Array[String] = []
	for raw_id: Variant in v2_3_simulation.spatial_locations.locations.keys():
		location_ids.append(str(raw_id))
	location_ids.sort()
	for location_id: String in location_ids:
		var location: Dictionary = (
			v2_3_simulation.spatial_locations.get_location(location_id)
		)
		var visible: bool = (
			truth
			or v2_3_simulation.spatial_locations.knows_location(
				observer_id, location_id
			)
		)
		locations.append({
			"location_id": location_id,
			"display_name": (
				str(location.get("display_name", location_id)) if visible else ""
			),
			"world_position": (
				location.get("world_position", []) as Array
			).duplicate(),
			"location_type": str(location.get("location_type", "")),
			"visible": visible,
		})
	var edges: Array[Dictionary] = []
	var edge_ids: Array[String] = []
	for raw_id: Variant in v2_3_simulation.travel_graph.edges.keys():
		edge_ids.append(str(raw_id))
	edge_ids.sort()
	for edge_id: String in edge_ids:
		var edge: Dictionary = v2_3_simulation.travel_graph.get_edge(edge_id)
		edges.append({
			"edge_id": edge_id,
			"from_location_id": str(edge.get("from_location_id", "")),
			"to_location_id": str(edge.get("to_location_id", "")),
			"available_modes": (
				edge.get("available_modes", []) as Array
			).duplicate(),
			"visible": (
				truth
				or v2_3_simulation.travel_graph.knows_edge(observer_id, edge_id)
			),
		})
	var active_plan: Dictionary = (
		v2_3_simulation.travel_execution.active_plan_for_person(observer_id)
	)
	var observer_position: Dictionary = (
		v2_3_simulation.spatial_locations.position_for(observer_id)
	)
	var positions: Array[Dictionary] = []
	for person: Dictionary in v2_3_simulation.v2_3_config.social_people():
		var person_id: String = str(person.get("person_id", ""))
		var position: Dictionary = (
			v2_3_simulation.spatial_locations.position_for(person_id)
		)
		var co_located: bool = (
			str(position.get("location_state", "")) == "at_location"
			and str(observer_position.get("location_state", "")) == "at_location"
			and str(position.get("current_location_id", ""))
			== str(observer_position.get("current_location_id", ""))
		)
		position["visible"] = truth or person_id == observer_id or co_located
		position["segment_progress"] = _segment_progress(position, active_plan)
		positions.append(position)
	return {
		"catalog_revision": int(
			v2_3_simulation.v2_3_config.get_document("locations").get(
				"config_version", 1
			)
		),
		"overlay_revision": _view_revision,
		"observer_id": observer_id,
		"truth_view": truth,
		"locations": locations,
		"edges": edges,
		"active_route_segments": (
			active_plan.get("route_segments", []) as Array
		).duplicate(true),
		"preview_route_segments": (
			route_preview.get("route_segments", []) as Array
		).duplicate(true),
		"person_positions": positions,
	}


func save_review() -> V2LifeLoopResult:
	var saved: SaveOperationResult = v2_3_save_service.save(v2_3_simulation)
	last_command_result = (
		V2LifeLoopResult.ok("V2.3 进度已保存：%s" % saved.path)
		if saved.success
		else V2LifeLoopResult.fail(saved.error_code, saved.message, saved.path)
	)
	view_changed.emit()
	return last_command_result


func load_review() -> V2LifeLoopResult:
	var loaded: SaveOperationResult = v2_3_save_service.load()
	if not loaded.success:
		last_command_result = V2LifeLoopResult.fail(
			loaded.error_code, loaded.message, loaded.path
		)
	else:
		var restored: SaveOperationResult = v2_3_save_service.restore(
			loaded.snapshot, v2_3_simulation
		)
		last_command_result = (
			V2LifeLoopResult.ok("V2.3 进度已载入")
			if restored.success
			else V2LifeLoopResult.fail(
				restored.error_code, restored.message, restored.path
			)
		)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func migrate_v2_2_review() -> V2LifeLoopResult:
	var migrated: SaveOperationResult = save_migration.migrate_file()
	if not migrated.success:
		last_command_result = V2LifeLoopResult.fail(
			migrated.error_code, migrated.message, migrated.path
		)
		view_changed.emit()
		return last_command_result
	return load_review()


func developer_command(command: String) -> V2LifeLoopResult:
	if command == "truth_toggle":
		return set_truth_view(not v2_3_simulation.truth_view)
	if command == "deliver_messages":
		var deliveries: Array[V2LifeLoopResult] = (
			v2_3_simulation.communication.process_deliveries(
				v2_3_simulation.clock.total_hours
			)
		)
		last_command_result = V2LifeLoopResult.ok(
			"已处理 %d 封到期消息" % deliveries.size()
		)
		_view_revision += 1
		view_changed.emit()
		return last_command_result
	return super.developer_command(command)


func debug_state() -> Dictionary:
	var state: Dictionary = super.debug_state()
	state["v2_3"] = true
	state["v2_3_schema_version"] = V23LifeLoopSimulation.V2_3_SCHEMA_VERSION
	state["route_preview"] = route_preview.duplicate(true)
	state["unread_message_count"] = (
		v2_3_simulation.communication.unread_count(selected_person_id())
	)
	state["knowledge_count"] = (
		v2_3_simulation.knowledge.records_for_person(selected_person_id()).size()
	)
	state["truth_view"] = v2_3_simulation.truth_view
	state["map_overlay_revision"] = _view_revision
	state["review_save_path"] = V23SaveService.REVIEW_PATH
	var product: V23ProductSimulation = (
		v2_3_simulation as V23ProductSimulation
	)
	if product != null:
		state["social_sandbox"] = {
			"event_count": product.social_sandbox.event_ledger.size(),
			"task_count": product.social_sandbox.tasks.size(),
			"commitment_count": product.social_sandbox.commitments.size(),
			"evidence_count": product.social_sandbox.evidence_records.size(),
			"last_hour": product.last_social_sandbox_hour.duplicate(true),
			"selected_explanation": (
				product.social_sandbox.explanation_for(
					selected_person_id()
				)
			),
		}
	return state


func _on_state_changed(change_set: Dictionary) -> void:
	_view_revision += 1
	super._on_state_changed(change_set)


func _decorate_messages(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for message: Dictionary in source:
		var decorated: Dictionary = message.duplicate(true)
		decorated["sender_name"] = _person_name(
			str(message.get("sender_person_id", ""))
		)
		decorated["recipient_name"] = _person_name(
			str(message.get("recipient_person_id", ""))
		)
		result.append(decorated)
	return result


func _person_name(person_id: String) -> String:
	if v2_3_simulation == null:
		return person_id
	for person: Dictionary in v2_3_simulation.v2_3_config.social_people():
		if str(person.get("person_id", "")) == person_id:
			return str(person.get("display_name_zh", person_id))
	return person_id


func _plan_modes(plan: Dictionary) -> Array[String]:
	var modes: Array[String] = []
	for raw_segment: Variant in plan.get("route_segments", []) as Array:
		var mode_id: String = str(
			(raw_segment as Dictionary).get("mode_id", "")
		)
		if not mode_id.is_empty() and mode_id not in modes:
			modes.append(mode_id)
	return modes


func _next_evening_hour() -> int:
	var current_hour: int = v2_3_simulation.clock.total_hours
	var value: Dictionary = V2DateTime.from_total_hour(current_hour)
	var start_of_day: int = current_hour - int(value.get("hour", 0))
	var candidate: int = start_of_day + 18
	if candidate <= current_hour + 24:
		candidate += 24
	return candidate


func _segment_progress(position: Dictionary, active_plan: Dictionary) -> float:
	if str(position.get("location_state", "")) != "in_transit":
		return 0.0
	var edge_id: String = str(position.get("current_edge_id", ""))
	for raw_segment: Variant in active_plan.get("route_segments", []) as Array:
		var segment: Dictionary = raw_segment as Dictionary
		if str(segment.get("edge_id", "")) != edge_id:
			continue
		var departure: int = int(segment.get("departure_hour", 0))
		var arrival: int = int(segment.get("arrival_hour", departure + 1))
		return clampf(
			float(v2_3_simulation.clock.total_hours - departure)
			/ float(maxi(1, arrival - departure)),
			0.0,
			1.0
		)
	return 0.5
