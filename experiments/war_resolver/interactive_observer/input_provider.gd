extends RefCounted
## One runtime choice; the existing Decision service consumes it with its Context.
var source: String = "person_runtime"
var proposal: Dictionary = {}

func evaluate(_context: Dictionary) -> Dictionary:
	var result: Dictionary = {"intent": proposal.duplicate(true)}
	proposal.clear()
	return result

const RUNTIME_FIELDS: Array[String] = ["source", "proposal"]

func runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> bool:
	return preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image, RUNTIME_FIELDS)
