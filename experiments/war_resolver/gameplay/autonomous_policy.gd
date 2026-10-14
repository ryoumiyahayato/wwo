extends RefCounted
## Both factions consume the same received task/observation envelope.
const Legacy = preload("res://experiments/war_resolver/gameplay/policy.gd")
const MAX_CANDIDATES: int = 8
const FRESH_SECONDS: float = 600.0
var source: String = "autonomous_received_events"
var _legacy: Legacy = Legacy.new()
var _sent: Dictionary = {}
var _requests: Dictionary = {}
var _seeded: Dictionary = {}
var _relayed: Dictionary = {}
var _supplied: Dictionary = {}
var _recon: Dictionary = {}
var _campaign_attempts: Dictionary = {}
var _replacement_attempts: Dictionary = {}
var _failed_objectives: Dictionary = {}
var _failure_seen: Dictionary = {}
var _recovery: Dictionary = {}
var _sea_attempts: Dictionary = {}
var _route_attempts: Dictionary = {}
var _tactical_attempts: Dictionary = {}

const RUNTIME_FIELDS: Array[String] = ["source", "_sent", "_requests", "_seeded", "_relayed", "_supplied", "_recon", "_campaign_attempts", "_replacement_attempts", "_failed_objectives", "_failure_seen", "_recovery", "_sea_attempts", "_route_attempts", "_tactical_attempts"]

func runtime_state() -> Dictionary:
	return {"fields": preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS), "legacy": _legacy.runtime_state()}

func restore_runtime(image: Dictionary) -> bool:
	return image.get("fields") is Dictionary and image.get("legacy") is Dictionary and preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image.fields, RUNTIME_FIELDS) and _legacy.restore_runtime(image.legacy)

func evaluate(context: Dictionary) -> Dictionary:
	if float(context.decision_time) < maxf(float(context.command_ready_at), float(context.command_issue_ready_at)):
		return _keep()
	_remember_failures(context)
	_remember_shipping(context)
	var relay: Dictionary = _relay(context)
	if not relay.is_empty():
		return relay
	var platform: Dictionary = _restore_platform(context)
	if not platform.is_empty():
		return platform
	var deployment: Dictionary = _deploy_ground_capability(context, true)
	if not deployment.is_empty():
		return deployment
	var engineering: Dictionary = _deploy_ground_capability(context, false)
	if not engineering.is_empty():
		return engineering
	var recovery: Dictionary = _recover_information(context)
	if not recovery.is_empty():
		return recovery
	var survey: Dictionary = _route_survey(context)
	if not survey.is_empty():
		return survey
	var candidates: Array[Dictionary] = []
	for task: Dictionary in context.get("operations", []):
		if not task.has("task_ref") or task.get("executor", "") != context.person_id:
			continue
		candidates.append(task)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: int = int(a.operation_priority) * 10 + int(a.priority)
		var second: int = int(b.operation_priority) * 10 + int(b.priority)
		return first > second if first != second else float(a.deadline) < float(b.deadline))
	var count: int = 0
	for task: Dictionary in candidates:
		count += 1
		if count > MAX_CANDIDATES:
			break
		var choice: Dictionary = _task(context, task)
		if not choice.is_empty():
			choice.operation_ref = task.operation_ref
			choice.task_ref = task.task_ref
			choice.selected_claim = task.claim_ref
			choice.assignment_revision = int(task.get("assignment_revision", 0))
			choice.decided_at = context.decision_time
			return choice
	var reconnaissance: Dictionary = _refresh_recon(context)
	var local_support: Dictionary = _local_support(context)
	if not local_support.is_empty():
		return local_support
	var tactical: Dictionary = _tactical(context)
	if not tactical.is_empty():
		return tactical
	var construction: Dictionary = _construct_position(context)
	if not construction.is_empty():
		return construction
	if not reconnaissance.is_empty():
		return reconnaissance
	var responsibility: Dictionary = _continue_land_responsibilities(context)
	if not responsibility.is_empty():
		return responsibility
	var reallocation: Dictionary = _reallocate_sea(context)
	if not reallocation.is_empty():
		return reallocation
	var sea_responsibility: Dictionary = _continue_sea_responsibilities(context)
	if not sea_responsibility.is_empty():
		return sea_responsibility
	for plan: Dictionary in context.standing_orders.get("purposes", []):
		for known: Dictionary in context.get("operations", []):
			if not known.has("task_ref") and known.get("status", "") in ["ACTIVE", "BLOCKED"] and known.get("scope", "") == plan.target and known.get("purpose", "") == plan.values.purpose:
				_seeded[plan.plan_ref] = true
		if not _seeded.has(plan.plan_ref) and "operation_intent" in context.coordination_kinds:
			return {"intent": _command(context, "operation_intent", str(plan.target), plan.values), "plan_ref": plan.plan_ref}
	var shipping: Dictionary = _sea_supply(context)
	if not shipping.is_empty():
		return shipping
	var delivery: Dictionary = _supply_delivery(context)
	if not delivery.is_empty():
		return delivery
	var supply: Dictionary = _supply_request(context)
	if not supply.is_empty():
		return supply
	var replacement: Dictionary = _replace_failed(context)
	if not replacement.is_empty():
		return replacement
	var continuation: Dictionary = _continue_campaign(context)
	if not continuation.is_empty():
		return continuation
	# Explicit old input scripts remain available for attachment experiments.
	if context.standing_orders.get("inputs", []).size() > 0 or context.standing_orders.get("prototype_policy", false):
		var legacy: Dictionary = _legacy.evaluate(context)
		if legacy.intent.get("kind", "") != "keep":
			return legacy
	return _keep()

func _local_support(context: Dictionary) -> Dictionary:
	var policy: Dictionary = context.standing_orders.get("local_support", {})
	if not policy.get("enabled", false) or context.role != "squad_leader" or "tactical_intent" not in context.coordination_kinds:
		return {}
	var unit: String = str(context.authority_targets.get(context.position_ref, {}).get("unit_ref", ""))
	var field: Dictionary = _unit_claim(context, unit)
	if field.is_empty() or float(context.decision_time) - float(field.get("observed_at", -INF)) > FRESH_SECONDS or field.get("suppression_level", "") == "HIGH":
		return {}
	var support: Dictionary = field.get("tactical", {}).get("local_support", {})
	if support.get("handling", {}).get("status", "") == "PENDING":
		return {}
	var manoeuvre: Dictionary = field.get("tactical", {}).get("manoeuvre", {})
	if not manoeuvre.is_empty() and manoeuvre.get("phase", "") not in ["STOPPED", "COMPLETE", "REGROUPED"]:
		return {} # A received stop/progress report, never a hidden executor query.
	var index: int = 0
	for candidate: Dictionary in policy.get("ammunition_orders", []).slice(0, 4):
		index += 1
		var values: Dictionary = candidate.get("values", {})
		if values.is_empty():
			continue
		var part: Dictionary = support.get("parts", {}).get(candidate.get("when_part_low", ""), {})
		if candidate.has("when_part_low") and (part.is_empty() or float(part.ammunition) > float(candidate.get("threshold", 1.0))):
			continue
		if candidate.get("when_unit_low", true) and field.get("ammunition_level", "") != "LOW":
			continue
		if values.get("ammo_action", "") == "move" and not context.known_routes.get("local:" + str(values.get("destination_ref", "")), []).has(values.get("local_path", [])):
			continue
		var key: String = "local_ammunition:" + unit + ":" + str(index)
		var basis: Dictionary = {"values": values, "parts": support.get("parts", {}), "phase": manoeuvre.get("phase", ""), "reason": manoeuvre.get("reason", ""), "capability": field.get("capability", ""), "ammunition": field.get("ammunition_level", "")}
		if _tactical_attempts.get(key, {}) != basis:
			return {"intent": _command(context, "tactical_intent", str(context.position_ref), values), "tactical_key": key, "tactical_basis": basis}
	for candidate: Dictionary in policy.get("rescue_orders", []).slice(0, 4):
		var carrier: String = str(candidate.get("carrier_ref", ""))
		var patient: String = str(candidate.get("patient_ref", ""))
		var known: Dictionary = {}
		for claim: Dictionary in context.received_claims:
			if claim.subject_ref == patient and claim.fact_kind == "person_status" and float(claim.reliability) > 0.0 and float(context.decision_time) - float(claim.observed_at) <= FRESH_SECONDS and claim.claimed_value.get("life_state", "") in ["WOUNDED", "INCAPACITATED"]:
				known = claim.claimed_value
		if known.is_empty():
			continue
		var current: Dictionary = support.get("helpers", {}).get(carrier, {})
		if current.get("action_pending", false) or current.get("status", "") in ["APPROACHING", "CONTACT_REACHED", "PICKUP_PENDING", "ROAD_EVACUATION", "PUT_DOWN", "HANDED_OVER"]:
			continue
		var values: Dictionary = {"action": "rescue"}
		if current.get("status", "") == "CARRYING":
			values.merge({"rescue_action": "carry", "local_path": candidate.get("carry_path", []), "destination_ref": candidate.get("drop_place", "")})
		elif current.get("status", "") == "ARRIVED_CARRYING":
			if candidate.get("road_path") is Array and context.known_routes.get(str(candidate.get("road_node", "")), []).has(candidate.road_path):
				values.merge({"rescue_action": "road", "path": candidate.road_path, "destination_node": candidate.road_node})
			else:
				values.rescue_action = "put_down"
		else:
			values.merge({"rescue_action": "approach", "patient_ref": patient, "local_path": candidate.get("approach_path", []), "destination_ref": candidate.get("patient_place", "")})
		if values.has("local_path") and not context.known_routes.get("local:" + str(values.destination_ref), []).has(values.local_path):
			continue
		var key: String = "local_rescue:" + carrier + ":" + patient
		var basis: Dictionary = {"values": values, "helper": current, "patient": known, "capability": field.get("capability", ""), "suppression": field.get("suppression_level", "")}
		if _tactical_attempts.get(key, {}) != basis:
			return {"intent": _command(context, "tactical_intent", str(context.position_ref), {"carrier_ref": carrier, "rescue_order": values}), "tactical_key": key, "tactical_basis": basis}
	return {}

func _tactical(context: Dictionary) -> Dictionary:
	if "tactical_intent" not in context.coordination_kinds or not context.standing_orders.get("tactics", {}).get("enabled", false):
		return {}
	if context.role == "squad_leader":
		var unit: String = str(context.authority_targets.get(context.position_ref, {}).get("unit_ref", ""))
		var field: Dictionary = _unit_claim(context, unit)
		var road: Dictionary = _road_tactical(context, unit, field)
		if not road.is_empty():
			return road
		if not field.is_empty() and not field.get("occupied", false) and not field.get("retained", false) and float(context.decision_time) - float(field.get("observed_at", -INF)) <= FRESH_SECONDS:
			var values: Dictionary = {}
			var mode: String = str(field.get("tactical", {}).get("fire_order", {}).get("fire_mode", ""))
			if field.get("ammunition_level", "") == "LOW" or field.get("fire_reason", "") in ["ammunition_exhausted", "no_effective_target"]:
				if mode != "cease":
					values = {"fire_mode": "cease"}
			else:
				var contact: Dictionary = _tactical_contact(context, field)
				if not contact.is_empty():
					values = {"fire_mode": "suppress" if field.get("suppression_level", "") == "HIGH" else "concentrate", "target_ref": contact.subject_ref, "seconds": minf(300.0, maxf(5.0, float(context.standing_orders.tactics.get("fire_seconds", 60.0))))}
				elif mode == "cease" and field.get("fire_reason", "") == "":
					values = {"fire_mode": "resume"}
			var key: String = "squad:" + unit
			var basis: Dictionary = {"order": values, "ammo": field.get("ammunition_level", ""), "suppression": field.get("suppression_level", ""), "contact": _tactical_contact(context, field).get("entry_id", "")}
			if not values.is_empty() and _tactical_attempts.get(key, {}) != basis:
				return {"intent": _command(context, "tactical_intent", str(context.position_ref), values), "tactical_key": key, "tactical_basis": basis}
	for unit: String in context.unit_reports:
		var field: Dictionary = _unit_claim(context, unit)
		if field.is_empty() or field.get("occupied", true) or field.get("retained", false) or float(context.decision_time) - float(field.get("observed_at", -INF)) > FRESH_SECONDS:
			continue
		if _resource_busy(context, "GROUND", unit):
			continue
		for gun: Dictionary in field.get("tactical", {}).get("guns", []).slice(0, 2):
			var target: String = ""
			for scope: String in context.command_targets:
				if context.authority_targets.get(scope, {}).get("unit_ref", "") == unit:
					target = scope
			if target == "" and context.position_ref in context.command_targets:
				target = str(context.position_ref)
			if target == "":
				continue
			var values: Dictionary = {}
			var key: String = "gun:" + str(gun.id)
			var basis: Dictionary = {"state": gun.state, "ammo": field.get("ammunition_level", ""), "ammunition_available": field.tactical.get("unreserved_ammunition", 0.0), "node": field.get("node_ref", ""), "equipment": field.get("available_equipment", 0.0), "crew": field.get("available_crew", 0.0), "suppression": field.get("suppression_level", "")}
			if gun.state in ["PACKED", "INTERRUPTED"] and field.get("ammunition_level", "") != "LOW":
				values = {"gun_ref": gun.id, "gun_action": "deploy"}
			elif gun.state == "EMPTY" and field.get("ammunition_level", "") != "LOW":
				values = {"gun_ref": gun.id, "gun_action": "reload"}
			elif gun.state == "READY" and float(gun.ready) > 0.000001:
				for claim: Dictionary in context.received_claims:
					if claim.fact_kind not in ["air_contact", "ground_contact"] or float(claim.reliability) <= 0.0 or float(context.decision_time) - float(claim.observed_at) > FRESH_SECONDS or not claim.claimed_value.get("xy") is Array or not field.get("xy") is Array:
						continue
					var point: Array = claim.claimed_value.xy
					var own: Array = field.xy
					if sqrt(pow(float(point[0]) - float(own[0]), 2.0) + pow(float(point[1]) - float(own[1]), 2.0)) > float(gun.profile.range_km):
						continue
					key = "gunshot:" + str(gun.id) + ":" + str(claim.entry_id)
					basis = {"claim": claim.entry_id}
					if _tactical_attempts.has(key):
						continue
					values = {"gun_ref": gun.id, "gun_action": "fire", "claim_ref": claim.entry_id, "missions": 1}
					break
			if not values.is_empty() and _tactical_attempts.get(key, {}) != basis:
				return {"intent": _command(context, "tactical_intent", target, values), "tactical_key": key, "tactical_basis": basis}
	return {}

func _road_tactical(context: Dictionary, unit: String, field: Dictionary) -> Dictionary:
	var policy: Dictionary = context.standing_orders.get("tactics", {}).get("manoeuvre", {})
	if policy.is_empty() or field.is_empty() or float(context.decision_time) - float(field.get("observed_at", -INF)) > FRESH_SECONDS:
		return {}
	var current: Dictionary = field.get("tactical", {}).get("manoeuvre", {})
	if current.get("mission_ref", "") != field.get("mission_ref", ""):
		current = {}
	var values: Dictionary = {}
	var key: String = "road:" + unit + ":" + str(field.get("mission_ref", ""))
	var phase: String = str(current.get("phase", ""))
	if phase in ["COMPLETE", "REGROUPED"]:
		return {}
	if not current.is_empty() and phase not in ["COMPLETE", "REGROUPED"]:
		if phase != "STOPPED" or field.get("capability", "") != "AVAILABLE" or field.get("suppression_level", "") == "HIGH":
			return {}
		if policy.get("regroup_on_stop", false):
			values = {"manoeuvre_action": "regroup"}
		elif policy.get("resume_on_route_report", false) and current.get("reason", "") == "actual_road_blocked" and _known_open(context, str(current.edge_ref), float(current.get("stopped_at", context.decision_time))):
			values = {"manoeuvre_action": "resume"}
		elif policy.get("resume_on_route_report", false) and current.get("reason", "") == "actual_local_path_blocked" and current.get("local_link", {}).get("state", "") == "OPEN" and float(current.local_link.observed_at) > float(current.get("stopped_at", context.decision_time)):
			values = {"manoeuvre_action": "resume"}
		else:
			return {}
		key += ":" + str(current.id) + ":" + str(values.manoeuvre_action)
	else:
		if field.get("occupied", false) or field.get("retained", false) or field.get("capability", "") != "AVAILABLE" or field.get("status", "") != "active" or not policy.get("parts") is Dictionary and not policy.get("movers") is Array or not policy.get("local_path", policy.get("path")) is Array:
			return {}
		var local: bool = policy.has("local_path")
		var destination: String = str(policy.get("destination_ref" if local else "destination_node", ""))
		var path: Array = policy.get("local_path", policy.get("path", []))
		if not context.known_routes.get("local:" + destination if local else destination, []).has(path):
			return {}
		values = {"manoeuvre_action": policy.get("manoeuvre_action", "advance"), "seconds": policy.get("seconds", 600.0), "require_cover": policy.get("require_cover", true)}
		values["local_path" if local else "path"] = path.duplicate()
		values["destination_ref" if local else "destination_node"] = destination
		if policy.has("parts"):
			values.parts = policy.parts.duplicate(true)
		else:
			values.movers = policy.movers.duplicate()
		var contact: Dictionary = _tactical_contact(context, field)
		if values.require_cover:
			if contact.is_empty():
				return {}
			values.target_ref = contact.subject_ref
	# Received observations choose the intent. Delivery rechecks actual members,
	# equipment, stock and geometry through the same path as a player's intent.
	var basis: Dictionary = {"values": values, "mission": field.get("mission_ref", ""),
		"node": field.get("node_ref", ""), "local_place": field.get("local_place_ref", ""), "ammunition": field.get("ammunition_level", ""), "suppression": field.get("suppression_level", "")}
	if _tactical_attempts.get(key, {}) == basis:
		return {}
	return {"intent": _command(context, "tactical_intent", str(context.position_ref), values), "tactical_key": key, "tactical_basis": basis}

