extends "res://experiments/war_resolver/interactive_observer/bound_scenario.gd"
const AutonomousPolicy = preload("res://experiments/war_resolver/gameplay/autonomous_policy.gd")
var _supply_responses: Dictionary = {}
var _land_chain: Dictionary = {}
var _prototype_policy: bool = false
var _purposes: Dictionary = {}
var _action_orders: Dictionary = {}

const SCENARIO_RUNTIME_FIELDS: Array[String] = ["name", "variant", "receipts", "_report_serial", "_objective_sent", "costs", "bound_actor", "selected_script_disabled", "_supply_responses", "_land_chain", "_prototype_policy", "_purposes", "_action_orders"]

func runtime_checkpoint() -> Dictionary:
	var world: Dictionary = F.runtime_state(env)
	if not world.get("ok", false):
		return world
	return {"ok": true, "version": "attachment-runtime-v1", "env": world,
		"scenario": F.F.State.capture_runtime_fields(self, SCENARIO_RUNTIME_FIELDS),
		"observation": F.F.State.capture_runtime_fields(observation, ["enabled", "debug_records", "person_records", "dropped", "_physical_ids", "_physical_time"])}

func restore_candidate(image: Dictionary) -> Dictionary:
	# No live-world mutation or replay of configure_bound/admit/initial orders.
	if not image.get("ok", false) or image.get("version", "") != "attachment-runtime-v1" or not image.get("env") is Dictionary or not image.get("scenario") is Dictionary or not image.get("observation") is Dictionary:
		return {"ok": false, "error": "unsupported_attachment_checkpoint"}
	var restored: Dictionary = F.restore_runtime(image.env)
	if not restored.ok:
		return restored
	var candidate: RefCounted = get_script().new()
	if not F.F.State.restore_runtime_fields(candidate, image.scenario, SCENARIO_RUNTIME_FIELDS) or not F.F.State.restore_runtime_fields(candidate.observation, image.observation, ["enabled", "debug_records", "person_records", "dropped", "_physical_ids", "_physical_time"]):
		return {"ok": false, "error": "invalid_scenario_continuation"}
	candidate.env = restored.env
	var focused: String = str(candidate.env.gameplay.focused_person)
	if candidate.bound_actor != focused or not candidate.env.decisions._persons.has(focused) or not candidate.env.decisions._persons[focused].provider is LiveProvider:
		return {"ok": false, "error": "controlled_person_provider_binding_missing"}
	candidate.provider = candidate.env.decisions._persons[focused].provider
	candidate.observation.configure(candidate.env.state)
	candidate.env.information.observation_recorded.connect(candidate.observation.on_observation)
	candidate.env.information.message_transition.connect(candidate.observation.on_message)
	candidate.env.gameplay.transition.connect(candidate.observation.on_gameplay)
	candidate.env.gameplay.transition.connect(candidate._on_goal)
	candidate.env.space.route_feedback.connect(candidate._on_route)
	candidate.env.decisions.input_issued.connect(candidate._on_input)
	return {"ok": true, "world": candidate}
