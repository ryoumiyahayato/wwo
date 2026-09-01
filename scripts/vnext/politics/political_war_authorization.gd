class_name VNextPoliticalWarAuthorization
extends RefCounted
## Immutable permission issued by Political for a bounded hostile action window.
## This is not war state: it cannot declare/end a war or mutate sovereignty.

const SCHEMA_ID: String = "vnext_political_war_authorization_v1"

var authorization_id: String = ""
var state_id: String = ""
var authorized_country_id: String = ""
var opponent_country_ids: Array[String] = []
var valid_from_hour: int = 0
var valid_until_hour: int = 0


func configure(
	authorization_id_value: String,
	state_id_value: String,
	authorized_country_id_value: String,
	opponent_country_ids_value: Array[String],
	valid_from_hour_value: int,
	valid_until_hour_value: int
) -> bool:
	if VNextStableId.kind_of(authorization_id_value) != "event":
		return false
	if VNextStableId.kind_of(state_id_value) != "state":
		return false
	if authorized_country_id_value.is_empty():
		return false
	if valid_from_hour_value < 0 or valid_until_hour_value < valid_from_hour_value:
		return false
	var normalized_opponents: Array[String] = []
	for opponent_id: String in opponent_country_ids_value:
		if (
			opponent_id.is_empty()
			or opponent_id == authorized_country_id_value
			or normalized_opponents.has(opponent_id)
		):
			return false
		normalized_opponents.append(opponent_id)
	if normalized_opponents.is_empty():
		return false
	normalized_opponents.sort()
	authorization_id = authorization_id_value
	state_id = state_id_value
	authorized_country_id = authorized_country_id_value
	opponent_country_ids = normalized_opponents
	valid_from_hour = valid_from_hour_value
	valid_until_hour = valid_until_hour_value
	return true


func allows_attack(attacker_country_id: String, defender_country_id: String, hour: int) -> bool:
	return (
		is_valid()
		and attacker_country_id == authorized_country_id
		and opponent_country_ids.has(defender_country_id)
		and hour >= valid_from_hour
		and hour <= valid_until_hour
	)


func is_valid() -> bool:
	var copy := VNextPoliticalWarAuthorization.new()
	return copy.configure(
		authorization_id,
		state_id,
		authorized_country_id,
		opponent_country_ids,
		valid_from_hour,
		valid_until_hour
	)


func snapshot() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"authorization_id": authorization_id,
		"state_id": state_id,
		"authorized_country_id": authorized_country_id,
		"opponent_country_ids": opponent_country_ids.duplicate(),
		"valid_from_hour": valid_from_hour,
		"valid_until_hour": valid_until_hour,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 7 or snapshot_value.get("schema_id", "") != SCHEMA_ID:
		return false
	if not snapshot_value.get("opponent_country_ids", []) is Array:
		return false
	var opponents: Array[String] = []
	for raw_id: Variant in snapshot_value.get("opponent_country_ids", []) as Array:
		if typeof(raw_id) != TYPE_STRING:
			return false
		opponents.append(str(raw_id))
	return configure(
		str(snapshot_value.get("authorization_id", "")),
		str(snapshot_value.get("state_id", "")),
		str(snapshot_value.get("authorized_country_id", "")),
		opponents,
		int(snapshot_value.get("valid_from_hour", -1)),
		int(snapshot_value.get("valid_until_hour", -1))
	)