func _tactical_contact(context: Dictionary, field: Dictionary) -> Dictionary:
	if not field.get("xy") is Array:
		return {}
	for index: int in range(context.received_claims.size() - 1, -1, -1):
		var claim: Dictionary = context.received_claims[index]
		if claim.fact_kind not in ["air_contact", "ground_contact"] or float(claim.reliability) <= 0.0 or float(context.decision_time) - float(claim.observed_at) > FRESH_SECONDS or claim.claimed_value.get("condition", "") == "INCAPACITATED" or not claim.claimed_value.get("xy") is Array:
			continue
		var point: Array = claim.claimed_value.xy
		var own: Array = field.xy
		if sqrt(pow(float(point[0]) - float(own[0]), 2.0) + pow(float(point[1]) - float(own[1]), 2.0)) <= float(field.get("tactical", {}).get("weapon_range_km", 0.0)):
			return claim
	return {}

func _construct_position(context: Dictionary) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds:
		return {}
	for plan: Dictionary in context.standing_orders.get("construction_plans", []).slice(0, MAX_CANDIDATES):
		var unit: String = str(plan.get("unit_ref", ""))
		var field: Dictionary = _unit_claim(context, unit)
		var kind: String = str(plan.get("position_kind", ""))
		var profile: Dictionary = field.get("engineering_capability", {}).get("positions", {}).get(kind, {})
		if not _in_scope_unit(context, unit) or field.is_empty() or field.get("occupied", true) or field.get("retained", false) or profile.is_empty() or float(field.get("engineering_spares", 0.0)) < float(profile.spares) or float(context.decision_time) - float(field.get("observed_at", -INF)) > FRESH_SECONDS or _resource_busy(context, "GROUND", unit):
			continue
		if field.get("ground_work", {}).get("position_ref", "") == plan.position_ref and field.ground_work.get("status", "") == "COMPLETE":
			continue
		var node: String = str(plan.node_ref)
		if not plan.routes.has(field.get("node_ref", "")):
			continue
		var key: String = "construct:" + str(plan.position_ref)
		var basis: Dictionary = {"node": field.node_ref, "materials": field.engineering_spares, "crew": field.get("available_crew", 0.0), "equipment": field.get("available_equipment", 0.0)}
		if _tactical_attempts.get(key, {}) == basis:
			continue
		var task: Dictionary = {"task_ref": "construct", "domain": "GROUND", "unit_ref": unit, "priority": 3, "required": true, "followup": false,
			"goal": {"intent": "advance", "target_node": node, "path": plan.routes[field.node_ref], "return_to_start": false},
			"engineering": {"action": "build", "position_ref": plan.position_ref, "position_kind": kind}, "routes": plan.routes.duplicate(true)}
		return {"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "begin", "purpose": "hold", "target_node": node, "priority": 3, "deadline_seconds": 3600.0, "tasks": [task]}), "tactical_key": key, "tactical_basis": basis}
	return {}

func _task(context: Dictionary, task: Dictionary) -> Dictionary:
	if task.status == "CANCEL_PENDING" and _may_send(context, task, "CANCEL"):
		var cancel: Dictionary = _cancel_task(context, task)
		return {"intent": cancel, "task_phase": "CANCEL"} if not cancel.is_empty() else {}
	if task.status in ["QUEUED", "WAITING_RESOURCE", "COMMAND_PENDING", "CANCELLED"]:
		return {}
	if task.status in ["COMPLETE", "FAILED"]:
		if task.domain == "GROUND" and task.get("followup", true) and not task.has("followup_status") and _may_send(context, task, "FOLLOW") and not _next_ground_task(context, task):
			var state: Dictionary = _unit_claim(context, str(task.unit_ref))
			if state.is_empty() or state.get("capability", "") == "UNAVAILABLE" or state.get("occupied", false) or _confirmed_unavailable(context, str(task.unit_ref)):
				return {}
			var follow: Dictionary = _hold(context, task, state)
			if not follow.is_empty():
				return {"intent": follow, "task_phase": "FOLLOW"}
		return {}
	if float(context.decision_time) >= float(task.deadline):
		return {}
	if task.domain == "GROUND":
		return _ground(context, task)
	if task.domain == "LAND" and task.status == "BLOCKED":
		var resumed: Dictionary = _resume_land(context, task)
		if not resumed.is_empty():
			return resumed
	if task.domain == "NAVAL" and task.status in ["EXECUTING", "BLOCKED"] and task.intent.values.get("operation", "") in ["transport", "continue_transport", "resume_transport", "unload", "reassign_cargo"]:
		var resumed: Dictionary = _resume_sea(context, task)
		if not resumed.is_empty():
			return resumed
	if task.domain == "NAVAL" and task.status == "BLOCKED" and task.intent.values.get("operation", "") == "sail":
		var resumed: Dictionary = _resume_navigation(context, task)
		if not resumed.is_empty():
			return resumed
	if task.status not in ["ASSIGNED", "BLOCKED"] or not _may_send(context, task, "EXECUTE"):
		return {}
	var intent: Dictionary = task.intent.duplicate(true)
	if intent.kind == "command":
		if intent.target != context.position_ref or intent.command_kind not in context.coordination_kinds:
			return {}
		var values: Dictionary = intent.values
		if task.get("target_from_recon", false):
			var contact: Dictionary = _contact(context, str(task.get("contact_node", task.target_node)))
			if contact.is_empty():
				return {}
			values.target_ref = contact.subject_ref
			if task.domain == "AIR":
				values.target_node = contact.claimed_value.node_ref
				values.outbound = [values.target_node]
		if task.domain == "AIR":
			for asset: Dictionary in context.owned_air:
				if asset.asset_ref != values.asset_ref:
					continue
				if asset.status not in ["LANDED", "READY", "WAITING_SUPPLY"] or not asset.get("service_ref", "").is_empty():
					return {}
				var armed: bool = values.operation in ["strike", "intercept"]
				if not asset.serviceable or float(asset.fuel) < 3.0 or armed and float(asset.load) < 1.0:
					if _may_send(context, task, "SERVICE"):
						return {"intent": _command(context, "air_intent", str(context.position_ref), {"asset_ref": asset.asset_ref, "operation": "service", "refuel": true, "rearm": armed, "repair": true}), "task_phase": "SERVICE"}
					return {}
				break
		elif task.domain == "NAVAL":
			var found: bool = false
			for vessel: Dictionary in context.owned_vessels:
				if vessel.vessel_ref == values.vessel_ref:
					found = true
					if values.operation == "continue_transport":
						if vessel.get("cargo_ref", "") != task.get("transport_ref", "") or vessel.status == "SUNK" or vessel.get("transfer_ref", "") != "":
							return {}
					elif values.operation == "transship_cargo":
						var received: bool = false
						for receiver: Dictionary in context.owned_vessels:
							if receiver.vessel_ref == values.recipient_vessel_ref and receiver.status in ["DOCKED", "ANCHORED", "CARGO_WAITING"] and str(receiver.get("transfer_ref", "")) == "":
								received = true
						if not received or vessel.get("cargo_ref", "") != task.get("transport_ref", ""):
							return {}
					elif values.operation in ["rendezvous", "reassign_cargo"]:
						if vessel.status not in ["DOCKED", "ANCHORED", "CARGO_WAITING", "WAITING_PORT", "BLOCKED"] or not vessel.get("mobile", false) or float(vessel.fuel) <= 0.0:
							return {}
					elif values.operation in ["resume_transport", "unload"]:
						if vessel.get("cargo_ref", "") != task.get("transport_ref", "") or vessel.status not in ["DOCKED", "ANCHORED", "BLOCKED", "CARGO_WAITING", "WAITING_PORT", "FUEL_EXHAUSTED", "IMMOBILE"]:
							return {}
						if values.operation == "resume_transport" and (not vessel.get("mobile", false) or float(vessel.fuel) <= 0.0):
							return {}
					elif vessel.status not in ["DOCKED", "ANCHORED"] or not str(vessel.get("cargo_ref", "")).is_empty() or not str(vessel.get("recovery_ref", "")).is_empty():
						return {}
					if task.has("routes"):
						if not task.routes.has(str(vessel.node_ref)):
							return {}
						values.path = task.routes[vessel.node_ref].duplicate()
			if not found:
				return {}
		elif task.domain == "LAND":
			if task.has("transport_ref") and values.get("operation", "") == "continue_transport":
				for report: Dictionary in context.land_transports:
					if report.transport_ref == task.transport_ref and report.status not in ["RECEIVED", "LOST", "CARGO_LOST", "CANCELLED_BEFORE_LOADING"] and float(context.decision_time) - float(report.observed_at) <= FRESH_SECONDS:
						intent.channel_ref = _channel(context)
						return {"intent": intent, "task_phase": "EXECUTE"}
				return {}
			if not _routes_reported(context, task):
				return {}
			var field: Dictionary = _unit_claim(context, str(values.unit_ref))
			if field.is_empty() or field.get("occupied", false) or field.get("capability", "") != "AVAILABLE" or not str(field.get("edge_ref", "")).is_empty():
				return {}
			if values.get("operation", "") == "transport":
				var quantity: float = 0.0
				for amount: Variant in values.cargo.values():
					quantity += float(amount)
				var capacity: float = float(field.get("transport_capacity", 0.0))
				if capacity <= 0.000001 or quantity <= 0.000001:
					return {}
				if quantity > capacity:
					for resource: String in values.cargo:
						values.cargo[resource] = float(values.cargo[resource]) * capacity / quantity
			if task.has("approach_routes"):
				if not task.approach_routes.has(str(field.node_ref)):
					return {}
				values.approach_path = task.approach_routes[field.node_ref].duplicate()
			if task.has("handover_unit"):
				var recipient: Dictionary = _unit_claim(context, str(task.handover_unit))
				if recipient.is_empty() or not str(recipient.edge_ref).is_empty() or not task.get("handover_routes", {}).has(str(recipient.node_ref)):
					return {}
				values.target_node = recipient.node_ref
				values.path = task.handover_routes[recipient.node_ref].duplicate()
			if not str(values.get("request_ref", "")).is_empty():
				var balance: Dictionary = _known_balance(context, str(values.request_ref))
				if balance.get("sea_delivery_ref", "") != "":
					var resource: String = str(balance.resource_class)
					var quantity: float = minf(float(values.cargo.get(resource, 0.0)), minf(float(balance.port_remaining), float(balance.quantity) - float(balance.received_quantity)))
					if quantity <= 0.000001 or balance.status != "REQUESTED":
						return {}
					values.cargo = {resource: quantity}
		intent.channel_ref = _channel(context)
	return {"intent": intent, "task_phase": "EXECUTE"}

func _ground(context: Dictionary, task: Dictionary) -> Dictionary:
	var state: Dictionary = _unit_claim(context, str(task.unit_ref))
	if state.is_empty() or state.get("occupied", false) or state.get("capability", "") == "UNAVAILABLE":
		return {}
	var contact: Dictionary = context.get("contact_states", {}).get("unit:" + str(task.unit_ref), {})
	if contact.get("status", "") in ["CONFIRMED_LOSS", "CONFIRMED_UNAVAILABLE"]:
		return {}
	if task.goal.target_node != state.get("node_ref", "") or not task.goal.path.is_empty():
		for gun: Dictionary in state.get("tactical", {}).get("guns", []):
			if gun.state == "PACKED":
				continue
			if gun.state == "PACKING":
				return {}
			var packing_target: String = _ground_target(context, str(task.unit_ref))
			if packing_target == "" and context.position_ref in context.command_targets:
				packing_target = context.position_ref
			if packing_target != "" and "tactical_intent" in context.coordination_kinds and _may_send(context, task, "FIRE_PACK_MOVE"):
				return {"intent": _command(context, "tactical_intent", packing_target, {"gun_ref": gun.id, "gun_action": "pack"}), "task_phase": "FIRE_PACK_MOVE", "fire_basis": _gun_basis(state, str(gun.id))}
			return {}
	if task.has("fire_support") and task.status in ["EXECUTING", "BLOCKED"] and state.get("mission_ref", "") == task.get("mission_ref", "__unassigned") and state.get("node_ref", "") == task.goal.target_node and str(state.get("edge_ref", "")) == "" and state.get("path", []).is_empty():
		var support: Dictionary = _gun_support(context, task, state)
		if not support.is_empty():
			return support
		return {}
	var limited: bool = state.get("ammunition_level", "") == "LOW" or state.get("reason", "") in ["fuel_exhausted", "suppression"] or state.get("capability", "") == "IMMOBILE"
	if task.status in ["EXECUTING", "BLOCKED"] and limited and task.goal.intent == "advance" and _may_send(context, task, "PAUSE"):
		var pause: Dictionary = _hold(context, task, state)
		if not pause.is_empty():
			return {"intent": pause, "task_phase": "PAUSE"}
	if task.status == "EXECUTING":
		return {}
	if limited and task.goal.intent == "advance":
		return {}
	if task.status in ["ASSIGNED", "RETAINED", "PAUSED", "BLOCKED"] and not _routes_reported(context, task):
		return {}
	if task.get("require_recon", false):
		var informed: bool = false
		for claim: Dictionary in context.received_claims:
			if claim.fact_kind == "recon_result" and claim.claimed_value.get("node_ref", "") == task.goal.target_node and float(claim.reliability) > 0.0 and float(claim.observed_at) >= float(task.get("recon_not_before", task.started_at)) and float(context.decision_time) - float(claim.observed_at) <= FRESH_SECONDS:
				informed = true
		if not informed:
			return {}
	var target: String = _ground_target(context, str(task.unit_ref))
	if target.is_empty():
		if "reserve_intent" not in context.coordination_kinds:
			return {}
		if task.status != "RETAINED" and not state.get("retained", false):
			if _may_send(context, task, "RETAIN"):
				return {"intent": _command(context, "reserve_intent", str(context.position_ref), {"policy": "retain", "units": [task.unit_ref]}), "task_phase": "RETAIN"}
			return {}
	var goal: Dictionary = task.goal.duplicate(true)
	var phase: String = "EXECUTE"
	var origin: String = str(state.node_ref)
	if task.get("routes", {}).has(origin):
		goal.path = task.routes[origin].duplicate()
	if state.get("reason", "") == "route_blocked":
		var alternatives: Array = task.get("alternatives", {}).get(origin, [])
		var reopened: bool = _known_open(context, str(state.get("blocked_edge", "")), float(state.get("blocked_at", state.get("observed_at", -INF))))
		if alternatives.is_empty() and not reopened:
			return {}
		if not reopened:
			goal.path = alternatives[0].duplicate()
		goal.return_to_start = not str(state.edge_ref).is_empty()
		if state.get("status", "") == "active" and state.get("mission_ref", "") == task.get("mission_ref", "__unassigned"):
			goal.resume = true
			phase = "REROUTE"
	if task.status in ["ASSIGNED", "RETAINED", "PAUSED", "BLOCKED"] and _may_send(context, task, phase):
		if target.is_empty():
			return {"intent": _command(context, "reserve_intent", str(context.position_ref), {"policy": "release", "tasks": [{"unit_ref": task.unit_ref, "goal": goal}]}), "task_phase": "EXECUTE"}
		return {"intent": _command(context, "goal_intent", target, goal), "task_phase": phase}
	return {}

func _gun_support(context: Dictionary, task: Dictionary, field: Dictionary) -> Dictionary:
	if "tactical_intent" not in context.coordination_kinds:
		return {}
	var target: String = _ground_target(context, str(task.unit_ref))
	if target == "" and context.position_ref in context.command_targets:
		target = context.position_ref
	if target == "":
		return {}
	for gun: Dictionary in field.get("tactical", {}).get("guns", []):
		if gun.id != task.fire_support.gun_ref:
			continue
		var values: Dictionary = {"gun_ref": gun.id}
		var phase: String = "FIRE_DEPLOY"
		if gun.state in ["PACKED", "INTERRUPTED"]:
			values.gun_action = "deploy"
		elif gun.state == "EMPTY" and field.get("ammunition_level", "") != "LOW":
			values.gun_action = "reload"
			phase = "FIRE_RELOAD"
		elif gun.state == "READY" and float(gun.ready) > 0.0:
			var claim: Dictionary = _contact(context, str(task.fire_support.target_node))
			if claim.is_empty():
				return {}
			values.gun_action = "fire"
			values.claim_ref = claim.entry_id
			values.missions = int(task.fire_support.get("missions", 1))
			phase = "FIRE_EXECUTE"
			if task.get("fire_command_ref", "") != "":
				if gun.get("last_fire", {}).get("command_ref", "") != task.fire_command_ref or int(gun.get("remaining", 0)) <= 0:
					return {}
				values.missions = int(gun.remaining)
				phase = "FIRE_RESUME"
		else:
			return {}
		if _may_send(context, task, phase):
			return {"intent": _command(context, "tactical_intent", target, values), "task_phase": phase, "fire_basis": _gun_basis(field, str(gun.id))}
	return {}

func _gun_basis(field: Dictionary, reference: String) -> Dictionary:
	for gun: Dictionary in field.get("tactical", {}).get("guns", []):
		if gun.id == reference:
			return {"gun_ref": gun.id, "state": gun.state, "revision": gun.revision, "ready": gun.ready, "remaining": gun.get("remaining", 0),
				"ammunition": field.tactical.get("unreserved_ammunition", 0.0), "node": field.get("node_ref", ""), "equipment": field.get("available_equipment", 0.0), "crew": field.get("available_crew", 0.0)}
	return {}

func _hold(context: Dictionary, task: Dictionary, state: Dictionary) -> Dictionary:
	var target: String = _ground_target(context, str(task.unit_ref))
	if target.is_empty():
		if "reserve_intent" in context.coordination_kinds:
			return _command(context, "reserve_intent", str(context.position_ref), {"policy": "retain", "units": [task.unit_ref]})
		return {}
	var returning: bool = not str(state.get("edge_ref", "")).is_empty()
	var node: String = str(state.get("from_node", "")) if returning else str(state.node_ref)
	if not context.known_routes.get(node, []).has([]):
		return {}
	return _command(context, "goal_intent", target, {"intent": "hold", "target_node": node, "path": [], "return_to_start": returning})

func _known_open(context: Dictionary, edge: String, not_before: float) -> bool:
	var latest: Dictionary = {}
	for claim: Dictionary in context.received_claims:
		if claim.fact_kind == "route_observation" and claim.subject_ref == edge and float(claim.reliability) > 0.0 and float(claim.observed_at) >= float(latest.get("observed_at", -INF)):
			latest = claim
	return not latest.is_empty() and latest.claimed_value.get("state", "") == "PASSABLE" and float(latest.observed_at) >= not_before and float(context.decision_time) - float(latest.observed_at) <= FRESH_SECONDS

func _resume_land(context: Dictionary, task: Dictionary) -> Dictionary:
	if not _may_send(context, task, "REDIRECT"):
		return {}
	for known: Dictionary in context.get("land_transports", []):
		if known.transport_ref != task.get("transport_ref", task.get("payload_ref", "")):
			continue
		if known.get("transport_status", known.status) == "STRANDED":
			return _recover_stranded(context, task, known)
		if known.get("transport_status", known.status) not in ["BLOCKED", "STOPPED", "CAPACITY_LOST", "FUEL_EXHAUSTED", "TEMPORARILY_IMMOBILE", "WAITING_RECIPIENT"]:
			continue
		var target: String = str(known.target_node) if known.get("loaded", false) else str(known.get("source_node", ""))
		var path: Array = []
		var redirected: bool = false
		if known.get("transport_status", known.status) == "WAITING_RECIPIENT" and task.has("handover_unit"):
			var recipient: Dictionary = _unit_claim(context, str(task.handover_unit))
			if recipient.is_empty() or str(recipient.edge_ref) != "":
				return {}
			if recipient.node_ref == target and str(known.edge_ref) == "" and known.node_ref == target:
				return {"intent": _command(context, "land_intent", str(context.position_ref), {"operation": "unload", "transport_ref": known.transport_ref}), "task_phase": "REDIRECT"}
			target = str(recipient.node_ref)
			redirected = true
			path = task.get("redirect_routes", {}).get(str(known.node_ref) + ":" + target, []).duplicate()
		else:
			var candidates: Array = task.get("alternative_routes", {}).get(str(known.node_ref) + ":" + target, [])
			if _known_open(context, str(known.get("blocked_edge", "")), float(known.get("blocked_at", known.observed_at))):
				var primary: Array = task.get("resume_routes", {}).get(str(known.node_ref), task.get("handover_routes", {}).get(target, task.intent.values.get("path", [])))
				if not primary.is_empty():
					candidates.push_front(primary)
			if candidates.is_empty():
				return {}
			path = candidates[0].duplicate()
		if path.is_empty() or not context.known_routes.get(target, []).has(path):
			return {}
		var values: Dictionary = {"operation": "redirect_transport" if redirected else "resume_transport", "transport_ref": known.transport_ref,
			"target_node": target, "path": path, "return_to_start": str(known.edge_ref) != ""}
		if redirected:
			values.recipient_kind = "unit"
			values.recipient_ref = task.handover_unit
		return {"intent": _command(context, "land_intent", str(context.position_ref), values), "task_phase": "REDIRECT"}
	return {}

func _recover_stranded(context: Dictionary, task: Dictionary, known: Dictionary) -> Dictionary:
	if not _may_send(context, task, "RECOVER") or str(known.edge_ref) != "" or known.get("payload_kind", "") != "CARGO":
		return {}
	var load: float = 0.0
	for quantity: Variant in known.get("cargo", {}).values():
		load += float(quantity)
	if load <= 0.0:
		return {}
	var count: int = 0
	for unit: String in task.get("recovery_carriers", []):
		count += 1
		if count > MAX_CANDIDATES:
			break
		var state: Dictionary = _unit_claim(context, unit)
		if unit == known.carrier_ref or state.is_empty() or state.get("occupied", false) or state.get("retained", false) or state.get("capability", "") != "AVAILABLE" or float(state.get("transport_capacity", 0.0)) < load or state.get("fuel_level", "") == "LOW" or str(state.edge_ref) != "" or state.node_ref != known.node_ref or _resource_busy(context, "GROUND", unit):
			continue
		return {"intent": _command(context, "land_intent", str(context.position_ref), {"operation": "recover_cargo", "transport_ref": known.transport_ref, "unit_ref": unit}), "task_phase": "RECOVER"}
	return {}

func _ground_target(context: Dictionary, unit: String) -> String:
	for node: String in context.command_targets:
		if context.authority_targets[node].unit_ref == unit:
			return node
	return ""

func _next_ground_task(context: Dictionary, task: Dictionary) -> bool:
	for other: Dictionary in context.get("operations", []):
		if other.get("domain", "") == "GROUND" and other.id != task.id and other.unit_ref == task.unit_ref and other.status not in ["COMPLETE", "FAILED", "CANCELLED"]:
			return true
	return false

func _cancel_task(context: Dictionary, task: Dictionary) -> Dictionary:
	if task.domain == "GROUND":
		var target: String = _ground_target(context, str(task.unit_ref))
		if task.has("fire_support") and "tactical_intent" in context.coordination_kinds:
			if target == "" and context.position_ref in context.command_targets:
				target = context.position_ref
			if target != "":
				return _command(context, "tactical_intent", target, {"gun_ref": task.fire_support.gun_ref, "gun_action": "stop"})
		if not target.is_empty():
			return _command(context, "goal_intent", target, {"intent": "cancel", "target_node": "", "path": [], "return_to_start": false})
		if "reserve_intent" in context.coordination_kinds:
			return _command(context, "reserve_intent", str(context.position_ref), {"policy": "retain", "units": [task.unit_ref]})
	elif task.domain == "AIR":
		for asset: Dictionary in context.owned_air:
			if asset.asset_ref == task.intent.values.asset_ref and asset.status in ["TAKING_OFF", "OUTBOUND", "OBSERVING", "RETURNING", "LANDING"]:
				return _command(context, "air_intent", str(context.position_ref), {"asset_ref": asset.asset_ref, "operation": "abort"})
	elif task.domain == "NAVAL":
		return _command(context, "naval_intent", str(context.position_ref), {"vessel_ref": task.intent.values.vessel_ref, "operation": "stop"})
	elif task.domain == "LAND" and not str(task.get("transport_ref", task.get("payload_ref", ""))).is_empty():
		return _command(context, "land_intent", str(context.position_ref), {"transport_ref": task.get("transport_ref", task.get("payload_ref", "")), "operation": "stop_transport"})
	return {}

func _unit_claim(context: Dictionary, unit: String) -> Dictionary:
	var result: Dictionary = context.get("unit_reports", {}).get(unit, {}).duplicate(true)
	var observed: float = float(result.get("observed_at", -1.0))
	for claim: Dictionary in context.received_claims:
		if claim.subject_ref == unit and claim.fact_kind in ["unit_state", "objective"] and float(claim.reliability) > 0.0 and (float(claim.observed_at) > observed or float(claim.observed_at) == observed and int(claim.claimed_value.get("report_revision", 0)) >= int(result.get("report_revision", 0))):
			result.merge(claim.claimed_value.duplicate(true), true)
			observed = float(claim.observed_at)
			result.observed_at = observed
			result.claim_ref = claim.message_id
	return result

func _resource_busy(context: Dictionary, domain: String, reference: String) -> bool:
	for task: Dictionary in context.get("operations", []):
		if not task.has("task_ref") or task.status in ["COMPLETE", "FAILED", "CANCELLED"]:
			continue
		if domain == "GROUND" and (task.domain == "GROUND" and task.unit_ref == reference or task.domain == "LAND" and task.get("actual_carrier_ref", task.intent.values.get("unit_ref", "")) == reference):
			return true
		if domain == "GROUND" and task.get("pending_carrier_ref", "") == reference:
			return true
		if domain == "AIR" and task.domain == "AIR" and task.intent.values.get("asset_ref", "") == reference:
			return true
		if domain == "NAVAL" and task.domain == "NAVAL" and task.intent.values.get("vessel_ref", "") == reference:
			return true
		if domain == "NAVAL" and task.domain == "NAVAL" and task.intent.values.get("recipient_vessel_ref", task.get("transfer_receiver_ref", "")) == reference:
			return true
	return false

func _in_scope_unit(context: Dictionary, unit: String) -> bool:
	for target: Dictionary in context.authority_targets.values():
		if target.unit_ref == unit:
			return true
	return false

func _confirmed_unavailable(context: Dictionary, unit: String) -> bool:
	return context.get("contact_states", {}).get("unit:" + unit, {}).get("status", "") in ["CONFIRMED_LOSS", "CONFIRMED_UNAVAILABLE"]

func _field_basis(state: Dictionary) -> Dictionary:
	# New command IDs and repeated timestamps do not change the available choices.
	return {"node": state.get("node_ref", ""), "edge": state.get("edge_ref", ""), "capability": state.get("capability", ""),
		"ammunition": state.get("ammunition_level", ""), "fuel": state.get("fuel_level", ""), "reason": state.get("reason", ""),
		"control": state.get("local_condition", false), "incoming": state.get("incoming_contact", false)}

func _failure_basis(context: Dictionary, unit: String, node: String) -> Dictionary:
	var state: Dictionary = _unit_claim(context, unit)
	var contact: Dictionary = _contact(context, node)
	return {"ammunition": state.get("ammunition_level", ""), "fuel": state.get("fuel_level", ""), "capability": state.get("capability", ""),
		"blocked": state.get("reason", "") in ["route_blocked", "fuel_exhausted", "suppression"], "incoming": state.get("incoming_contact", false),
		"contact": contact.get("subject_ref", ""), "contacts_sampled": _coverage(context, node).get("contacts_sampled", -1)}

func _remember_failures(context: Dictionary) -> void:
	for task: Dictionary in context.get("operations", []):
		if task.get("domain", "") != "GROUND" or task.status != "FAILED" or task.goal.intent != "advance":
			continue
		var receipt: String = str(task.id) + ":" + str(task.get("assignment_revision", 0))
		if _failure_seen.has(receipt):
			continue
		_failure_seen[receipt] = true
		var key: String = str(task.unit_ref) + ":" + str(task.goal.target_node)
		_failed_objectives[key] = _failure_basis(context, str(task.unit_ref), str(task.goal.target_node))
	while _failure_seen.size() > 72:
		_failure_seen.erase(_failure_seen.keys()[0])
	while _failed_objectives.size() > 32:
		_failed_objectives.erase(_failed_objectives.keys()[0])

func _objective_may_retry(context: Dictionary, unit: String, node: String) -> bool:
	var previous: Dictionary = _failed_objectives.get(unit + ":" + node, {})
	if previous.is_empty():
		return true
	var current: Dictionary = _failure_basis(context, unit, node)
	if _coverage(context, node).is_empty():
		# Aging information is a reason to observe again, rather than evidence of recovery.
		current.contact = previous.contact
		current.contacts_sampled = previous.contacts_sampled
	return current != previous

func _replace_failed(context: Dictionary) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds:
		return {}
	var examined: int = 0
	for task: Dictionary in context.get("operations", []):
		if task.get("domain", "") != "GROUND" or task.get("scope", "") != context.position_ref or task.status != "FAILED" or not task.get("required", false) or float(task.deadline) <= float(context.decision_time):
			continue
		for unit: String in context.standing_orders.get("reserve_candidates", []):
			examined += 1
			if examined > MAX_CANDIDATES:
				return {}
			var state: Dictionary = _unit_claim(context, unit)
			if unit == task.unit_ref or not _in_scope_unit(context, unit) or state.is_empty() or _confirmed_unavailable(context, unit) or float(context.decision_time) - float(state.get("observed_at", -INF)) > FRESH_SECONDS or state.get("capability", "") != "AVAILABLE" or state.get("ammunition_level", "") == "LOW" or state.get("occupied", false) or str(state.edge_ref) != "" or _resource_busy(context, "GROUND", unit):
				continue
			if not task.get("routes", {}).has(str(state.node_ref)):
				continue
			var goal: Dictionary = task.goal.duplicate(true)
			goal.path = task.routes[state.node_ref].duplicate()
			goal.return_to_start = false
			if not context.known_routes.get(goal.target_node, []).has(goal.path):
				continue
			var key: String = str(task.id) + ":" + unit + ":" + str(task.get("assignment_revision", 0))
			var basis: Dictionary = _field_basis(state)
			if _replacement_attempts.get(key, {}) == basis:
				continue
			return {"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "reassign", "operation_ref": task.operation_ref,
				"task_ref": task.task_ref, "unit_ref": unit, "goal": goal}), "replacement_key": key, "replacement_basis": basis}
	return {}

