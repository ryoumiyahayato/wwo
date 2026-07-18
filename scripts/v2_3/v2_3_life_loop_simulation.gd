class_name V23LifeLoopSimulation
extends V2LifeLoopSimulationPolish
## V2.3 composition root on the existing V2.2 clock, schedule and economy.

const V2_3_SCHEMA_VERSION: String = "v2_3_space_cognition_1"
const JULES_ID: String = "character_jules_martin"
const LUCIEN_ID: String = "character_lucien_moreau"
const FORMAL_PERSON_IDS: PackedStringArray = [PIERRE_ID, ALBERT_ID]
const TRAVEL_TYPES: PackedStringArray = [
	"wait_for_transport", "travel_walk", "travel_urban_transit",
	"travel_regional_train",
]
const LOCATION_ALIASES: Dictionary = {
	"location:pierre_home": "location_lille_pierre_home",
	"location:albert_home": "location_lille_albert_home",
	"location:lille_mechanical_factory": "location_lille_fives_factory",
	"location:prefecture_nord": "location_lille_prefecture_office",
	"location:lille_living_goods": "location_lille_wazemmes_market",
	"location:metalworkers_nord_hall": "location_lille_metalworkers_union_hall",
}

var v2_3_config := V23Config.new()
var spatial_locations := SpatialLocationService.new()
var travel_graph := TravelGraphService.new()
var route_planner := RoutePlannerService.new()
var travel_execution := TravelExecutionService.new()
var communication := CommunicationService.new()
var knowledge := KnowledgeService.new()
var dynamic_relationships := V23RelationshipService.new()
var appointments := SocialAppointmentService.new()
var introductions := SocialIntroductionService.new()
var npc_routines := SpatialNpcRoutineService.new()

var truth_view: bool = false
var review_mode: bool = true
var background_person_ids: Array[String] = []
var v2_3_initialization_error: String = ""
var v2_3_hours_processed: int = 0
var last_delivery_count: int = 0
var last_knowledge_expiration_count: int = 0
var last_appointment_result_count: int = 0
var local_overlay_revision: int = 0
var public_notice_id: String = ""
var _commute_planned_through_day: int = -1


func initialize(simulation_clock: SimulationClock = null) -> bool:
	if not super.initialize(simulation_clock):
		return false
	if v2_3_config.load_all() != OK:
		v2_3_initialization_error = "; ".join(v2_3_config.errors)
		initialization_error = v2_3_initialization_error
		initialized = false
		return false
	var start_hour: int = V2DateTime.total_hour_from_iso(
		str(v2_3_config.scenario().get("start_datetime", ""))
	)
	if start_hour < 0:
		return _fail_v2_3_initialization("V2.3 场景起始时间无效")
	var start_value: Dictionary = V2DateTime.from_total_hour(start_hour)
	if not clock.set_datetime_for_debug(
		int(start_value.get("year", 1900)),
		int(start_value.get("month", 1)),
		int(start_value.get("day", 1)),
		int(start_value.get("hour", 0))
	):
		return _fail_v2_3_initialization("无法把权威时钟定位到 V2.3 起点")
	random.set_seed(int(v2_3_config.scenario().get("random_seed", 2301900)))
	_initialize_state(start_hour)
	var people: Array = v2_3_config.social_people()
	var location_result: V2LifeLoopResult = spatial_locations.configure(
		v2_3_config.location_records(), people, start_hour
	)
	if not location_result.success:
		return _fail_v2_3_initialization(location_result.user_message)
	var graph_result: V2LifeLoopResult = travel_graph.configure(
		v2_3_config.edge_records(), v2_3_config.transport_records(), spatial_locations
	)
	if not graph_result.success:
		return _fail_v2_3_initialization(graph_result.user_message)
	route_planner.configure(travel_graph, spatial_locations)
	var balance: Dictionary = v2_3_config.get_document("balance")
	travel_execution.configure(
		spatial_locations, travel_graph, route_planner, balance
	)
	knowledge.configure(
		people, v2_3_config.get_document("knowledge"), spatial_locations, start_hour
	)
	var relationship_result: V2LifeLoopResult = dynamic_relationships.configure(
		v2_3_config.relationship_records(),
		v2_3_config.get_document("relationships"),
		people,
		int((balance.get("history_limits", {}) as Dictionary).get("idempotency_keys", 1024))
	)
	if not relationship_result.success:
		return _fail_v2_3_initialization(relationship_result.user_message)
	var communication_result: V2LifeLoopResult = communication.configure(
		people,
		v2_3_config.get_document("communication").get("channels", []) as Array,
		balance
	)
	if not communication_result.success:
		return _fail_v2_3_initialization(communication_result.user_message)
	appointments.configure(balance)
	introductions.configure()
	npc_routines.configure(people, balance, start_hour)
	_configure_shared_schedule(people, start_hour)
	_sync_formal_person_states()
	_initialize_background_people(people)
	_commute_planned_through_day = -1
	_replace_fixed_commutes(start_hour, "scenario_initialization")
	_seed_public_notice(start_hour)
	truth_view = false
	review_mode = bool(v2_3_config.scenario().get("review_mode_default", true))
	selected_person_id = str(
		v2_3_config.scenario().get("default_selected_person_id", PIERRE_ID)
	)
	v2_3_hours_processed = 0
	last_delivery_count = 0
	last_knowledge_expiration_count = 0
	last_appointment_result_count = 0
	local_overlay_revision = 1
	state_changed.emit({"v2_3_initialized": true, "local_overlay": local_overlay_revision})
	return true


