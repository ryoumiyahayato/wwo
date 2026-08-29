class_name HistoricalFactEvidence
extends RefCounted
## Typed, domain-neutral evidence attached to one historical runtime fact.

const REQUIRED_FIELDS: Array[String] = [
	"fact_id",
	"domain",
	"subject_id",
	"value",
	"unit",
	"source_id",
	"source_version",
	"source_locator",
	"observation_period",
	"spatial_scope",
	"methodology",
	"confidence",
	"lower_bound",
	"upper_bound",
	"license",
	"review_status",
	"generator",
	"input_hash",
	"output_hash",
]

var fact_id: String
var domain: String
var subject_id: String
var value: Variant
var unit: String
var source_id: String
var source_version: String
var source_locator: String
var observation_period: Dictionary
var spatial_scope: Dictionary
var methodology: String
var confidence: float
var lower_bound: Variant
var upper_bound: Variant
var license: String
var review_status: String
var generator: String
var input_hash: String
var output_hash: String


static func from_dictionary(document: Dictionary) -> HistoricalFactEvidence:
	for field: String in REQUIRED_FIELDS:
		if not document.has(field):
			return null
	if not document.get("observation_period") is Dictionary:
		return null
	if not document.get("spatial_scope") is Dictionary:
		return null
	var evidence := HistoricalFactEvidence.new()
	evidence.fact_id = str(document.get("fact_id"))
	evidence.domain = str(document.get("domain"))
	evidence.subject_id = str(document.get("subject_id"))
	evidence.value = document.get("value")
	evidence.unit = str(document.get("unit"))
	evidence.source_id = str(document.get("source_id"))
	evidence.source_version = str(document.get("source_version"))
	evidence.source_locator = str(document.get("source_locator"))
	evidence.observation_period = (document.get("observation_period") as Dictionary).duplicate(true)
	evidence.spatial_scope = (document.get("spatial_scope") as Dictionary).duplicate(true)
	evidence.methodology = str(document.get("methodology"))
	evidence.confidence = float(document.get("confidence"))
	evidence.lower_bound = document.get("lower_bound")
	evidence.upper_bound = document.get("upper_bound")
	evidence.license = str(document.get("license"))
	evidence.review_status = str(document.get("review_status"))
	evidence.generator = str(document.get("generator"))
	evidence.input_hash = str(document.get("input_hash"))
	evidence.output_hash = str(document.get("output_hash"))
	return evidence


func validation_error() -> String:
	for value_to_check: String in [
		fact_id, domain, subject_id, unit, source_id, source_version,
		source_locator, methodology, license, review_status, generator,
	]:
		if value_to_check.strip_edges().is_empty():
			return "required evidence text is empty"
	if observation_period.is_empty():
		return "observation_period is empty"
	if spatial_scope.is_empty():
		return "spatial_scope is empty"
	if confidence < 0.0 or confidence > 1.0 or is_nan(confidence):
		return "confidence is outside [0, 1]"
	if not is_sha256(input_hash) or not is_sha256(output_hash):
		return "evidence hash is not SHA-256"
	if output_hash != sha256(output_material()):
		return "output hash mismatch"
	return ""


func output_material() -> Dictionary:
	return {
		"lower_bound": lower_bound,
		"observation_period": observation_period.duplicate(true),
		"spatial_scope": spatial_scope.duplicate(true),
		"subject_id": subject_id,
		"unit": unit,
		"upper_bound": upper_bound,
		"value": value,
	}


func to_dictionary() -> Dictionary:
	return {
		"fact_id": fact_id,
		"domain": domain,
		"subject_id": subject_id,
		"value": value,
		"unit": unit,
		"source_id": source_id,
		"source_version": source_version,
		"source_locator": source_locator,
		"observation_period": observation_period.duplicate(true),
		"spatial_scope": spatial_scope.duplicate(true),
		"methodology": methodology,
		"confidence": confidence,
		"lower_bound": lower_bound,
		"upper_bound": upper_bound,
		"license": license,
		"review_status": review_status,
		"generator": generator,
		"input_hash": input_hash,
		"output_hash": output_hash,
	}


static func sha256(value_to_hash: Variant) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(canonical_json(value_to_hash).to_utf8_buffer())
	return context.finish().hex_encode()


static func canonical_json(value_to_encode: Variant) -> String:
	if value_to_encode is Dictionary:
		var dictionary := value_to_encode as Dictionary
		var keys: Array[String] = []
		for key: Variant in dictionary.keys():
			keys.append(str(key))
		keys.sort()
		var members: Array[String] = []
		for key: String in keys:
			members.append(JSON.stringify(key) + ":" + canonical_json(dictionary.get(key)))
		return "{" + ",".join(members) + "}"
	if value_to_encode is Array:
		var members: Array[String] = []
		for item: Variant in value_to_encode as Array:
			members.append(canonical_json(item))
		return "[" + ",".join(members) + "]"
	if typeof(value_to_encode) == TYPE_FLOAT:
		var number := float(value_to_encode)
		if is_finite(number) and number == floor(number):
			return str(int(number))
	return JSON.stringify(value_to_encode)


static func is_sha256(candidate: String) -> bool:
	if candidate.length() != 64:
		return false
	for character: String in candidate.to_lower():
		if character not in "0123456789abcdef":
			return false
	return true