func _continue_campaign(context: Dictionary) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds or not context.standing_orders.has("campaign_options"):
		return {}
	var options: Dictionary = context.standing_orders.campaign_options
	var previous: Dictionary = {}
	for operation: Dictionary in context.get("operations", []):
		if operation.has("task_ref") or operation.get("scope", "") != context.position_ref:
			continue
		if operation.get("purpose", "") not in ["hold", "advance", "withdraw", "route_security"] or operation.get("supports_operation_ref", "") != "":
			continue
		if operation.status in ["ACTIVE", "BLOCKED"]:
			return {}
		if float(operation.get("observed_at", -1.0)) > float(previous.get("observed_at", -1.0)):
			previous = operation
	if previous.is_empty() or previous.status == "CANCELLED":
		return {}
	var candidates: Array[Dictionary] = []
	for candidate: Dictionary in options.get("objectives", []):
		if candidates.size() >= MAX_CANDIDATES:
			break
		candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	var examined: int = 0
	for unit: String in options.get("units", []):
		examined += 1
		if examined > MAX_CANDIDATES:
			break
		var state: Dictionary = _unit_claim(context, unit)
		if not _in_scope_unit(context, unit) or state.is_empty() or _confirmed_unavailable(context, unit) or float(context.decision_time) - float(state.get("observed_at", -INF)) > FRESH_SECONDS or state.get("capability", "") == "UNAVAILABLE" or state.get("occupied", false) or _resource_busy(context, "GROUND", unit) or str(state.edge_ref) != "":
			continue
		var settling: bool = false
		for task: Dictionary in context.get("operations", []):
			if task.get("domain", "") == "GROUND" and task.unit_ref == unit and task.operation_ref == previous.operation_ref and task.status in ["COMPLETE", "FAILED"] and task.get("followup", true) and not task.has("followup_status"):
				settling = true
		if settling:
			continue
		for candidate: Dictionary in candidates:
			var node: String = str(candidate.get("target_node", ""))
			if not context.known_routes.has(node):
				continue
			var purpose: String = "advance"
			var target: String = node
			var limited: bool = state.get("ammunition_level", "") == "LOW" or state.get("fuel_level", "") == "LOW" or state.get("capability", "") == "IMMOBILE" or state.get("reason", "") in ["fuel_exhausted", "suppression"]
			if limited or previous.status == "FAILED":
				target = str(options.get("fallback_node", state.node_ref)) if state.capability == "AVAILABLE" and state.get("fuel_level", "") != "LOW" and state.get("reason", "") != "fuel_exhausted" else str(state.node_ref)
				purpose = "withdraw" if target != state.node_ref else "hold"
			elif state.node_ref == node:
				if state.get("target_node", "") == node and state.get("local_condition", false) and not state.get("incoming_contact", false):
					continue
				purpose = "hold"
			if purpose == "advance" and not _objective_may_retry(context, unit, node):
				continue
			var routes: Dictionary = candidate.get("routes", {}) if target == node else options.get("fallback_routes", {})
			var path: Array = [] if target == state.node_ref else routes.get(str(state.node_ref), []).duplicate()
			if target != state.node_ref and path.is_empty() or not context.known_routes.get(target, []).has(path):
				continue
			var key: String = str(context.position_ref) + ":" + unit + ":" + purpose + ":" + target
			var basis: Dictionary = _field_basis(state)
			var coverage: Dictionary = _coverage(context, node)
			basis.recon_contacts = int(coverage.get("contacts_sampled", -1))
			basis.route = path.duplicate()
			if _campaign_attempts.get(key, {}).get("basis", {}) == basis:
				continue
			var tasks: Array[Dictionary] = []
			var dependencies: Array[String] = []
			if purpose == "advance" and candidate.get("require_recon", true) and coverage.is_empty():
				var recon: Dictionary = _recon_task(context, node)
				if recon.is_empty():
					continue
				tasks.append(recon)
				dependencies.append("recon")
			tasks.append({"task_ref": "maneuver", "domain": "GROUND", "unit_ref": unit,
				"goal": {"intent": purpose, "target_node": target, "path": path, "return_to_start": false}, "routes": routes.duplicate(true),
				"priority": clampi(int(candidate.get("priority", 3)), 0, 5), "required": true, "after": dependencies,
				"followup": false, "require_recon": purpose == "advance" and candidate.get("require_recon", true),
				"recon_not_before": float(coverage.get("observed_at", context.decision_time))})
			if not limited and purpose in ["advance", "hold"]:
				tasks.append_array(_campaign_support(context, options, node, dependencies))
			var values: Dictionary = {"operation": "begin", "purpose": purpose, "target_node": target, "priority": clampi(int(candidate.get("priority", 3)), 0, 5),
				"deadline_seconds": clampf(float(options.get("deadline_seconds", 14400.0)), 60.0, 86400.0), "tasks": tasks, "predecessor_ref": previous.operation_ref}
			return {"intent": _command(context, "operation_intent", str(context.position_ref), values), "campaign_key": key, "campaign_basis": basis,
				"predecessor_ref": previous.operation_ref, "decided_at": context.decision_time}
	return {}

