extends RefCounted
## One runtime choice; the existing Decision service consumes it with its Context.
var source: String = "person_runtime"
var proposal: Dictionary = {}

func evaluate(_context: Dictionary) -> Dictionary:
	var result: Dictionary = {"intent": proposal.duplicate(true)}
	proposal.clear()
	return result
