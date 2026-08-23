class_name VNextPopulationUnitId
extends RefCounted
## Canonical identity for one demographic accounting state.

const KIND: String = "population"


static func compose(local_id: String) -> String:
	return VNextStableId.compose(KIND, local_id)


static func is_valid(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == KIND


static func local_id(value: String) -> String:
	return VNextStableId.local_id_of(value) if is_valid(value) else ""