func _coverage(context: Dictionary, node: String) -> Dictionary:
	var latest: Dictionary = {}
	for claim: Dictionary in context.received_claims:
		if claim.fact_kind != "recon_result" or float(claim.reliability) <= 0.0 or claim.claimed_value.get("node_ref", "") != node or float(context.decision_time) - float(claim.observed_at) > FRESH_SECONDS:
			continue
		if float(claim.observed_at) >= float(latest.get("observed_at", -INF)):
			latest = claim.claimed_value.duplicate(true)
			latest.observed_at = claim.observed_at
	return latest

func _recon_task(context: Dictionary, node: String) -> Dictionary:
	var reference: String = str(context.standing_orders.get("recon_asset_ref", ""))
	if "air_intent" not in context.coordination_kinds or _resource_busy(context, "AIR", reference):
		return {}
	for asset: Dictionary in context.owned_air:
		if asset.asset_ref == reference and asset.status in ["LANDED", "READY", "WAITING_SUPPLY"] and str(asset.get("service_ref", "")) == "" and str(asset.get("recovery_ref", "")) == "":
			return {"task_ref": "recon", "domain": "AIR", "intent": _command(context, "air_intent", str(context.position_ref),
				{"asset_ref": reference, "operation": "recon", "target_node": node, "target_ref": "", "outbound": [node], "inbound": [asset.base]}), "priority": 4, "required": true, "after": []}
	return {}

func _campaign_support(context: Dictionary, options: Dictionary, node: String, after: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if options.get("air_support", false) and "air_intent" in context.coordination_kinds:
		var reference: String = str(context.standing_orders.get("recon_asset_ref", ""))
		for asset: Dictionary in context.owned_air:
			if asset.asset_ref == reference and not _resource_busy(context, "AIR", reference):
				result.append({"task_ref": "air_support", "domain": "AIR", "intent": _command(context, "air_intent", str(context.position_ref),
					{"asset_ref": reference, "operation": "strike", "target_node": node, "target_ref": "", "outbound": [node], "inbound": [asset.base]}),
					"priority": 2, "required": false, "after": after.duplicate(), "target_from_recon": true, "contact_node": node})
	var naval: Dictionary = options.get("naval_support", {})
	if "naval_intent" in context.coordination_kinds and not naval.is_empty():
		for vessel: Dictionary in context.owned_vessels:
			if vessel.vessel_ref == naval.get("vessel_ref", "") and not _resource_busy(context, "NAVAL", str(vessel.vessel_ref)) and vessel.status in ["DOCKED", "ANCHORED"] and str(vessel.get("cargo_ref", "")) == "" and str(vessel.get("recovery_ref", "")) == "" and naval.get("routes", {}).has(str(vessel.node_ref)):
				result.append({"task_ref": "shore_support", "domain": "NAVAL", "intent": _command(context, "naval_intent", str(context.position_ref),
					{"vessel_ref": vessel.vessel_ref, "operation": "shore_support", "target_node": naval.target_node, "target_ref": "", "path": naval.routes[vessel.node_ref].duplicate()}),
					"routes": naval.routes.duplicate(true), "priority": 1, "required": false, "after": after.duplicate(), "target_from_recon": true, "contact_node": node})
	return result

func _contact(context: Dictionary, node: String) -> Dictionary:
	for index: int in range(context.received_claims.size() - 1, -1, -1):
		var claim: Dictionary = context.received_claims[index]
		if claim.fact_kind in ["air_contact", "ground_contact"] and claim.subject_kind == "unit" and float(claim.reliability) > 0.0 and claim.claimed_value.get("node_ref", "") == node and float(context.decision_time) - float(claim.observed_at) <= FRESH_SECONDS:
			return claim
	return {}

func _supply_request(context: Dictionary) -> Dictionary:
	if "logistics_request" not in context.output_kinds:
		return {}
	var levels: Dictionary = {"AMMUNITION": "ammunition_level", "FUEL": "fuel_level", "SPARES": "spares_level"}
	var quantities: Dictionary = context.standing_orders.get("supply_quantities", {"AMMUNITION": 10.0, "FUEL": 10.0, "SPARES": 2.0})
	for node: String in context.authority_targets:
		var unit: String = str(context.authority_targets[node].unit_ref)
		if unit.is_empty():
			continue
		var state: Dictionary = _unit_claim(context, unit)
		for resource: String in levels:
			if not quantities.has(resource):
				continue
			var key: String = unit + ":" + resource
			for request: Dictionary in context.get("supply_requests", []):
				if request.claimed_value.target_ref != unit or request.claimed_value.resource_class != resource:
					continue
				var complete: bool = float(_known_balance(context, str(request.claimed_value.request_ref)).get("received_quantity", 0.0)) >= float(request.claimed_value.quantity) - 0.000001
				for delivered: Dictionary in context.get("land_transports", []):
					complete = complete or delivered.get("request_ref", "") == request.claimed_value.request_ref and delivered.get("transport_status", delivered.status) == "RECEIVED" and float(delivered.get("received_quantity", delivered.get("cumulative_received_quantity", 0.0))) >= float(request.claimed_value.quantity) - 0.000001
				if not complete:
					_requests[key] = request.claimed_value.request_ref
				elif _requests.get(key, "") == request.claimed_value.request_ref:
					_requests.erase(key)
			if state.get(levels[resource], "") == "LOW" and not _requests.has(key) and float(quantities[resource]) > 0.0:
				return {"intent": {"kind": "logistics_request", "target": node, "resource_class": resource, "quantity": float(quantities[resource])}, "supply_unit": key}
	return {}

func _relay(context: Dictionary) -> Dictionary:
	if "report_forward" not in context.output_kinds:
		return {}
	for task: Dictionary in context.get("operations", []):
		if task.get("domain", "") not in ["GROUND", "LAND"] or task.get("executor", "") == context.person_id or task.get("status", "") in ["COMPLETE", "FAILED", "CANCELLED"] or not task.get("require_recon", false) and task.get("require_route_reports", []).is_empty() and not task.has("fire_support"):
			continue
		for claim: Dictionary in context.received_claims:
			var relevant: bool = task.domain == "GROUND" and claim.fact_kind in ["recon_result", "air_contact", "ground_contact"] and claim.claimed_value.get("node_ref", "") == (task.fire_support.target_node if task.has("fire_support") else task.goal.target_node) or claim.fact_kind == "route_observation" and claim.subject_ref in task.get("require_route_reports", [])
			if not relevant or float(claim.reliability) <= 0.0 or float(context.decision_time) - float(claim.observed_at) > FRESH_SECONDS:
				continue
			var key: String = str(claim.message_id) + ":" + str(task.executor)
			if not _relayed.has(key):
				return {"intent": {"kind": "report_forward", "message_ref": claim.message_id, "recipient_ref": task.executor}, "relay_key": key}
	return {}

func _routes_reported(context: Dictionary, task: Dictionary) -> bool:
	for edge: String in task.get("require_route_reports", []):
		var latest: Dictionary = {}
		for claim: Dictionary in context.received_claims:
			if claim.fact_kind == "route_observation" and claim.subject_ref == edge and float(claim.reliability) > 0.0 and float(claim.observed_at) > float(latest.get("observed_at", -INF)):
				latest = claim
		if latest.is_empty() or latest.claimed_value.get("state", "") != "PASSABLE" or float(latest.observed_at) < float(task.get("route_not_before", task.started_at)) or float(context.decision_time) - float(latest.observed_at) > FRESH_SECONDS:
			return false
	return true

func _deploy_ground_capability(context: Dictionary, relay: bool) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds:
		return {}
	var plans: Array = context.standing_orders.get("relay_deployments" if relay else "engineering_plans", [])
	for dependent: Dictionary in context.operations:
		if not dependent.has("task_ref") or dependent.scope != context.position_ref or dependent.status in ["COMPLETE", "FAILED", "CANCELLED"] or dependent.has("engineering") or dependent.has("relay_deployment"):
			continue
		var source: String = ""
		var evidence: Dictionary = {}
		if relay:
			var subject: String = str(dependent.get("unit_ref", dependent.get("intent", {}).get("values", {}).get("unit_ref", "")))
			var contact: Dictionary = context.contact_states.get("unit:" + subject, {})
			if subject == "" or contact.get("status", "") not in ["OUT_OF_CONTACT", "COMMUNICATION_FAILED", "STALE"]:
				continue
			for claim: Dictionary in context.received_claims:
				if claim.subject_ref == subject and claim.fact_kind == "unit_state" and float(claim.reliability) > 0.0 and float(claim.observed_at) >= float(evidence.get("observed_at", -INF)):
					evidence = claim
			if evidence.is_empty():
				continue
			source = str(evidence.source_ref)
		for plan: Dictionary in plans.slice(0, MAX_CANDIDATES):
			var field: Dictionary = _unit_claim(context, str(plan.get("unit_ref", "")))
			if not _in_scope_unit(context, str(plan.get("unit_ref", ""))) or field.is_empty() or field.get("occupied", true) or field.get("retained", false) or field.get("capability", "") != "AVAILABLE" or field.get("edge_ref", "") != "" or float(context.decision_time) - float(field.get("observed_at", -INF)) > FRESH_SECONDS or _resource_busy(context, "GROUND", str(plan.unit_ref)):
				continue
			var node: String = str(plan.get("node_ref", ""))
			var path: Array = plan.get("routes", {}).get(str(field.node_ref), [])
			if not context.known_routes.get(node, []).has(path) or not plan.get("routes", {}).has(str(field.node_ref)):
				continue
			var metadata: Dictionary = {}
			if relay:
				if int(field.get("field_report_capabilities", 0)) < 1:
					continue
				metadata = {"platform_ref": plan.get("platform_ref", ""), "source_ref": source, "recipient_ref": context.person_id, "channel_ref": "report"}
			else:
				var edge: String = str(plan.get("edge_ref", ""))
				var relevant: bool = edge in dependent.get("goal", {}).get("path", []) or edge in dependent.get("intent", {}).get("values", {}).get("path", []) or edge in dependent.get("require_route_reports", [])
				if not relevant or field.get("engineering_capability", {}).is_empty():
					continue
				var latest: Dictionary = {}
				for claim: Dictionary in context.received_claims:
					if claim.fact_kind == "route_observation" and claim.subject_ref == edge and float(claim.reliability) > 0.0 and float(claim.observed_at) > float(latest.get("observed_at", -INF)):
						latest = claim
				if latest.is_empty() or latest.claimed_value.get("state", "") != "BLOCKED":
					continue
				evidence = latest
				var action: String = str(plan.get("action", ""))
				if latest.claimed_value.get("obstruction", "") != ("debris" if action == "clear" else "limited_damage"):
					continue
				if float(field.get("engineering_spares", 0.0)) < float(field.engineering_capability.get(action + "_spares", INF)):
					continue
				metadata = {"edge_ref": edge, "action": action}
			var key: String = str(context.person_id) + (":deploy_relay:" if relay else ":engineering:") + str(dependent.operation_ref) + ":" + str(plan.unit_ref) + ":" + node
			var basis: Dictionary = {"field": _field_basis(field), "crew": field.get("available_crew", 0.0), "equipment": field.get("available_equipment", 0.0), "spares": field.get("engineering_spares", 0.0), "target": metadata, "evidence": evidence.claimed_value, "path": path}
			var task: Dictionary = {"task_ref": "deploy_relay" if relay else "engineering", "domain": "GROUND", "unit_ref": plan.unit_ref, "priority": 4, "required": true, "followup": false,
				"goal": {"intent": "advance", "target_node": node, "path": path.duplicate(), "return_to_start": false}, "routes": plan.routes.duplicate(true)}
			task["relay_deployment" if relay else "engineering"] = metadata
			var intent: Dictionary = _command(context, "operation_intent", str(context.position_ref), {"operation": "begin", "purpose": "recon_support" if relay else "route_security", "target_node": node,
				"priority": int(dependent.operation_priority), "deadline_seconds": 3600.0, "supports_operation_ref": dependent.operation_ref, "tasks": [task]})
			var proposal: Dictionary = _sea_choice(context, intent, key, basis)
			if not proposal.is_empty():
				return proposal
	return {}

func _route_survey(context: Dictionary) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds:
		return {}
	for task: Dictionary in context.operations:
		if task.get("domain", "") not in ["GROUND", "LAND"] or task.get("require_route_reports", []).is_empty() or task.status not in ["ASSIGNED", "PAUSED", "BLOCKED", "RETAINED"] or _routes_reported(context, task) or task.scope != context.position_ref:
			continue
		var key: String = str(task.id) + ":route"
		for known: Dictionary in context.operations:
			if not known.has("task_ref") and known.get("supports_operation_ref", "") == task.operation_ref and known.purpose == "route_security" and known.status not in ["COMPLETE", "FAILED", "CANCELLED"]:
				return {}
		for scout: Dictionary in context.standing_orders.get("recovery_scouts", []).slice(0, MAX_CANDIDATES):
			var field: Dictionary = _unit_claim(context, str(scout.unit_ref))
			var destination: String = str(task.goal.target_node) if task.domain == "GROUND" else str(task.intent.values.target_node)
			var routes: Dictionary = scout.get("routes", {}).get(destination, {})
			if field.get("capability", "") != "AVAILABLE" or field.get("occupied", true) or field.get("retained", false) or str(field.get("edge_ref", "")) != "" or int(field.get("field_report_capabilities", 0)) < 1 or _resource_busy(context, "GROUND", str(scout.unit_ref)) or not routes.has(str(field.node_ref)):
				continue
			var path: Array = routes[field.node_ref].duplicate()
			var covers: bool = true
			for edge: String in task.require_route_reports:
				covers = covers and edge in path
			if not covers:
				continue
			var basis: Dictionary = {"unit": scout.unit_ref, "field": _field_basis(field), "path": path}
			if _route_attempts.get(key, {}) == basis:
				continue
			return {"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "begin", "purpose": "route_security", "target_node": destination,
				"priority": int(task.operation_priority), "deadline_seconds": minf(1200.0, maxf(60.0, float(task.deadline) - float(context.decision_time))), "supports_operation_ref": task.operation_ref,
				"tasks": [{"task_ref": "survey_route", "domain": "GROUND", "unit_ref": scout.unit_ref, "priority": 4, "required": true, "survey_edges": task.require_route_reports.duplicate(),
					"goal": {"intent": "advance", "target_node": destination, "path": path, "return_to_start": false}}]}), "route_key": key, "route_basis": basis}
	return {}

