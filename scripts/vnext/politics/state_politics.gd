class_name VNextStatePolitics
extends RefCounted

## Authoritative political state for one country/state.
## period_index, streaks and history periods are authoritative elapsed days.

const SNAPSHOT_SCHEMA_ID: String = "vnext_state_politics_v1"
const FORCE_SUPPORT_THRESHOLD: float = 10.0
const FORCE_OPPOSITION_THRESHOLD: float = -10.0
const MAX_FORCE_HISTORY: int = 64
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

enum {
	MAX_ELAPSED_DAYS = 9_000_000,
	VIABILITY_SUPPORT_THRESHOLD = 46,
	VIABILITY_CONTROL_THRESHOLD = 32,
	VIABILITY_LEGITIMACY_THRESHOLD = 38,
	VIABILITY_STABILITY_THRESHOLD = 42,
}


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
	var candidate: Dictionary = _canonicalize_snapshot(snapshot_value)
	if not _validate_snapshot(candidate):
		return false
	_state = candidate
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
	return float((_state.get("capacity", {}) as Dictionary).get(capacity_key, 0.0))


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
		var support := float(force.get("government_support", 0.0))
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
		"state_id", "regime_type", "government_id", "government_group_id",
		"government_leader_id", "capacity", "forces", "policies",
	]:
		if not config.has(required_field):
			return {}
	if typeof(config.get("capacity")) != TYPE_DICTIONARY:
		return {}
	if typeof(config.get("forces")) != TYPE_ARRAY or typeof(config.get("policies")) != TYPE_ARRAY:
		return {}

	var period_index := _normalize_int(config.get("period_index", 0), 0, MAX_ELAPSED_DAYS)
	if period_index < 0:
		return {}

	var forces: Array[Dictionary] = []
	for raw_force: Variant in config.get("forces") as Array:
		if typeof(raw_force) != TYPE_DICTIONARY:
			return {}
		var force: Dictionary = (raw_force as Dictionary).duplicate(true)
		force["support_history"] = []
		force["last_support_delta"] = 0.0
		forces.append(force)
	forces = _sorted_dictionary_array(forces)

	var policies: Array[Dictionary] = []
	for raw_policy: Variant in config.get("policies") as Array:
		if typeof(raw_policy) != TYPE_DICTIONARY:
			return {}
		policies.append((raw_policy as Dictionary).duplicate(true))
	policies = _sorted_dictionary_array(policies)

	var configured_active: Variant = config.get("active_policies", config.get("active_policy_ids", []))
	if typeof(configured_active) != TYPE_ARRAY:
		return {}
	var active_policies: Array[Dictionary] = []
	for raw_active: Variant in configured_active as Array:
		var policy_id := ""
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
	active_policies = _sorted_dictionary_array(active_policies)

	var pressure_input: Dictionary = {}
	if typeof(config.get("last_pressure_input", {})) == TYPE_DICTIONARY:
		pressure_input = (config.get("last_pressure_input", {}) as Dictionary).duplicate(true)
	if pressure_input.is_empty():
		var neutral_input := VNextPoliticsPressureInput.create(1)
		if neutral_input == null:
			return {}
		pressure_input = neutral_input.snapshot()

	var government_support := _weighted_support_from_forces(forces)
	var capacity_value := (config.get("capacity") as Dictionary).duplicate(true)
	var legitimacy_value := float(config.get("legitimacy", 60.0))
	var stability_value := float(config.get("stability", 60.0))
	var candidate := {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"state_id": config.get("state_id", ""),
		"regime_type": config.get("regime_type", ""),
		"government_id": config.get("government_id", ""),
		"government_group_id": config.get("government_group_id", ""),
		"government_leader_id": config.get("government_leader_id", ""),
		"capacity": capacity_value,
		"legitimacy": legitimacy_value,
		"stability": stability_value,
		"government_support": government_support,
		"government_viability": _derive_viability(government_support, capacity_value, legitimacy_value, stability_value),
		"crisis_stage": str(config.get("crisis_stage", "stable")),
		"instability_streak": int(config.get("instability_streak", 0)),
		"recovery_streak": int(config.get("recovery_streak", 0)),
		"period_index": period_index,
		"last_policy_review_period": int(config.get("last_policy_review_period", period_index)),
		"forces": forces,
		"policies": policies,
		"active_policies": active_policies,
		"policy_history": (config.get("policy_history", []) as Array).duplicate(true) if typeof(config.get("policy_history", [])) == TYPE_ARRAY else [],
		"government_change_history": (config.get("government_change_history", []) as Array).duplicate(true) if typeof(config.get("government_change_history", [])) == TYPE_ARRAY else [],
		"last_pressure_input": pressure_input,
	}
	return _canonicalize_snapshot(candidate)


