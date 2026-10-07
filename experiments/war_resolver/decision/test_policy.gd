extends RefCounted
## Deterministic test provider only. No state/reader/role/service capability.
var mode: String = "status"

func evaluate(context: Dictionary) -> Dictionary:
	if mode == "keep":
		return {"intent": {"kind": "keep"}, "selected_claim": ""}
	if mode == "attach":
		return {"intent": {"kind": "structure_request", "values": context.standing_orders.attachment.duplicate(true)}, "selected_claim": ""}
	var selected: Dictionary = {}
	var fact: String = "ammunition" if mode == "ammo" else "status"
	for claim: Dictionary in context.received_claims:
		if claim.fact_kind != fact:
			continue
		if selected.is_empty() or _before(selected, claim):
			selected = claim
	if selected.is_empty():
		return {"intent": {"kind": "keep"}, "selected_claim": ""}
	var intent: Dictionary = {"kind": "keep"}
	if mode == "ammo" and selected.claimed_value.level == "LOW" and "logistics_request" in context.output_kinds:
		intent = {"kind": "logistics_request", "target": context.standing_orders.target, "resource_class": "AMMUNITION", "quantity": 10.0}
	elif mode == "status" and "command" in context.output_kinds and str(context.standing_orders.target) in context.command_targets:
		if float(context.decision_time) < maxf(float(context.command_ready_at), float(context.command_issue_ready_at)):
			return {"intent": {"kind": "keep"}, "selected_claim": selected.entry_id}
		var posture: String = "hold" if "hold" in selected.claimed_value.states or "stalled" in selected.claimed_value.states else "withdraw"
		var values: Dictionary = {"posture": posture, "objective": 0.0, "direction": -1.0}
		if context.command_kind == "tactical_intent":
			values = {"posture": posture}
		intent = {"kind": "command", "command_kind": context.command_kind, "target": context.standing_orders.target,
			"values": values, "channel_ref": "decision_channel"}
	return {"intent": intent, "selected_claim": selected.entry_id}

static func _before(a: Dictionary, b: Dictionary) -> bool:
	# Prefer quality, then observation time, receipt time, stable claim ID.
	for key: String in ["reliability", "observed_at", "received_at"]:
		if a[key] != b[key]:
			return float(a[key]) < float(b[key])
	return str(a.entry_id) < str(b.entry_id)
