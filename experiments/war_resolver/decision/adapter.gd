extends RefCounted
## Both sources receive exactly one copied data context; no host capability.
var source: String = "autonomous"
var _policy: RefCounted
var _proposal: Dictionary = {}

func configure(kind: String, policy: RefCounted, proposal: Dictionary = {}) -> bool:
	if _policy != null or kind not in ["player", "autonomous"]:
		return false
	source = kind
	_policy = policy
	_proposal = proposal.duplicate(true)
	return true

func evaluate(context: Dictionary) -> Dictionary:
	return {"intent": _proposal.duplicate(true), "selected_claim": "player_input"} if source == "player" and not _proposal.is_empty() else _policy.evaluate(context.duplicate(true))
