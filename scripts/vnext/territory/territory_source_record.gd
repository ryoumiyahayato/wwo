class_name VNextTerritorySourceRecord
extends RefCounted
## Immutable evidence identity for one geographic source snapshot.
##
## This record owns provenance/admission metadata only. Geometry remains in the
## referenced resource and runtime territory/control/population state remains
## outside this contract.

const SOURCE_ID_PREFIX: String = "territory_source:"
const STATUS_REFERENCE_ONLY: String = "REFERENCE_ONLY"
const STATUS_CANDIDATE: String = "CANDIDATE"
const STATUS_ADMITTED: String = "ADMITTED"
const STATUS_REJECTED: String = "REJECTED"
const ADMISSION_STATUSES: Array[String] = [
	STATUS_REFERENCE_ONLY,
	STATUS_CANDIDATE,
	STATUS_ADMITTED,
	STATUS_REJECTED,
]
const DERIVATION_RAW_EXTERNAL: String = "RAW_EXTERNAL"
const DERIVATION_DERIVED_SNAPSHOT: String = "DERIVED_SNAPSHOT"
const DERIVATION_POLITICAL_EVIDENCE_PROJECTION: String = "POLITICAL_EVIDENCE_PROJECTION"
const DERIVATION_PROTOTYPE_GEOMETRY: String = "PROTOTYPE_GEOMETRY"
const DERIVATION_KINDS: Array[String] = [
	DERIVATION_RAW_EXTERNAL,
	DERIVATION_DERIVED_SNAPSHOT,
	DERIVATION_POLITICAL_EVIDENCE_PROJECTION,
	DERIVATION_PROTOTYPE_GEOMETRY,
]
const HISTORICAL_FIT_STRONG: String = "STRONG"
const HISTORICAL_FIT_QUALIFIED: String = "QUALIFIED"
const HISTORICAL_FIT_FAIL: String = "FAIL"
const HISTORICAL_FIT_UNRESOLVED: String = "UNRESOLVED"
const HISTORICAL_FIT_STATUSES: Array[String] = [
	HISTORICAL_FIT_STRONG,
	HISTORICAL_FIT_QUALIFIED,
	HISTORICAL_FIT_FAIL,
	HISTORICAL_FIT_UNRESOLVED,
]
const REQUIRED_FIELDS: Array[String] = [
	"source_snapshot_id",
	"dataset_name",
	"dataset_version",
	"provider",
	"source_page",
	"download_url",
	"local_resource_path",
	"source_sha256",
	"snapshot_date",
	"valid_from",
	"valid_to",
	"geometry_scope",
	"geometry_granularity",
	"feature_count",
	"coordinate_reference_system",
	"derivation_kind",
	"parent_source_snapshot_ids",
	"derivation_method",
	"derivation_parameters",
	"historical_target_date",
	"historical_fit_status",
	"license_id",
	"license_url",
	"redistribution_allowed",
	"derivative_work_allowed",
	"commercial_use_allowed",
	"share_alike_required",
	"attribution_required",
	"prototype_only",
	"production_admission_status",
	"production_admission_reason",
]

var _configured: bool = false
var _data: Dictionary = {}


func configure(record_value: Variant) -> bool:
	if _configured or typeof(record_value) != TYPE_DICTIONARY:
		return false
	var candidate: Dictionary = (record_value as Dictionary).duplicate(true)
	if not _validate_shape(candidate):
		return false
	_data = candidate
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func source_snapshot_id() -> String:
	return str(_data.get("source_snapshot_id", "")) if _configured else ""


func production_admission_status() -> String:
	return str(_data.get("production_admission_status", "")) if _configured else ""


func prototype_only() -> bool:
	return bool(_data.get("prototype_only", false)) if _configured else false


func derivation_kind() -> String:
	return str(_data.get("derivation_kind", "")) if _configured else ""


func parent_source_snapshot_ids() -> Array[String]:
	var result: Array[String] = []
	if not _configured:
		return result
	for value: Variant in _data.get("parent_source_snapshot_ids", []) as Array:
		result.append(str(value))
	return result


func value(key: String, default_value: Variant = null) -> Variant:
	if not _configured:
		return default_value
	return _data.get(key, default_value)


func to_detached_dict() -> Dictionary:
	return _data.duplicate(true) if _configured else {}


func copy_detached() -> VNextTerritorySourceRecord:
	if not _configured:
		return null
	var copied := VNextTerritorySourceRecord.new()
	if not copied.configure(_data):
		return null
	return copied


static func is_valid_source_snapshot_id(candidate: String) -> bool:
	if not candidate.begins_with(SOURCE_ID_PREFIX):
		return false
	if candidate.count(":") != 1:
		return false
	var local_id := candidate.trim_prefix(SOURCE_ID_PREFIX)
	if local_id.is_empty():
		return false
	for index: int in local_id.length():
		var character := local_id.substr(index, 1)
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true


