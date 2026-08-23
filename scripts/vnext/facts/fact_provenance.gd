class_name VNextFactProvenance
extends RefCounted
## Small cross-domain vocabulary for facts that may later reach product views.

const HISTORICALLY_SUPPORTED: String = "HISTORICALLY_SUPPORTED"
const NEAR_1900_SUPPORTED: String = "NEAR_1900_SUPPORTED"
const REFERENCE_ONLY: String = "REFERENCE_ONLY"
const PROTOTYPE_ONLY: String = "PROTOTYPE_ONLY"
const TEMPORALLY_UNKNOWN: String = "TEMPORALLY_UNKNOWN"
const UNAVAILABLE: String = "UNAVAILABLE"

const EXACT: String = "EXACT"
const ALLOCATED: String = "ALLOCATED"
const ESTIMATED: String = "ESTIMATED"
const REGIONAL_PROXY: String = "REGIONAL_PROXY"
const PRECISION_REFERENCE_ONLY: String = "REFERENCE_ONLY"
const UNKNOWN: String = "UNKNOWN"

const BASIS_POINTS: int = 10_000


static func create(
	applicability: String,
	precision: String,
	source_id: String,
	source_revision: String,
	valid_from: String = "",
	valid_to: String = "",
	observation_date: String = "",
	reference_date: String = "",
	simulation_initialization_date: String = "",
	coverage_bp: int = -1
) -> Dictionary:
	var unresolved_bp: int = -1 if coverage_bp < 0 else BASIS_POINTS - coverage_bp
	var result: Dictionary = {
		"applicability": applicability,
		"precision": precision,
		"source_id": source_id,
		"source_revision": source_revision,
		"valid_from": valid_from,
		"valid_to": valid_to,
		"observation_date": observation_date,
		"reference_date": reference_date,
		"simulation_initialization_date": simulation_initialization_date,
		"coverage_bp": coverage_bp,
		"unresolved_bp": unresolved_bp,
	}
	return result if is_valid(result) else {}


static func unavailable(source_id: String, source_revision: String) -> Dictionary:
	return create(UNAVAILABLE, UNKNOWN, source_id, source_revision)


static func is_valid(value: Dictionary) -> bool:
	for field_name: String in [
		"applicability", "precision", "source_id", "source_revision",
		"valid_from", "valid_to", "observation_date", "reference_date",
		"simulation_initialization_date", "coverage_bp", "unresolved_bp",
	]:
		if not value.has(field_name):
			return false
	if not is_applicability(str(value.get("applicability", ""))):
		return false
	if not is_precision(str(value.get("precision", ""))):
		return false
	if str(value.get("source_id", "")).is_empty() or str(value.get("source_revision", "")).is_empty():
		return false
	for field_name: String in [
		"valid_from", "valid_to", "observation_date", "reference_date",
		"simulation_initialization_date",
	]:
		var date_value: String = str(value.get(field_name, ""))
		if not date_value.is_empty() and not is_iso_date(date_value):
			return false
	var valid_from: String = str(value.get("valid_from", ""))
	var valid_to: String = str(value.get("valid_to", ""))
	if valid_from.is_empty() != valid_to.is_empty():
		return false
	if not valid_from.is_empty() and valid_from > valid_to:
		return false
	var coverage_bp: int = int(value.get("coverage_bp", -2))
	var unresolved_bp: int = int(value.get("unresolved_bp", -2))
	if coverage_bp == -1:
		return unresolved_bp == -1
	return (
		coverage_bp >= 0
		and coverage_bp <= BASIS_POINTS
		and unresolved_bp == BASIS_POINTS - coverage_bp
	)


static func supports_date(value: Dictionary, query_date: String) -> bool:
	if not is_valid(value) or not is_iso_date(query_date):
		return false
	var valid_from: String = str(value.get("valid_from", ""))
	var valid_to: String = str(value.get("valid_to", ""))
	return not valid_from.is_empty() and query_date >= valid_from and query_date <= valid_to


static func is_applicability(value: String) -> bool:
	return value in [
		HISTORICALLY_SUPPORTED, NEAR_1900_SUPPORTED, REFERENCE_ONLY,
		PROTOTYPE_ONLY, TEMPORALLY_UNKNOWN, UNAVAILABLE,
	]


static func is_precision(value: String) -> bool:
	return value in [
		EXACT, ALLOCATED, ESTIMATED, REGIONAL_PROXY,
		PRECISION_REFERENCE_ONLY, UNKNOWN,
	]


static func is_iso_date(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	var year_text: String = value.substr(0, 4)
	var month_text: String = value.substr(5, 2)
	var day_text: String = value.substr(8, 2)
	if not year_text.is_valid_int() or not month_text.is_valid_int() or not day_text.is_valid_int():
		return false
	var year: int = int(year_text)
	var month: int = int(month_text)
	var day: int = int(day_text)
	if year <= 0 or month < 1 or month > 12:
		return false
	var days_in_month: int = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
	if month == 2 and (year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)):
		days_in_month = 29
	return day >= 1 and day <= days_in_month
