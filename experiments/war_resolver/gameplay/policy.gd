extends RefCounted
## Replaceable finite script and received-route reaction; receives only Context.
var source: String = "autonomous"
var _submitted: Dictionary = {}
var _supply_episodes: Dictionary = {}
var _chain_reports: Dictionary = {}

func evaluate(context: Dictionary) -> Dictionary:
	if context.standing_orders.has("supply_chain"):
		var continuation: Dictionary = _supply_chain(context)
		if not continuation.is_empty():
			return continuation
	for entry: Dictionary in context.standing_orders.get("inputs", []):
		if _submitted.has(entry.id) or float(context.decision_time) < float(entry.at):
			continue
		var claim_ref: String = ""
		if entry.has("require_route_state"):
			for claim: Dictionary in context.received_claims:
				if claim.fact_kind == "route" and claim.subject_ref == entry.subject and claim.claimed_value.state == entry.require_route_state:
					claim_ref = str(claim.entry_id)
			if claim_ref.is_empty():
				continue
		_submitted[entry.id] = true
		return {"intent": entry.intent.duplicate(true), "selected_claim": claim_ref, "script_ref": entry.id}
	if context.standing_orders.has("supply_response"):
		var supply: Dictionary = _supply_response(context)
		if not supply.is_empty():
			return supply
	if context.standing_orders.has("joint"):
		return _joint(context)
	return {"intent": {"kind": "keep"}, "selected_claim": ""}

func _supply_response(context: Dictionary) -> Dictionary:
	var plan: Dictionary = context.standing_orders.supply_response
	if float(context.decision_time) < maxf(float(context.command_ready_at), float(context.command_issue_ready_at)):
		return {}
	for index: int in range(context.received_claims.size() - 1, -1, -1):
		var claim: Dictionary = context.received_claims[index]
		if claim.fact_kind not in ["sea_status", "supply_status", "land_supply_status", "ammunition"] or float(claim.reliability) <= 0.0:
			continue
		var matches: bool = plan.get("request_ref", "") != "" and claim.claimed_value.get("request_ref", "") == plan.request_ref or plan.get("transport_ref", "") != "" and claim.claimed_value.get("transport_ref", "") == plan.transport_ref or claim.fact_kind == "ammunition" and claim.subject_ref == plan.get("subject_ref", "")
		if not matches:
			continue
		var status: String = str(claim.claimed_value.get("transport_status", "")) if claim.fact_kind == "sea_status" else str(claim.claimed_value.get("status", ""))
		var choice: String = ""
		if claim.fact_kind in ["supply_status", "land_supply_status"] and status == "RECEIVED":
			choice = "on_unit_received"
		elif claim.fact_kind == "sea_status" and status == "RECEIVED":
			choice = "on_port_received"
		elif claim.fact_kind == "ammunition" and claim.claimed_value.get("level", "") == "LOW":
			choice = "on_low_ammunition"
		elif status == "IN_TRANSIT":
			choice = "on_departed"
		elif status in ["VESSEL_SUNK", "BLOCKED", "IMMOBILE", "TEMPORARILY_IMMOBILE", "FUEL_EXHAUSTED", "CAPACITY_LOST", "STRANDED", "PARTIAL_CARGO_LOSS", "WAITING_RECIPIENT", "STOPPED", "STOPPED_AT_ACTUAL_POSITION", "CANCELLED_AT_ACTUAL_POSITION", "REJECTED_RETURNED", "WAITING_ACTUAL_UNLOADING_PORT", "LOADING_INTERRUPTED", "ATTACK_INTERRUPTED_CARGO_HANDLING", "PORT_CLOSED_DURING_CARGO_HANDLING"]:
			choice = "on_interrupted"
		var key: String = str(plan.get("request_ref", plan.get("transport_ref", ""))) + ":" + str(claim.fact_kind)
		var episode: String = str(claim.claimed_value.get("transport_ref", claim.subject_ref)) + ":" + status + ":" + choice
		if _supply_episodes.get(key, "") == episode:
			return {}
		_supply_episodes[key] = episode
		if choice == "" or not plan.get(choice) is Dictionary:
			return {}
		var paused_key: String = "supply_pause_" + str(plan.get("request_ref", plan.get("transport_ref", "")))
		if choice == "on_unit_received" and plan.get("resume_only_after_interruption", false) and not _submitted.get(paused_key, false):
			return {}
		if choice == "on_interrupted":
			_submitted[paused_key] = true
		elif choice == "on_unit_received":
			_submitted[paused_key] = false
		# The supplied intention is an ordinary task/reserve command, using known routes.
		return {"intent": plan[choice].duplicate(true), "selected_claim": claim.entry_id}
	return {}

