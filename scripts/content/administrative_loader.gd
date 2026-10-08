class_name AdministrativeLoader
extends RefCounted
## Historical administrative names and country dossiers, without substitute boundaries.

const PROFILE_PATH: String = "res://data/world_map/historical/major_state_profiles_1900.json"
const ADMIN_PATH: String = "res://data/world_map/historical/historical_admin1_1900.json"
const AUTHORITY_PATH: String = "res://data/world_map/historical/historical_authorities_1900.json"
const COVERAGE_PATH: String = "res://data/world_map/historical/arabia_authority_coverage_1900.json"
const FRANCE_IDENTITY_PATH: String = "res://data/world_map/historical/france_administrative_identity_1900.json"
var errors: Array[String] = []
var profiles: Dictionary = {}
var observer_notes: Dictionary = {}
var historical_by_source: Dictionary = {}
var authority_assignments: Array[Dictionary] = []
var coverage_by_feature: Dictionary = {}
var unresolved_by_feature: Dictionary = {}
var map_display_records: Array[Dictionary] = []

func load_current(gate: HistoricalProvenanceGate) -> bool:
	var profile_document := ContentDocument.read(PROFILE_PATH, errors)
	observer_notes = profile_document.get("observer_notes_zh", {}) as Dictionary
	for raw_profile: Variant in profile_document.get("profiles", []) as Array:
		if raw_profile is Dictionary:
			var profile := raw_profile as Dictionary
			profiles[str(profile.get("entity_id", ""))] = profile
	var admin_document := ContentDocument.read(ADMIN_PATH, errors)
	for raw_country: Variant in admin_document.get("countries", []) as Array:
		if not raw_country is Dictionary:
			continue
		var country := raw_country as Dictionary
		var source_id := str(country.get("entity_id", ""))
		var units: Array[Dictionary] = []
		for raw_name: Variant in country.get("units", []) as Array:
			if not str(raw_name).is_empty():
				units.append({"id": "%s_admin_%03d" % [source_id, units.size()], "name_zh": str(raw_name)})
		country["runtime_units"] = units
		historical_by_source[source_id] = country
	_load_authorities(gate, AUTHORITY_PATH, "map_authorities_1900_01_01")
	_load_authorities(gate, COVERAGE_PATH, "arabia_authority_coverage_1900_01_01")
	_load_france_identity(gate)
	return errors.is_empty()

func _load_france_identity(gate: HistoricalProvenanceGate) -> void:
	var document := ContentDocument.read(FRANCE_IDENTITY_PATH, errors)
	if document.get("schema_id") != "france_administrative_identity_r1" or not document.get("units") is Array:
		errors.append("Unsupported France administrative identity evidence")
		return
	var assertion := {
		"subject_id": "france_administrative_identity_1900",
		"value": document, "unit": "historical_identity_reference",
		"observation_period": {"from": "1900-01-01", "to": "1900-01-01"},
		"spatial_scope": {"kind": "partial_department_roster", "id": "country_fra"},
		"lower_bound": null, "upper_bound": null,
	}
	if gate == null or not gate.is_verified("administrative_identity:france_administrative_identity_1900", "administrative_identity", assertion):
		errors.append("France administrative identities failed evidence admission")
		return
	# This supplies the existing historical dossier only, never current world facts.
	document["runtime_units"] = document.units.duplicate(true)
	historical_by_source["country_fra"] = document

func administration_for(source_id: String, date: String) -> Dictionary:
	var document := historical_by_source.get(source_id, {}) as Dictionary
	if document.has("valid_from") and not (str(document.valid_from) <= date and date < str(document.valid_to)):
		return {}
	return document.duplicate(true)

