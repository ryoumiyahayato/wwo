class_name VNextStatePolitics
extends RefCounted

## Authoritative political state for one country/state.
## It owns political structure and policy decisions, but not economy, war or UI.

const SNAPSHOT_SCHEMA_ID: String = "vnext_state_politics_v1"
const FORCE_SUPPORT_THRESHOLD: float = 10.0
const FORCE_OPPOSITION_THRESHOLD: float = -10.0
const MAX_FORCE_HISTORY: int = 12
const MAX_POLICY_HISTORY: int = 96
const MAX_GOVERNMENT_CHANGE_HISTORY: int = 32

const REGIME_TYPES: Array[String] = [
	"absolute_monarchy",
	"constitutional_monarchy",
	"parliamentary_monarchy",
	"parliamentary_republic",
	"presidential_republic",
	"federal_republic",
	"military_rule",
	"imperial_bureaucracy",
	"colonial_administration",
]
const POLICY_DOMAINS: Array[String] = [
	"trade",
	"tax",
	"labor",
	"social_spending",
	"public_order",
	"military_mobilization",
]
const PRESSURE_SIGNAL_KEYS: Array[String] = [
	"price_pressure",
	"unemployment_pressure",
	"fiscal_pressure",
	"shortage_pressure",
	"growth_signal",
	"war_pressure",
	"casualty_pressure",
	"mobilization_pressure",
	"military_result_signal",
]
const CAPACITY_KEYS: Array[String] = [
	"administrative",
	"enforcement",
	"fiscal",
	"corruption",
	"control",
]

var _state: Dictionary = {}


static func create_from_config(config: Dictionary) -> VNextStatePolitics:
	var result := VNextStatePolitics.new()
	if not result.initialize(config):
		return null
	return result


static func validate_config(config: Dictionary) -> bool:
	return create_from_config(config) != null


func initialize(config: Dictionary) -> bool:
	var candidate := _snapshot_from_config(config)
	if candidate.is_empty():
		return false
	return restore(candidate)


func is_valid() -> bool:
	return _validate_snapshot(_state)


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func restore(snapshot_value: Dictionary) -> bool:
	if not _validate_snapshot(snapshot_value):
		return false
	_state = snapshot_value.duplicate(true)
	return true


func state_id() -> String:
	return str(_state.get("state_id", ""))


func regime_type() -> String:
	return str(_state.get("regime_type", ""))


func government_id() -> String:
	return str(_state.get("government_id", ""))


func government_group_id() -> String:
	return str(_state.get("government_group_id", ""))


func government_leader_id() -> String:
	return str(_state.get("government_leader_id", ""))


func capacity(capacity_key: String) -> float:
	var capacities: Dictionary = _state.get("capacity", {}) as Dictionary
	return float(capacities.get(capacity_key, 0.0))


func capacity_snapshot() -> Dictionary:
	return (_state.get("capacity", {}) as Dictionary).duplicate(true)


func legitimacy() -> float:
	return float(_state.get("legitimacy", 0.0))


func stability() -> float:
	return float(_state.get("stability", 0.0))


func government_support() -> float:
	return float(_state.get("government_support", 0.0))


func government_is_viable() -> bool:
	return bool(_state.get("government_viability", false))


func crisis_stage() -> String:
	return str(_state.get("crisis_stage", ""))


func period_index() -> int:
	return int(_state.get("period_index", 0))


func instability_streak() -> int:
	return int(_state.get("instability_streak", 0))


func recovery_streak() -> int:
	return int(_state.get("recovery_streak", 0))


func political_forces() -> Array[Dictionary]:
	return _sorted_dictionary_array(_state.get("forces", []) as Array)


func political_force(force_id: String) -> Dictionary:
	for force: Dictionary in political_forces():
		if str(force.get("force_id", "")) == force_id:
			return force.duplicate(true)
	return {}


func policy_definitions() -> Array[Dictionary]:
	return _sorted_dictionary_array(_state.get("policies", []) as Array)


