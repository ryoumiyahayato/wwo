extends RefCounted
## Test rules over copied received claims; no engine or authority capabilities.
var _initial_issued: bool = false
var _blocked: Dictionary = {}
var _low_episode: bool = false

func evaluate(context: Dictionary) -> Dictionary:
	if context.standing_orders.get("keep_only", false):
		return {"intent": {"kind": "keep"}, "selected_claim": ""}
	var selected_route: Dictionary = {}
	var selected_ammo: Dictionary = {}
	for claim: Dictionary in context.received_claims:
		if claim.subject_ref != context.standing_orders.subject:
			continue
		if claim.fact_kind == "route" and (selected_route.is_empty() or _before(selected_route, claim)):
			selected_route = claim
		if claim.fact_kind == "ammunition" and (selected_ammo.is_empty() or _before(selected_ammo, claim)):
			selected_ammo = claim
	var orders: Dictionary = context.standing_orders
	var ready: bool = float(context.decision_time) >= maxf(float(context.command_ready_at), float(context.command_issue_ready_at))
	if ready and str(orders.target) in context.command_targets:
		if not _initial_issued and not selected_route.is_empty() and selected_route.claimed_value.state == "AVAILABLE":
			_initial_issued = true
			return _route(context, orders.initial_path, false, selected_route)
		if not selected_route.is_empty() and selected_route.claimed_value.state == "BLOCKED":
			var key: String = str(selected_route.claimed_value.edge_ref) + ":" + str(selected_route.claimed_value.cause_ref)
			if not _blocked.has(key):
				_blocked[key] = true
				return _route(context, orders.fallback_path, true, selected_route)
	if not selected_ammo.is_empty():
		if selected_ammo.claimed_value.level == "AVAILABLE":
			_low_episode = false
		elif selected_ammo.claimed_value.level == "LOW" and not _low_episode and "logistics_request" in context.output_kinds:
			_low_episode = true
			return {"intent": {"kind": "logistics_request", "target": orders.target, "resource_class": "AMMUNITION", "quantity": 10.0}, "selected_claim": selected_ammo.entry_id}
	return {"intent": {"kind": "keep"}, "selected_claim": ""}

static func _route(context: Dictionary, path: Array, returning: bool, claim: Dictionary) -> Dictionary:
	return {"intent": {"kind": "command", "command_kind": "route_intent", "target": context.standing_orders.target,
		"values": {"path": path.duplicate(), "return_to_start": returning}, "channel_ref": "command"}, "selected_claim": claim.entry_id}

static func _before(a: Dictionary, b: Dictionary) -> bool:
	# Newer observation, then receipt and stable ID; reliability breaks equal times.
	for key: String in ["observed_at", "reliability", "received_at"]:
		if a[key] != b[key]:
			return float(a[key]) < float(b[key])
	return str(a.entry_id) < str(b.entry_id)