## Same fixture and war ports. Only finite external decisions are arranged here.
func configure_bound(scene: String, seed_value: int, actor: String, options: Dictionary = {}) -> bool:
	if not env.is_empty() or scene not in ["A1", "A2", "A3"] or actor not in ["soldier", "scout", "squad", "platoon", "recipient", "company", "red_commander"]:
		return false
	name = scene
	variant = "continuity"
	bound_actor = actor
	_prototype_policy = options.get("autonomy_mode", "events") == "prototype"
	_supply_responses = options.get("supply_responses", {}).duplicate(true) if options.get("supply_responses", {}) is Dictionary else {}
	observation.enabled = bool(options.get("diagnostic", false))
	selected_script_disabled = true
	env = F.setup(seed_value, {"background": true, "personal": true, "blue_point": "B" if scene == "A1" else "A",
		"red_ammunition": 2000.0, "medical_unit_stock": 2.0, "medical_depot_stock": 8.0, "joint": true, "transport_motor_units": ["unit_001", "unit_003"], "sleeping_areas": options.get("sleeping_areas", 0)})
	if not env.structure.enable_attachment_continuity():
		return false
	if not _configure_battlefield_actions(options):
		return false
	env.structure.member_adjustments = true
	env.gameplay.summary_goals = true
	env.gameplay.focused_person = actor
	if not env.gameplay.participants.admit("scout").ok:
		return false
	# Existing squad leader gets one share of the same initial anonymous capacity.
	if not env.gameplay.participants.admit("squad").ok:
		return false
	# Both existing officers consume shares of unit_001; their bodies are at C.
	if not env.gameplay.participants.admit("platoon", "unit_001", "C").ok or not env.gameplay.participants.admit("company", "unit_001", "C").ok or not env.gameplay.medical.admit_healer("scout"):
		return false
	if not env.gameplay.focus_continuity.relate("squad", "platoon", "command_service") or not env.gameplay.focus_continuity.relate("platoon", "company", "command_service"):
		return false
	if not env.gameplay.participants.admit("red_commander", "unit_003", "D").ok:
		return false
	if not _configure_tactical_actions(options):
		return false
	if not env.gameplay.air.support.admit("A", "blue_company", "source") or not env.gameplay.air.support.admit("D", "red_company", "red_source"):
		return false
	if not env.gameplay.air.recovery.admit("unit_001") or not env.gameplay.air.recovery.admit("unit_003"):
		return false
	if not env.gameplay.air.admit("air_recon_01", "blue_company", "A", "source", 6.0, 4.0) or not env.gameplay.air.admit("air_interceptor_01", "red_company", "D", "red_source", 6.0, 12.0, true):
		return false
	if not env.gameplay.sea.support.admit_port("PORT_B", "blue_company", "source", "blue_port_repair") or not env.gameplay.sea.support.admit_port("PORT_F", "blue_company", "front_source", "front_port_repair") or not env.gameplay.sea.support.admit_port("PORT_R", "red_company", "red_source", "red_port_repair"):
		return false
	if not env.gameplay.sea.admit("surface_blue_01", "blue_company", "PORT_B", "source", 8.0, 20.0):
		return false
	# The two-vessel ceiling permits either a hostile ship or a second actual escort.
	var escort: bool = options.get("second_vessel_role", "opponent") == "escort"
	if not env.gameplay.sea.admit("surface_blue_02" if escort else "surface_red_01", "blue_company" if escort else "red_company", "PORT_B" if escort else "PORT_R", "source" if escort else "red_source", 8.0, 20.0):
		return false
	if not env.logistics.admit_port_report_source("front_source", "port_supply_PORT_F", "blue_company"):
		return false
	if not env.gameplay.land.admit("unit_001", 40.0, true) or not env.gameplay.land.admit("unit_003", 40.0, true):
		return false
	env.gameplay.operations.activate()
	for unit: String in ["unit_000", "unit_001", "unit_002", "unit_003"]:
		if not env.gameplay.operations.admit_field_observer(unit):
			return false
	if options.get("local_communications", false):
		var devices: Dictionary = {}
		var platform_relays: Variant = options.get("relay_platforms", [])
		if not platform_relays is Array:
			return false
		for unit: String in env.gameplay.operations._field_sources:
			devices[env.gameplay.operations._field_sources[unit]] = {"kind": "field", "range_km": float(options.get("field_radio_km", 0.12))}
		for unit: String in env.gameplay.land.carriers:
			devices[env.gameplay.land.carriers[unit].report_source] = {"kind": "unit", "subject_ref": unit, "range_km": float(options.get("field_radio_km", 0.12))}
		for vessel: String in env.gameplay.sea.vessels:
			devices[vessel] = {"kind": "vessel", "range_km": float(options.get("naval_radio_km", 0.3))}
		for asset: String in env.gameplay.air.assets:
			devices[asset] = {"kind": "aircraft", "range_km": float(options.get("air_radio_km", 0.3))}
		devices.port_supply_PORT_F = {"kind": "depot", "subject_ref": "front_source", "range_km": float(options.get("field_radio_km", 0.12))}
		if not env.information.enable_local_communications(["report", "command", "red_command"], devices, {"contact_km": 0.01, "short_range_km": 0.025,
			"retry_seconds": 120.0, "wait_seconds": 3600.0, "relay_people": options.get("relay_people", [] if not platform_relays.is_empty() else ["platoon", "red_commander"]), "relay_platforms": platform_relays}):
			return false
		var interruptions: Variant = options.get("communication_facts", [])
		if not interruptions is Array or interruptions.size() > 8:
			return false
		for fact: Variant in interruptions:
			if not fact is Dictionary or not fact.get("id") is String or not fact.get("node_ref") is String or not fact.get("open") is bool or not fact.get("at") is float and not fact.get("at") is int:
				return false
			if not env.space.schedule_site(str(fact.id), float(fact.at), str(fact.node_ref), "communication_open", bool(fact.open)).ok:
				return false
	if not env.gameplay.sea.recovery.admit("surface_blue_01") or not env.gameplay.sea.recovery.admit_shore("PORT_B", "A") or not env.gameplay.sea.recovery.admit_shore("PORT_F", "B"):
		return false
	var aa: Dictionary = {"detect_range_km": 0.25, "range_km": 0.2, "minimum_altitude": 0.02, "maximum_altitude": 0.6,
		"rounds": 3.0, "damage_per_round": 0.06, "interval_seconds": 15.0, "tracking_seconds": 5.0, "bearing_degrees": 180.0, "arc_degrees": 300.0, "minimum_equipment": 1.0}
	if not env.gameplay.air.defense.admit("unit_002", "red_commander", aa):
		return false
	aa.bearing_degrees = 0.0
	if not env.gameplay.air.defense.admit("unit_001", "company", aa):
		return false
	for person: String in ["soldier", "scout", "squad", "platoon", "company", "red_commander"]:
		var source: String = person + "_body"
		env.information._sources[source] = {"observer_ref": person, "scope_ref": env.people[person].formation_id, "origin": "DIRECT", "quality": 1.0, "precision_km": 0.02, "fact_kinds": ["person_status"]}
		if not env.information._person_sources.has(person):
			env.information._person_sources[person] = []
		env.information._person_sources[person].append(source)
	if not env.gameplay.focus_continuity.relate("soldier", "squad", "same_squad") or not env.gameplay.focus_continuity.relate("soldier", "scout", "same_platoon") or not env.gameplay.focus_continuity.relate("squad", "scout", "same_platoon"):
		return false
	for person: String in ["soldier", "scout"]:
		# Same local source, now able to report the current group's objective fact.
		env.information._sources[person + "_local"].fact_kinds.append("objective")
		env.information._sources[person + "_local"].fact_kinds.append("route")
	env.information._sources.local.fact_kinds.append("cover")
	observation.configure(env.state)
	env.information.observation_recorded.connect(observation.on_observation)
	env.information.message_transition.connect(observation.on_message)
	env.gameplay.transition.connect(observation.on_gameplay)
	env.gameplay.transition.connect(_on_goal)
	env.space.route_feedback.connect(_on_route)
	env.decisions.input_issued.connect(_on_input)
	env.gameplay.participants.debug_calculations = false
	env.lod.physical_event_sink = Callable()
	for side: String in ["blue", "red"]:
		var ids: Array[String] = ["remote_" + side + "_0", "remote_" + side + "_1"]
		if not env.lod.coalesce("remote_" + side + "_platoon", ids, "platoon").ok:
			return false
	if not env.gameplay.admit_standing("unit_000", "standing_primary", "squad", F.intent("hold", "B" if scene == "A1" else "A")).ok:
		return false
	if not F.report(env, "soldier", "soldier_local", "cover", "initial_cover", "soldier"):
		return false
	if not F.report(env, "squad", "local", "cover", "initial_squad_cover", "squad"):
		return false
	if not F.report(env, "squad", "local", "objective", "old_inflight_report", "platoon", "report"):
		return false
	if not _finite_supply(300.0):
		return false
	var front_node: String = "B" if scene == "A1" else "A"
	_land_chain = {"request_ref": "finite_request", "channel_ref": "command",
		"approach_routes": {"A": ["AB"], "B": []},
		"return_to_source": {"vessel_ref": "surface_blue_01", "operation": "sail", "path": ["water_BF"], "target_node": "PORT_B", "target_ref": ""},
		"sea": {"vessel_ref": "surface_blue_01", "operation": "transport", "source_port": "PORT_B", "destination_port": "PORT_F", "path": ["water_BM", "water_MF"],
			"cargo": {"AMMUNITION": 30.0}, "supply_request_ref": "finite_request", "land_required": true, "notify": ["platoon"]},
		"land": {"operation": "transport", "unit_ref": "unit_001", "source_ref": "front_source", "recipient_kind": "unit", "recipient_ref": "unit_000",
			"target_node": front_node, "approach_path": ["AB"], "path": [] if front_node == "B" else ["AB"], "cargo": {"AMMUNITION": 30.0}, "request_ref": "finite_request", "notify": ["platoon"]}}
	var custom_company_response: bool = _supply_responses.has("company")
	_purposes = {"company": _campaign("blue", front_node, escort), "red_commander": _campaign("red", "D", escort)}
	for officer: String in _purposes:
		var orders: Dictionary = _orders(officer, [])
		orders.erase("purposes")
		orders.erase("inputs")
		env.gameplay.operations.admit_office_orders(str(env.structure.command_person(officer).formation_id), orders)
	for officer: String in ["company", "platoon"]:
		if not _supply_responses.has(officer):
			_supply_responses[officer] = {"request_ref": "finite_request", "subject_ref": "unit_000",
				"on_interrupted": {"kind": "command", "command_kind": "coordination", "target": "node_unit_000", "channel_ref": "command", "values": {"posture": "hold", "release_after": 0.0}},
				"on_unit_received": {"kind": "command", "command_kind": "coordination", "target": "node_unit_000", "channel_ref": "command", "values": {"posture": "advance", "release_after": 0.0}},
				"on_low_ammunition": {"kind": "logistics_request", "target": "node_unit_000", "resource_class": "AMMUNITION", "quantity": 10.0}}
	if not custom_company_response:
		_supply_responses.company.on_interrupted = {"kind": "command", "command_kind": "reserve_intent", "target": "blue_company", "channel_ref": "command", "values": {"policy": "retain", "units": ["unit_000"]}}
		_supply_responses.company.on_unit_received = {"kind": "command", "command_kind": "reserve_intent", "target": "blue_company", "channel_ref": "command",
			"values": {"policy": "release", "tasks": [{"unit_ref": "unit_000", "goal": F.intent("hold", front_node)}]}}
		_supply_responses.company.resume_only_after_interruption = true
	var inputs: Dictionary = {}
	if scene == "A1":
		inputs.company = [{"id": "during_personal_action", "at": 10.0, "intent": _attach(2.0, 588.0)}]
	elif scene == "A2":
		inputs.company = [{"id": "crossing_command", "at": 0.0, "intent": _attach(5.0, 895.0)}]
		if actor != "platoon" and not F.command(env, "platoon", "old_inflight_command", F.intent("advance", "B", ["AB"])).ok:
			return false
	else:
		var entries: Array = []
		for index: int in range(6):
			entries.append({"id": "bounded_attachment_%d" % index, "at": float(index * 600), "intent": _attach(5.0, 295.0)})
		inputs.company = entries
	if actor != "soldier" and scene == "A1":
		inputs.soldier = [{"id": "cover_input", "at": 10.0, "intent": {"kind": "local_action", "values": {"action": "take_cover"}}}]
	for person: String in inputs:
		if person != actor and not _enroll(person, inputs[person]):
			return false
	for person: String in _supply_responses:
		if not env.people.has(person) or not _supply_responses[person] is Dictionary:
			return false
		if person != actor and person != "red_commander" and not inputs.has(person) and not _enroll(person, []):
			return false
	if actor != "red_commander" and _prototype_policy:
		var opponent: Policy = Policy.new()
		var routes: Dictionary = {"PORT_R:SEA_M": ["water_MR"], "PORT_R:PORT_B": ["water_MR", "water_BM"], "PORT_R:PORT_F": ["water_MR", "water_MF"],
			"SEA_M:PORT_B": ["water_BM"], "SEA_M:PORT_R": ["water_MR"], "SEA_M:PORT_F": ["water_MF"],
			"PORT_B:SEA_M": ["water_BM"], "PORT_B:PORT_R": ["water_BM", "water_MR"], "PORT_F:SEA_M": ["water_MF"], "PORT_F:PORT_R": ["water_MF", "water_MR"]}
		if not env.decisions.enroll("red_commander", {"cadence": 300.0, "targets": ["red_company", "red_platoon", "node_unit_002", "node_unit_003"],
			"urgent": false, "command_kind": "goal_intent", "standing_orders": {"joint": {"channel_ref": "red_command", "air_asset_ref": "air_interceptor_01", "vessel_ref": "surface_red_01", "routes": routes}}}, opponent):
			return false
		if not env.decisions.start_cycle("red_commander", "joint_red_orders", 0.0, 360.0, 1800.0, 6).ok:
			return false
	for person: String in env.people:
		if person != actor and not env.decisions._persons.has(person) and not _enroll(person, []):
			return false
	var cadence: float = float(F.F.Roles.INPUT_SECONDS[F.F.Roles.ROLES.find(str(env.people[actor].role))])
	var command_targets: Array = ["red_company", "red_platoon", "node_unit_002", "node_unit_003"] if actor == "red_commander" else ["node_unit_000", "node_unit_001", "blue_platoon", "blue_destination", "blue_company"]
	if not env.decisions.enroll(actor, {"cadence": cadence, "targets": command_targets,
		"urgent": false, "command_kind": "goal_intent", "standing_orders": _orders(actor, [])}, provider):
		return false
	if not _prototype_policy:
		if not env.decisions.enable_autonomy(actor):
			return false
		env.decisions.suspend_autonomy(actor, true)
	for unit: String in ["unit_000", "unit_001", "unit_002", "unit_003"]:
		env.gameplay.operations.on_unit(unit)
	return advance(0.0).ok

