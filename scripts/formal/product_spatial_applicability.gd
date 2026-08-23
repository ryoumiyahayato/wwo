class_name ProductSpatialApplicability
extends RefCounted
## Fail-closed applicability vocabulary for Spatial facts shown by the product.

const HISTORICALLY_SUPPORTED: String = "HISTORICALLY_SUPPORTED"
const NEAR_1900_SUPPORTED: String = "NEAR_1900_SUPPORTED"
const REFERENCE_ONLY: String = "REFERENCE_ONLY"
const PROTOTYPE_ONLY: String = "PROTOTYPE_ONLY"
const TEMPORALLY_UNKNOWN: String = "TEMPORALLY_UNKNOWN"
const UNAVAILABLE: String = "UNAVAILABLE"


static func classes() -> Array[String]:
	return [
		HISTORICALLY_SUPPORTED,
		NEAR_1900_SUPPORTED,
		REFERENCE_ONLY,
		PROTOTYPE_ONLY,
		TEMPORALLY_UNKNOWN,
		UNAVAILABLE,
	]


static func may_present_as_normal_truth(applicability: String) -> bool:
	return applicability in [HISTORICALLY_SUPPORTED, NEAR_1900_SUPPORTED]


static func classify_document(document: Dictionary) -> String:
	if document.is_empty():
		return UNAVAILABLE
	if bool(document.get("prototype_only", false)) or document.has("prototype_notice"):
		return PROTOTYPE_ONLY
	var historical_status := str(document.get("historical_status", ""))
	match historical_status:
		"historically_supported":
			return HISTORICALLY_SUPPORTED
		"near_1900_supported":
			return NEAR_1900_SUPPORTED
		"modern_reference_only", "reference_only":
			return REFERENCE_ONLY
		"temporally_unknown":
			return TEMPORALLY_UNKNOWN
	return TEMPORALLY_UNKNOWN

