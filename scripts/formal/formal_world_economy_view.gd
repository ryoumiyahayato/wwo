class_name FormalWorldEconomyView
extends RefCounted
## Immutable point-in-time economy observer view. All returned containers are copies.

var _snapshot: Dictionary = {}


func _init(snapshot: Dictionary = {}) -> void:
	_snapshot = snapshot.duplicate(true)


var total_hour: int:
	get:
		return int(_snapshot.get("total_hour", 0))


var country_states: Dictionary:
	get:
		return (_snapshot.get("country_states", {}) as Dictionary).duplicate(true)


var economy_by_polity_id: Dictionary:
	get:
		return (
			(_snapshot.get("economy_by_polity_id", {}) as Dictionary).duplicate(true)
		)


var routes: Array[Dictionary]:
	get:
		return DataRecordUtils.to_dictionary_array(_snapshot.get("routes", []))


var shipments: Array[Dictionary]:
	get:
		return DataRecordUtils.to_dictionary_array(_snapshot.get("shipments", []))


var history: Array[Dictionary]:
	get:
		return DataRecordUtils.to_dictionary_array(_snapshot.get("history", []))


var _last_day_index: int:
	get:
		return int(_snapshot.get("last_day_index", -1))


func world_summary() -> Dictionary:
	return (_snapshot.get("world_summary", {}) as Dictionary).duplicate(true)


func country_summary(entity_id: String) -> Dictionary:
	return (
		(_snapshot.get("country_summaries", {}) as Dictionary).get(
			entity_id, {}
		) as Dictionary
	).duplicate(true)


func economy_entity_for_polity(polity_id: String) -> String:
	return str(economy_by_polity_id.get(polity_id, ""))


func polity_ids_for_economy(economy_id: String) -> Array[String]:
	return DataRecordUtils.to_string_array(
		(_snapshot.get("economy_polity_ids", {}) as Dictionary).get(
			economy_id, []
		)
	)


func observation() -> Dictionary:
	return {
		"schema_id": str(_snapshot.get("schema_id", "")),
		"domain_owner": "FormalWorldEconomyService",
		"state_revision": int(_snapshot.get("state_revision", 0)),
		"fact_sources": (
			(_snapshot.get("fact_sources", {}) as Dictionary).duplicate(true)
		),
		"economic_state": {
			"total_hour": total_hour,
			"country_states": (
				(_snapshot.get("dynamic_country_states", {}) as Dictionary)
				.duplicate(true)
			),
			"shipments": shipments,
		},
		"derived_view": {
			"world_summary": world_summary(),
			"country_summaries": (
				(_snapshot.get("country_summaries", {}) as Dictionary).duplicate(true)
			),
		},
	}