func _finite_supply(at: float) -> bool:
	# This declared seaborne request has no abstract arrival event or source debit.
	var request: Dictionary = env.logistics.submit("platoon", {"id": "finite_request", "kind": "request", "target_kind": "unit",
		"target": "unit_000", "resource_class": "AMMUNITION", "quantity": 30.0})
	if request.ok:
		env.logistics._requests.finite_request.sea_required = true
	receipts.append({"request": request, "allocation": {"ok": true, "status": "WAITING_ACTUAL_SEA_ALLOCATION"}, "requested_at": at})
	return request.ok

static func _attach(delay: float, duration: float) -> Dictionary:
	return {"kind": "structure_request", "values": {"target": "node_unit_000", "parent": "blue_destination", "delay": delay, "duration": duration}}

func _enroll(person: String, entries: Array) -> bool:
	if not _prototype_policy:
		var cadence: float = float(F.F.Roles.INPUT_SECONDS[F.F.Roles.ROLES.find(str(env.people[person].role))])
		var targets: Array = ["red_company", "red_platoon", "node_unit_002", "node_unit_003"] if person == "red_commander" else ["node_unit_000", "node_unit_001", "blue_platoon", "blue_destination", "blue_company"]
		if not env.decisions.enroll(person, {"cadence": cadence, "targets": targets, "urgent": false,
			"command_kind": "goal_intent", "standing_orders": _orders(person, entries)}, AutonomousPolicy.new()):
			return false
		return env.decisions.enable_autonomy(person, maxf(600.0, cadence))
	if entries.size() <= 1 and not _supply_responses.has(person):
		return super._enroll(person, entries)
	var policy: Policy = Policy.new()
	var orders: Dictionary = {"inputs": entries.duplicate(true)}
	if _supply_responses.has(person):
		orders.supply_response = _supply_responses[person].duplicate(true)
	if person == "company":
		orders.supply_chain = _land_chain.duplicate(true)
	if not env.decisions.enroll(person, {"cadence": 300.0, "targets": ["node_unit_000", "node_unit_001", "blue_platoon", "blue_destination", "blue_company"],
		"urgent": false, "command_kind": "goal_intent", "standing_orders": orders}, policy):
		return false
	return env.decisions.start_cycle(person, "bounded_" + person, 0.0, 600.0, 6600.0, 12).ok

