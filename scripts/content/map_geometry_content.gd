class_name MapGeometryContent
extends RefCounted
## Detached admitted geometry. Consumers receive copies, never a file loader.

var _parts_by_feature: Dictionary = {}

func _init(parts_by_feature: Dictionary = {}) -> void:
	_parts_by_feature = parts_by_feature.duplicate(true)

func feature_ids() -> Array:
	return _parts_by_feature.keys()

func has_feature(feature_id: String) -> bool:
	return _parts_by_feature.has(feature_id)

func parts(feature_id: String) -> Array:
	return (_parts_by_feature.get(feature_id, []) as Array).duplicate(true)
