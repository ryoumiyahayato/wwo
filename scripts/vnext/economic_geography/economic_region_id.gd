class_name VNextEconomicRegionId
extends RefCounted

const KIND: String = "economic_region"


static func compose(local_id: String) -> String:
	return VNextStableId.compose(KIND, local_id)


static func is_valid(value: String) -> bool:
	return VNextStableId.is_valid(value) and VNextStableId.kind_of(value) == KIND