func _configure_tactical_actions(options: Dictionary) -> bool:
	var profiles: Variant = options.get("weapon_profiles", {})
	var crews: Variant = options.get("gun_crews", {})
	var sites: Variant = options.get("position_sites", {})
	if not profiles is Dictionary or profiles.size() > 6 or not crews is Dictionary or crews.size() > 2 or not sites is Dictionary or sites.size() > 8:
		return false
	# These are allocations of equipment already in the unit, never new weapons.
	if options.get("infantry_actions", true):
		for person: String in ["soldier", "scout", "squad"]:
			if not profiles.has(person):
				profiles[person] = {}
	for person: String in profiles:
		if not profiles[person] is Dictionary or not env.gameplay.tactics.admit_weapon(person, profiles[person]):
			return false
	for id: String in crews:
		if not crews[id] is Dictionary or not crews[id].get("unit_ref") is String or not crews[id].get("profile") is Dictionary or not env.gameplay.tactics.admit_gun(id, str(crews[id].unit_ref), crews[id].profile):
			return false
	for node: String in sites:
		if not sites[node] is Array or not env.space.admit_position_site(node, sites[node]):
			return false
	return true

func _configure_battlefield_actions(options: Dictionary) -> bool:
	for key: String in ["local_sites", "local_links", "local_lanes", "local_known"]:
		if not options.get(key, {}) is Dictionary:
			return false
	if not env.space.admit_local_space(options.get("local_sites", {}), options.get("local_links", {}), options.get("local_lanes", {})):
		return false
	for person: String in options.get("local_known", {}):
		if not options.local_known[person] is Dictionary or not env.gameplay.admit_local_routes(person, options.local_known[person]):
			return false
	var local_facts: Variant = options.get("local_facts", [])
	if not local_facts is Array or local_facts.size() > 8:
		return false
	for fact: Variant in local_facts:
		if not fact is Dictionary or not fact.get("id") is String or not fact.get("link_ref") is String or not fact.get("open") is bool or not env.gameplay.tactics._nonnegative(fact.get("at")):
			return false
		if not env.space.schedule_local_fact(str(fact.id), float(fact.at), str(fact.link_ref), bool(fact.open)).get("ok", false):
			return false
	var units: Variant = options.get("engineers", {})
	var facilities: Variant = options.get("engineering_edges", {})
	var facts: Variant = options.get("engineering_facts", [])
	var orders: Variant = options.get("action_orders", {})
	if not units is Dictionary or units.size() > 2 or not facilities is Dictionary or facilities.size() > 4 or not facts is Array or facts.size() > 8 or not orders is Dictionary or orders.size() > 8:
		return false
	for unit: String in units:
		if not units[unit] is Dictionary or not env.gameplay.operations.admit_engineer(unit, units[unit]):
			return false
	for edge: String in facilities:
		if not facilities[edge] is Dictionary or not facilities[edge].get("actions") is Array or not facilities[edge].get("work_nodes") is Array or not env.space.admit_engineering(edge, facilities[edge].actions, facilities[edge].work_nodes):
			return false
	for fact: Variant in facts:
		if not fact is Dictionary or not fact.get("id") is String or not fact.get("edge_ref") is String or not fact.get("obstruction") is String or not (fact.get("at") is int or fact.get("at") is float):
			return false
		if not env.space.schedule_obstruction(str(fact.id), float(fact.at), str(fact.edge_ref), str(fact.obstruction)).get("ok", false):
			return false
	for person: String in orders:
		if not env.people.has(person) or not orders[person] is Dictionary:
			return false
		for key: String in orders[person]:
			if key == "local_support":
				var support: Variant = orders[person][key]
				if not support is Dictionary or not support.get("enabled", false) is bool or not support.get("ammunition_orders", []) is Array or support.get("ammunition_orders", []).size() > 4 or not support.get("rescue_orders", []) is Array or support.get("rescue_orders", []).size() > 4:
					return false
				for candidate: Variant in support.get("ammunition_orders", []):
					if not candidate is Dictionary or not candidate.get("values") is Dictionary or candidate.values.get("ammo_action", "") not in ["take", "handover", "recover", "move"] or not candidate.get("when_unit_low", true) is bool or not env.gameplay.tactics._nonnegative(candidate.get("threshold", 1.0)):
						return false
					if candidate.has("when_part_low") and candidate.when_part_low not in ["front", "rear"]:
						return false
					if candidate.values.ammo_action == "move":
						if candidate.values.get("part_ref", "") not in ["front", "rear"] or not candidate.values.get("local_path") is Array or candidate.values.local_path.is_empty() or candidate.values.local_path.size() > 4 or env.space.local_endpoint(str(candidate.values.get("destination_ref", ""))).is_empty():
							return false
					elif not env.gameplay.tactics._positive(candidate.values.get("quantity")):
						return false
				for candidate: Variant in support.get("rescue_orders", []):
					if not candidate is Dictionary or not env.people.has(candidate.get("carrier_ref", "")) or not env.people.has(candidate.get("patient_ref", "")):
						return false
					for pair: Array in [["approach_path", "patient_place"], ["carry_path", "drop_place"]]:
						var path: Variant = candidate.get(pair[0])
						if not path is Array or path.is_empty() or path.size() > 4 or env.space.local_endpoint(str(candidate.get(pair[1], ""))).is_empty():
							return false
						for edge: Variant in path:
							if not edge is String or not env.space._local_edges.has(edge):
								return false
					if candidate.has("road_path") and (not candidate.road_path is Array or candidate.road_path.is_empty() or candidate.road_path.size() > 16 or not env.space._nodes.has(candidate.get("road_node", ""))):
						return false
				continue
			if key == "tactics":
				var tactics: Variant = orders[person][key]
				if not tactics is Dictionary or not tactics.get("enabled", true) is bool:
					return false
				if tactics.has("manoeuvre"):
					var plan: Variant = tactics.manoeuvre
					if not plan is Dictionary:
						return false
					var local: bool = plan.has("local_path")
					var path: Variant = plan.get("local_path", plan.get("path"))
					if not path is Array or path.is_empty() or path.size() > 4 or (env.space.local_endpoint(str(plan.get("destination_ref", ""))).is_empty() if local else not env.space._nodes.has(plan.get("destination_node", ""))):
						return false
					var members: Array = []
					if plan.has("parts"):
						if not plan.parts is Dictionary or plan.parts.size() != 2 or not plan.parts.has("front") or not plan.parts.has("rear"):
							return false
						for key_part: String in ["front", "rear"]:
							var part: Variant = plan.parts[key_part]
							if not part is Dictionary or not part.get("members", []) is Array or part.get("members", []).size() > 4 or not env.gameplay.tactics._nonnegative(part.get("anonymous", 0.0)):
								return false
							members.append_array(part.get("members", []))
					else:
						if not plan.get("movers") is Array or plan.movers.is_empty() or plan.movers.size() > 4:
							return false
						members = plan.movers
					for member: Variant in members:
						if not member is String or not env.people.has(member):
							return false
					for edge: Variant in path:
						if not edge is String or not (env.space._local_edges if local else env.space._edges).has(edge):
							return false
				continue
			if key not in ["relay_deployments", "engineering_plans", "rendezvous_plans", "construction_plans"] or not orders[person][key] is Array or orders[person][key].size() > 8:
				return false
			for plan: Variant in orders[person][key]:
				if not plan is Dictionary or not plan.get("node_ref") is String or not env.space._nodes.has(plan.node_ref) or not plan.get("routes") is Dictionary or plan.routes.size() > 8:
					return false
				if key == "construction_plans" and (not plan.get("unit_ref") is String or not env.state.units.has(plan.unit_ref) or not plan.get("position_ref") is String or str(plan.position_ref).is_empty() or plan.get("position_kind", "") not in ["personal", "squad", "weapon"]):
					return false
				for path: Variant in plan.routes.values():
					if not path is Array or path.size() > 8:
						return false
		_action_orders[person] = orders[person].duplicate(true)
	return true