func reset_scenario() -> V2LifeLoopResult:
	if not initialize(clock):
		return V2LifeLoopResult.fail(
			"v2_3_reset_failed", "V2.3 场景重置失败", initialization_error
		)
	return V2LifeLoopResult.ok("V2.3 场景已重置")


func request_travel(
	person_id: String,
	destination_id: String,
	preference: String = "fastest",
	start_hour: int = -1
) -> V2LifeLoopResult:
	var actual_start: int = clock.total_hours + 1 if start_hour < 0 else start_hour
	var household: Dictionary = households.household_for_person(person_id)
	var fatigue: int = int(conditions.get_state(person_id).get("fatigue", 0))
	var plan_result: V2LifeLoopResult = travel_execution.create_plan(
		person_id, destination_id, preference, actual_start,
		int(household.get("cash_centimes", 0)), fatigue
	)
	if not plan_result.success:
		return plan_result
	var plan: Dictionary = plan_result.data.get("travel_plan", {}) as Dictionary
	var scheduled: V2LifeLoopResult = travel_execution.schedule_plan(
		str(plan.get("travel_plan_id", "")), schedule, clock.total_hours, "player"
	)
	if scheduled.success:
		local_overlay_revision += 1
		state_changed.emit({
			"travel_plan": str(plan.get("travel_plan_id", "")),
			"local_overlay": local_overlay_revision,
		})
	return scheduled


func preview_route(
	person_id: String,
	destination_id: String,
	preference: String = "fastest",
	start_hour: int = -1
) -> V2LifeLoopResult:
	var position: Dictionary = spatial_locations.position_for(person_id)
	var household: Dictionary = households.household_for_person(person_id)
	return route_planner.plan_route(
		person_id,
		str(position.get("current_location_id", "")),
		destination_id,
		clock.total_hours + 1 if start_hour < 0 else start_hour,
		preference,
		int(household.get("cash_centimes", 0)),
		int(conditions.get_state(person_id).get("fatigue", 0))
	)


func send_private_message(
	sender_id: String,
	recipient_id: String,
	content_type: String,
	payload: Dictionary
) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = communication.send_message(
		sender_id, recipient_id, "local_letter", content_type, payload,
		clock.total_hours, spatial_locations, knowledge, dynamic_relationships,
		households, ledger
	)
	if result.success:
		state_changed.emit({"messages": true})
	return result


func request_introduction(
	requester_id: String, intermediary_id: String, target_id: String
) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = introductions.request_introduction(
		requester_id, intermediary_id, target_id, clock.total_hours,
		communication, spatial_locations, knowledge, dynamic_relationships,
		households, ledger
	)
	if result.success:
		state_changed.emit({"messages": true, "introductions": true})
	return result


func invite_appointment(
	initiator_id: String,
	participant_id: String,
	location_id: String,
	start_hour: int,
	end_hour: int,
	purpose: String
) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = appointments.invite(
		initiator_id, participant_id, location_id, start_hour, end_hour, purpose,
		clock.total_hours, spatial_locations, communication, knowledge,
		dynamic_relationships, households, ledger
	)
	if result.success:
		state_changed.emit({"appointments": true, "messages": true})
	return result


func read_message_now(person_id: String, message_id: String) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = communication.read_message(
		person_id, message_id, clock.total_hours, knowledge
	)
	if result.success:
		_process_message_consequence(person_id, message_id, clock.total_hours)
		state_changed.emit({"messages": true, "knowledge": true})
	return result