func _resume_sea(context: Dictionary, task: Dictionary) -> Dictionary:
	if task.get("meeting_partner_ref", "") != "":
		var meeting: Dictionary = _rendezvous_choice(context, task, {}, {})
		if not meeting.is_empty():
			return meeting
		# Each ship retains its own sailing/waiting stage until actual meeting reports.
		for ship: Dictionary in context.owned_vessels:
			if ship.get("rendezvous_ref", "") == task.get("meeting_ref", "") and ship.get("rendezvous_status", "") not in ["RENDEZVOUS_EXPIRED_AT_ACTUAL_POSITION", "WATERWAY_BLOCKED", "MOBILITY_LOST"]:
				return {}
	for report: Dictionary in context.sea_transports:
		if report.transport_ref != task.get("transport_ref", task.get("payload_ref", "")) or report.vessel_ref != task.intent.values.vessel_ref or report.status not in ["BLOCKED", "ONBOARD", "CARGO_WAITING", "IMMOBILE", "FUEL_EXHAUSTED", "WAITING_ACTUAL_UNLOADING_PORT", "CARGO_LOADED", "IN_TRANSIT", "STOPPED_AT_ACTUAL_POSITION", "CANCELLED_AT_ACTUAL_POSITION"]:
			continue
		for vessel: Dictionary in context.owned_vessels:
			if vessel.vessel_ref != report.vessel_ref or vessel.status not in ["BLOCKED", "CARGO_WAITING", "WAITING_PORT", "FUEL_EXHAUSTED", "DOCKED", "ANCHORED", "IMMOBILE"]:
				continue
			var port: Dictionary = context.get("known_ports", {}).get(str(vessel.node_ref), {})
			var basis: Dictionary = {"node": vessel.node_ref, "status": vessel.status, "fuel": vessel.fuel, "cargo": report.get("cargo", {}), "routes": task.get("resume_routes", {}), "entries": vessel.get("waterway_entries", {}), "port_open": port.get("open", false), "port_busy": port.get("busy", "")}
			var key: String = str(task.id) + ":resume"
			if not _sea_retry(context, key, basis):
				continue
			var values: Dictionary = {"vessel_ref": vessel.vessel_ref, "operation": "unload"}
			if vessel.node_ref != report.destination_port:
				var path: Array = _water_path(vessel, task.get("resume_routes", {}).get(str(vessel.node_ref), []), task.get("resume_alternatives", {}).get(str(vessel.node_ref), []))
				if float(vessel.fuel) <= 0.0 or not vessel.get("mobile", false) or path.is_empty():
					var transferred: Dictionary = _transship_choice(context, task, vessel, report)
					if not transferred.is_empty():
						return transferred
					var meeting: Dictionary = _rendezvous_choice(context, task, vessel, report)
					if not meeting.is_empty():
						return meeting
					continue
				values = {"vessel_ref": vessel.vessel_ref, "operation": "resume_transport", "target_node": report.destination_port, "path": path}
			elif not port.get("open", false) or not str(port.get("busy", "")).is_empty():
				continue
			return {"intent": _command(context, "naval_intent", str(context.position_ref), values), "task_phase": "RESUME", "sea_key": key, "sea_basis": basis}
	return {}

func _transship_choice(context: Dictionary, task: Dictionary, source_vessel: Dictionary, report: Dictionary) -> Dictionary:
	if source_vessel.get("transfer_ref", "") != "" or float(context.decision_time) - float(report.observed_at) > FRESH_SECONDS or not source_vessel.get("mobile", false):
		return {}
	var quantity: float = 0.0
	for amount: Variant in report.get("cargo", {}).values():
		quantity += float(amount)
	if quantity <= 0.0:
		return {}
	for receiver: Dictionary in context.owned_vessels:
		if receiver.vessel_ref == source_vessel.vessel_ref or _resource_busy(context, "NAVAL", str(receiver.vessel_ref)) and receiver.vessel_ref != task.get("meeting_partner_ref", "") or not receiver.get("mobile", false) or float(receiver.fuel) <= 0.0 or float(receiver.get("observed_at", -INF)) < float(context.decision_time) - FRESH_SECONDS or receiver.status not in ["DOCKED", "ANCHORED", "CARGO_WAITING"] or receiver.get("cargo_ref", "") not in ["", report.transport_ref] or receiver.get("transfer_ref", "") != "" or receiver.get("recovery_ref", "") != "" or receiver.get("port_job_ref", "") != "":
			continue
		var carried: float = 0.0
		for portion: Dictionary in context.sea_transports:
			if portion.vessel_ref == receiver.vessel_ref and portion.transport_ref == report.transport_ref:
				for amount: Variant in portion.get("cargo", {}).values():
					carried += float(amount)
		if float(receiver.cargo_capacity) < quantity + carried:
			continue
		if not receiver.get("xy", []) is Array or not source_vessel.get("xy", []) is Array or receiver.xy.size() != 2 or source_vessel.xy.size() != 2:
			continue
		var distance: float = sqrt(pow(float(receiver.xy[0]) - float(source_vessel.xy[0]), 2.0) + pow(float(receiver.xy[1]) - float(source_vessel.xy[1]), 2.0))
		if distance > float(context.standing_orders.get("transshipment_radius_km", 0.005)) or float(receiver.get("sea_state", 1.0)) > 0.5 or float(source_vessel.get("sea_state", 1.0)) > 0.5 or float(receiver.get("handling_crew", 0.0)) < 0.5 or float(source_vessel.get("handling_crew", 0.0)) < 0.5:
			continue
		var basis: Dictionary = {"source": source_vessel.vessel_ref, "receiver": receiver.vessel_ref, "source_fuel": source_vessel.fuel, "receiver_fuel": receiver.fuel,
			"source_integrity": source_vessel.integrity, "receiver_integrity": receiver.integrity, "source_sea_state": source_vessel.get("sea_state", 0.0), "receiver_sea_state": receiver.get("sea_state", 0.0),
			"source_crew": source_vessel.get("handling_crew", 0.0), "receiver_crew": receiver.get("handling_crew", 0.0), "cargo": report.cargo, "revision": report.get("carriage_revision", 0)}
		var key: String = str(task.id) + ":transfer"
		if _sea_retry(context, key, basis):
			return {"intent": _command(context, "naval_intent", str(context.position_ref), {"operation": "transship_cargo", "vessel_ref": source_vessel.vessel_ref, "recipient_vessel_ref": receiver.vessel_ref, "cargo": report.cargo.duplicate()}),
				"task_phase": "TRANSFER", "sea_key": key, "sea_basis": basis}
	return {}

func _rendezvous_choice(context: Dictionary, task: Dictionary, source: Dictionary, report: Dictionary) -> Dictionary:
	if task.get("meeting_partner_ref", "") != "":
		var partner: Dictionary = {}
		for ship: Dictionary in context.owned_vessels:
			if ship.vessel_ref == task.intent.values.vessel_ref:
				source = ship
			if ship.vessel_ref == task.meeting_partner_ref:
				partner = ship
		for cargo: Dictionary in context.sea_transports:
			if cargo.vessel_ref == task.intent.values.vessel_ref and cargo.transport_ref == task.get("transport_ref", task.get("payload_ref", "")):
				report = cargo
		if source.is_empty() or partner.is_empty() or report.is_empty():
			return {}
		if source.get("rendezvous_status", "") == "RENDEZVOUS_READY" and partner.get("rendezvous_status", "") == "RENDEZVOUS_READY" and source.get("rendezvous_ref", "") == task.meeting_ref and partner.get("rendezvous_ref", "") == task.meeting_ref:
			return _transship_choice(context, task, source, report)
		if partner.get("rendezvous_ref", "") != task.meeting_ref and partner.status in ["DOCKED", "ANCHORED", "CARGO_WAITING"] and float(context.decision_time) - float(partner.observed_at) <= FRESH_SECONDS and task.meeting_routes.has(str(partner.node_ref)):
			var values: Dictionary = {"operation": "rendezvous", "vessel_ref": partner.vessel_ref, "partner_ref": source.vessel_ref, "rendezvous_ref": task.meeting_ref,
				"target_node": task.meeting_node_ref, "path": task.meeting_routes[partner.node_ref].duplicate(), "deadline_seconds": 1200.0}
			var basis: Dictionary = {"meeting": task.meeting_ref, "partner_node": partner.node_ref, "partner_fuel": partner.fuel, "route": values.path}
			var choice: Dictionary = _sea_choice(context, _command(context, "naval_intent", str(context.position_ref), values), str(task.id) + ":meeting_partner", basis)
			if not choice.is_empty():
				choice.task_phase = "MEET_PARTNER"
				return choice
		return {}
	if source.is_empty() or report.is_empty() or not source.get("mobile", false) or float(source.get("fuel", 0.0)) <= 0.0:
		return {}
	var load: float = 0.0
	for amount: Variant in report.get("cargo", {}).values():
		load += float(amount)
	for partner: Dictionary in context.owned_vessels:
		if partner.vessel_ref == source.vessel_ref or partner.status not in ["DOCKED", "ANCHORED"] or partner.get("cargo_ref", "") != "" or partner.get("transfer_ref", "") != "" or partner.get("recovery_ref", "") != "" or partner.get("port_job_ref", "") != "" or not partner.get("mobile", false) or float(partner.fuel) <= 0.0 or float(partner.cargo_capacity) < load or _resource_busy(context, "NAVAL", str(partner.vessel_ref)) or float(context.decision_time) - float(partner.get("observed_at", -INF)) > FRESH_SECONDS:
			continue
		for plan: Dictionary in context.standing_orders.get("rendezvous_plans", []).slice(0, MAX_CANDIDATES):
			var node: String = str(plan.get("node_ref", ""))
			var routes: Dictionary = plan.get("routes", {})
			if not context.known_routes.has(node) or not routes.has(str(source.node_ref)) or not routes.has(str(partner.node_ref)):
				continue
			var path: Array = routes[source.node_ref].duplicate()
			if not path.is_empty() and _water_path(source, path, []).is_empty():
				continue
			var reference: String = str(task.id) + ":meeting:" + node + ":" + str(report.get("carriage_revision", 0))
			var basis: Dictionary = {"source_node": source.node_ref, "source_fuel": source.fuel, "partner": partner.vessel_ref, "partner_node": partner.node_ref, "partner_fuel": partner.fuel, "cargo": report.cargo, "path": path}
			var values: Dictionary = {"operation": "rendezvous", "vessel_ref": source.vessel_ref, "partner_ref": partner.vessel_ref, "rendezvous_ref": reference, "target_node": node, "path": path, "deadline_seconds": 1200.0}
			var choice: Dictionary = _sea_choice(context, _command(context, "naval_intent", str(context.position_ref), values), str(task.id) + ":meeting_source", basis)
			if not choice.is_empty():
				choice.task_phase = "MEET"
				choice.meeting_routes = routes.duplicate(true)
				return choice
	return {}

func _water_path(vessel: Dictionary, first: Array, alternatives: Array) -> Array:
	var candidates: Array = [first]
	candidates.append_array(alternatives.slice(0, 4))
	for path: Array in candidates:
		if vessel.get("waterway_entries", {}).is_empty() and str(vessel.get("current_waterway", "")) != "" and not path.is_empty() and path[0] != vessel.current_waterway:
			continue
		if not path.is_empty() and vessel.get("waterway_entries", {}).get(str(path[0]), "UNKNOWN") != "ENTRY_BLOCKED":
			return path.duplicate()
	return []

func _resume_navigation(context: Dictionary, task: Dictionary) -> Dictionary:
	for vessel: Dictionary in context.owned_vessels:
		if vessel.vessel_ref != task.intent.values.vessel_ref or vessel.status not in ["BLOCKED", "ANCHORED", "DOCKED"] or not vessel.get("mobile", false) or float(vessel.fuel) <= 0.0 or not str(vessel.get("cargo_ref", "")).is_empty():
			continue
		var path: Array = _water_path(vessel, task.get("routes", {}).get(str(vessel.node_ref), task.intent.values.path), task.get("alternatives", {}).get(str(vessel.node_ref), []))
		if path.is_empty():
			continue
		var basis: Dictionary = {"node": vessel.node_ref, "fuel": vessel.fuel, "path": path, "entries": vessel.get("waterway_entries", {})}
		var key: String = str(task.id) + ":navigation"
		if _sea_retry(context, key, basis):
			return {"intent": _command(context, "naval_intent", str(context.position_ref), {"vessel_ref": vessel.vessel_ref, "operation": "sail", "target_node": task.intent.values.target_node, "target_ref": "", "path": path}), "task_phase": "REROUTE", "sea_key": key, "sea_basis": basis}
	return {}

