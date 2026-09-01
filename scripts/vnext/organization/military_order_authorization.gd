class_name VNextMilitaryOrderAuthorization
extends RefCounted
## Immutable authorization seam supplied by Organization.
## It proves permission only; it does not implement membership or appointments.

const SCHEMA_ID: String = "vnext_military_order_authorization_v1"
const REQUIRED_CAPABILITY: String = "military.issue_strategic_order"

var authorization_id: String = ""
var organization_id: String = ""
var formation_id: String = ""
var capability_id: String = REQUIRED_CAPABILITY
var valid_from_hour: int = 0
var valid_until_hour: int = 0


func configure(
	authorization_id_value: String,
	organization_id_value: String,
	formation_id_value: String,
	valid_from_hour_value: int,
	valid_until_hour_value: int,
	capability_id_value: String = REQUIRED_CAPABILITY
) -> bool:
	if VNextStableId.kind_of(authorization_id_value) != "event":
		return false
	if VNextStableId.kind_of(organization_id_value) != "organization":
		return false
	if VNextStableId.kind_of(formation_id_value) != "formation":
		return false
	if capability_id_value != REQUIRED_CAPABILITY:
		return false
	if valid_from_hour_value < 0 or valid_until_hour_value < valid_from_hour_value:
		return false
	authorization_id = authorization_id_value
	organization_id = organization_id_value
	formation_id = formation_id_value
	capability_id = capability_id_value
	valid_from_hour = valid_from_hour_value
	valid_until_hour = valid_until_hour_value
	return true


func allows_order(
	formation_id_value: String, organization_id_value: String, hour: int
) -> bool:
	return (
		is_valid()
		and formation_id_value == formation_id
		and organization_id_value == organization_id
		and hour >= valid_from_hour
		and hour <= valid_until_hour
	)


func is_valid() -> bool:
	var copy := VNextMilitaryOrderAuthorization.new()
	return copy.configure(
		authorization_id,
		organization_id,
		formation_id,
		valid_from_hour,
		valid_until_hour,
		capability_id
	)


func snapshot() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"authorization_id": authorization_id,
		"organization_id": organization_id,
		"formation_id": formation_id,
		"capability_id": capability_id,
		"valid_from_hour": valid_from_hour,
		"valid_until_hour": valid_until_hour,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 7 or snapshot_value.get("schema_id", "") != SCHEMA_ID:
		return false
	return configure(
		str(snapshot_value.get("authorization_id", "")),
		str(snapshot_value.get("organization_id", "")),
		str(snapshot_value.get("formation_id", "")),
		int(snapshot_value.get("valid_from_hour", -1)),
		int(snapshot_value.get("valid_until_hour", -1)),
		str(snapshot_value.get("capability_id", ""))
	)