func _orders(person: String, entries: Array) -> Dictionary:
	var orders: Dictionary = {"inputs": entries.duplicate(true), "channel_ref": "red_command" if person == "red_commander" else "command", "physical_supply": true}
	orders.tactics = {"enabled": true, "fire_seconds": 60.0}
	if _purposes.has(person):
		orders.recon_asset_ref = "air_interceptor_01" if person == "red_commander" else "air_recon_01"
		orders.purposes = [{"plan_ref": "initial_" + person, "target": env.structure.command_person(person).formation_id, "values": _purposes[person].duplicate(true)}]
		orders.delivery_plan = {"carrier_ref": "unit_003" if person == "red_commander" else "unit_001", "source_ref": "red_source" if person == "red_commander" else "source", "capacity": 40.0,
			"approach_routes": {"D": [], "B": ["bridge_BD"], "A": ["AB", "bridge_BD"], "C": ["CD"]} if person == "red_commander" else {"A": [], "B": ["AB"], "C": ["AC"], "D": ["bridge_BD", "AB"]},
			"handover_routes": {"D": [], "B": ["bridge_BD"], "A": ["bridge_BD", "AB"], "C": ["CD"]} if person == "red_commander" else {"A": [], "B": ["AB"], "C": ["AC"], "D": ["AB", "bridge_BD"]}}
		# Existing carriers may survey only while free of their real transport duties.
		orders.recovery_scouts = [{"unit_ref": orders.delivery_plan.carrier_ref, "routes": {
			"A": {"B": ["AB"], "C": ["AC"], "D": ["bridge_BD", "AB"]},
			"B": {"A": ["AB"], "C": ["AC", "AB"], "D": ["bridge_BD"]},
			"C": {"A": ["AC"], "B": ["AB", "AC"], "D": ["CD"]},
			"D": {"A": ["AB", "bridge_BD"], "B": ["bridge_BD"], "C": ["CD"]}}}]
		orders.sea_supply_plans = []
		var office: String = str(env.structure.command_person(person).formation_id)
		var ships: Array[String] = []
		for vessel: Dictionary in env.gameplay.sea.vessels.values():
			if env.structure._contains(office, str(vessel.owner)):
				ships.append(str(vessel.id))
		if env.structure._contains(office, str(env.gameplay.sea.support.ports.PORT_B.owner)) and env.structure._contains(office, str(env.gameplay.sea.support.ports.PORT_F.owner)):
			orders.sea_supply_plans.append({"source_port": "PORT_B", "source_ref": "source", "destination_port": "PORT_F", "vessel_refs": ships,
				"recipient_nodes": ["B", "C", "D"], "resource_classes": ["AMMUNITION", "FUEL", "SPARES", "MEDICAL"], "path": ["water_BM", "water_MF"], "minimum_fuel": 1.0, "deadline_seconds": 3600.0,
				"approach_routes": {"PORT_B": [], "PORT_F": ["water_MF", "water_BM"], "SEA_M": ["water_BM"]},
				"resume_routes": {"PORT_B": ["water_BF"], "SEA_M": ["water_MF"]},
				"resume_alternatives": {"PORT_B": [["water_BM", "water_MF"]]}, "return_alternatives": {"PORT_F": [["water_BF"]]},
				"land": {"carrier_ref": orders.delivery_plan.carrier_ref, "source_ref": "front_source", "capacity": 40.0,
					"approach_routes": {"A": ["AB"], "B": [], "C": ["AC", "AB"], "D": ["bridge_BD"]},
					"handover_routes": {"A": ["AB"], "B": [], "C": ["AB", "AC"], "D": ["bridge_BD"]},
					"redirect_routes": {"B:A": ["AB"], "B:C": ["AB", "AC"], "B:D": ["bridge_BD"], "A:B": ["AB"], "C:B": ["AC", "AB"], "D:B": ["bridge_BD"]},
					"alternative_routes": {"B:A": [["bridge_BD", "CD", "AC"]], "B:C": [["bridge_BD", "CD"]]}, "recovery_carriers": []}})
		orders.campaign_options = {"units": ["unit_002" if person == "red_commander" else "unit_000"], "deadline_seconds": 14400.0,
			"fallback_node": "D" if person == "red_commander" else "A", "fallback_routes": orders.delivery_plan.approach_routes.duplicate(true),
			"air_support": true,
			"objectives": [{"target_node": "B", "priority": 3, "require_recon": true,
				"routes": {"A": ["AB"], "B": [], "D": ["bridge_BD"], "C": ["CD", "bridge_BD"]}}]}
		orders.campaign_options.naval_support = {"vessel_ref": "surface_red_01" if person == "red_commander" else "surface_blue_01", "target_node": "SEA_M",
			"routes": {"PORT_F": ["water_MF"], "PORT_B": ["water_BM"], "PORT_R": ["water_MR"], "SEA_M": []}}
		# Transport groups remain finite carriers, rather than free combat reserves.
		orders.reserve_candidates = []
	orders.merge(_action_orders.get(person, {}), true)
	if orders.has("tactics") and not orders.tactics.has("enabled"):
		orders.tactics.enabled = true
	return orders

