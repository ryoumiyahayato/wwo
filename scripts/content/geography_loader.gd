class_name GeographyLoader
extends RefCounted

const RELIEF_PATH: String = "res://data/presentation/global_physical_relief.json"
const GEOMETRY_PATH: String = "res://data/world_map/historical/cshapes_1900_snapshot.json"
const SUPPLEMENT_PATH: String = "res://data/world_map/historical/arabia_gulf_geography_1900.json"
const REGIONAL_DISPLAY_PATH: String = "res://data/presentation/cshapes_region_display_r3.json"
var errors: Array[String] = []
var metadata: Dictionary = {}
var parts_by_feature: Dictionary = {}

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
	return errors.is_empty()

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

static func prepare_regional_display(lod: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var failures: Array[String] = []
	var result: Dictionary = {"errors": failures, "lod": lod, "meshes": {}, "metrics": {}}
	var document := ContentDocument.read(REGIONAL_DISPLAY_PATH, failures)
	var sources := HistoricalSourceRegistry.new()
	var facts := HistoricalEvidenceCatalog.new()
	if str(document.get("schema_id", "")) != "regional_political_display_r3" or not sources.load_document(document.get("source_registry", {}) as Dictionary) or not facts.load_document(document.get("evidence_catalog", {}) as Dictionary):
		failures.append("Invalid regional display evidence")
		return result
	var evidence := facts.fact("regional_display:cshapes_1900")
	var gate := HistoricalProvenanceGate.new(sources, facts)
	if evidence == null or not gate.admit_runtime_fact(evidence.fact_id, "spatial_boundary", evidence.output_material()):
		failures.append("Unadmitted regional display geometry")
		return result
	var value := evidence.value as Dictionary
	if str(value.get("geometry_role", "")) != "PRESENTATION_ONLY" or str(value.get("encoding", "")) != "ZLIB_JSON_UTF8":
		failures.append("Regional geometry cannot replace canonical territory")
		return result
	if FileAccess.get_sha256(GEOMETRY_PATH) != str(value.get("canonical_geometry_sha256", "")):
		failures.append("Regional display canonical binding mismatch")
		return result
	var asset: Dictionary = {}
	for candidate: Dictionary in value.assets:
		if str(candidate.id) == lod: asset = candidate
	if asset.is_empty():
		failures.append("Missing regional display LOD")
		return result
	var bytes := FileAccess.get_file_as_bytes(str(asset.path))
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	if bytes.size() != int(asset.bytes) or hash.finish().hex_encode() != str(asset.sha256):
		failures.append("Regional display payload binding mismatch")
		return result
	var decoded := bytes.decompress_dynamic(int(asset.decoded_bytes), FileAccess.COMPRESSION_DEFLATE)
	if decoded.size() != int(asset.decoded_bytes):
		failures.append("Invalid regional display encoding")
		return result
	var parser := JSON.new()
	if parser.parse(decoded.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		failures.append("Invalid regional display JSON")
		return result
	var loader := GeographyLoader.new()
	loader._load_features(parser.data as Dictionary)
	failures.append_array(loader.errors)
	var ids := loader.parts_by_feature.keys()
	ids.sort()
	var expected := (value.feature_ids as Array).duplicate()
	expected.sort()
	if ids != expected or not failures.is_empty():
		failures.append("Regional display identities differ from canonical snapshot")
		return result
	result.metrics["decode_usec"] = Time.get_ticks_usec() - started
	for id: String in ids:
		(result.meshes as Dictionary)[id] = GlobeProjection.source_mesh(loader.parts_by_feature[id] as Array, id)
	result.metrics["prepare_usec"] = Time.get_ticks_usec() - started
	result.metrics["source_bytes"] = bytes.size()
	return result

static func decode_relief(level: String, admitted: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var failures: Array[String] = []
	var result: Dictionary = {"errors": failures, "metrics": {"started_usec": started}}
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
	result.metrics["source_resolution_usec"] = Time.get_ticks_usec() - started
	if not admitted.has(level):
		failures.append("Missing relief level")
		return result
	var asset := admitted[level] as Dictionary
	started = Time.get_ticks_usec()
	var buffer := FileAccess.get_file_as_bytes(str(asset.path))
	result.metrics["file_read_usec"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(buffer)
	if hash.finish().hex_encode() != str(asset.sha256):
		failures.append("Relief byte identity mismatch")
		return result
	result.metrics["hash_usec"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var image := Image.new()
	if image.load_png_from_buffer(buffer) != OK or image.get_width() != int(asset.width) or image.get_height() != int(asset.height):
		failures.append("Invalid relief image")
		return result
	result.metrics["decode_usec"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	image.convert(Image.FORMAT_RG8)
	result.metrics["cpu_format_usec"] = Time.get_ticks_usec() - started
	result["image"] = image
	return result
