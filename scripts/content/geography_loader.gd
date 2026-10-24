class_name GeographyLoader
extends RefCounted

const RELIEF_PATH: String = "res://data/presentation/global_physical_relief.json"
const GEOMETRY_PATH: String = "res://data/world_map/historical/cshapes_1900_snapshot.json"
const SUPPLEMENT_PATH: String = "res://data/world_map/historical/arabia_gulf_geography_1900.json"
var errors: Array[String] = []
var metadata: Dictionary = {}
var parts_by_feature: Dictionary = {}
var presentation: Dictionary = {}

func load_current(gate: HistoricalProvenanceGate) -> bool:
	var document := ContentDocument.read(GEOMETRY_PATH, errors)
	if not HistoricalProvenanceFoundation.admit_spatial_boundary_document(gate, document):
		errors.append("历史边界未通过 Provenance admission")
		return false
	_load_features(document)
	document.erase("features")
	metadata = document
	var supplement := ContentDocument.read(SUPPLEMENT_PATH, errors)
	var subject := "arabia_gulf_geography_1900_01_01"
	if supplement.get("schema_version") != 1 or not supplement.get("features") is Array or supplement.get("feature_count") != (supplement.features as Array).size() or not HistoricalFactEvidence.valid_date(str(supplement.get("target_date", ""))):
		errors.append("Unsupported or invalid geography supplement format")
		return false
	var assertion := {
		"subject_id": subject,
		"value": {"feature_count": int(supplement.get("feature_count", 0)), "target_date": str(supplement.get("target_date", "")), "features": supplement.features},
		"unit": "historical_content_supplement", "observation_period": {"from": "1900-01-01", "to": "1900-01-01"},
		"spatial_scope": {"kind": "historical_supplement", "id": subject}, "lower_bound": null, "upper_bound": null,
	}
	if not gate.admit_runtime_fact("spatial_boundary:" + subject, "spatial_boundary", assertion):
		errors.append("历史 geography supplement 未通过 Provenance admission")
		return false
	_load_features(supplement)
	supplement.erase("features")
	metadata["supplement"] = supplement
	metadata["combined_feature_count"] = parts_by_feature.size()
	_load_presentation()
	return errors.is_empty()

func _load_presentation() -> void:
	# These detached derivatives affect labels and strokes, never admitted ownership.
	var labels := ContentDocument.read("res://data/presentation/country_label_layout_r3.json", errors)
	if str(labels.get("schema_id", "")) != "country_label_layout_r3" or not labels.get("layouts") is Dictionary:
		errors.append("Invalid country label layout format")
		return
	var borders := ContentDocument.read("res://data/presentation/political_border_display_r39.json", errors)
	if str(borders.get("schema_id", "")) != "political_border_display_r39" or str(borders.get("geometry_role", "")) != "DISPLAY_PARTITION_SHARED_EDGES_ONLY_NOT_SOVEREIGNTY" or not borders.get("boundaries") is Array:
		errors.append("Invalid political display border format")
		return
	var annotations := ContentDocument.read("res://data/presentation/geographic_annotations_r3.json", errors)
	var islands := ContentDocument.read("res://data/world_map/historical/island_political_references_1900.json",errors)
	if islands.get("schema_id")!="island_political_references_1900_v1" or not islands.get("annotations") is Array:
		errors.append("Sourced island reference content unavailable")
	else:
		(annotations.annotations as Array).append_array(islands.annotations as Array)
	presentation = {"country_labels": labels, "shared_borders": borders, "geographic_annotations": annotations}

func _load_features(document: Dictionary) -> void:
	for raw_feature: Variant in document.get("features", []) as Array:
		if not raw_feature is Dictionary:
			errors.append("Geography feature must be an object")
			continue
		var feature := raw_feature as Dictionary
		var geometry := feature.get("geometry", {}) as Dictionary
		var coordinates := geometry.get("coordinates", []) as Array
		var parts: Array[Dictionary] = []
		if str(geometry.get("type", "")) == "Polygon":
			_append_part(coordinates, parts)
		elif str(geometry.get("type", "")) == "MultiPolygon":
			for raw_part: Variant in coordinates:
				if raw_part is Array:
					_append_part(raw_part as Array, parts)
		var feature_id := str(feature.get("id", ""))
		if feature_id.is_empty() or parts_by_feature.has(feature_id) or parts.is_empty():
			errors.append("无效或重复 historical geography feature: " + feature_id)
			continue
		parts_by_feature[feature_id] = parts

func parts(feature_id: String) -> Array:
	return parts_by_feature.get(feature_id, []) as Array

func _append_part(raw_part: Array, output: Array[Dictionary]) -> void:
	if raw_part.is_empty():
		errors.append("Geography polygon requires an exterior ring")
		return
	var rings: Array[PackedVector2Array] = []
	for raw_ring: Variant in raw_part:
		var ring := _points_from_raw(raw_ring)
		if ring.size() > 3 and ring[0].is_equal_approx(ring[ring.size() - 1]):
			ring.resize(ring.size() - 1)
		if ring.size() >= 3:
			rings.append(ring)
		else:
			errors.append("Geography ring has fewer than three points")
	if not rings.is_empty():
		output.append({"outer": rings[0], "holes": rings.slice(1)})