func _campaign(side: String, starting_node: String, escort: bool) -> Dictionary:
	# Declared local purposes and known routes do not prescribe a battle result.
	var blue: bool = side == "blue"
	var office: String = "blue_company" if blue else "red_company"
	var channel: String = "command" if blue else "red_command"
	var unit: String = "unit_000" if blue else "unit_002"
	var carrier: String = "unit_001" if blue else "unit_003"
	var aircraft: String = "air_recon_01" if blue else "air_interceptor_01"
	var vessel: String = "surface_blue_01" if blue else "surface_red_01"
	var base: String = "A" if blue else "D"
	var tasks: Array[Dictionary] = [
		{"task_ref": "initial_reserve", "domain": "GROUND", "unit_ref": unit, "goal": F.intent("hold", starting_node), "priority": 5, "required": false, "after": [], "retain_before_execution": true, "followup": false},
		{"task_ref": "recon", "domain": "AIR", "intent": {"kind": "command", "command_kind": "air_intent", "target": office, "channel_ref": channel,
			"values": {"asset_ref": aircraft, "operation": "recon", "target_node": "B", "target_ref": "", "outbound": ["B"], "inbound": [base]}}, "priority": 4, "required": true, "after": []},
		{"task_ref": "advance", "domain": "GROUND", "unit_ref": unit, "goal": F.intent("advance", "B", [] if starting_node == "B" else (["AB"] if blue else ["bridge_BD"])),
			"routes": {"A": ["AB"], "B": [], "D": ["bridge_BD"], "C": ["CD", "bridge_BD"]}, "alternatives": {"A": [["AC", "CD", "bridge_BD"]], "D": [["CD", "AC", "AB"]]},
			"priority": 3, "required": true, "after": ["initial_reserve", "recon"], "require_recon": true},
		{"task_ref": "air_support", "domain": "AIR", "intent": {"kind": "command", "command_kind": "air_intent", "target": office, "channel_ref": channel,
			"values": {"asset_ref": aircraft, "operation": "strike", "target_node": "B", "target_ref": "", "outbound": ["B"], "inbound": [base]}},
			"priority": 2, "required": false, "after": ["recon"], "target_from_recon": true, "contact_node": "B"}]
	if blue:
		tasks.insert(2, {"task_ref": "sea_supply", "domain": "NAVAL", "intent": {"kind": "command", "command_kind": "naval_intent", "target": office, "channel_ref": channel, "values": _land_chain.sea.duplicate(true)}, "priority": 4, "required": false, "after": []})
		tasks.insert(3, {"task_ref": "front_supply", "domain": "LAND", "intent": {"kind": "command", "command_kind": "land_intent", "target": office, "channel_ref": channel, "values": _land_chain.land.duplicate(true)},
			"approach_routes": {"A": ["AB"], "B": []}, "handover_unit": unit, "handover_routes": {"A": ["AB"], "B": [], "D": ["bridge_BD"], "C": ["AB", "AC"]},
			"alternative_routes": {"B:A": [["bridge_BD", "CD", "AC"]]}, "redirect_routes": {"B:A": ["AB"], "B:D": ["bridge_BD"], "B:C": ["AB", "AC"], "A:B": ["AB"]},
			"priority": 4, "required": false, "after": ["sea_supply"]})
	else:
		tasks.insert(2, {"task_ref": "front_supply", "domain": "LAND", "intent": {"kind": "command", "command_kind": "land_intent", "target": office, "channel_ref": channel,
			"values": {"operation": "transport", "unit_ref": carrier, "source_ref": "red_source", "recipient_kind": "unit", "recipient_ref": unit, "target_node": "D", "path": [], "approach_path": [], "cargo": {"AMMUNITION": 10.0}}},
			"approach_routes": {"D": []}, "handover_unit": unit, "handover_routes": {"D": [], "B": ["bridge_BD"]}, "alternative_routes": {"D:B": [["CD", "AC", "AB"]]}, "redirect_routes": {"D:B": ["bridge_BD"], "B:D": ["bridge_BD"]},
			"priority": 3, "required": false, "after": []})
	if blue or not escort:
		tasks.append({"task_ref": "shore_support", "domain": "NAVAL", "intent": {"kind": "command", "command_kind": "naval_intent", "target": office, "channel_ref": channel,
			"values": {"vessel_ref": vessel, "operation": "shore_support", "target_node": "SEA_M", "target_ref": "", "path": ["water_MF"] if blue else ["water_MR"]}},
			"routes": {"PORT_F": ["water_MF"], "PORT_B": ["water_BM"], "PORT_R": ["water_MR"], "SEA_M": []},
			"priority": 1, "required": false, "after": ["recon", "sea_supply"] if blue else ["recon"], "target_from_recon": true, "contact_node": "B"})
	return {"operation": "begin", "purpose": "advance", "target_node": "B", "priority": 3, "deadline_seconds": 14400.0, "tasks": tasks}