static func is_valid_sha256(candidate: String) -> bool:
	if candidate.is_empty():
		return true
	if candidate.length() != 64:
		return false
	for index: int in candidate.length():
		if not "0123456789abcdef".contains(candidate.substr(index, 1)):
			return false
	return true


static func is_valid_machine_code(candidate: String) -> bool:
	if candidate.is_empty() or candidate != candidate.strip_edges():
		return false
	for index: int in candidate.length():
		var character := candidate.substr(index, 1)
		if not "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_".contains(character):
			return false
	return true


static func is_valid_iso_date_or_empty(candidate: String) -> bool:
	if candidate.is_empty():
		return true
	if candidate.length() != 10 or candidate.substr(4, 1) != "-" or candidate.substr(7, 1) != "-":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9]:
		if not "0123456789".contains(candidate.substr(index, 1)):
			return false
	var year := candidate.substr(0, 4).to_int()
	var month := candidate.substr(5, 2).to_int()
	var day := candidate.substr(8, 2).to_int()
	if year <= 0 or month < 1 or month > 12 or day < 1:
		return false
	var days_in_month: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and _is_leap_year(year):
		days_in_month[1] = 29
	return day <= days_in_month[month - 1]


static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


static func _validate_shape(candidate: Dictionary) -> bool:
	for field_name: String in REQUIRED_FIELDS:
		if not candidate.has(field_name):
			return false
	if typeof(candidate.get("source_snapshot_id")) != TYPE_STRING:
		return false
	if not is_valid_source_snapshot_id(str(candidate.get("source_snapshot_id"))):
		return false
	for field_name: String in [
		"dataset_name",
		"dataset_version",
		"provider",
		"source_page",
		"download_url",
		"local_resource_path",
		"source_sha256",
		"snapshot_date",
		"valid_from",
		"valid_to",
		"geometry_scope",
		"geometry_granularity",
		"coordinate_reference_system",
		"derivation_kind",
		"derivation_method",
		"historical_target_date",
		"historical_fit_status",
		"license_id",
		"license_url",
		"production_admission_status",
		"production_admission_reason",
	]:
		if typeof(candidate.get(field_name)) != TYPE_STRING:
			return false
	if str(candidate.get("dataset_name")).strip_edges().is_empty():
		return false
	if str(candidate.get("provider")).strip_edges().is_empty():
		return false
	if not is_valid_sha256(str(candidate.get("source_sha256"))):
		return false
	for field_name: String in ["snapshot_date", "valid_from", "valid_to", "historical_target_date"]:
		if not is_valid_iso_date_or_empty(str(candidate.get(field_name))):
			return false
	var valid_from := str(candidate.get("valid_from"))
	var valid_to := str(candidate.get("valid_to"))
	if not valid_from.is_empty() and not valid_to.is_empty() and valid_from > valid_to:
		return false
	if not DERIVATION_KINDS.has(str(candidate.get("derivation_kind"))):
		return false
	if not HISTORICAL_FIT_STATUSES.has(str(candidate.get("historical_fit_status"))):
		return false
	if not ADMISSION_STATUSES.has(str(candidate.get("production_admission_status"))):
		return false
	if not is_valid_machine_code(str(candidate.get("production_admission_reason"))):
		return false
	if typeof(candidate.get("parent_source_snapshot_ids")) != TYPE_ARRAY:
		return false
	var parent_ids: Array[String] = []
	for parent_value: Variant in candidate.get("parent_source_snapshot_ids") as Array:
		if typeof(parent_value) != TYPE_STRING:
			return false
		var parent_id := str(parent_value)
		if not is_valid_source_snapshot_id(parent_id):
			return false
		if parent_id == str(candidate.get("source_snapshot_id")) or parent_ids.has(parent_id):
			return false
		parent_ids.append(parent_id)
	if typeof(candidate.get("derivation_parameters")) != TYPE_DICTIONARY:
		return false
	var derivation_kind := str(candidate.get("derivation_kind"))
	if derivation_kind == DERIVATION_RAW_EXTERNAL:
		if not parent_ids.is_empty():
			return false
	else:
		if parent_ids.is_empty() or str(candidate.get("derivation_method")).strip_edges().is_empty():
			return false
	var feature_count_value: Variant = candidate.get("feature_count")
	if feature_count_value != null:
		if typeof(feature_count_value) != TYPE_INT or int(feature_count_value) < 0:
			return false
	for field_name: String in [
		"redistribution_allowed",
		"derivative_work_allowed",
		"commercial_use_allowed",
		"share_alike_required",
		"attribution_required",
	]:
		var value: Variant = candidate.get(field_name)
		if value != null and typeof(value) != TYPE_BOOL:
			return false
	if typeof(candidate.get("prototype_only")) != TYPE_BOOL:
		return false
	return true