func _points_from_raw(raw_value: Variant) -> PackedVector2Array:
	var output := PackedVector2Array()
	if not raw_value is Array:
		errors.append("Geography ring must be an array")
		return output
	for point_value: Variant in raw_value as Array:
		if not point_value is Array or (point_value as Array).size() != 2:
			errors.append("Geography point requires longitude and latitude")
			return PackedVector2Array()
		var point := point_value as Array
		if typeof(point[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(point[1]) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("Geography coordinates must be numbers")
			return PackedVector2Array()
		var lon := float(point[0])
		var lat := float(point[1])
		if not is_finite(lon) or not is_finite(lat) or abs(lon) > 180.0 or abs(lat) > 90.0:
			errors.append("Geography coordinates are outside longitude/latitude bounds")
			return PackedVector2Array()
		output.append(Vector2(lon, lat))
	return output

static func decode_relief(level: String, admitted: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var result: Dictionary = {"errors": failures}
	if level in ["france_catalog","british_catalog","german_catalog","spain_catalog","canary_catalog","benelux_catalog","europe_catalog","siberian_catalog","asian_catalog","northern_catalog","arid_catalog","european_catalog","sampling_catalog"]:
		# REGION-only metadata admission; WORLD never reads regional images.
		var pack := {"france_catalog":"france_r42","british_catalog":"british_r43","german_catalog":"german_r44","spain_catalog":"spain_r45","canary_catalog":"canary_r45","benelux_catalog":"benelux_r46","europe_catalog":"europe_r48","siberian_catalog":"siberian_r50","asian_catalog":"asian_r51","northern_catalog":"northern_r52","arid_catalog":"arid_r53","european_catalog":"european_r55","sampling_catalog":"sampling_r57"}[level] as String
		var document := ContentDocument.read("res://data/presentation/"+pack.replace("_r","_surface_r")+".json",failures)
		var sources := HistoricalSourceRegistry.new()
		var facts := HistoricalEvidenceCatalog.new()
		if not sources.load_document(document.get("source_registry",{}) as Dictionary) or not facts.load_document(document.get("evidence_catalog",{}) as Dictionary):
			failures.append_array(sources.errors())
			failures.append_array(facts.errors())
			return result
		var fact := facts.fact("physical_relief:"+pack)
		var gate := HistoricalProvenanceGate.new(sources,facts)
		if fact==null or not gate.admit_runtime_fact(fact.fact_id,"physical_reference_content",fact.output_material()) or str((fact.value as Dictionary).get("status",""))!="PHYSICAL_REFERENCE":
			failures.append("Surface requires admitted modern physical reference: "+pack)
			return result
		# The shared catalogue retains each upstream provenance assertion and ID.
		var material_facts: Array = document.evidence_catalog.facts if level in ["europe_catalog","asian_catalog","northern_catalog","arid_catalog","european_catalog","sampling_catalog"] else [document.evidence_catalog.facts[0]]
		for material: Dictionary in material_facts:
			var item := facts.fact(str(material.get("fact_id","")))
			if item==null or not gate.admit_runtime_fact(item.fact_id,"physical_reference_content",item.output_material()):
				failures.append("Shared surface contains an unadmitted reference")
				return result
			for asset: Dictionary in (item.value as Dictionary).assets:
				admitted[str(asset.id).get_slice(":",1)] = asset
		result["assets"] = admitted
		return result
	if admitted.is_empty():
		var document := ContentDocument.read(RELIEF_PATH, failures)
		var sources := HistoricalSourceRegistry.new()
		var facts := HistoricalEvidenceCatalog.new()
		if not sources.load_document(document.get("source_registry", {}) as Dictionary) or not facts.load_document(document.get("evidence_catalog", {}) as Dictionary):
			failures.append_array(sources.errors())
			failures.append_array(facts.errors())
			return result
		var fact := facts.fact("physical_relief:etopo_2022")
		var gate := HistoricalProvenanceGate.new(sources, facts)
		if fact == null or not gate.admit_runtime_fact(fact.fact_id, "physical_reference_content", fact.output_material()) or str((fact.value as Dictionary).get("status", "")) != "PHYSICAL_REFERENCE":
			failures.append("Relief requires admitted physical reference")
			return result
		for asset: Dictionary in (fact.value as Dictionary).assets:
			admitted[str(asset.id).get_slice(":", 1)] = asset
		result["assets"] = admitted
	if not admitted.has(level):
		failures.append("Missing relief level")
		return result
	var asset := admitted[level] as Dictionary
	var buffer := FileAccess.get_file_as_bytes(str(asset.path))
	if str(asset.format)=="RGBA8_MIP_DEFLATE":
		# Offline linear-data mips, not a colour image interpreted as height.
		if buffer.size()<20 or buffer.slice(0,5).get_string_from_ascii()!="FRT42" or buffer.decode_u32(8)!=int(asset.width) or buffer.decode_u32(12)!=int(asset.height) or buffer.decode_u32(16)!=int(asset.decoded_bytes):
			failures.append("Invalid geographic surface header")
			return result
		var pixels := buffer.slice(20).decompress(int(asset.decoded_bytes),FileAccess.COMPRESSION_DEFLATE)
		if pixels.size()!=int(asset.decoded_bytes):
			failures.append("Invalid geographic surface data")
			return result
		result["image"] = Image.create_from_data(int(asset.width),int(asset.height),true,Image.FORMAT_RGBA8,pixels)
		return result
	var image := Image.new()
	if image.load_png_from_buffer(buffer) != OK or image.get_width() != int(asset.width) or image.get_height() != int(asset.height):
		failures.append("Invalid relief image")
		return result
	image.convert(Image.FORMAT_R8 if str(asset.format)=="R8" else Image.FORMAT_RG8)
	result["image"] = image
	return result