func observe_public_notice(person_id: String) -> V2LifeLoopResult:
	var position: Dictionary = spatial_locations.position_for(person_id)
	var result: V2LifeLoopResult = communication.read_public_notice(
		person_id, public_notice_id,
		str(position.get("current_location_id", "")),
		clock.total_hours, knowledge
	)
	if result.success:
		state_changed.emit({"knowledge": true})
	return result


func set_truth_view(enabled: bool) -> V2LifeLoopResult:
	truth_view = enabled
	state_changed.emit({"truth_view": truth_view})
	return V2LifeLoopResult.ok(
		"开发者真相视角已%s" % ("开启" if enabled else "关闭"),
		{"truth_view": truth_view}
	)


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["schema_version"] = V2_3_SCHEMA_VERSION
	state["v2_3_scenario_id"] = str(v2_3_config.scenario().get("scenario_id", ""))
	state["spatial_state"] = spatial_locations.get_persistent_state()
	state["travel_graph_state"] = travel_graph.get_persistent_state()
	state["travel_state"] = travel_execution.get_persistent_state()
	state["communication_state"] = communication.get_persistent_state()
	state["knowledge_state"] = knowledge.get_persistent_state()
	state["dynamic_relationship_state"] = dynamic_relationships.get_persistent_state()
	state["appointment_state"] = appointments.get_persistent_state()
	state["introduction_state"] = introductions.get_persistent_state()
	state["npc_spatial_state"] = npc_routines.get_persistent_state()
	state["truth_view"] = truth_view
	state["review_mode"] = review_mode
	state["background_person_ids"] = background_person_ids.duplicate()
	state["v2_3_hours_processed"] = v2_3_hours_processed
	state["local_overlay_revision"] = local_overlay_revision
	state["public_notice_id"] = public_notice_id
	state["commute_planned_through_day"] = _commute_planned_through_day
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	if str(state.get("schema_version", "")) != V2_3_SCHEMA_VERSION:
		return V2LifeLoopResult.fail(
			"incompatible_version", "V2.3 存档版本不兼容",
			str(state.get("schema_version", ""))
		)
	for field: String in [
		"spatial_state", "travel_graph_state", "travel_state",
		"communication_state", "knowledge_state", "dynamic_relationship_state",
		"appointment_state", "introduction_state", "npc_spatial_state",
	]:
		if not state.get(field, {}) is Dictionary:
			return V2LifeLoopResult.fail(
				"corrupt_save", "V2.3 存档字段损坏：%s" % field, field
			)
	if not state.get("background_person_ids", []) is Array:
		return V2LifeLoopResult.fail("corrupt_save", "背景人物索引损坏")
	return V2LifeLoopResult.ok("V2.3 存档结构有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var validation: V2LifeLoopResult = validate_v2_3_state(state)
	if not validation.success:
		return validation
	var previous: Dictionary = get_persistent_state()
	if not _apply_v2_3_state(state):
		if not _apply_v2_3_state(previous):
			push_error("V2.3 载入失败后无法恢复原运行状态")
		return V2LifeLoopResult.fail(
			"restore_failed", "V2.3 存档载入失败，当前状态保持不变"
		)
	state_changed.emit({"loaded": true, "v2_3": true})
	return V2LifeLoopResult.ok("V2.3 存档已载入")


func determinism_snapshot() -> Dictionary:
	return {
		"time": V2DateTime.iso_from_total_hour(clock.total_hours),
		"person_positions": spatial_locations.person_positions.duplicate(true),
		"travel": travel_execution.get_persistent_state(),
		"travel_costs": _transport_transactions(),
		"schedule": schedule.get_persistent_state(),
		"attendance": employment.attendance_records.duplicate(true),
		"households": households.get_persistent_state(),
		"ledger": ledger.get_persistent_state(),
		"conditions": conditions.get_persistent_state(),
		"messages": communication.get_persistent_state(),
		"knowledge": knowledge.get_persistent_state(),
		"known_locations": spatial_locations.known_location_ids.duplicate(true),
		"known_people": _known_people_snapshot(),
		"relationships": dynamic_relationships.get_persistent_state(),
		"appointments": appointments.get_persistent_state(),
		"introductions": introductions.get_persistent_state(),
		"npc": npc_routines.get_persistent_state(),
	}


func _settle_hour(total_hour: int) -> void:
	super._settle_hour(total_hour)
	_process_background_hour(total_hour)
	var delivery_results: Array[V2LifeLoopResult] = communication.process_deliveries(
		total_hour + 1
	)
	last_delivery_count = delivery_results.size()
	for delivery: V2LifeLoopResult in delivery_results:
		var message: Dictionary = delivery.data.get("message", {}) as Dictionary
		var recipient_id: String = str(message.get("recipient_person_id", ""))
		var message_id: String = str(message.get("message_id", ""))
		npc_routines.queue_message(recipient_id, message_id)
		_schedule_npc_message_read(recipient_id, message_id, total_hour + 1)
	last_knowledge_expiration_count = knowledge.expire_due(total_hour + 1)
	var appointment_results: Array[V2LifeLoopResult] = appointments.process_hour(
		total_hour, spatial_locations, dynamic_relationships
	)
	last_appointment_result_count = appointment_results.size()
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if int(value.get("hour", -1)) == 23:
		travel_execution.expire_stale_plans(total_hour + 1)
		_replace_fixed_commutes(total_hour + 1, "new_day")
	v2_3_hours_processed += 1
	if (
		last_delivery_count > 0
		or last_knowledge_expiration_count > 0
		or last_appointment_result_count > 0
	):
		state_changed.emit({
			"messages": last_delivery_count,
			"knowledge_expired": last_knowledge_expiration_count,
			"appointments": last_appointment_result_count,
		})


func _apply_activity_location(
	person_id: String, activity: Dictionary, total_hour: int
) -> void:
	var activity_type: String = str(activity.get("activity_type", ""))
	if activity_type in TRAVEL_TYPES:
		var result: V2LifeLoopResult = travel_execution.settle_activity(
			person_id, activity, total_hour, households, ledger, conditions
		)
		if not result.success:
			schedule.set_activity_result(
				person_id, str(activity.get("activity_id", "")), false,
				result.to_dict(), result.error_code
			)
	var position: Dictionary = spatial_locations.position_for(person_id)
	var person_state: Dictionary = person_states[person_id] as Dictionary
	person_state["current_location_id"] = str(position.get("current_location_id", ""))
	person_state["location_state"] = str(position.get("location_state", ""))
	person_state["current_route_id"] = str(position.get("current_route_id", ""))
	person_state["expected_arrival_datetime"] = str(
		position.get("expected_arrival_datetime", "")
	)
	person_states[person_id] = person_state
	if activity_type in TRAVEL_TYPES:
		local_overlay_revision += 1


func _record_employment_hour(
	person_id: String,
	total_hour: int,
	activity_type: String,
	activity: Dictionary,
	condition_rules: Dictionary
) -> void:
	var effective_type: String = activity_type
	if employment.is_required_work_hour(person_id, total_hour):
		var position: Dictionary = spatial_locations.position_for(person_id)
		var required_location: String = _workplace_for(person_id)
		var present: bool = (
			activity_type == "work"
			and str(position.get("location_state", "")) == "at_location"
			and str(position.get("current_location_id", "")) == required_location
		)
		if not present:
			effective_type = "absence"
	employment.record_hour(person_id, total_hour, effective_type, condition_rules)
	if effective_type != activity_type:
		schedule.set_activity_result(
			person_id, str(activity.get("activity_id", "")), false,
			{"location_failure": true, "required_location_id": _workplace_for(person_id)},
			"not_at_workplace"
		)


func _apply_activity_condition(
	person_id: String,
	activity_type: String,
	activity: Dictionary,
	total_hour: int
) -> void:
	if activity_type in TRAVEL_TYPES:
		return
	var position: Dictionary = spatial_locations.position_for(person_id)
	if activity_type in ["sleep", "rest"]:
		var home_id: String = _home_for(person_id)
		if (
			str(position.get("location_state", "")) != "at_location"
			or str(position.get("current_location_id", "")) != home_id
		):
			return
	if activity_type == "work" and str(position.get("current_location_id", "")) != _workplace_for(person_id):
		conditions.apply_activity(person_id, "absence", total_hour)
		return
	super._apply_activity_condition(person_id, activity_type, activity, total_hour)


func _complete_activity(
	person_id: String, activity: Dictionary, total_hour: int
) -> void:
	var activity_type: String = str(activity.get("activity_type", ""))
	if activity_type in TRAVEL_TYPES:
		return
	if activity_type in ["purchase_food", "purchase_essentials"]:
		if not _at_service_location(person_id, activity_type, total_hour):
			schedule.set_activity_result(
				person_id, str(activity.get("activity_id", "")), false,
				{"required_service": activity_type}, "remote_purchase_rejected"
			)
			return
	if activity_type == "union_activity":
		if not _at_location(person_id, "location_lille_metalworkers_union_hall"):
			schedule.set_activity_result(
				person_id, str(activity.get("activity_id", "")), false,
				{}, "not_at_union_hall"
			)
			return
	if activity_type == "social_contact":
		_complete_face_to_face(person_id, activity, total_hour)
		return
	if activity_type == "read_message":
		var message_id: String = str(activity.get("message_id", ""))
		var read: V2LifeLoopResult = communication.read_message(
			person_id, message_id, total_hour + 1, knowledge
		)
		if read.success:
			_process_message_consequence(person_id, message_id, total_hour + 1)
		else:
			schedule.set_activity_result(
				person_id, str(activity.get("activity_id", "")), false,
				read.to_dict(), read.error_code
			)
		return
	if activity_type == "write_message" or activity_type == "meet_person":
		return
	super._complete_activity(person_id, activity, total_hour)


func _process_background_hour(total_hour: int) -> void:
	for person_id: String in background_person_ids:
		schedule.ensure_future(person_id, total_hour, "background_horizon")
		var activity: Dictionary = schedule.begin_hour(person_id, total_hour)
		if activity.is_empty():
			continue
		var activity_type: String = str(activity.get("activity_type", ""))
		if activity_type in TRAVEL_TYPES:
			var result: V2LifeLoopResult = travel_execution.settle_activity(
				person_id, activity, total_hour
			)
			if not result.success:
				schedule.set_activity_result(
					person_id, str(activity.get("activity_id", "")), false,
					result.to_dict(), result.error_code
				)
		var completed: Dictionary = schedule.finish_hour(
			person_id, total_hour, str(activity.get("activity_id", ""))
		)
		if completed.is_empty():
			continue
		if activity_type == "read_message":
			var message_id: String = str(activity.get("message_id", ""))
			var read: V2LifeLoopResult = communication.read_message(
				person_id, message_id, total_hour + 1, knowledge
			)
			if read.success:
				_process_message_consequence(person_id, message_id, total_hour + 1)


func _process_message_consequence(
	person_id: String, message_id: String, total_hour: int
) -> void:
	var message: Dictionary = communication.get_message(message_id)
	var content_type: String = str(message.get("content_type", ""))
	var introduction_request: Dictionary = introductions.request_for_message(message_id)
	if content_type == "introduction_request" and not introduction_request.is_empty():
		var intermediary_id: String = str(introduction_request.get("intermediary_id", ""))
		var requester_id: String = str(introduction_request.get("requester_id", ""))
		var relation: Dictionary = dynamic_relationships.get_relationship(
			intermediary_id, requester_id
		)
		var accept: bool = npc_routines.deterministic_accepts_relationship_request(
			relation, 0, true
		)
		introductions.decide_after_read(
			str(introduction_request.get("request_id", "")), total_hour, accept,
			communication, spatial_locations, knowledge, dynamic_relationships
		)
	elif content_type == "introduction" and not introduction_request.is_empty():
		introductions.complete_after_read(
			str(introduction_request.get("request_id", "")), total_hour,
			communication, knowledge, dynamic_relationships
		)
	elif content_type == "appointment_invitation":
		var appointment_id: String = str(
			(message.get("payload", {}) as Dictionary).get("appointment_id", "")
		)
		if appointments.appointments.has(appointment_id):
			appointments.respond(
				appointment_id, person_id, true, total_hour, schedule,
				communication, spatial_locations, knowledge, dynamic_relationships
			)
	elif content_type == "greeting":
		communication.reply_message(
			person_id, message_id, "greeting_reply",
			{
				"fact_id": "private_reply:%s" % message_id,
				"subject_id": str(message.get("sender_person_id", "")),
				"fact_type": "private_reply",
				"claim": "问候已回复",
			},
			total_hour, spatial_locations, knowledge, dynamic_relationships
		)
	elif content_type == "greeting_reply":
		var sender_id: String = str(message.get("sender_person_id", ""))
		if dynamic_relationships.has_relationship(person_id, sender_id):
			dynamic_relationships.apply_interaction(
				person_id, sender_id, "private_reply",
				"reply_read:%s" % message_id, total_hour,
				"私人问候回复实际送达并被阅读"
			)


func _complete_face_to_face(
	person_id: String, activity: Dictionary, total_hour: int
) -> void:
	var target_id: String = str(activity.get("related_entity_id", ""))
	var first: Dictionary = spatial_locations.position_for(person_id)
	var second: Dictionary = spatial_locations.position_for(target_id)
	if (
		second.is_empty()
		or str(first.get("location_state", "")) != "at_location"
		or str(second.get("location_state", "")) != "at_location"
		or str(first.get("current_location_id", ""))
		!= str(second.get("current_location_id", ""))
	):
		schedule.set_activity_result(
			person_id, str(activity.get("activity_id", "")), false,
			{}, "face_to_face_requires_same_location"
		)
		return
	var result: V2LifeLoopResult = dynamic_relationships.apply_interaction(
		person_id, target_id, "face_to_face",
		str(activity.get("activity_id", "")), total_hour + 1,
		"双方同地且在同一小时完成面对面交流"
	)
	if result.success:
		conditions.apply_delta(
			person_id, "stress", -15, total_hour,
			"面对面交流缓解压力", "face_to_face",
			str(activity.get("activity_id", ""))
		)


func _configure_shared_schedule(people: Array, start_hour: int) -> void:
	var combined: Array = config.person_records().duplicate(true)
	for raw_person: Variant in people:
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		if person_id in FORMAL_PERSON_IDS:
			continue
		var schedule_person: Dictionary = person.duplicate(true)
		schedule_person["default_schedule"] = {
			"sleep_start_hour": 22,
			"sleep_end_hour": 6,
			"commute_to_work_start_hour": 7,
			"meal_break_start_hour": 12,
			"commute_home_start_hour": 16,
		}
		combined.append(schedule_person)
	schedule.configure(
		combined, employment, start_hour, config.get_document("balance")
	)
	_plan_life_needs(start_hour, "v2_3_shared_schedule")


func _initialize_background_people(people: Array) -> void:
	background_person_ids.clear()
	for raw_person: Variant in people:
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		if person_id not in FORMAL_PERSON_IDS:
			background_person_ids.append(person_id)
	background_person_ids.sort()


func _replace_fixed_commutes(start_hour: int, reason: String) -> void:
	# The shared schedule guarantees a 48-hour future window. Planning one
	# additional day absorbs route waiting. Only the newly exposed tail (plus
	# one retry day) is routed: rebuilding the full rolling horizon every
	# midnight adds deterministic work without changing any authoritative
	# activity.
	var configured_horizon: int = int(
		(v2_3_config.get_document("balance").get("npc", {}) as Dictionary).get(
			"background_schedule_horizon_hours", 48
		)
	)
	var horizon: int = start_hour + maxi(48, configured_horizon) + 24
	var target_through_day: int = _day_start(horizon - 1) + 24
	var planning_start: int = _day_start(start_hour)
	if _commute_planned_through_day >= 0:
		planning_start = maxi(
			planning_start, _commute_planned_through_day - 24
		)
	for person_id: String in FORMAL_PERSON_IDS:
		schedule.cancel_future_activity_types(
			person_id,
			PackedStringArray(["commute_to_work", "commute_home"]),
			start_hour,
			"replaced_by_v2_3_route"
		)
		if planning_start < target_through_day:
			_plan_formal_commutes(
				person_id, planning_start, target_through_day, reason
			)
	for person_id: String in background_person_ids:
		schedule.cancel_future_activity_types(
			person_id,
			PackedStringArray(["commute_to_work", "commute_home"]),
			start_hour,
			"replaced_by_v2_3_route"
		)
		if planning_start < target_through_day:
			_plan_background_routine(
				person_id, planning_start, target_through_day, reason
			)
	_commute_planned_through_day = maxi(
		_commute_planned_through_day, target_through_day
	)


func _plan_formal_commutes(
	person_id: String, start_hour: int, horizon: int, reason: String
) -> void:
	var contract: Dictionary = employment.contract_for_person(person_id)
	var home_id: String = _home_for(person_id)
	var workplace_id: String = _workplace_for(person_id)
	var cash: int = int(households.household_for_person(person_id).get("cash_centimes", 0))
	var fatigue: int = int(conditions.get_state(person_id).get("fatigue", 0))
	var preference: String = "fastest" if person_id == PIERRE_ID else "cheapest"
	for day_start: int in range(
		_day_start(start_hour), horizon, 24
	):
		var value: Dictionary = V2DateTime.from_total_hour(day_start)
		if int(value.get("weekday", -1)) not in (contract.get("work_days", []) as Array):
			continue
		var segments: Array = contract.get("shift_segments", []) as Array
		if segments.is_empty():
			continue
		var work_start: int = day_start + int((segments[0] as Dictionary).get("start_hour", 8))
		var work_end: int = day_start + int(
			(segments[-1] as Dictionary).get("end_hour", 17)
		)
		var commute_duration: int = 1
		var proposed_start: int = work_start - commute_duration
		_schedule_commute(
			person_id, home_id, workplace_id, proposed_start, preference,
			cash, fatigue, "work:%s" % V2DateTime.date_from_total_hour(day_start), reason
		)
		_schedule_commute(
			person_id, workplace_id, home_id, work_end, preference,
			cash, fatigue, "return:%s" % V2DateTime.date_from_total_hour(day_start), reason
		)


func _plan_background_routine(
	person_id: String, start_hour: int, horizon: int, reason: String
) -> void:
	var person: Dictionary = _social_person(person_id)
	var home_id: String = str(person.get("home_location_id", ""))
	var workplace_id: String = str(person.get("workplace_location_id", ""))
	for day_start: int in range(_day_start(start_hour), horizon, 24):
		var weekday: int = int(V2DateTime.from_total_hour(day_start).get("weekday", -1))
		if weekday >= 5:
			continue
		var work_start: int = day_start + 8
		var work_end: int = day_start + 16
		if work_start >= start_hour:
			schedule.schedule_rule_activity(
				person_id, "work", work_start, 8, workplace_id, "npc_rule",
				"background_work:%s" % person_id
			)
		_schedule_commute(
			person_id, home_id, workplace_id, work_start - 1, "cheapest",
			0, 0, "background_work", reason
		)
		_schedule_commute(
			person_id, workplace_id, home_id, work_end, "cheapest",
			0, 0, "background_return", reason
		)


func _schedule_commute(
	person_id: String,
	origin_id: String,
	destination_id: String,
	departure_hour: int,
	preference: String,
	cash: int,
	fatigue: int,
	purpose_id: String,
	reason: String
) -> void:
	if departure_hour < clock.total_hours:
		return
	if travel_execution.has_nonterminal_plan(
		person_id, origin_id, destination_id, departure_hour
	):
		return
	var plan_result: V2LifeLoopResult = travel_execution.create_plan(
		person_id, destination_id, preference, departure_hour, cash, fatigue,
		purpose_id, true, origin_id
	)
	if not plan_result.success:
		return
	var plan: Dictionary = plan_result.data.get("travel_plan", {}) as Dictionary
	var schedule_result: V2LifeLoopResult = travel_execution.schedule_plan(
		str(plan.get("travel_plan_id", "")), schedule, clock.total_hours, "npc_rule"
	)
	if schedule_result.success:
		npc_routines.mark_planned(
			person_id, clock.total_hours, reason, str(plan.get("travel_plan_id", ""))
		)


func _schedule_npc_message_read(
	person_id: String, message_id: String, available_from_hour: int
) -> void:
	var read_hour: int = schedule.find_available_hour(
		person_id, available_from_hour, available_from_hour + 24, 0, 24
	)
	if read_hour < 0:
		return
	var result: V2LifeLoopResult = schedule.schedule_rule_activity(
		person_id, "read_message", read_hour, 1,
		str(spatial_locations.position_for(person_id).get("current_location_id", "")),
		"npc_rule", message_id
	)
	if result.success:
		var activity_id: String = str(
			(result.data.get("activity", {}) as Dictionary).get("activity_id", "")
		)
		schedule.merge_activity_metadata(
			person_id, activity_id, {"message_id": message_id}
		)


func _seed_public_notice(start_hour: int) -> void:
	var result: V2LifeLoopResult = communication.post_public_notice(
		"jeanne", "location_lille_public_square", "public_announcement",
		{
			"fact_id": "public_notice:union_open_meeting",
			"subject_id": "union_metalworkers_nord",
			"fact_type": "organization_activity",
			"claim": "本周三晚举行公开工人会议",
			"expires_hour": start_hour + 7 * 24,
		},
		start_hour
	)
	if result.success:
		public_notice_id = str(
			(result.data.get("message", {}) as Dictionary).get("message_id", "")
		)


func _apply_v2_3_state(state: Dictionary) -> bool:
	var base_state: Dictionary = state.duplicate(true)
	base_state["schema_version"] = V2LifeLoopSimulation.SCHEMA_VERSION
	var base_result: V2LifeLoopResult = super.restore_persistent_state(base_state)
	if not base_result.success:
		return false
	if (
		not spatial_locations.restore_persistent_state(state["spatial_state"] as Dictionary)
		or not travel_graph.restore_persistent_state(state["travel_graph_state"] as Dictionary)
		or not travel_execution.restore_persistent_state(state["travel_state"] as Dictionary)
		or not communication.restore_persistent_state(state["communication_state"] as Dictionary)
		or not knowledge.restore_persistent_state(state["knowledge_state"] as Dictionary)
		or not dynamic_relationships.restore_persistent_state(
			state["dynamic_relationship_state"] as Dictionary
		)
		or not appointments.restore_persistent_state(state["appointment_state"] as Dictionary)
		or not introductions.restore_persistent_state(state["introduction_state"] as Dictionary)
		or not npc_routines.restore_persistent_state(state["npc_spatial_state"] as Dictionary)
	):
		return false
	truth_view = bool(state.get("truth_view", false))
	review_mode = bool(state.get("review_mode", true))
	background_person_ids.clear()
	for raw_id: Variant in state.get("background_person_ids", []) as Array:
		background_person_ids.append(str(raw_id))
	v2_3_hours_processed = int(state.get("v2_3_hours_processed", 0))
	local_overlay_revision = int(state.get("local_overlay_revision", 0))
	public_notice_id = str(state.get("public_notice_id", ""))
	_commute_planned_through_day = int(
		state.get(
			"commute_planned_through_day",
			_day_start(clock.total_hours) + 72
		)
	)
	route_planner.invalidate_cache()
	_sync_formal_person_states()
	return true


func _sync_formal_person_states() -> void:
	for person_id: String in FORMAL_PERSON_IDS:
		var position: Dictionary = spatial_locations.position_for(person_id)
		var state: Dictionary = person_states.get(person_id, {}) as Dictionary
		state["current_location_id"] = str(position.get("current_location_id", ""))
		state["location_state"] = str(position.get("location_state", ""))
		state["current_route_id"] = str(position.get("current_route_id", ""))
		state["expected_arrival_datetime"] = str(
			position.get("expected_arrival_datetime", "")
		)
		person_states[person_id] = state


func _at_service_location(
	person_id: String, service_id: String, total_hour: int
) -> bool:
	var position: Dictionary = spatial_locations.position_for(person_id)
	var location_id: String = str(position.get("current_location_id", ""))
	return (
		str(position.get("location_state", "")) == "at_location"
		and spatial_locations.provides_service(location_id, service_id)
		and spatial_locations.is_open(location_id, total_hour)
	)


func _at_location(person_id: String, location_id: String) -> bool:
	var position: Dictionary = spatial_locations.position_for(person_id)
	return (
		str(position.get("location_state", "")) == "at_location"
		and str(position.get("current_location_id", "")) == location_id
	)


func _home_for(person_id: String) -> String:
	return str(_social_person(person_id).get("home_location_id", ""))


func _workplace_for(person_id: String) -> String:
	return str(_social_person(person_id).get("workplace_location_id", ""))


func _social_person(person_id: String) -> Dictionary:
	for raw_person: Variant in v2_3_config.social_people():
		var person: Dictionary = raw_person as Dictionary
		if str(person.get("person_id", "")) == person_id:
			return person
	return {}


func _known_people_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for raw_person: Variant in v2_3_config.social_people():
		var person_id: String = str((raw_person as Dictionary).get("person_id", ""))
		var known: Array[String] = []
		for raw_target: Variant in v2_3_config.social_people():
			var target_id: String = str((raw_target as Dictionary).get("person_id", ""))
			if knowledge.knows_person(person_id, target_id):
				known.append(target_id)
		known.sort()
		result[person_id] = known
	return result


func _transport_transactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for transaction: Dictionary in ledger.transactions:
		if str(transaction.get("category", "")) == "transport":
			result.append(transaction.duplicate(true))
	return result


func _fail_v2_3_initialization(message: String) -> bool:
	v2_3_initialization_error = message
	initialization_error = message
	initialized = false
	return false


static func _day_start(total_hour: int) -> int:
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	return V2DateTime.to_total_hour({
		"year": int(value.get("year", 1900)),
		"month": int(value.get("month", 1)),
		"day": int(value.get("day", 1)),
		"hour": 0,
	})