func _load_authorities(gate: HistoricalProvenanceGate, path: String, subject: String) -> void:
	var authority_document := ContentDocument.read(path, errors)
	if authority_document.get("schema_version") != 1 or not authority_document.get("assignments") is Array or not HistoricalFactEvidence.valid_date(str(authority_document.get("target_date", ""))):
		errors.append("Unsupported or invalid authority supplement format: " + path)
		return
	var assignments := authority_document.assignments as Array
	var value: Dictionary = {"assignment_count": assignments.size(), "target_date": authority_document.target_date, "assignments": assignments}
	for field: String in ["geometry_binding", "map_display_records", "unresolved_regions"]:
		if authority_document.has(field):
			value[field] = authority_document[field]
	var assertion := {
		"subject_id": subject,
		"value": value,
		"unit": "historical_content_supplement", "observation_period": {"from": "1900-01-01", "to": "1900-01-01"},
		"spatial_scope": {"kind": "historical_supplement", "id": subject}, "lower_bound": null, "upper_bound": null,
	}
	if gate == null or not gate.admit_runtime_fact("administrative_authority:" + subject, "administrative_authority", assertion):
		errors.append("历史 administrative authority 未通过 Provenance admission")
		return
	var geometry_binding := authority_document.get("geometry_binding", {}) as Dictionary
	if not geometry_binding.is_empty():
		var geometry := ContentDocument.read(str(geometry_binding.get("path", "")), errors)
		var matched := false
		for feature: Dictionary in geometry.get("features", []) as Array:
			if str(feature.id) == str(geometry_binding.get("feature_id", "")):
				matched = (feature.geometry.coordinates as Array).size() == geometry_binding.get("exterior_count")
		if geometry.get("schema_version") != geometry_binding.get("schema_version") or not matched:
			errors.append("Authority coverage geometry reference/format mismatch")
			return
	if not geometry_binding.is_empty():
		unresolved_by_feature[str(geometry_binding.feature_id)] = authority_document.get("unresolved_regions", [])
	for display_record: Dictionary in authority_document.get("map_display_records", []) as Array:
		map_display_records.append(display_record.duplicate(true))
	for assignment: Dictionary in assignments:
		if assignment.has("geometry_component_indices"):
			var indices: Array[int] = []
			for raw_index: Variant in assignment.geometry_component_indices as Array:
				indices.append(int(raw_index))
			assignment["geometry_component_indices"] = indices
		authority_assignments.append(assignment.duplicate(true))
		if assignment.has("geometry_component_indices"):
			var feature_id := str(assignment.geometry_feature_id)
			if not coverage_by_feature.has(feature_id):
				coverage_by_feature[feature_id] = []
			(coverage_by_feature[feature_id] as Array).append(assignment.duplicate(true))

func authority_at(feature_id: String, component: int, lon_lat: Vector2, date: String) -> String:
	# These are sourced influence masks over existing land, never geography.
	# Ordered, explicit masks handle overlaps; no nearest-state inference.
	for residual: Dictionary in unresolved_by_feature.get(feature_id, []) as Array:
		if int(residual.component_index) == component and _inside_region(lon_lat, residual.authority_region as Array):
			return ""
	for assignment: Dictionary in coverage_by_feature.get(feature_id, []) as Array:
		if not (str(assignment.valid_from) <= date and date < str(assignment.valid_to)) or not (assignment.geometry_component_indices as Array).has(component):
			continue
		var regions := assignment.get("authority_regions", []) as Array
		if regions.is_empty():
			return str(assignment.id)
		for region: Array in regions:
			if _inside_region(lon_lat, region):
				return str(assignment.id)
	return ""

func display_records_active_on(date: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for record: Dictionary in map_display_records:
		if str(record.valid_from) <= date and date < str(record.valid_to):
			output.append(record.duplicate(true))
	return output

func _inside_region(lon_lat: Vector2, region: Array) -> bool:
	var ring := PackedVector2Array()
	for point: Array in region:
		ring.append(Vector2(float(point[0]), float(point[1])))
	return Geometry2D.is_point_in_polygon(lon_lat, ring)

func authorities_active_on(date: String) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for assignment: Dictionary in authority_assignments:
		if str(assignment.valid_from) <= date and date < str(assignment.valid_to):
			output.append(assignment.duplicate(true))
	return output

func observer_note(home_source: String, target_source: String) -> String:
	return str((observer_notes.get(home_source, {}) as Dictionary).get(target_source, ""))
