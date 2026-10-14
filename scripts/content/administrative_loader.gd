class_name AdministrativeLoader
extends RefCounted
## Historical administrative names and country dossiers, without substitute boundaries.

const PROFILE_PATH: String = "res://data/world_map/historical/major_state_profiles_1900.json"
const ADMIN_PATH: String = "res://data/world_map/historical/historical_admin1_1900.json"
const AUTHORITY_PATH: String = "res://data/world_map/historical/historical_authorities_1900.json"
const COVERAGE_PATH: String = "res://data/world_map/historical/arabia_authority_coverage_1900.json"
const FRANCE_IDENTITY_PATH: String = "res://data/world_map/historical/france_administrative_identity_1900.json"
const REFERENCE_PATHS: Array[String] = ["res://data/world_map/historical/france_lower_1900_identity.json","res://data/world_map/historical/britain_historic_counties_identity.json","res://data/world_map/historical/german_administration_1900_identity.json","res://data/world_map/historical/russian_empire_1897_identity.json"]
var errors: Array[String] = []
var profiles: Dictionary = {}
var observer_notes: Dictionary = {}
var historical_by_source: Dictionary = {}
var authority_assignments: Array[Dictionary] = []
var coverage_by_feature: Dictionary = {}
var unresolved_by_feature: Dictionary = {}
var map_display_records: Array[Dictionary] = []
var france_boundaries: Dictionary = {}
var france_identity: Dictionary = {}
var reference_documents: Array[Dictionary] = []

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
	load_france_identity(gate)
	load_reference_identities()
	return errors.is_empty()

func load_reference_identities() -> void:
	# Detached historical references. These do not create present-day land members.
	for path: String in REFERENCE_PATHS:
		var document := ContentDocument.read(path,errors)
		if document.get("schema_id")!="historical_administrative_reference_identity_v1" or not document.get("units") is Array:
			errors.append("Historical administrative reference unavailable: "+path)
			continue
		var boundaries := ContentDocument.read(str(document.get("boundary_path","")),errors)
		if boundaries.get("schema_id")!="historical_administrative_reference_index_v1" or not boundaries.get("features") is Array or boundaries.get("entity_id")!=document.get("entity_id"):
			errors.append("Historical administrative index unavailable: "+path)
			continue
		var source_id := str(document.entity_id)
		var previous := historical_by_source.get(source_id,{}) as Dictionary
		var entries: Array[Dictionary] = []
		if previous.has("boundary_path"): entries.assign(previous.get("runtime_units",[]) as Array)
		for unit: Dictionary in document.units as Array:
			if int(unit.get("level",1))<=1: entries.append(unit)
		var dossier := document.duplicate()
		if previous.has("boundary_path"):
			dossier = previous.duplicate()
			dossier["units"] = (previous.units as Array).duplicate()+document.units
		dossier["runtime_units"] = entries
		historical_by_source[source_id] = dossier
		reference_documents.append({"identity":document,"boundaries":boundaries})

func load_france_identity(gate: HistoricalProvenanceGate) -> void:
	var document := ContentDocument.read(FRANCE_IDENTITY_PATH, errors)
	if document.get("schema_id") != "france_administrative_identity_r1" or not document.get("units") is Array:
		errors.append("Unsupported France administrative identity evidence")
		return
	var assertion := {
		"subject_id": "france_administrative_identity_1900",
		"value": document, "unit": "historical_identity_reference",
		"observation_period": {"from": "1900-01-01", "to": "1900-01-01"},
		"spatial_scope": {"kind": "metropolitan_historical_admin_reference", "id": "country_fra"},
		"lower_bound": null, "upper_bound": null,
	}
	if gate == null or not gate.is_verified("administrative_identity:france_administrative_identity_1900", "administrative_identity", assertion):
		errors.append("France administrative identities failed evidence admission")
		return
	france_boundaries = ContentDocument.read(str(document.get("boundary_path","")),errors)
	var boundary_assertion := {"subject_id":"france_trf_gis_departments_1900","value":france_boundaries,"unit":"historical_gis_reconstructed_boundary",
		"observation_period":{"from":"1900-01-01","to":"1900-12-31"},"spatial_scope":{"kind":"metropolitan_france_annual_departments","id":"country_fra"},"lower_bound":null,"upper_bound":null}
	if france_boundaries.get("schema_id") != "france_department_reference_index_1900_v2" or gate == null or not gate.admit_runtime_fact("spatial_boundary:france_trf_gis_departments_1900","spatial_boundary",boundary_assertion):
		errors.append("TRF-GIS 1900 boundary content unavailable")
		return
	# This supplies the existing historical dossier only, never current world facts.
	document["runtime_units"] = document.units.duplicate(true)
	france_identity = document
	historical_by_source["country_fra"] = document

func administration_for(source_id: String, date: String) -> Dictionary:
	var document := historical_by_source.get(source_id, {}) as Dictionary
	if document.has("boundary_path") and date >= str(document.get("valid_from","9999-01-01")):
		# Annual source validity does not remove the world's dynamic administration.
		var result := document.duplicate()
		result.erase("units")
		result = result.duplicate(true)
		result["historical_reference_active"] = date < str(document.get("valid_to",""))
		return result
	if document.has("valid_from") and not (str(document.valid_from) <= date and date < str(document.valid_to)):
		return {}
	return document.duplicate(true)

static func department_geometry(descriptor: Dictionary, lod: String) -> Dictionary:
	var errors: Array[String] = []
	var document := ContentDocument.read(str(descriptor.get(lod+"_path","")),errors)
	if document.get("schema_id")=="historical_administrative_reference_geometry_v1":
		if not errors.is_empty() or document.get("id")!=descriptor.get("id") or document.get("source_unit_id")!=descriptor.get("source_unit_id") or document.get("observation_year")!=descriptor.get("observation_year") or document.get("lod")!=lod or not document.get("local_polygons") is Array: return {}
	else:
		if not errors.is_empty() or document.get("schema_id") != "trf_gis_1900_reference_geometry_v1" or document.get("id") != descriptor.get("id") or document.get("source_dep_id") != descriptor.get("source_dep_id") or document.get("observation_year") != 1900 or document.get("lod") != lod or not document.get("local_polygons") is Array: return {}
	return document

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

static func identity_introduction(polity: Dictionary) -> String:
	var name := str(polity.get("name_zh",""))
	if name.is_empty(): return ""
	var identity := {"sovereign":"独立政治实体","colony":"殖民地","dependency":"属地","dominion":"自治领","protectorate":"受保护政治地域","occupied":"军事占领下的地域","condominium":"共管地域","contested":"政治归属存在争议的地域"}
	var kind := str(identity.get(str(polity.get("status","")),"历史政治地域"))
	var text := "1900 年的"+name+"是"+kind+"。"
	var capital := polity.get("capital",{}) as Dictionary
	if not str(capital.get("name","")).is_empty(): text += "首府为 "+str(capital.name)+"。"
	return text