func policy_definition(policy_id: String) -> Dictionary:
	for policy: Dictionary in policy_definitions():
		if str(policy.get("policy_id", "")) == policy_id:
			return policy.duplicate(true)
	return {}


func active_policies() -> Array[Dictionary]:
	return _sorted_dictionary_array(_state.get("active_policies", []) as Array)


func active_policy_ids() -> Array[String]:
	var result: Array[String] = []
	for active_policy: Dictionary in active_policies():
		result.append(str(active_policy.get("policy_id", "")))
	result.sort()
	return result


func supporting_force_ids() -> Array[String]:
	return _force_ids_at_or_above(FORCE_SUPPORT_THRESHOLD)


func opposing_force_ids() -> Array[String]:
	return _force_ids_at_or_below(FORCE_OPPOSITION_THRESHOLD)


func neutral_force_ids() -> Array[String]:
	var result: Array[String] = []
	for force: Dictionary in political_forces():
		var support: float = float(force.get("government_support", 0.0))
		if support > FORCE_OPPOSITION_THRESHOLD and support < FORCE_SUPPORT_THRESHOLD:
			result.append(str(force.get("force_id", "")))
	result.sort()
	return result


func last_pressure_input() -> Dictionary:
	return (_state.get("last_pressure_input", {}) as Dictionary).duplicate(true)


func policy_history() -> Array[Dictionary]:
	return _sorted_dictionary_array(_state.get("policy_history", []) as Array)


func government_change_history() -> Array[Dictionary]:
	return _sorted_dictionary_array(_state.get("government_change_history", []) as Array)


func last_policy_review_period() -> int:
	return int(_state.get("last_policy_review_period", -1))


func _force_ids_at_or_above(threshold: float) -> Array[String]:
	var result: Array[String] = []
	for force: Dictionary in political_forces():
		if float(force.get("government_support", 0.0)) >= threshold:
			result.append(str(force.get("force_id", "")))
	result.sort()
	return result


func _force_ids_at_or_below(threshold: float) -> Array[String]:
	var result: Array[String] = []
	for force: Dictionary in political_forces():
		if float(force.get("government_support", 0.0)) <= threshold:
			result.append(str(force.get("force_id", "")))
	result.sort()
	return result