func physical() -> Dictionary:
	var result: Dictionary = super.physical()
	if env.state.public_pending():
		return result
	result.attachments = env.structure._attachments.duplicate(true)
	result.participant_bindings = env.gameplay.participants._units.duplicate()
	result.personal_actions = env.gameplay.participants._actions.duplicate(true)
	result.goal_bindings = env.gameplay._goals.duplicate()
	result.supply_receipts = env.logistics._deliveries.duplicate(true)
	return result

func _recipients(unit_node: String = "node_unit_000") -> Array[String]:
	var recipients: Array[String] = []
	for node: String in env.structure._path(unit_node):
		var person: String = str(env.structure._positions.get(node, {}).get("person", ""))
		if not person.is_empty() and env.structure.command_person(person).has_position:
			recipients.append(person)
	return recipients

func _objective_source(unit_id: String) -> Dictionary:
	var node: String = str(env.structure._unit_nodes.get(unit_id, ""))
	if not env.structure.active(node):
		return {}
	var candidates: Dictionary = env.structure._node_people[node].duplicate()
	var unit: Dictionary = env.lod.preview_leaf(unit_id)
	for person: String in unit.get("gameplay_personnel", {}).get("members", {}):
		candidates[person] = true
	var people: Array[String] = F.F.State.sorted_ids(candidates)
	for officer: bool in [true, false]:
		for person: String in people:
			if (env.structure.command_person(person).role != "ordinary_soldier") != officer or not env.gameplay.participants.observation_opportunity(person, unit_id):
				continue
			for id: String in env.information._person_sources.get(person, []):
				var source: Dictionary = env.information._sources[id]
				if source.origin == "DIRECT" and source.scope_ref == node and "objective" in source.fact_kinds:
					return {"person": person, "source": id, "node": node}
	return {}

