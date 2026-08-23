class_name FormalDatedPoliticalCatalog
extends RefCounted
## Query authority over existing dated political records and their matching
## CShapes features. Reference date is never treated as a validity interval.

var _loaded: bool = false
var _reference_date: String = ""
var _units_by_id: Dictionary = {}
var _features_by_id: Dictionary = {}


func load_documents(units_document: Dictionary, geometry_document: Dictionary) -> bool:
	if _loaded:
		return false
	var reference_date: String = str(geometry_document.get("snapshot_date", ""))
	if not VNextFactProvenance.is_iso_date(reference_date):
		return false
	var features: Dictionary = {}
	for raw_feature: Variant in geometry_document.get("features", []) as Array:
		if not raw_feature is Dictionary:
			return false
		var feature := raw_feature as Dictionary
		var feature_id: String = str(feature.get("id", ""))
		if feature_id.is_empty() or features.has(feature_id) or not _valid_interval(feature):
			return false
		features[feature_id] = feature.duplicate(true)
	var units: Dictionary = {}
	for raw_unit: Variant in units_document.get("units", []) as Array:
		if not raw_unit is Dictionary:
			return false
		var unit := raw_unit as Dictionary
		var unit_id: String = str(unit.get("id", ""))
		var feature_id: String = str(unit.get("geometry_feature_id", ""))
		if (
			unit_id.is_empty() or units.has(unit_id) or not features.has(feature_id)
			or not _valid_interval(unit)
			or str(unit.get("valid_from", "")) != str((features[feature_id] as Dictionary).get("valid_from", ""))
			or str(unit.get("valid_to", "")) != str((features[feature_id] as Dictionary).get("valid_to", ""))
		):
			return false
		units[unit_id] = unit.duplicate(true)
	if units.is_empty() or units.size() != features.size():
		return false
	_loaded = true
	_reference_date = reference_date
	_units_by_id = units
	_features_by_id = features
	return true


func is_loaded() -> bool:
	return _loaded and not _reference_date.is_empty() and not _units_by_id.is_empty()


func reference_date() -> String:
	return _reference_date


func total_record_count() -> int:
	return _units_by_id.size()


func active_units_on(query_date: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not is_loaded() or not VNextFactProvenance.is_iso_date(query_date):
		return output
	var ids: Array[String] = []
	for raw_id: Variant in _units_by_id.keys():
		ids.append(str(raw_id))
	ids.sort()
	for unit_id: String in ids:
		var unit := _units_by_id[unit_id] as Dictionary
		if _supports_date(unit, query_date):
			output.append(unit.duplicate(true))
	return output


func active_unit_ids_on(query_date: String) -> Array[String]:
	var output: Array[String] = []
	for unit: Dictionary in active_units_on(query_date):
		output.append(str(unit.get("id", "")))
	return output


func temporally_unavailable_units_on(query_date: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if not is_loaded() or not VNextFactProvenance.is_iso_date(query_date):
		return output
	var ids: Array[String] = []
	for raw_id: Variant in _units_by_id.keys():
		ids.append(str(raw_id))
	ids.sort()
	for unit_id: String in ids:
		var unit := _units_by_id[unit_id] as Dictionary
		if not _supports_date(unit, query_date):
			output.append(unit.duplicate(true))
	return output


func temporally_unavailable_unit_ids_on(query_date: String) -> Array[String]:
	var output: Array[String] = []
	for unit: Dictionary in temporally_unavailable_units_on(query_date):
		output.append(str(unit.get("id", "")))
	return output


func unit_record(unit_id: String) -> Dictionary:
	var value: Variant = _units_by_id.get(unit_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func feature_for_unit_on(unit_id: String, query_date: String) -> Dictionary:
	if not _units_by_id.has(unit_id):
		return {}
	var unit := _units_by_id[unit_id] as Dictionary
	if not _supports_date(unit, query_date):
		return {}
	var feature: Variant = _features_by_id.get(str(unit.get("geometry_feature_id", "")), {})
	return (feature as Dictionary).duplicate(true) if feature is Dictionary else {}


func reference_feature_for_unit(unit_id: String) -> Dictionary:
	if not _units_by_id.has(unit_id):
		return {}
	var unit := _units_by_id[unit_id] as Dictionary
	var value: Variant = _features_by_id.get(str(unit.get("geometry_feature_id", "")), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func temporal_status(unit_id: String, query_date: String) -> String:
	if not is_loaded() or not VNextFactProvenance.is_iso_date(query_date) or not _units_by_id.has(unit_id):
		return VNextFactProvenance.UNAVAILABLE
	return (
		VNextFactProvenance.HISTORICALLY_SUPPORTED
		if _supports_date(_units_by_id[unit_id] as Dictionary, query_date)
		else VNextFactProvenance.TEMPORALLY_UNKNOWN
	)


static func _valid_interval(value: Dictionary) -> bool:
	var valid_from: String = str(value.get("valid_from", ""))
	var valid_to: String = str(value.get("valid_to", ""))
	return (
		VNextFactProvenance.is_iso_date(valid_from)
		and VNextFactProvenance.is_iso_date(valid_to)
		and valid_from <= valid_to
	)


static func _supports_date(value: Dictionary, query_date: String) -> bool:
	return query_date >= str(value.get("valid_from", "")) and query_date <= str(value.get("valid_to", ""))
