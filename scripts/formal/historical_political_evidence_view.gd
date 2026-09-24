class_name HistoricalPoliticalEvidenceView
extends RefCounted
## Immutable evidence snapshot exposed by the formal composition root. Consumers
## can query historical metadata but cannot initialize or replace the catalog.

var _configured: bool = false
var _fingerprint: String = ""
var _snapshot_date: String = ""
var _records_by_source_id: Dictionary = {}
var _sorted_source_ids: Array[String] = []


func _init(snapshot: Dictionary = {}) -> void:
	_configured = bool(snapshot.get("configured", false))
	_fingerprint = str(snapshot.get("fingerprint", ""))
	_snapshot_date = str(snapshot.get("snapshot_date", ""))
	for record_value: Variant in snapshot.get("records", []) as Array:
		if not record_value is Dictionary:
			continue
		var record := (record_value as Dictionary).duplicate(true)
		var source_id := str(record.get("source_historical_id", ""))
		if source_id.is_empty() or _records_by_source_id.has(source_id):
			continue
		_records_by_source_id[source_id] = record
		_sorted_source_ids.append(source_id)
	_sorted_source_ids.sort()


func is_configured() -> bool:
	return _configured


func record_count() -> int:
	return _records_by_source_id.size()


func fingerprint() -> String:
	return _fingerprint


func snapshot_date() -> String:
	return _snapshot_date


func has_source(source_historical_id: String) -> bool:
	return _records_by_source_id.has(source_historical_id)


func record(source_historical_id: String) -> Dictionary:
	return (
		(_records_by_source_id.get(source_historical_id, {}) as Dictionary)
		.duplicate(true)
	)


func source_ids() -> Array[String]:
	return _sorted_source_ids.duplicate()


func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source_id: String in _sorted_source_ids:
		result.append(record(source_id))
	return result


func records_active_on(date: String) -> Array[Dictionary]:
	if not _is_date_shape(date):
		return []
	var result: Array[Dictionary] = []
	for source_id: String in _sorted_source_ids:
		var candidate := _records_by_source_id[source_id] as Dictionary
		if (
			str(candidate.get("valid_from", "")) <= date
			and date <= str(candidate.get("valid_to", ""))
		):
			result.append(candidate.duplicate(true))
	return result


func source_ids_active_on(date: String) -> Array[String]:
	var result: Array[String] = []
	for candidate: Dictionary in records_active_on(date):
		result.append(str(candidate.get("source_historical_id", "")))
	return result


func _is_date_shape(value: String) -> bool:
	return (
		value.length() == 10
		and value.substr(4, 1) == "-"
		and value.substr(7, 1) == "-"
	)
