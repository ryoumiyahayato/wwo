extends RefCounted
## Replaceable finite script and received-route reaction; receives only Context.
var source: String = "autonomous"
var _submitted: Dictionary = {}

func evaluate(context: Dictionary) -> Dictionary:
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
	return {"intent": {"kind": "keep"}, "selected_claim": ""}
