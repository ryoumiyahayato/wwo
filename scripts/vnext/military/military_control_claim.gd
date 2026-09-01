class_name VNextMilitaryControlClaim
extends RefCounted
## Military evidence proposing a controller change. A claim is never territorial truth.

const SCHEMA_ID: String = "vnext_military_control_claim_v1"

var location: String = ""
var military_presence: Dictionary = {}
var battle_result: Dictionary = {}
var candidate_control_outcome: Dictionary = {}
var timestamp: int = 0


func configure(
	location_value: String,
	military_presence_value: Dictionary,
	battle_result_value: Dictionary,
	candidate_control_outcome_value: Dictionary,
	timestamp_value: int
) -> bool:
	if location_value.is_empty() or timestamp_value < 0:
		return false
	if VNextStableId.kind_of(str(military_presence_value.get("formation_id", ""))) != "formation":
		return false
	if str(military_presence_value.get("country_id", "")).is_empty():
		return false
	if int(military_presence_value.get("personnel", -1)) <= 0:
		return false
	if VNextStableId.kind_of(str(battle_result_value.get("action_id", ""))) != "military_action":
		return false
	if (
		str(battle_result_value.get("outcome", "")) != "attacker_win"
		or str(battle_result_value.get("target_region_id", "")) != location_value
		or str(battle_result_value.get("attacker_formation_id", ""))
		!= str(military_presence_value.get("formation_id", ""))
		or str(battle_result_value.get("attacker_country_id", ""))
		!= str(military_presence_value.get("country_id", ""))
	):
		return false
	var expected_controller_id: String = str(
		candidate_control_outcome_value.get("expected_controller_id", "")
	)
	var candidate_controller_id: String = str(
		candidate_control_outcome_value.get("candidate_controller_id", "")
	)
	if (
		expected_controller_id.is_empty()
		or candidate_controller_id.is_empty()
		or expected_controller_id == candidate_controller_id
		or expected_controller_id != str(battle_result_value.get("defender_country_id", ""))
		or candidate_controller_id != str(military_presence_value.get("country_id", ""))
	):
		return false
	location = location_value
	military_presence = military_presence_value.duplicate(true)
	battle_result = battle_result_value.duplicate(true)
	candidate_control_outcome = candidate_control_outcome_value.duplicate(true)
	timestamp = timestamp_value
	return true


func is_valid() -> bool:
	var copy := VNextMilitaryControlClaim.new()
	return copy.configure(
		location,
		military_presence,
		battle_result,
		candidate_control_outcome,
		timestamp
	)


func snapshot() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"location": location,
		"military_presence": military_presence.duplicate(true),
		"battle_result": battle_result.duplicate(true),
		"candidate_control_outcome": candidate_control_outcome.duplicate(true),
		"timestamp": timestamp,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 6 or snapshot_value.get("schema_id", "") != SCHEMA_ID:
		return false
	for field_name: String in [
		"military_presence", "battle_result", "candidate_control_outcome",
	]:
		if not snapshot_value.get(field_name, {}) is Dictionary:
			return false
	return configure(
		str(snapshot_value.get("location", "")),
		snapshot_value.get("military_presence", {}) as Dictionary,
		snapshot_value.get("battle_result", {}) as Dictionary,
		snapshot_value.get("candidate_control_outcome", {}) as Dictionary,
		int(snapshot_value.get("timestamp", -1))
	)