static func _snapshot_from_config(config: Dictionary) -> Dictionary:
	for required_field: String in [
		"state_id",
		"regime_type",
		"government_id",
		"government_group_id",
		"government_leader_id",
		"capacity",
		"forces",
		"policies",
	]:
		if not config.has(required_field):
			return {}
	if typeof(config.get("capacity")) != TYPE_DICTIONARY:
		return {}
	if typeof(config.get("forces")) != TYPE_ARRAY or typeof(config.get("policies")) != TYPE_ARRAY:
		return {}
	var forces: Array[Dictionary] = []
	for raw_force: Variant in config.get("forces") as Array:
		if typeof(raw_force) != TYPE_DICTIONARY:
			return {}
		var force: Dictionary = (raw_force as Dictionary).duplicate(true)
		force["support_history"] = []
		force["last_support_delta"] = 0.0
		forces.append(force)
	var policies: Array[Dictionary] = []
	for raw_policy: Variant in config.get("policies") as Array:
		if typeof(raw_policy) != TYPE_DICTIONARY:
			return {}
		policies.append((raw_policy as Dictionary).duplicate(true))
	var period_index: int = _normalize_int(config.get("period_index", 0), 0, 9_000_000)
	if period_index < 0:
		return {}
	var active_policies: Array[Dictionary] = []
	var configured_active: Variant = config.get("active_policies", config.get("active_policy_ids", []))
	if typeof(configured_active) != TYPE_ARRAY:
		return {}
	for raw_active: Variant in configured_active as Array:
		var policy_id: String = ""
		if typeof(raw_active) == TYPE_STRING:
			policy_id = raw_active as String
		elif typeof(raw_active) == TYPE_DICTIONARY:
			policy_id = str((raw_active as Dictionary).get("policy_id", ""))
		else:
			return {}
		if policy_id.is_empty():
			return {}
		active_policies.append({
			"policy_id": policy_id,
			"started_period": period_index,
			"implementation_strength": 0.65,
			"last_review_period": period_index,
			"status": "implementing",
		})
	var pressure_input: Dictionary = config.get("last_pressure_input", {}) as Dictionary
	if pressure_input.is_empty():
		var neutral_input := VNextPoliticsPressureInput.create(30)
		if neutral_input == null:
			return {}
		pressure_input = neutral_input.snapshot()
	var initial_support: float = float(config.get(
		"government_support", _weighted_support_from_forces(forces)
	))
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"state_id": config.get("state_id", ""),
		"regime_type": config.get("regime_type", ""),
		"government_id": config.get("government_id", ""),
		"government_group_id": config.get("government_group_id", ""),
		"government_leader_id": config.get("government_leader_id", ""),
		"capacity": (config.get("capacity") as Dictionary).duplicate(true),
		"legitimacy": float(config.get("legitimacy", 60.0)),
		"stability": float(config.get("stability", 60.0)),
		"government_support": initial_support,
		"government_viability": bool(config.get("government_viability", true)),
		"crisis_stage": str(config.get("crisis_stage", "stable")),
		"instability_streak": int(config.get("instability_streak", 0)),
		"recovery_streak": int(config.get("recovery_streak", 0)),
		"period_index": period_index,
		"last_policy_review_period": int(config.get("last_policy_review_period", period_index)),
		"forces": forces,
		"policies": policies,
		"active_policies": active_policies,
		"policy_history": (config.get("policy_history", []) as Array).duplicate(true),
		"government_change_history": (
			config.get("government_change_history", []) as Array
		).duplicate(true),
		"last_pressure_input": pressure_input.duplicate(true),
	}