static func _validate_snapshot(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 22:
		return false
	for required_field: String in [
		"schema_id", "state_id", "regime_type", "government_id",
		"government_group_id", "government_leader_id", "capacity", "legitimacy",
		"stability", "government_support", "government_viability", "crisis_stage",
		"instability_streak", "recovery_streak", "period_index",
		"last_policy_review_period", "forces", "policies", "active_policies",
		"policy_history", "government_change_history", "last_pressure_input",
	]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	if not _valid_id(snapshot_value.get("state_id"), "state"):
		return false
	if typeof(snapshot_value.get("regime_type")) != TYPE_STRING or str(snapshot_value.get("regime_type")) not in REGIME_TYPES:
		return false
	if not _valid_id(snapshot_value.get("government_id"), "organization"):
		return false
	if not _valid_id(snapshot_value.get("government_group_id"), "organization"):
		return false
	if not _valid_id(snapshot_value.get("government_leader_id"), "person"):
		return false
	if typeof(snapshot_value.get("government_viability")) != TYPE_BOOL:
		return false
	if str(snapshot_value.get("crisis_stage")) not in ["stable", "strained", "crisis", "transition"]:
		return false
	for numeric_field: String in ["legitimacy", "stability", "government_support"]:
		if not _in_range_number(snapshot_value.get(numeric_field), 0.0, 100.0):
			return false

	var period := _normalize_int(snapshot_value.get("period_index"), 0, MAX_ELAPSED_DAYS)
	var instability_days := _normalize_int(snapshot_value.get("instability_streak"), 0, MAX_ELAPSED_DAYS)
	var recovery_days := _normalize_int(snapshot_value.get("recovery_streak"), 0, MAX_ELAPSED_DAYS)
	var last_review := _normalize_int(snapshot_value.get("last_policy_review_period"), -1, MAX_ELAPSED_DAYS)
	if period < 0 or instability_days < 0 or recovery_days < 0 or last_review < -1 or last_review > period:
		return false
	if instability_days > period or recovery_days > period:
		return false
	if not _validate_capacity(snapshot_value.get("capacity")):
		return false
	if typeof(snapshot_value.get("forces")) != TYPE_ARRAY or typeof(snapshot_value.get("policies")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("active_policies")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("policy_history")) != TYPE_ARRAY or typeof(snapshot_value.get("government_change_history")) != TYPE_ARRAY:
		return false
	if typeof(snapshot_value.get("last_pressure_input")) != TYPE_DICTIONARY:
		return false
	if VNextPoliticsPressureInput.from_snapshot(snapshot_value.get("last_pressure_input") as Dictionary) == null:
		return false

	var force_ids: Dictionary = {}
	var leader_by_force: Dictionary = {}
	var government_force_found := false
	for raw_force: Variant in snapshot_value.get("forces") as Array:
		if typeof(raw_force) != TYPE_DICTIONARY:
			return false
		var force := raw_force as Dictionary
		if not _validate_force(force, period):
			return false
		var force_id := str(force.get("force_id", ""))
		if force_ids.has(force_id):
			return false
		force_ids[force_id] = true
		leader_by_force[force_id] = str(force.get("leader_id", ""))
		if force_id == str(snapshot_value.get("government_group_id", "")):
			government_force_found = true
	if not government_force_found:
		return false
	if str(leader_by_force.get(str(snapshot_value.get("government_group_id", "")), "")) != str(snapshot_value.get("government_leader_id", "")):
		return false

	var derived_support := _weighted_support_from_forces(_dictionary_array(snapshot_value.get("forces") as Array))
	if not is_equal_approx(derived_support, float(snapshot_value.get("government_support", 0.0))):
		return false
	var expected_viability := _derive_viability(
		derived_support,
		snapshot_value.get("capacity") as Dictionary,
		float(snapshot_value.get("legitimacy", 0.0)),
		float(snapshot_value.get("stability", 0.0))
	)
	if bool(snapshot_value.get("government_viability", false)) != expected_viability:
		return false

	var policy_ids: Dictionary = {}
	for raw_policy: Variant in snapshot_value.get("policies") as Array:
		if typeof(raw_policy) != TYPE_DICTIONARY:
			return false
		var policy := raw_policy as Dictionary
		if not _validate_policy(policy):
			return false
		var policy_id := str(policy.get("policy_id", ""))
		if policy_ids.has(policy_id):
			return false
		policy_ids[policy_id] = true

	var active_ids: Dictionary = {}
	for raw_active: Variant in snapshot_value.get("active_policies") as Array:
		if typeof(raw_active) != TYPE_DICTIONARY:
			return false
		var active := raw_active as Dictionary
		if active.size() != 5:
			return false
		for key: String in ["policy_id", "started_period", "implementation_strength", "last_review_period", "status"]:
			if not active.has(key):
				return false
		var active_id := str(active.get("policy_id", ""))
		if not policy_ids.has(active_id) or active_ids.has(active_id):
			return false
		var started := _normalize_int(active.get("started_period"), 0, period)
		var active_review := _normalize_int(active.get("last_review_period"), 0, period)
		if started < 0 or active_review < started or active_review > period:
			return false
		if not _in_range_number(active.get("implementation_strength"), 0.0, 1.0):
			return false
		if active.get("status") != "implementing":
			return false
		active_ids[active_id] = true
	if (snapshot_value.get("active_policies") as Array).size() > 6:
		return false

	if not _validate_policy_history(snapshot_value.get("policy_history") as Array, policy_ids, period):
		return false
	if not _validate_government_history(
		snapshot_value.get("government_change_history") as Array,
		force_ids,
		leader_by_force,
		period,
		str(snapshot_value.get("government_group_id", "")),
		str(snapshot_value.get("government_leader_id", ""))
	):
		return false
	return true


static func _validate_capacity(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var capacity_value := value as Dictionary
	if capacity_value.size() != CAPACITY_KEYS.size():
		return false
	for key: String in CAPACITY_KEYS:
		if not capacity_value.has(key) or not _in_range_number(capacity_value.get(key), 0.0, 100.0):
			return false
	return true


static func _validate_force(force: Dictionary, current_period: int) -> bool:
	if force.size() != 14:
		return false
	for required_field: String in [
		"force_id", "name", "kind", "leader_id", "influence",
		"government_support", "base_government_support", "institutional_access",
		"mobilization_capacity", "government_eligible", "policy_preferences",
		"pressure_response", "support_history", "last_support_delta",
	]:
		if not force.has(required_field):
			return false
	if not _valid_id(force.get("force_id"), "organization") or not _valid_id(force.get("leader_id"), "person"):
		return false
	for string_field: String in ["name", "kind"]:
		if typeof(force.get(string_field)) != TYPE_STRING or str(force.get(string_field)).is_empty():
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
	var history := force.get("support_history") as Array
	if history.size() > MAX_FORCE_HISTORY:
		return false
	for raw_record: Variant in history:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record := raw_record as Dictionary
		if record.size() != 3 or not record.has("period") or not record.has("support") or not record.has("delta"):
			return false
		var record_period := _normalize_int(record.get("period"), 0, current_period)
		if record_period < 0:
			return false
		if not _in_range_number(record.get("support"), -100.0, 100.0) or not _in_range_number(record.get("delta"), -200.0, 200.0):
			return false
	if not history.is_empty():
		var ordered := _sorted_dictionary_array(history)
		if not is_equal_approx(float(ordered.back().get("support", 0.0)), float(force.get("government_support", 0.0))):
			return false
	return _in_range_number(force.get("last_support_delta"), -200.0, 200.0)


static func _validate_policy(policy: Dictionary) -> bool:
	if policy.size() != 9:
		return false
	for required_field: String in [
		"policy_id", "name", "domain", "position", "fiscal_demand",
		"administrative_demand", "required_control", "pressure_targets", "political_relief",
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
	return _validate_preference_dictionary(policy.get("political_relief"), 0.0, 100.0, PRESSURE_SIGNAL_KEYS)


static func _validate_policy_history(history: Array, policy_ids: Dictionary, current_period: int) -> bool:
	if history.size() > MAX_POLICY_HISTORY:
		return false
	for raw_record: Variant in history:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record := raw_record as Dictionary
		if record.size() != 6:
			return false
		for key: String in ["period", "action", "policy_id", "replaced_policy_id", "political_pressure", "support_score"]:
			if not record.has(key):
				return false
		if _normalize_int(record.get("period"), 0, current_period) < 0 or record.get("action") != "adopted":
			return false
		var policy_id := str(record.get("policy_id", ""))
		var replaced_id := str(record.get("replaced_policy_id", ""))
		if not policy_ids.has(policy_id) or (not replaced_id.is_empty() and not policy_ids.has(replaced_id)):
			return false
		if not _in_range_number(record.get("political_pressure"), 0.0, 100.0):
			return false
		if not _in_range_number(record.get("support_score"), -1000.0, 1000.0):
			return false
	return true


static func _validate_government_history(
	history: Array,
	force_ids: Dictionary,
	leader_by_force: Dictionary,
	current_period: int,
	current_government_group_id: String,
	current_government_leader_id: String
) -> bool:
	if history.size() > MAX_GOVERNMENT_CHANGE_HISTORY:
		return false
	if history.is_empty():
		return true

	# Persistence validation must reject malformed raw variants before sorting can filter them.
	for raw_record: Variant in history:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false

	var ordered := _sorted_dictionary_array(history)
	var previous: Dictionary = {}
	var previous_period := -1
	for raw_record: Variant in ordered:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record := raw_record as Dictionary
		if record.size() != 10:
			return false
		for key: String in [
			"period", "reason", "old_government_group_id", "new_government_group_id",
			"old_leader_id", "new_leader_id", "political_pressure", "mandate_score",
			"procedure_score", "coalition_score",
		]:
			if not record.has(key):
				return false
		var record_period := _normalize_int(record.get("period"), 0, current_period)
		if record_period < 0 or record.get("reason") != "sustained_government_failure":
			return false
		var old_group := str(record.get("old_government_group_id", ""))
		var new_group := str(record.get("new_government_group_id", ""))
		var old_leader := str(record.get("old_leader_id", ""))
		var new_leader := str(record.get("new_leader_id", ""))
		if old_group == new_group or not force_ids.has(old_group) or not force_ids.has(new_group):
			return false
		if str(leader_by_force.get(old_group, "")) != old_leader:
			return false
		if str(leader_by_force.get(new_group, "")) != new_leader:
			return false
		for score_key: String in ["political_pressure", "mandate_score", "procedure_score", "coalition_score"]:
			if not _in_range_number(record.get(score_key), 0.0, 100.0):
				return false

		if not previous.is_empty():
			if record_period <= previous_period:
				return false
			if old_group != str(previous.get("new_government_group_id", "")):
				return false
			if old_leader != str(previous.get("new_leader_id", "")):
				return false
		previous = record
		previous_period = record_period

	var last := ordered.back() as Dictionary
	if str(last.get("new_government_group_id", "")) != current_government_group_id:
		return false
	if str(last.get("new_leader_id", "")) != current_government_leader_id:
		return false
	return true


static func _validate_preference_dictionary(value: Variant, minimum: float, maximum: float, allowed_keys: Array[String]) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for raw_key: Variant in (value as Dictionary).keys():
		var key := str(raw_key)
		if key not in allowed_keys or not _in_range_number((value as Dictionary).get(key), minimum, maximum):
			return false
	return true


static func _derive_viability(government_support: float, capacity_value: Dictionary, legitimacy_value: float, stability_value: float) -> bool:
	return (
		government_support >= VIABILITY_SUPPORT_THRESHOLD
		and float(capacity_value.get("control", 0.0)) >= VIABILITY_CONTROL_THRESHOLD
		and legitimacy_value >= VIABILITY_LEGITIMACY_THRESHOLD
		and stability_value >= VIABILITY_STABILITY_THRESHOLD
	)


static func _weighted_support_from_forces(forces: Array[Dictionary]) -> float:
	var ordered := _sorted_dictionary_array(forces)
	var total_influence := 0.0
	var weighted_support := 0.0
	for force: Dictionary in ordered:
		var influence := float(force.get("influence", 0.0))
		total_influence += influence
		weighted_support += influence * ((float(force.get("government_support", 0.0)) + 100.0) / 2.0)
	if total_influence <= 0.0:
		return 0.0
	return clampf(weighted_support / total_influence, 0.0, 100.0)


static func _valid_id(value: Variant, expected_kind: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var candidate := value as String
	return VNextStableId.is_valid(candidate) and VNextStableId.kind_of(candidate) == expected_kind


static func _in_range_number(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric >= minimum and numeric <= maximum


static func _normalize_int(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) == TYPE_INT:
		var integer_value := int(value)
		return integer_value if integer_value >= minimum and integer_value <= maximum else minimum - 1
	if typeof(value) != TYPE_FLOAT:
		return minimum - 1
	var float_value := float(value)
	if not is_finite(float_value) or float_value != floor(float_value):
		return minimum - 1
	var normalized := int(float_value)
	return normalized if normalized >= minimum and normalized <= maximum else minimum - 1


static func _canonicalize_snapshot(snapshot_value: Dictionary) -> Dictionary:
	var result := snapshot_value.duplicate(true)
	result["forces"] = _sorted_dictionary_array(result.get("forces", []) as Array)
	var forces: Array = result.get("forces", []) as Array
	for index: int in range(forces.size()):
		var force := (forces[index] as Dictionary).duplicate(true)
		force["support_history"] = _sorted_dictionary_array(force.get("support_history", []) as Array)
		forces[index] = force
	result["forces"] = forces
	result["policies"] = _sorted_dictionary_array(result.get("policies", []) as Array)
	result["active_policies"] = _sorted_dictionary_array(result.get("active_policies", []) as Array)
	result["policy_history"] = _sorted_dictionary_array(result.get("policy_history", []) as Array)
	result["government_change_history"] = _sorted_dictionary_array(result.get("government_change_history", []) as Array)
	return result


static func _dictionary_array(raw_array: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_value: Variant in raw_array:
		if typeof(raw_value) == TYPE_DICTIONARY:
			result.append(raw_value as Dictionary)
	return result


static func _sorted_dictionary_array(raw_array: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_value: Variant in raw_array:
		if typeof(raw_value) == TYPE_DICTIONARY:
			result.append((raw_value as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _dictionary_record_less(left, right)
	)
	return result


static func _dictionary_record_less(left: Dictionary, right: Dictionary) -> bool:
	var left_has_period := left.has("period")
	var right_has_period := right.has("period")
	if left_has_period != right_has_period:
		return left_has_period
	if left_has_period:
		var left_period := int(left.get("period", 0))
		var right_period := int(right.get("period", 0))
		if left_period != right_period:
			return left_period < right_period
	for key: String in [
		"force_id", "policy_id", "old_government_group_id", "new_government_group_id",
		"old_leader_id", "new_leader_id", "replaced_policy_id", "action", "reason",
	]:
		var left_text := str(left.get(key, ""))
		var right_text := str(right.get(key, ""))
		if left_text != right_text:
			return left_text < right_text
	for key: String in [
		"support", "delta", "political_pressure", "mandate_score",
		"procedure_score", "coalition_score", "support_score",
	]:
		var left_number := float(left.get(key, 0.0))
		var right_number := float(right.get(key, 0.0))
		if left_number != right_number:
			return left_number < right_number
	return false