func _supply_chain(context: Dictionary) -> Dictionary:
	var plan: Dictionary = context.standing_orders.supply_chain
	if float(context.decision_time) < maxf(float(context.command_ready_at), float(context.command_issue_ready_at)):
		return {}
	for claim: Dictionary in context.received_claims:
		if claim.fact_kind not in ["sea_status", "land_supply_status"] or float(claim.reliability) <= 0.0 or claim.claimed_value.get("request_ref", "") != plan.request_ref:
			continue
		var old: Dictionary = _chain_reports.get(claim.fact_kind, {})
		if old.is_empty() or float(claim.observed_at) > float(old.observed_at) or claim.observed_at == old.observed_at and float(claim.received_at) >= float(old.received_at):
			_chain_reports[claim.fact_kind] = claim.duplicate(true)
	if not _chain_reports.has("land_supply_status"):
		return _initial_supply_chain(context)
	var land: Dictionary = _chain_reports.land_supply_status
	if land.claimed_value.status != "RECEIVED":
		return {}
	var remaining: float = float(land.claimed_value.get("requested_quantity", 0.0)) - float(land.claimed_value.get("received_quantity", 0.0))
	if remaining <= 0.000001 or not _chain_reports.has("sea_status"):
		return {}
	var sea: Dictionary = _chain_reports.sea_status
	var resource: String = str(land.claimed_value.get("resource_class", "AMMUNITION"))
	if sea.claimed_value.delivery_ref != land.claimed_value.sea_delivery_ref:
		if sea.claimed_value.get("transport_status", "") != "RECEIVED":
			return {}
		var continuation: Dictionary = context.duplicate(true)
		continuation.received_claims = [sea.duplicate(true)]
		continuation.standing_orders.supply_chain.land.cargo = {}
		continuation.standing_orders.supply_chain.land.cargo[resource] = remaining
		var node: String = str(land.claimed_value.node_ref)
		if str(land.claimed_value.edge_ref) != "" or not plan.get("approach_routes", {}).has(node):
			return {}
		continuation.standing_orders.supply_chain.land.approach_path = plan.approach_routes[node].duplicate()
		return _initial_supply_chain(continuation)
	if not plan.has("return_to_source"):
		return {}
	for vessel: Dictionary in context.get("owned_vessels", []):
		if vessel.vessel_ref != plan.sea.vessel_ref or vessel.status not in ["DOCKED", "ANCHORED"]:
			continue
		var values: Dictionary
		if vessel.node_ref == plan.sea.source_port:
			values = plan.sea.duplicate(true)
			values.cargo = {}
			values.cargo[resource] = remaining
		elif vessel.node_ref == plan.sea.destination_port:
			values = plan.return_to_source.duplicate(true)
		else:
			return {}
		var key: String = "replacement_" + str(land.entry_id) + ":" + str(values.operation)
		if float(context.decision_time) - float(_submitted.get(key, -600.0)) < 600.0:
			return {}
		_submitted[key] = context.decision_time
		return {"intent": {"kind": "command", "command_kind": "naval_intent", "target": context.position_ref,
			"channel_ref": plan.get("channel_ref", "command"), "values": values}, "selected_claim": land.entry_id}
	return {}

func _initial_supply_chain(context: Dictionary) -> Dictionary:
	var plan: Dictionary = context.standing_orders.supply_chain
	if float(context.decision_time) < maxf(float(context.command_ready_at), float(context.command_issue_ready_at)):
		return {}
	for claim: Dictionary in context.received_claims:
		if claim.fact_kind == "land_supply_status" and float(claim.reliability) > 0.0 and claim.claimed_value.get("request_ref", "") == plan.request_ref:
			return {}
	for index: int in range(context.received_claims.size() - 1, -1, -1):
		var claim: Dictionary = context.received_claims[index]
		if claim.fact_kind != "sea_status" or float(claim.reliability) <= 0.0 or claim.claimed_value.get("request_ref", "") != plan.request_ref or claim.claimed_value.get("transport_status", "") != "RECEIVED":
			continue
		var key: String = "land_after_" + str(claim.claimed_value.delivery_ref)
		if float(context.decision_time) - float(_submitted.get(key, -600.0)) < 600.0:
			return {}
		_submitted[key] = context.decision_time
		return {"intent": {"kind": "command", "command_kind": "land_intent", "target": context.position_ref, "channel_ref": plan.get("channel_ref", "command"),
			"values": plan.land.duplicate(true)}, "selected_claim": claim.entry_id}
	if not _submitted.has("initial_sea_supply"):
		_submitted.initial_sea_supply = true
		return {"intent": {"kind": "command", "command_kind": "naval_intent", "target": context.position_ref, "channel_ref": plan.get("channel_ref", "command"),
			"values": plan.sea.duplicate(true)}, "selected_claim": ""}
	return {}