static func _validate_snapshot(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 22:
		return false
	for required_field: String in [
		"schema_id",
		"state_id",
		"regime_type",
		"government_id",
		"government_group_id",
		"government_leader_id",
		"capacity",
		"legitimacy",
		"stability",
		"government_support",
		"government_viability",
		"crisis_stage",
		"instability_streak",
		"recovery_streak",
		"period_index",
		"last_policy_review_period",
		"forces",
		"policies",
		"active_policies",
		"policy_history",
		"government_change_history",
		"last_pressure_input",
	]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if not _valid_id(snapshot_value.get("state_id"), "state"):
		return false
	if typeof(snapshot_value.get("regime_type")) != TYPE_STRING:
		return false
	if str(snapshot_value.get("regime_type")) not in REGIME_TYPES:
		return false
	if not _valid_id(snapshot_value.get("government_id"), "organization"):
		return false
	if not _valid_id(snapshot_value.get("government_group_id"), "organization"):
		return false
	if not _valid_id(snapshot_value.get("government_leader_id"), "person"):
		return false
	if typeof(snapshot_value.get("government_viability")) != TYPE_BOOL:
		return false
	if str(snapshot_value.get("crisis_stage")) not in [
		"stable", "strained", "crisis", "transition"
	]:
		return false
	for numeric_field: String in ["legitimacy", "stability", "government_support"]:
		if not _in_range_number(snapshot_value.get(numeric_field), -100.0, 100.0):
			return false
	for integer_field: String in [
		"instability_streak", "recovery_streak", "period_index"
	]:
		if _normalize_int(snapshot_value.get(integer_field), 0, 9_000_000) < 0:
			return false
	if _normalize_int(snapshot_value.get("last_policy_review_period"), -1, 9_000_000) < -1:
		return false
	if not _validate_capacity(snapshot_value.get("capacity")):
		return false
	if typeof(snapshot_value.get("forces")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("policies")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("active_policies")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("policy_history")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("government_change_history")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("last_pressure_input")) != TYPE_DICTIONARY:
		return false
	if VNextPoliticsPressureInput.from_snapshot(
		snapshot_value.get("last_pressure_input") as Dictionary
	) == null:
		return false
	var force_ids: Dictionary = {}
	var government_force_found: bool = false
	var government_leader_found: bool = false
	var total_influence: float = 0.0
	for raw_force: Variant in snapshot_value.get("forces") as Array:
		if typeof(raw_force) != TYPE_DICTIONARY:
			return false
		var force: Dictionary = raw_force as Dictionary
		if not _validate_force(force):
			return false
		var force_id: String = str(force.get("force_id", ""))
		if force_ids.has(force_id):
			return false
		force_ids[force_id] = true
		total_influence += float(force.get("influence", 0.0))
		if force_id == str(snapshot_value.get("government_group_id", "")):
			government_force_found = true
			government_leader_found = str(force.get("leader_id", "")) == str(
				snapshot_value.get("government_leader_id", ""))
	if total_influence <= 0.0 or not government_force_found or not government_leader_found:
		return false
	var policy_ids: Dictionary = {}
	for raw_policy: Variant in snapshot_value.get("policies") as Array:
		if typeof(raw_policy) != TYPE_DICTIONARY:
			return false
		var policy: Dictionary = raw_policy as Dictionary
		if not _validate_policy(policy):
			return false
		var policy_id: String = str(policy.get("policy_id", ""))
		if policy_ids.has(policy_id):
			return false
		policy_ids[policy_id] = true
	var active_ids: Dictionary = {}
	for raw_active: Variant in snapshot_value.get("active_policies") as Array:
		if typeof(raw_active) != TYPE_DICTIONARY:
			return false
		var active: Dictionary = raw_active as Dictionary
		var active_id: String = str(active.get("policy_id", ""))
		if not policy_ids.has(active_id) or active_ids.has(active_id):
			return false
		if _normalize_int(active.get("started_period"), 0, 9_000_000) < 0:
			return false
		if _normalize_int(active.get("last_review_period"), 0, 9_000_000) < 0:
			return false
		if not _in_range_number(active.get("implementation_strength"), 0.0, 1.0):
			return false
		if typeof(active.get("status")) != TYPE_STRING:
			return false
		active_ids[active_id] = true
	if (snapshot_value.get("active_policies") as Array).size() > 6:
		return false
	if not _validate_history(snapshot_value.get("policy_history") as Array, MAX_POLICY_HISTORY):
		return false
	return _validate_history(
		snapshot_value.get("government_change_history") as Array,
		MAX_GOVERNMENT_CHANGE_HISTORY
	)


static func _validate_capacity(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var capacity_value: Dictionary = value as Dictionary
	if capacity_value.size() != CAPACITY_KEYS.size():
		return false
	for key: String in CAPACITY_KEYS:
		if not capacity_value.has(key) or not _in_range_number(capacity_value.get(key), 0.0, 100.0):
			return false
	return true


static func _validate_force(force: Dictionary) -> bool:
	for required_field: String in [
		"force_id",
		"name",
		"kind",
		"leader_id",
		"influence",
		"government_support",
		"base_government_support",
		"institutional_access",
		"mobilization_capacity",
		"government_eligible",
		"policy_preferences",
		"pressure_response",
		"support_history",
		"last_support_delta",
	]:
		if not force.has(required_field):
			return false
	if not _valid_id(force.get("force_id"), "organization"):
		return false
	for string_field: String in ["name", "kind"]:
		if typeof(force.get(string_field)) != TYPE_STRING or str(force.get(string_field)).is_empty():
			return false
	if not _valid_id(force.get("leader_id"), "person"):
		return false
	for number_field: String in ["influence", "institutional_access", "mobilization_capacity"]:
		if not _in_range_number(force.get(number_field), 0.0, 100.0):
			return false
	for support_field: String in ["government_support", "base_government_support"]:
		if not _in_range_number(force.get(support_field), -100.0, 100.0):
			return false
	if typeof(force.get("government_eligible")) != TYPE_BOOL:
		return false
	if not _validate_preference_dictionary(force.get("policy_preferences"), -100.0, 100.0, POLICY_DOMAINS):
		return false
	if not _validate_preference_dictionary(force.get("pressure_response"), -2.0, 2.0, PRESSURE_SIGNAL_KEYS):
		return false
	if typeof(force.get("support_history")) != TYPE_ARRAY:
		return false
	if (force.get("support_history") as Array).size() > MAX_FORCE_HISTORY:
		return false
	return _in_range_number(force.get("last_support_delta"), -100.0, 100.0)


static func _validate_policy(policy: Dictionary) -> bool:
	for required_field: String in [
		"policy_id",
		"name",
		"domain",
		"position",
		"fiscal_demand",
		"administrative_demand",
		"required_control",
		"pressure_targets",
		"political_relief",
	]:
		if not policy.has(required_field):
			return false
	if not _valid_id(policy.get("policy_id"), "policy"):
		return false
	if typeof(policy.get("name")) != TYPE_STRING or str(policy.get("name")).is_empty():
		return false
	if typeof(policy.get("domain")) != TYPE_STRING or str(policy.get("domain")) not in POLICY_DOMAINS:
		return false
	if not _in_range_number(policy.get("position"), -100.0, 100.0):
		return false
	for number_field: String in ["fiscal_demand", "administrative_demand", "required_control"]:
		if not _in_range_number(policy.get(number_field), 0.0, 100.0):
			return false
	if not _validate_preference_dictionary(policy.get("pressure_targets"), 0.0, 100.0, PRESSURE_SIGNAL_KEYS):
		return false
	return _validate_preference_dictionary(
		policy.get("political_relief"), 0.0, 100.0, PRESSURE_SIGNAL_KEYS
	)


static func _validate_preference_dictionary(
	value: Variant, minimum: float, maximum: float, allowed_keys: Array[String]
) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for raw_key: Variant in (value as Dictionary).keys():
		var key: String = str(raw_key)
		if key not in allowed_keys or not _in_range_number((value as Dictionary).get(key), minimum, maximum):
			return false
	return true


static func _validate_history(history: Array, maximum_size: int) -> bool:
	if history.size() > maximum_size:
		return false
	for record: Variant in history:
		if typeof(record) != TYPE_DICTIONARY:
			return false
	return true


static func _weighted_support_from_forces(forces: Array[Dictionary]) -> float:
	var total_influence: float = 0.0
	var weighted_support: float = 0.0
	for force: Dictionary in forces:
		var influence: float = float(force.get("influence", 0.0))
		total_influence += influence
		weighted_support += influence * ((float(force.get("government_support", 0.0)) + 100.0) / 2.0)
	if total_influence <= 0.0:
		return 0.0
	return clampf(weighted_support / total_influence, 0.0, 100.0)


static func _valid_id(value: Variant, expected_kind: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var candidate: String = value as String
	return VNextStableId.is_valid(candidate) and VNextStableId.kind_of(candidate) == expected_kind


static func _in_range_number(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric: float = float(value)
	return is_finite(numeric) and numeric >= minimum and numeric <= maximum


static func _normalize_int(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) == TYPE_INT:
		var integer_value: int = int(value)
		return integer_value if integer_value >= minimum and integer_value <= maximum else minimum - 1
	if typeof(value) != TYPE_FLOAT:
		return minimum - 1
	var float_value: float = float(value)
	if not is_finite(float_value) or float_value != floor(float_value):
		return minimum - 1
	var normalized: int = int(float_value)
	return normalized if normalized >= minimum and normalized <= maximum else minimum - 1


static func _sorted_dictionary_array(raw_array: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_value: Variant in raw_array:
		if typeof(raw_value) == TYPE_DICTIONARY:
			result.append((raw_value as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_id: String = str(left.get("force_id", left.get("policy_id", left.get("period", ""))))
		var right_id: String = str(right.get("force_id", right.get("policy_id", right.get("period", ""))))
		return left_id < right_id
	)
	return result