func _restore_platform(context: Dictionary) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds:
		return {}
	for contact: Dictionary in context.get("contact_states", {}).values():
		if contact.get("status", "") != "REPORT_SOURCE_UNAVAILABLE" or float(context.decision_time) - float(contact.observation_time) > FRESH_SECONDS:
			continue
		var subject: String = str(contact.subject_ref)
		var receiver: Dictionary = contact.latest_observation
		for donor: String in context.unit_reports:
			var field: Dictionary = _unit_claim(context, donor)
			if int(field.get("field_report_capabilities", 0)) < 2 or field.get("node_ref", "") != receiver.get("node_ref", "") or str(field.get("edge_ref", "")) != "":
				continue
			var key: String = "platform:" + subject
			var basis: Dictionary = {"donor": donor, "receiver": subject, "node": receiver.node_ref, "capabilities": field.field_report_capabilities}
			if _route_attempts.get(key, {}) != basis:
				return {"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "transfer_observer", "source_unit": donor, "unit_ref": subject}), "route_key": key, "route_basis": basis}
	return {}

func _recover_information(context: Dictionary) -> Dictionary:
	if "operation_intent" not in context.coordination_kinds:
		return {}
	var seen: Dictionary = {}
	for task: Dictionary in context.get("operations", []):
		if not task.has("task_ref") or task.get("purpose", "") == "recon_support" or task.status in ["COMPLETE", "FAILED", "CANCELLED", "CANCEL_PENDING", "CANCELLING"] or float(task.deadline) <= float(context.decision_time):
			continue
		var kind: String = "unit" if task.domain in ["GROUND", "LAND"] else "vessel" if task.domain == "NAVAL" else ""
		var subject: String = str(task.get("unit_ref", task.get("intent", {}).get("values", {}).get("unit_ref", ""))) if kind == "unit" else str(task.get("intent", {}).get("values", {}).get("vessel_ref", ""))
		var state: Dictionary = context.get("contact_states", {}).get(kind + ":" + subject, {})
		var last_report: float = float(state.get("report_observed_at", -1.0))
		if subject.is_empty() or seen.has(subject) or state.get("status", "") not in ["STALE", "OUT_OF_CONTACT", "COMMUNICATION_FAILED", "UNREPORTED", "OBSERVED_ONLY", "REPORT_SOURCE_UNAVAILABLE"] or float(context.decision_time) - (last_report if last_report >= 0.0 else float(task.started_at)) < FRESH_SECONDS:
			continue
		seen[subject] = true
		var node: String = str(state.get("latest_observation", {}).get("node_ref", state.get("last_value", {}).get("node_ref", task.target_node)))
		if not context.known_routes.has(node):
			node = str(task.target_node)
		var key: String = str(context.person_id) + ":" + subject + ":" + str(task.operation_ref)
		var epoch: float = float(state.get("report_observed_at", -1.0))
		var previous: Dictionary = _recovery.get(key, {})
		var slots: int = 0
		for known: Dictionary in context.operations:
			slots += int(not known.has("task_ref") and known.status not in ["COMPLETE", "FAILED", "CANCELLED"])
		var basis: Dictionary = {"scope": context.position_ref, "active_purposes": slots, "node": node}
		if not previous.is_empty() and float(previous.epoch) == epoch:
			if str(previous.get("id", "")).is_empty():
				if previous.get("basis", {}) == basis:
					continue
				previous = {}
			elif previous.stage == "SURVEY" or previous.stage == "TRANSFER":
				continue
			var ended: bool = false
			for known: Dictionary in context.operations:
				ended = ended or not known.has("task_ref") and known.operation_ref == previous.get("id", "") and known.status in ["FAILED", "CANCELLED"]
			for receipt: Dictionary in context.get("own_command_results", []):
				ended = ended or receipt.id == previous.get("id", "") and receipt.status == "REJECTED"
			if not previous.is_empty() and not ended:
				continue
		var proposal: Dictionary = {}
		var stage: String = "REPORT"
		var tasks: Array[Dictionary] = []
		if previous.is_empty() or float(previous.epoch) != epoch:
			tasks.append({"task_ref": "restore_report", "domain": "REPORT", "priority": 4, "required": true,
				"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "request_report", "subject_kind": kind, "subject_ref": subject})})
		else:
			var receiver: Dictionary = _unit_claim(context, subject)
			for donor: String in context.unit_reports:
				var field: Dictionary = _unit_claim(context, donor)
				if int(receiver.get("field_report_capabilities", 1)) == 0 and int(field.get("field_report_capabilities", 0)) > 1 and field.get("node_ref", "") == receiver.get("node_ref", "") and str(field.get("edge_ref", "")) == "" and str(receiver.get("edge_ref", "")) == "":
					proposal.intent = _command(context, "operation_intent", str(context.position_ref), {"operation": "transfer_observer", "source_unit": donor, "unit_ref": subject})
					stage = "TRANSFER"
					break
			if proposal.is_empty() and "air_intent" in context.coordination_kinds:
				for asset: Dictionary in context.owned_air:
					if asset.asset_ref != context.standing_orders.get("recon_asset_ref", "") or _resource_busy(context, "AIR", str(asset.asset_ref)) or asset.status not in ["LANDED", "READY"] or not asset.serviceable or float(asset.fuel) < 3.0 or not str(asset.get("service_ref", "")).is_empty() or not str(asset.get("recovery_ref", "")).is_empty():
						continue
					var values: Dictionary = {"asset_ref": asset.asset_ref, "operation": "recon", "target_node": node, "target_ref": "", "outbound": [node], "inbound": [asset.base]}
					values["observe_unit" if kind == "unit" else "observe_vessel"] = subject
					tasks.append({"task_ref": "locate_source", "domain": "AIR", "priority": 4, "required": true, "intent": _command(context, "air_intent", str(context.position_ref), values)})
					stage = "SURVEY"
					break
			if kind == "unit" and tasks.is_empty() and proposal.is_empty():
				for scout: Dictionary in context.standing_orders.get("recovery_scouts", []).slice(0, MAX_CANDIDATES):
					var field: Dictionary = _unit_claim(context, str(scout.unit_ref))
					var path: Array = scout.get("routes", {}).get(node, {}).get(str(field.get("node_ref", "")), [])
					if scout.unit_ref == subject or field.get("occupied", true) or field.get("capability", "") != "AVAILABLE" or int(field.get("field_report_capabilities", 0)) < 1 or str(field.get("edge_ref", "")) != "" or _resource_busy(context, "GROUND", str(scout.unit_ref)) or path.is_empty():
						continue
					tasks.append({"task_ref": "local_search", "domain": "GROUND", "unit_ref": scout.unit_ref, "priority": 4, "required": true, "survey_unit": subject, "survey_edges": path.slice(0, 4),
						"goal": {"intent": "advance", "target_node": node, "path": path, "return_to_start": false}})
					stage = "SURVEY"
					break
		if proposal.is_empty() and not tasks.is_empty():
			proposal.intent = _command(context, "operation_intent", str(context.position_ref), {"operation": "begin", "purpose": "recon_support", "target_node": node, "priority": 4,
				"deadline_seconds": minf(600.0 if stage == "SURVEY" else 300.0, maxf(60.0, float(task.deadline) - float(context.decision_time))), "supports_operation_ref": task.operation_ref, "tasks": tasks})
		if not proposal.is_empty():
			proposal.recovery_key = key
			proposal.recovery_epoch = epoch
			proposal.recovery_stage = stage
			proposal.recovery_basis = basis
			return proposal
	return {}

func _supply_delivery(context: Dictionary) -> Dictionary:
	if "land_intent" not in context.coordination_kinds or not context.standing_orders.has("delivery_plan"):
		return {}
	var plan: Dictionary = context.standing_orders.delivery_plan
	var carrier: Dictionary = _unit_claim(context, str(plan.carrier_ref))
	if carrier.is_empty() or carrier.get("occupied", false) or carrier.get("retained", false) or carrier.get("capability", "") != "AVAILABLE" or str(carrier.edge_ref) != "" or not plan.approach_routes.has(str(carrier.node_ref)):
		return {}
	for task: Dictionary in context.get("operations", []):
		if (task.get("domain", "") == "LAND" and task.intent.values.unit_ref == plan.carrier_ref or task.get("domain", "") == "GROUND" and task.unit_ref == plan.carrier_ref) and task.status not in ["COMPLETE", "FAILED", "CANCELLED"]:
			return {}
	var requests: Array = context.get("supply_requests", []).duplicate()
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: int = _request_priority(context, str(a.claimed_value.target_ref))
		var second: int = _request_priority(context, str(b.claimed_value.target_ref))
		return first > second if first != second else float(a.observed_at) < float(b.observed_at))
	for claim: Dictionary in requests:
		if claim.fact_kind != "supply_request" or float(claim.reliability) <= 0.0 or claim.claimed_value.get("target_kind", "") != "unit":
			continue
		var request: Dictionary = claim.claimed_value
		if _sea_plan(context, request).size() > 0 or not _known_balance(context, str(request.request_ref)).get("sea_delivery_ref", "").is_empty():
			continue
		var recipient: Dictionary = _unit_claim(context, str(request.target_ref))
		if recipient.is_empty() or str(recipient.edge_ref) != "" or not plan.handover_routes.has(str(recipient.node_ref)):
			continue
		var remaining: float = float(request.quantity)
		var retry: bool = not _supplied.has(request.request_ref)
		if _supplied.has(request.request_ref):
			var previous: Dictionary = _supplied[request.request_ref]
			if str(previous.id).is_empty():
				retry = maxf(float(carrier.get("observed_at", -1.0)), float(recipient.get("observed_at", -1.0))) > float(previous.at)
			for result: Dictionary in context.get("own_command_results", []):
				if result.id == previous.id and result.status == "REJECTED":
					retry = float(carrier.get("observed_at", -1.0)) > float(previous.at)
		for report: Dictionary in context.received_claims:
			if report.fact_kind == "land_supply_status" and report.claimed_value.get("request_ref", "") == request.request_ref and report.claimed_value.get("status", "") in ["RECEIVED", "CANCELLED_BEFORE_LOADING"]:
				remaining = minf(remaining, maxf(0.0, float(request.quantity) - float(report.claimed_value.get("cumulative_received_quantity", 0.0))))
				retry = retry or float(report.observed_at) > float(_supplied.get(request.request_ref, {}).get("at", INF))
		if not retry or remaining <= 0.0:
			continue
		var values: Dictionary = {"operation": "transport", "unit_ref": plan.carrier_ref, "source_ref": plan.source_ref,
			"recipient_kind": "unit", "recipient_ref": request.target_ref, "target_node": recipient.node_ref,
			"approach_path": plan.approach_routes[carrier.node_ref].duplicate(), "path": plan.handover_routes[recipient.node_ref].duplicate(),
			"cargo": {str(request.resource_class): minf(remaining, float(plan.capacity))}, "request_ref": request.request_ref, "notify": [str(request.requester_ref)]}
		return {"intent": _command(context, "land_intent", str(context.position_ref), values), "supply_delivery_ref": request.request_ref, "decided_at": context.decision_time}
	return {}

func _known_balance(context: Dictionary, request: String) -> Dictionary:
	var balance: Dictionary = {}
	var observed: float = -INF
	var revision: int = -1
	for claim: Dictionary in context.received_claims:
		var value: Dictionary = claim.claimed_value
		var candidate: Dictionary = value.get("request_balance", {}) if value.get("request_ref", "") == request else value.get("allocation_balances", {}).get(request, {})
		if candidate.is_empty() or float(claim.reliability) <= 0.0:
			continue
		if float(claim.observed_at) > observed or claim.observed_at == observed and int(value.get("report_revision", 0)) >= revision:
			balance = candidate.duplicate(true)
			observed = float(claim.observed_at)
			revision = int(value.get("report_revision", 0))
	return balance

func _sea_plan(context: Dictionary, request: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var recipient: Dictionary = _unit_claim(context, str(request.target_ref))
	for plan: Dictionary in context.standing_orders.get("sea_supply_plans", []).slice(0, MAX_CANDIDATES):
		if request.resource_class in plan.get("resource_classes", []) and plan.get("recipient_nodes", []).has(str(recipient.get("node_ref", ""))):
			result.append(plan)
	return result

func _remember_shipping(context: Dictionary) -> void:
	var receipts: Dictionary = {}
	var purposes: Dictionary = {}
	for receipt: Dictionary in context.get("own_command_results", []):
		receipts[receipt.id] = receipt.status
	for operation: Dictionary in context.operations:
		if not operation.has("task_ref"):
			purposes[operation.operation_ref] = operation.status
	for attempt: Dictionary in _sea_attempts.values():
		var id: String = str(attempt.get("id", ""))
		if receipts.has(id):
			attempt.acknowledged = receipts[id] == "EXECUTED"
			attempt.rejected = receipts[id] == "REJECTED"
		if purposes.has(id):
			attempt.purpose_received = true
			attempt.closed = purposes[id] in ["COMPLETE", "FAILED", "CANCELLED"]

func _sea_retry(context: Dictionary, key: String, basis: Dictionary) -> bool:
	var previous: Dictionary = _sea_attempts.get(key, {})
	if previous.is_empty():
		return true
	if str(previous.get("id", "")).is_empty():
		return previous.basis != basis
	if previous.get("rejected", false):
		return previous.basis != basis
	var executed: bool = previous.get("closed", false) if previous.get("purpose", false) else previous.get("acknowledged", false)
	var purpose_received: bool = previous.get("purpose_received", false)
	var purpose_closed: bool = previous.get("closed", false)
	for receipt: Dictionary in context.get("own_command_results", []):
		if receipt.id == previous.id:
			if receipt.status == "REJECTED":
				return previous.basis != basis
			executed = true
	for operation: Dictionary in context.operations:
		if not operation.has("task_ref") and operation.operation_ref == previous.id:
			purpose_received = true
			if operation.status not in ["COMPLETE", "FAILED", "CANCELLED"]:
				return false
			purpose_closed = true
			executed = true
	if previous.get("purpose", false) and (not purpose_received or not purpose_closed):
		return false
	return executed and previous.basis != basis

func _sea_choice(context: Dictionary, intent: Dictionary, key: String, basis: Dictionary) -> Dictionary:
	return {"intent": intent, "sea_key": key, "sea_basis": basis} if _sea_retry(context, key, basis) else {}

func _supply_contact(context: Dictionary, request: Dictionary, plans: Array[Dictionary]) -> Dictionary:
	for plan: Dictionary in plans:
		for vessel: Dictionary in context.owned_vessels:
			if vessel.vessel_ref not in plan.get("vessel_refs", []):
				continue
			var contact: Dictionary = context.get("contact_states", {}).get("vessel:" + str(vessel.vessel_ref), {})
			if contact.get("status", "") not in ["STALE", "OUT_OF_CONTACT", "UNREPORTED", "OBSERVED_ONLY", "COMMUNICATION_FAILED"] or float(context.decision_time) - maxf(0.0, float(contact.get("report_observed_at", 0.0))) < FRESH_SECONDS:
				continue
			var recipient: Dictionary = _unit_claim(context, str(request.target_ref))
			if recipient.is_empty():
				continue
			var values: Dictionary = {"operation": "begin", "purpose": "recon_support", "target_node": recipient.node_ref, "priority": 4, "deadline_seconds": 300.0,
				"tasks": [{"task_ref": "cargo_report", "domain": "REPORT", "priority": 4, "required": true, "request_ref": request.request_ref,
					"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "request_report", "subject_kind": "vessel", "subject_ref": vessel.vessel_ref})}]}
			var basis: Dictionary = {"request": request.request_ref, "report_time": contact.get("report_observed_at", -1.0), "source": contact.get("source_ref", "")}
			var choice: Dictionary = _sea_choice(context, _command(context, "operation_intent", str(context.position_ref), values), str(request.request_ref) + ":report:" + str(vessel.vessel_ref), basis)
			if not choice.is_empty():
				return choice
	return {}

func _purpose_ended(context: Dictionary, reference: String) -> bool:
	for purpose: Dictionary in context.operations:
		if not purpose.has("task_ref") and purpose.operation_ref == reference and purpose.status in ["COMPLETE", "FAILED", "CANCELLED"]:
			return true
	return false

func _reallocate_sea(context: Dictionary) -> Dictionary:
	if "naval_intent" not in context.coordination_kinds or "operation_intent" not in context.coordination_kinds:
		return {}
	var requests: Array = context.supply_requests.duplicate()
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _request_priority(context, str(a.subject_ref)) > _request_priority(context, str(b.subject_ref)))
	for report: Dictionary in context.sea_transports.slice(0, MAX_CANDIDATES):
		if report.get("cargo", {}).size() != 1 or float(context.decision_time) - float(report.observed_at) > FRESH_SECONDS or _resource_busy(context, "NAVAL", str(report.vessel_ref)):
			continue
		var orphan: bool = false
		for previous: Dictionary in context.operations:
			if previous.get("domain", "") == "NAVAL" and previous.get("transport_ref", previous.get("payload_ref", "")) == report.transport_ref and _purpose_ended(context, str(previous.operation_ref)):
				orphan = true
		if not orphan:
			continue
		for vessel: Dictionary in context.owned_vessels:
			if vessel.vessel_ref != report.vessel_ref or vessel.get("cargo_ref", "") != report.transport_ref or vessel.status not in ["BLOCKED", "CARGO_WAITING", "WAITING_PORT", "DOCKED", "ANCHORED"] or not vessel.get("mobile", false) or float(vessel.fuel) <= 0.0 or vessel.get("transfer_ref", "") != "":
				continue
			for claim: Dictionary in requests.slice(0, MAX_CANDIDATES):
				if float(claim.reliability) <= 0.0:
					continue
				var request: Dictionary = claim.claimed_value
				if request.get("request_ref", "") == report.get("request_ref", "") or request.get("status", "") != "REQUESTED" or not report.cargo.has(request.get("resource_class", "")):
					continue
				var balance: Dictionary = _known_balance(context, str(request.request_ref))
				var quantity: float = float(report.cargo[request.resource_class])
				if quantity <= 0.0 or quantity > float(balance.get("uncommitted_quantity", request.quantity)) or float(balance.get("sea_committed", 0.0)) + float(balance.get("port_remaining", 0.0)) + float(balance.get("land_committed", 0.0)) > 0.000001:
					continue
				var recipient: Dictionary = _unit_claim(context, str(request.target_ref))
				if recipient.is_empty() or recipient.get("edge_ref", "") != "":
					continue
				for plan: Dictionary in _sea_plan(context, request):
					var route: Array = plan.get("resume_routes", {}).get(str(vessel.node_ref), [])
					if vessel.node_ref != plan.destination_port and route.is_empty():
						if vessel.node_ref == plan.source_port:
							route = plan.path.duplicate()
						else:
							continue
					if not route.is_empty() and _water_path(vessel, route, []).is_empty():
						continue
					var port: Dictionary = context.known_ports.get(plan.destination_port, {})
					if port.is_empty() or not port.get("open", false):
						continue
					var tasks: Array[Dictionary] = [{"task_ref": "reassigned_sea", "domain": "NAVAL", "priority": 4, "required": true, "request_ref": request.request_ref, "transport_ref": report.transport_ref,
						"resume_routes": plan.get("resume_routes", {}).duplicate(true), "resume_alternatives": plan.get("resume_alternatives", {}).duplicate(true),
						"intent": _command(context, "naval_intent", str(context.position_ref), {"operation": "reassign_cargo", "vessel_ref": vessel.vessel_ref, "supply_request_ref": request.request_ref,
							"destination_port": plan.destination_port, "path": route, "land_required": true})}]
					var land: Dictionary = plan.get("land", {})
					if not land.is_empty() and land.get("handover_routes", {}).has(str(recipient.node_ref)):
						tasks.append({"task_ref": "reassigned_front_delivery", "domain": "LAND", "priority": 4, "required": true, "after": ["reassigned_sea"],
							"approach_routes": land.approach_routes.duplicate(true), "handover_routes": land.handover_routes.duplicate(true), "handover_unit": request.target_ref,
							"alternative_routes": land.get("alternative_routes", {}).duplicate(true), "redirect_routes": land.get("redirect_routes", {}).duplicate(true), "recovery_carriers": land.get("recovery_carriers", []).duplicate(),
							"intent": _command(context, "land_intent", str(context.position_ref), {"operation": "transport", "unit_ref": land.carrier_ref, "source_ref": land.source_ref,
								"recipient_kind": "unit", "recipient_ref": request.target_ref, "target_node": recipient.node_ref, "approach_path": [], "path": land.handover_routes[recipient.node_ref].duplicate(),
								"cargo": {str(request.resource_class): quantity}, "request_ref": request.request_ref})})
					var intent: Dictionary = _command(context, "operation_intent", str(context.position_ref), {"operation": "begin", "purpose": "supply", "target_node": recipient.node_ref,
						"priority": _request_priority(context, str(request.target_ref)), "deadline_seconds": 3600.0, "tasks": tasks})
					var basis: Dictionary = {"vessel": vessel.vessel_ref, "node": vessel.node_ref, "fuel": vessel.fuel, "cargo": report.cargo, "revision": report.get("carriage_revision", 0), "request": request.request_ref, "port": plan.destination_port}
					var choice: Dictionary = _sea_choice(context, intent, str(report.transport_ref) + ":reallocate:" + str(vessel.vessel_ref) + ":" + str(request.request_ref), basis)
					if not choice.is_empty():
						return choice
	return {}

func _continue_sea_responsibilities(context: Dictionary) -> Dictionary:
	if "naval_intent" not in context.coordination_kinds:
		return {}
	for report: Dictionary in context.sea_transports.slice(0, MAX_CANDIDATES):
		if report.status in ["RECEIVED", "PORTION_RECEIVED", "PORTION_LOST", "LOST", "VESSEL_SUNK", "CANCELLED_BEFORE_LOADING", "RETURNED_TO_SOURCE"] or float(context.decision_time) - float(report.observed_at) > FRESH_SECONDS:
			continue
		for vessel: Dictionary in context.owned_vessels:
			if vessel.vessel_ref != report.vessel_ref or vessel.get("cargo_ref", "") != report.transport_ref or vessel.get("transfer_ref", "") != "" or vessel.status == "SUNK" or _resource_busy(context, "NAVAL", str(vessel.vessel_ref)):
				continue
			var previous: Dictionary = {}
			for task: Dictionary in context.operations:
				if task.get("domain", "") != "NAVAL" or task.get("transport_ref", task.get("payload_ref", "")) != report.transport_ref:
					continue
				for purpose: Dictionary in context.operations:
					if not purpose.has("task_ref") and purpose.operation_ref == task.operation_ref and purpose.status in ["COMPLETE", "FAILED", "CANCELLED"]:
						previous = task
			if previous.is_empty():
				continue
			var task: Dictionary = {"task_ref": "continue_loaded_sea", "domain": "NAVAL", "transport_ref": report.transport_ref, "request_ref": report.get("request_ref", ""), "priority": 4, "required": true,
				"resume_routes": previous.get("resume_routes", {}).duplicate(true), "resume_alternatives": previous.get("resume_alternatives", {}).duplicate(true),
				"intent": _command(context, "naval_intent", str(context.position_ref), {"operation": "continue_transport", "vessel_ref": vessel.vessel_ref})}
			var target: String = str(previous.target_node)
			var values: Dictionary = {"operation": "begin", "purpose": "supply", "target_node": target, "priority": 4, "deadline_seconds": 3600.0, "tasks": [task]}
			if previous.get("scope", "") == context.position_ref:
				values.predecessor_ref = previous.operation_ref
			var basis: Dictionary = {"transport": report.transport_ref, "carrier": vessel.vessel_ref, "previous": previous.operation_ref, "status": vessel.status,
				"cargo": report.get("cargo", {}), "node": vessel.node_ref, "revision": report.get("responsibility_revision", 0)}
			return _sea_choice(context, _command(context, "operation_intent", str(context.position_ref), values), "sea_responsibility:" + str(report.transport_ref) + ":" + str(vessel.vessel_ref), basis)
	return {}

func _continue_land_responsibilities(context: Dictionary) -> Dictionary:
	if "land_intent" not in context.coordination_kinds:
		return {}
	var examined: int = 0
	for report: Dictionary in context.land_transports:
		examined += 1
		if examined > MAX_CANDIDATES:
			break
		if report.get("payload_kind", "") != "CARGO" or report.status in ["RECEIVED", "LOST", "CARGO_LOST", "CANCELLED_BEFORE_LOADING"] or not _in_scope_unit(context, str(report.carrier_ref)) or _resource_busy(context, "GROUND", str(report.carrier_ref)):
			continue
		var previous: Dictionary = {}
		for task: Dictionary in context.operations:
			if task.get("domain", "") != "LAND" or task.get("transport_ref", task.get("payload_ref", "")) != report.transport_ref:
				continue
			for purpose: Dictionary in context.operations:
				if not purpose.has("task_ref") and purpose.operation_ref == task.operation_ref and purpose.status in ["COMPLETE", "FAILED", "CANCELLED"]:
					previous = task
		if previous.is_empty():
			continue
		if float(context.decision_time) - float(report.observed_at) > FRESH_SECONDS:
			var request: Dictionary = {"operation": "begin", "purpose": "recon_support", "target_node": report.node_ref, "priority": 4, "deadline_seconds": 300.0,
				"tasks": [{"task_ref": "unfinished_cargo_report", "domain": "REPORT", "priority": 4, "required": true,
					"intent": _command(context, "operation_intent", str(context.position_ref), {"operation": "request_report", "subject_kind": "unit", "subject_ref": report.carrier_ref})}]}
			var waiting: Dictionary = _sea_choice(context, _command(context, "operation_intent", str(context.position_ref), request), "land_responsibility_report:" + str(report.transport_ref), {"transport": report.transport_ref, "last_report_at": report.observed_at, "source": report.carrier_ref})
			if not waiting.is_empty():
				return waiting
			continue
		var task: Dictionary = {"task_ref": "continue_loaded_land", "domain": "LAND", "transport_ref": report.transport_ref, "actual_carrier_ref": report.carrier_ref,
			"request_ref": report.get("request_ref", ""), "priority": 4, "required": true,
			"intent": _command(context, "land_intent", str(context.position_ref), {"operation": "continue_transport", "transport_ref": report.transport_ref})}
		for key: String in ["handover_unit", "redirect_routes", "alternative_routes", "recovery_carriers", "require_route_reports", "return_routes"]:
			if previous.has(key):
				task[key] = previous[key].duplicate(true) if previous[key] is Dictionary or previous[key] is Array else previous[key]
		if report.get("recipient_kind", "") == "unit":
			task.handover_unit = report.recipient_ref
		elif report.get("recipient_kind", "") == "depot":
			task.erase("handover_unit")
		var values: Dictionary = {"operation": "begin", "purpose": "supply", "target_node": report.target_node, "priority": 4, "deadline_seconds": 3600.0, "tasks": [task]}
		if previous.get("scope", "") == context.position_ref:
			values.predecessor_ref = previous.operation_ref
		var basis: Dictionary = {"transport": report.transport_ref, "previous": previous.operation_ref, "status": report.status, "carrier": report.carrier_ref,
			"node": report.node_ref, "edge": report.edge_ref, "cargo": report.get("cargo", {}), "revision": report.get("responsibility_revision", 0)}
		var choice: Dictionary = _sea_choice(context, _command(context, "operation_intent", str(context.position_ref), values), "land_responsibility:" + str(report.transport_ref), basis)
		if not choice.is_empty():
			return choice
	return {}

func _continue_loaded_supply(context: Dictionary, request: Dictionary, balance: Dictionary, plans: Array[Dictionary]) -> Dictionary:
	if float(balance.get("sea_committed", 0.0)) <= 0.0:
		return {}
	for report: Dictionary in context.sea_transports:
		if report.get("request_ref", "") != request.request_ref or report.delivery_ref != balance.get("sea_delivery_ref", ""):
			continue
		for vessel: Dictionary in context.owned_vessels:
			if vessel.vessel_ref != report.vessel_ref or vessel.get("cargo_ref", "") != report.transport_ref or _resource_busy(context, "NAVAL", str(vessel.vessel_ref)) or vessel.status not in ["BLOCKED", "CARGO_WAITING", "WAITING_PORT", "FUEL_EXHAUSTED", "DOCKED", "ANCHORED", "IMMOBILE"]:
				continue
			for plan: Dictionary in plans:
				if plan.destination_port != report.destination_port or vessel.vessel_ref not in plan.vessel_refs:
					continue
				var land: Dictionary = plan.land
				var recipient: Dictionary = _unit_claim(context, str(request.target_ref))
				if recipient.is_empty() or not land.handover_routes.has(str(recipient.node_ref)):
					continue
				var values: Dictionary = {"vessel_ref": vessel.vessel_ref, "operation": "unload"}
				var port: Dictionary = context.get("known_ports", {}).get(str(vessel.node_ref), {})
				if vessel.node_ref != report.destination_port:
					var path: Array = _water_path(vessel, plan.get("resume_routes", {}).get(str(vessel.node_ref), []), plan.get("resume_alternatives", {}).get(str(vessel.node_ref), []))
					if path.is_empty() or not vessel.get("mobile", false) or float(vessel.fuel) <= 0.0:
						continue
					values = {"vessel_ref": vessel.vessel_ref, "operation": "resume_transport", "path": path, "target_node": report.destination_port}
				elif not port.get("open", false) or not str(port.get("busy", "")).is_empty():
					continue
				var quantity: float = minf(float(balance.sea_committed), float(land.capacity))
				var tasks: Array[Dictionary] = [
					{"task_ref": "continue_cargo", "domain": "NAVAL", "transport_ref": report.transport_ref, "request_ref": request.request_ref, "priority": 4, "required": true,
						"resume_routes": plan.get("resume_routes", {}).duplicate(true), "resume_alternatives": plan.get("resume_alternatives", {}).duplicate(true), "intent": _command(context, "naval_intent", str(context.position_ref), values)},
					{"task_ref": "front_handover", "domain": "LAND", "priority": 4, "required": true, "after": ["continue_cargo"], "handover_unit": request.target_ref,
						"require_route_reports": land.get("require_route_reports", []).duplicate(),
						"approach_routes": land.approach_routes.duplicate(true), "handover_routes": land.handover_routes.duplicate(true), "redirect_routes": land.get("redirect_routes", {}).duplicate(true), "alternative_routes": land.get("alternative_routes", {}).duplicate(true),
						"intent": _command(context, "land_intent", str(context.position_ref), {"operation": "transport", "unit_ref": land.carrier_ref, "source_ref": land.source_ref, "recipient_kind": "unit", "recipient_ref": request.target_ref,
							"target_node": recipient.node_ref, "approach_path": [], "path": land.handover_routes[recipient.node_ref], "cargo": {str(request.resource_class): quantity}, "request_ref": request.request_ref, "notify": [str(request.requester_ref)]})}]
				var basis: Dictionary = {"delivery": report.delivery_ref, "cargo": report.get("cargo", {}), "node": vessel.node_ref, "fuel": vessel.fuel, "entries": vessel.get("waterway_entries", {}), "port_open": port.get("open", false), "port_busy": port.get("busy", ""), "values": values}
				return _sea_choice(context, _command(context, "operation_intent", str(context.position_ref), {"operation": "begin", "purpose": "supply", "target_node": recipient.node_ref, "priority": 4, "deadline_seconds": float(plan.get("deadline_seconds", 3600.0)), "tasks": tasks}), str(request.request_ref) + ":continue_cargo", basis)
	return {}

func _sea_supply(context: Dictionary) -> Dictionary:
	if "naval_intent" not in context.coordination_kinds or context.standing_orders.get("sea_supply_plans", []).is_empty():
		return {}
	var requests: Array = context.get("supply_requests", []).duplicate()
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: int = _request_priority(context, str(a.claimed_value.target_ref))
		var second: int = _request_priority(context, str(b.claimed_value.target_ref))
		return first > second if first != second else float(a.observed_at) < float(b.observed_at))
	var considered: Dictionary = {}
	for claim: Dictionary in requests:
		if considered.size() >= MAX_CANDIDATES:
			break
		var request: Dictionary = claim.claimed_value
		if float(claim.reliability) <= 0.0 or request.get("target_kind", "") != "unit" or considered.has(request.request_ref) or not _in_scope_unit(context, str(request.target_ref)):
			continue
		considered[request.request_ref] = true
		var balance: Dictionary = _known_balance(context, str(request.request_ref))
		var remaining: float = maxf(0.0, float(request.quantity) - float(balance.get("received_quantity", 0.0)))
		if remaining <= 0.000001:
			continue
		var plans: Array[Dictionary] = _sea_plan(context, request)
		var contact: Dictionary = _supply_contact(context, request, plans)
		if not contact.is_empty():
			return contact
		var continued: Dictionary = _continue_loaded_supply(context, request, balance, plans)
		if not continued.is_empty():
			return continued
		if balance.get("status", "") not in ["", "REQUESTED"] or float(balance.get("sea_committed", 0.0)) > 0.0 or float(balance.get("land_committed", 0.0)) > 0.0:
			continue
		var recipient: Dictionary = _unit_claim(context, str(request.target_ref))
		if recipient.is_empty() or str(recipient.get("edge_ref", "")) != "":
			continue
		for plan: Dictionary in plans:
			var land: Dictionary = plan.get("land", {})
			if land.is_empty() or not land.get("handover_routes", {}).has(str(recipient.node_ref)):
				continue
			var port_quantity: float = float(balance.get("port_remaining", 0.0))
			var source_port: String = str(plan.source_port)
			var destination_port: String = str(plan.destination_port)
			var carrier: Dictionary = _unit_claim(context, str(land.carrier_ref))
			var tasks: Array[Dictionary] = []
			var basis: Dictionary = {"balance": balance, "recipient": _field_basis(recipient), "source_port": source_port, "destination_port": destination_port}
			var quantity: float = 0.0
			if port_quantity > 0.000001:
				if balance.get("port_depot_ref", "") != land.source_ref or carrier.get("occupied", true) or carrier.get("retained", false) or carrier.get("capability", "") != "AVAILABLE" or str(carrier.get("edge_ref", "")) != "" or not land.approach_routes.has(str(carrier.get("node_ref", ""))) or _resource_busy(context, "GROUND", str(land.carrier_ref)):
					continue
				quantity = minf(remaining, minf(port_quantity, minf(float(land.capacity), float(carrier.get("transport_capacity", 0.0)))))
				basis.carrier = _field_basis(carrier)
			else:
				var port: Dictionary = context.get("known_ports", {}).get(source_port, {})
				if port.get("depot_ref", "") != plan.source_ref or not port.get("open", false) or not str(port.get("busy", "")).is_empty():
					continue
				var available: float = float(port.get("available_stock", {}).get(request.resource_class, 0.0))
				if available <= 0.0:
					continue
				for vessel: Dictionary in context.owned_vessels:
					if vessel.vessel_ref not in plan.get("vessel_refs", []).slice(0, MAX_CANDIDATES) or _resource_busy(context, "NAVAL", str(vessel.vessel_ref)) or not str(vessel.get("cargo_ref", "")).is_empty() or not str(vessel.get("recovery_ref", "")).is_empty() or not str(vessel.get("port_job_ref", "")).is_empty() or vessel.status not in ["DOCKED", "ANCHORED", "SUPPLY_EXHAUSTED"] or not vessel.get("mobile", false):
						continue
					basis.ship = {"id": vessel.vessel_ref, "node": vessel.node_ref, "fuel": vessel.fuel, "status": vessel.status, "capacity": vessel.cargo_capacity}
					basis.available = available
					var key: String = str(request.request_ref) + ":" + str(vessel.vessel_ref)
					if float(vessel.fuel) < float(plan.get("minimum_fuel", 1.0)):
						var local: Dictionary = context.get("known_ports", {}).get(str(vessel.node_ref), {})
						if local.get("open", false) and str(local.get("busy", "")).is_empty() and float(local.get("available_stock", {}).get("FUEL", 0.0)) > 0.0:
							basis.local_fuel = local.available_stock.FUEL
							var service: Dictionary = _sea_choice(context, _command(context, "naval_intent", str(context.position_ref), {"vessel_ref": vessel.vessel_ref, "operation": "service"}), key + ":service", basis)
							if not service.is_empty():
								return service
						continue
					if vessel.node_ref != source_port:
						if not plan.get("approach_routes", {}).has(str(vessel.node_ref)):
							continue
						var position: Dictionary = _sea_choice(context, _command(context, "naval_intent", str(context.position_ref), {"vessel_ref": vessel.vessel_ref, "operation": "sail", "target_node": source_port, "target_ref": "", "path": plan.approach_routes[vessel.node_ref]}), key + ":return", basis)
						if not position.is_empty():
							return position
						continue
					quantity = minf(remaining, minf(available, minf(float(vessel.cargo_capacity), float(land.capacity))))
					if quantity <= 0.000001:
						continue
					tasks.append({"task_ref": "sea_batch", "domain": "NAVAL", "priority": 4, "required": true,
						"intent": _command(context, "naval_intent", str(context.position_ref), {"vessel_ref": vessel.vessel_ref, "operation": "transport", "source_port": source_port, "destination_port": destination_port,
							"path": plan.path, "cargo": {str(request.resource_class): quantity}, "supply_request_ref": request.request_ref, "land_required": true, "notify": [str(request.requester_ref)]}),
						"resume_routes": plan.get("resume_routes", {}).duplicate(true), "resume_alternatives": plan.get("resume_alternatives", {}).duplicate(true)})
					break
				if tasks.is_empty():
					continue
			if quantity <= 0.000001:
				continue
			var dependencies: Array = [] if port_quantity > 0.0 else ["sea_batch"]
			tasks.append({"task_ref": "front_handover", "domain": "LAND", "priority": 4, "required": true, "after": dependencies, "handover_unit": request.target_ref,
				"require_route_reports": land.get("require_route_reports", []).duplicate(),
				"approach_routes": land.approach_routes.duplicate(true), "handover_routes": land.handover_routes.duplicate(true), "redirect_routes": land.get("redirect_routes", {}).duplicate(true),
				"alternative_routes": land.get("alternative_routes", {}).duplicate(true), "recovery_carriers": land.get("recovery_carriers", []).duplicate(),
				"intent": _command(context, "land_intent", str(context.position_ref), {"operation": "transport", "unit_ref": land.carrier_ref, "source_ref": land.source_ref,
					"recipient_kind": "unit", "recipient_ref": request.target_ref, "target_node": recipient.node_ref, "approach_path": [], "path": land.handover_routes[recipient.node_ref],
					"cargo": {str(request.resource_class): quantity}, "request_ref": request.request_ref, "notify": [str(request.requester_ref)]})})
			if port_quantity <= 0.0:
				var ship: String = str(tasks[0].intent.values.vessel_ref)
				if plan.approach_routes.has(destination_port):
					tasks.append({"task_ref": "return_empty", "domain": "NAVAL", "priority": 2, "required": false, "after": ["sea_batch"], "completion": "arrival",
						"routes": plan.approach_routes.duplicate(true), "alternatives": plan.get("return_alternatives", {}).duplicate(true), "intent": _command(context, "naval_intent", str(context.position_ref), {"vessel_ref": ship, "operation": "sail", "target_node": source_port, "target_ref": "", "path": plan.approach_routes[destination_port]})})
			var values: Dictionary = {"operation": "begin", "purpose": "supply", "target_node": recipient.node_ref, "priority": clampi(int(_request_priority(context, str(request.target_ref)) / 10), 1, 5), "deadline_seconds": float(plan.get("deadline_seconds", 3600.0)), "tasks": tasks}
			for active: Dictionary in context.operations:
				if active.get("domain", "") == "GROUND" and active.unit_ref == request.target_ref and active.scope == context.position_ref and active.status not in ["COMPLETE", "FAILED", "CANCELLED"]:
					values.supports_operation_ref = active.operation_ref
					break
			var choice: Dictionary = _sea_choice(context, _command(context, "operation_intent", str(context.position_ref), values), str(request.request_ref) + ":batch", basis)
			if not choice.is_empty():
				return choice
	return {}

func _request_priority(context: Dictionary, unit: String) -> int:
	var priority: int = 0
	for task: Dictionary in context.get("operations", []):
		if task.get("domain", "") == "GROUND" and task.unit_ref == unit and task.status not in ["COMPLETE", "FAILED", "CANCELLED"]:
			priority = maxi(priority, int(task.operation_priority) * 10 + int(task.priority))
	return priority

func _refresh_recon(context: Dictionary) -> Dictionary:
	if "air_intent" not in context.coordination_kinds or not context.standing_orders.has("recon_asset_ref"):
		return {}
	for task: Dictionary in context.get("operations", []):
		if task.get("domain", "") != "GROUND" or not task.get("require_recon", false) or task.status in ["COMPLETE", "FAILED", "CANCELLED", "CANCEL_PENDING", "CANCELLING"] or float(context.decision_time) >= float(task.deadline):
			continue
		var observed: float = -INF
		for claim: Dictionary in context.received_claims:
			if claim.fact_kind == "recon_result" and claim.claimed_value.get("node_ref", "") == task.goal.target_node and float(claim.reliability) > 0.0:
				observed = maxf(observed, float(claim.observed_at))
		if float(context.decision_time) - observed <= FRESH_SECONDS:
			continue
		# The first sortie is already a task; only refresh completed coverage.
		var completed: bool = false
		for supporting: Dictionary in context.get("operations", []):
			completed = completed or supporting.get("domain", "") == "AIR" and supporting.operation_ref == task.operation_ref and supporting.intent.values.get("operation", "") == "recon" and supporting.status == "COMPLETE"
		completed = completed or task.has("recon_not_before")
		if not completed:
			continue
		if _resource_busy(context, "AIR", str(context.standing_orders.recon_asset_ref)):
			continue
		var key: String = str(task.operation_ref) + ":" + str(task.goal.target_node)
		if float(context.decision_time) - float(_recon.get(key, -INF)) < FRESH_SECONDS:
			continue
		for asset: Dictionary in context.owned_air:
			if asset.asset_ref != context.standing_orders.recon_asset_ref or asset.status not in ["LANDED", "READY", "WAITING_SUPPLY"] or str(asset.get("service_ref", "")) != "" or str(asset.get("recovery_ref", "")) != "":
				continue
			var values: Dictionary = {"asset_ref": asset.asset_ref, "operation": "recon", "target_node": task.goal.target_node,
				"target_ref": "", "outbound": [task.goal.target_node], "inbound": [asset.base]}
			if not asset.serviceable or float(asset.fuel) < 3.0:
				values = {"asset_ref": asset.asset_ref, "operation": "service", "refuel": true, "rearm": false, "repair": true}
			return {"intent": _command(context, "air_intent", str(context.position_ref), values), "recon_key": key, "decided_at": context.decision_time}
	return {}

func _may_send(context: Dictionary, task: Dictionary, phase: String) -> bool:
	var key: String = _attempt_key(task, phase)
	if not _sent.has(key):
		return true
	var previous: Dictionary = _sent[key]
	if phase == "FIRE_PACK_MOVE" and previous.has("fire_basis"):
		return previous.fire_basis != _gun_basis(_unit_claim(context, str(task.unit_ref)), str(previous.fire_basis.gun_ref))
	if str(phase).begins_with("FIRE_") and task.has("fire_support"):
		return previous.get("fire_basis", {}) != _gun_basis(_unit_claim(context, str(task.unit_ref)), str(task.fire_support.gun_ref))
	if str(previous.id).is_empty():
		var learned: float = float(task.observed_at)
		if task.domain == "GROUND":
			learned = maxf(learned, float(_unit_claim(context, str(task.unit_ref)).get("observed_at", -1.0)))
		elif task.domain == "LAND":
			for report: Dictionary in context.get("land_transports", []):
				if report.transport_ref == task.get("transport_ref", task.get("payload_ref", "")):
					learned = maxf(learned, float(report.observed_at))
			if task.has("handover_unit"):
				learned = maxf(learned, float(_unit_claim(context, str(task.handover_unit)).get("observed_at", -1.0)))
			for carrier: String in task.get("recovery_carriers", []):
				learned = maxf(learned, float(_unit_claim(context, carrier).get("observed_at", -1.0)))
		return learned > float(previous.at)
	if task.status == "PAUSED" and phase == "EXECUTE" and float(task.observed_at) > float(previous.at):
		return true
	if phase in ["REROUTE", "REDIRECT", "RECOVER"]:
		var processed: float = INF
		for receipt: Dictionary in context.get("own_command_results", []):
			if receipt.id == previous.id:
				processed = float(receipt.processed_at)
		if phase == "REROUTE":
			var state: Dictionary = _unit_claim(context, str(task.unit_ref))
			if state.get("reason", "") == "route_blocked" and float(state.get("observed_at", -1.0)) > processed:
				return true
		else:
			for report: Dictionary in context.get("land_transports", []):
				if report.transport_ref == task.get("transport_ref", task.get("payload_ref", "")) and float(report.observed_at) > processed:
					return true
			if task.has("handover_unit") and float(_unit_claim(context, str(task.handover_unit)).get("observed_at", -1.0)) > processed:
				return true
			if phase == "RECOVER":
				for carrier: String in task.get("recovery_carriers", []):
					if float(_unit_claim(context, carrier).get("observed_at", -1.0)) > processed:
						return true
	for receipt: Dictionary in context.get("own_command_results", []):
		if receipt.id == previous.id and receipt.status == "REJECTED":
			return float(task.observed_at) > float(previous.at) and float(context.decision_time) - float(previous.at) >= float(context.cadence_seconds)
	return false

func on_result(proposal: Dictionary, validation: Dictionary, issued: Dictionary) -> void:
	if proposal.has("tactical_key"):
		_tactical_attempts[proposal.tactical_key] = proposal.tactical_basis.duplicate(true)
		while _tactical_attempts.size() > 32:
			_tactical_attempts.erase(_tactical_attempts.keys()[0])
	if proposal.has("route_key"):
		_route_attempts[proposal.route_key] = proposal.route_basis.duplicate(true)
		while _route_attempts.size() > 32:
			_route_attempts.erase(_route_attempts.keys()[0])
	if proposal.has("sea_key"):
		_sea_attempts[proposal.sea_key] = {"basis": proposal.sea_basis.duplicate(true), "purpose": proposal.intent.get("command_kind", "") == "operation_intent" and proposal.intent.get("values", {}).get("operation", "") == "begin",
			"id": issued.get("id", "") if validation.get("ok", false) and issued.get("result", {}).get("ok", false) else ""}
		while _sea_attempts.size() > 64:
			_sea_attempts.erase(_sea_attempts.keys()[0])
	if proposal.has("recovery_key"):
		_recovery[proposal.recovery_key] = {"epoch": proposal.recovery_epoch, "stage": proposal.recovery_stage, "basis": proposal.recovery_basis.duplicate(true), "id": issued.get("id", "") if validation.get("ok", false) and issued.get("result", {}).get("ok", false) else ""}
		while _recovery.size() > 32:
			_recovery.erase(_recovery.keys()[0])
	if proposal.has("campaign_key"):
		_campaign_attempts[proposal.campaign_key] = {"basis": proposal.campaign_basis.duplicate(true), "at": proposal.get("decided_at", 0.0)}
		while _campaign_attempts.size() > 32:
			_campaign_attempts.erase(_campaign_attempts.keys()[0])
	if proposal.has("replacement_key"):
		_replacement_attempts[proposal.replacement_key] = proposal.replacement_basis.duplicate(true)
		while _replacement_attempts.size() > 32:
			_replacement_attempts.erase(_replacement_attempts.keys()[0])
	if not validation.get("ok", false) or not issued.get("result", {}).get("ok", false):
		if proposal.has("supply_delivery_ref"):
			_supplied[proposal.supply_delivery_ref] = {"id": "", "at": float(proposal.get("decided_at", 0.0))}
		if proposal.has("task_ref"):
			var attempt: String = str(proposal.operation_ref) + ":" + str(proposal.task_ref) + ":" + str(proposal.get("assignment_revision", 0)) + ":" + str(proposal.get("task_phase", "EXECUTE"))
			_sent[attempt] = {"id": "", "at": float(proposal.get("decided_at", 0.0))}
			if proposal.has("fire_basis"):
				_sent[attempt].fire_basis = proposal.fire_basis.duplicate(true)
		return
	if proposal.has("relay_key"):
		_relayed[proposal.relay_key] = true
		while _relayed.size() > 64:
			_relayed.erase(_relayed.keys()[0])
	if proposal.has("recon_key"):
		_recon[proposal.recon_key] = issued.issued_at
		while _recon.size() > 16:
			_recon.erase(_recon.keys()[0])
	if proposal.has("supply_delivery_ref"):
		_supplied[proposal.supply_delivery_ref] = {"id": issued.id, "at": issued.issued_at}
		while _supplied.size() > 64:
			_supplied.erase(_supplied.keys()[0])
	if proposal.has("plan_ref"):
		_seeded[proposal.plan_ref] = true
	if proposal.has("supply_unit"):
		_requests[proposal.supply_unit] = str(issued.id)
	if proposal.has("task_ref"):
		var key: String = str(proposal.operation_ref) + ":" + str(proposal.task_ref) + ":" + str(proposal.get("assignment_revision", 0)) + ":" + str(proposal.get("task_phase", "EXECUTE"))
		_sent[key] = {"id": issued.id, "at": issued.issued_at}
		if proposal.has("fire_basis"):
			_sent[key].fire_basis = proposal.fire_basis.duplicate(true)
		while _sent.size() > 128:
			_sent.erase(_sent.keys()[0])

func _command(context: Dictionary, kind: String, target: String, values: Dictionary) -> Dictionary:
	return {"kind": "command", "command_kind": kind, "target": target, "channel_ref": _channel(context), "values": values.duplicate(true)}

func _attempt_key(task: Dictionary, phase: String) -> String:
	return str(task.id) + ":" + str(task.get("assignment_revision", 0)) + ":" + phase

func _channel(context: Dictionary) -> String:
	return str(context.standing_orders.get("channel_ref", "command"))

static func _keep() -> Dictionary:
	return {"intent": {"kind": "keep"}}