func _joint(context: Dictionary) -> Dictionary:
	# This bounded opponent sees own navigation and delivered claims only.
	var orders: Dictionary = context.standing_orders.joint
	for asset: Dictionary in context.get("owned_air", []):
		if asset.asset_ref != orders.air_asset_ref or asset.status not in ["LANDED", "READY", "WAITING_SUPPLY"]:
			continue
		if float(asset.fuel) < 3.0 or float(asset.load) < 6.0 or float(asset.integrity) < 1.0:
			return _joint_command(context, "air_intent", {"asset_ref": asset.asset_ref, "operation": "service", "refuel": true, "rearm": true, "repair": true})
		if not asset.serviceable:
			continue
		for index: int in range(context.received_claims.size() - 1, -1, -1):
			var claim: Dictionary = context.received_claims[index]
			if claim.fact_kind != "air_track" or _submitted.has(claim.entry_id) or float(context.decision_time) - float(claim.observed_at) > 600.0:
				continue
			_submitted[claim.entry_id] = true
			return _joint_command(context, "air_intent", {"asset_ref": asset.asset_ref, "operation": "intercept", "target_node": claim.claimed_value.node_ref,
				"outbound": [claim.claimed_value.node_ref], "inbound": [asset.base], "target_ref": claim.subject_ref}, str(claim.entry_id))
	for vessel: Dictionary in context.get("owned_vessels", []):
		if vessel.vessel_ref != orders.vessel_ref or vessel.status in ["SUNK", "LOADING", "UNLOADING", "REPAIRING", "SERVICING"]:
			continue
		if float(vessel.get("flooding", 0.0)) + float(vessel.get("fire", 0.0)) > 0.0 and not vessel.get("control_active", false) and float(vessel.get("spares", 0.0)) >= 0.1:
			return _joint_command(context, "naval_intent", {"vessel_ref": vessel.vessel_ref, "operation": "damage_control", "active": true})
		if vessel.status not in ["DOCKED", "ANCHORED", "SUPPLY_EXHAUSTED", "IMMOBILE"]:
			continue
		if float(vessel.integrity) < 1.0 and float(vessel.get("flooding", 0.0)) + float(vessel.get("fire", 0.0)) <= 0.0 and vessel.node_ref == vessel.port:
			return _joint_command(context, "naval_intent", {"vessel_ref": vessel.vessel_ref, "operation": "repair"})
		if float(vessel.fuel) < 1.0 or float(vessel.ammunition) < 2.0:
			if vessel.node_ref == vessel.port:
				return _joint_command(context, "naval_intent", {"vessel_ref": vessel.vessel_ref, "operation": "service"})
			var home_path: Array = orders.routes.get(str(vessel.node_ref) + ":" + str(vessel.port), [])
			return _joint_command(context, "naval_intent", {"vessel_ref": vessel.vessel_ref, "operation": "sail", "path": home_path, "target_node": vessel.port, "target_ref": ""})
		for index: int in range(context.received_claims.size() - 1, -1, -1):
			var claim: Dictionary = context.received_claims[index]
			if claim.fact_kind != "sea_contact" or _submitted.has(claim.entry_id) or float(context.decision_time) - float(claim.observed_at) > 600.0:
				continue
			var node: String = str(claim.claimed_value.node_ref)
			var key: String = str(vessel.node_ref) + ":" + node
			if vessel.node_ref != node and not orders.routes.has(key):
				continue
			_submitted[claim.entry_id] = true
			return _joint_command(context, "naval_intent", {"vessel_ref": vessel.vessel_ref, "operation": "intercept", "path": orders.routes.get(key, []), "target_node": node, "target_ref": claim.subject_ref}, str(claim.entry_id))
		if vessel.node_ref == "SEA_M" or orders.routes.has(str(vessel.node_ref) + ":SEA_M"):
			return _joint_command(context, "naval_intent", {"vessel_ref": vessel.vessel_ref, "operation": "blockade", "path": orders.routes.get(str(vessel.node_ref) + ":SEA_M", []), "target_node": "SEA_M", "target_ref": ""})
	return {"intent": {"kind": "keep"}, "selected_claim": ""}

func _joint_command(context: Dictionary, kind: String, values: Dictionary, claim: String = "") -> Dictionary:
	return {"intent": {"kind": "command", "command_kind": kind, "target": context.position_ref,
		"channel_ref": context.standing_orders.joint.channel_ref, "values": values}, "selected_claim": claim}

const RUNTIME_FIELDS: Array[String] = ["source", "_submitted", "_supply_episodes", "_chain_reports"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
