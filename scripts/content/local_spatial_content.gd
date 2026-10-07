class_name LocalSpatialContent
extends RefCounted
## A detached Content shard; no simulation owner or persistent state.

var metadata: Dictionary = {}
var features: Array[Dictionary] = []
var metrics: Dictionary = {}
var errors: Array[String] = []
var line_chunks: Array[Dictionary] = []

func active_on(date: String) -> bool:
	return errors.is_empty() and not features.is_empty() and str(metadata.get("valid_from", "")) <= date and date < str(metadata.get("valid_to", ""))

func dated_features(date: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for feature: Dictionary in features:
		if str(feature.valid_from) <= date and date < str(feature.valid_to):
			result.append(feature.duplicate(true))
	return result