func _on_goal(record: Dictionary) -> void:
	if not record.kind.begins_with("goal_"):
		return
	var unit_id: String = str(record.subject_ref)
	var source: Dictionary = _objective_source(unit_id)
	if source.is_empty():
		return
	var subject_ids: Array[String] = [unit_id]
	var signature: String = unit_id + ":" + JSON.stringify(env.gameplay.visible_fact(subject_ids, "objective"))
	if _objective_sent.has(signature):
		return
	_report_serial += 1
	var recipients: Array[String] = _recipients(str(source.node))
	if source.person not in recipients:
		recipients.append(str(source.person))
	var sent: bool = false
	for recipient: String in recipients:
		sent = F.report(env, str(source.person), str(source.source), "objective", "goal_report_%d_%s" % [_report_serial, recipient],
			recipient, "instant" if recipient == source.person else "report", unit_id) or sent
	if sent:
		_objective_sent[signature] = true

func _on_route(unit_id: String, _kind: String, _cause: String) -> void:
	var source: Dictionary = _objective_source(unit_id)
	if source.is_empty() or "route" not in env.information._sources[source.source].fact_kinds:
		return
	_report_serial += 1
	var recipients: Array[String] = _recipients(str(source.node))
	var unit: Dictionary = env.lod.preview_leaf(unit_id)
	for person: String in unit.get("gameplay_personnel", {}).get("members", {}):
		if env.gameplay.participants._units.get(person, "") == unit_id and person not in recipients:
			recipients.append(person)
	for recipient: String in recipients:
		F.report(env, str(source.person), str(source.source), "route", "route_report_%d_%s" % [_report_serial, recipient],
			recipient, "instant" if recipient == source.person else "report", unit_id)
