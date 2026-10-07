extends RefCounted
## Identical capability boundary for player and autonomous test paths, not an AI.
var _reader: RefCounted

func configure(reader: RefCounted) -> bool:
	if _reader != null:
		return false
	_reader = reader
	return true

func decision_input() -> Dictionary:
	var received: Dictionary = _reader.knowledge()
	var statuses: Array[Dictionary] = []
	for entry: Dictionary in received.entries:
		if entry.fact_kind == "status":
			statuses.append(entry.duplicate(true))
	return {"holder_ref": received.holder_ref, "received_status_claims": statuses,
		"unknown": statuses.is_empty(), "policy": "test path consumes only received knowledge"}
