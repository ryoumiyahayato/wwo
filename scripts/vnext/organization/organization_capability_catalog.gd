class_name VNextOrganizationCapabilityCatalog
extends RefCounted

## Minimal controlled authorization vocabulary needed by OrganizationState.
## These are authorization facts only; they do not execute gameplay commands.

const MANAGE_APPOINTMENTS: String = "organization.manage_appointments"

const _CAPABILITY_IDS: Array[String] = [
	MANAGE_APPOINTMENTS,
]


static func ids() -> Array[String]:
	return _CAPABILITY_IDS.duplicate()


static func is_known(capability_id: String) -> bool:
	return _CAPABILITY_IDS.has(capability_id)


static func fingerprint() -> String:
	return JSON.stringify(_CAPABILITY_IDS).sha256_text()


static func is_known_operation(operation_id: String) -> bool:
	# This rule ID already belongs to the existing defend command.
	return is_known(operation_id) or operation_id == "military.defend"
