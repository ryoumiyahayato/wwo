class_name MapGeometryContent
extends RefCounted
## Detached admitted geometry. Consumers receive copies, never a file loader.

var _parts_by_feature: Dictionary = {}
var _presentation: Dictionary = {}

func _init(parts_by_feature: Dictionary = {}, presentation: Dictionary = {}) -> void:
	_parts_by_feature = parts_by_feature.duplicate(true)
	_presentation = presentation.duplicate(true)

func presentation_document(name: String) -> Dictionary:
	return (_presentation.get(name, {}) as Dictionary).duplicate(true)

func feature_ids() -> Array:
	return _parts_by_feature.keys()

func has_feature(feature_id: String) -> bool:
	return _parts_by_feature.has(feature_id)

func parts(feature_id: String) -> Array:
	return (_parts_by_feature.get(feature_id, []) as Array).duplicate(true)
