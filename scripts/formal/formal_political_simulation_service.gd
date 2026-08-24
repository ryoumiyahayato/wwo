class_name FormalPoliticalSimulationService
extends RefCounted
## Daily, deterministic political evolution for every formal historical polity.
## Inputs are restricted to the formal polity registry, completed economy results,
## and this service's persisted history. Politics affects the following economy day.

const SCHEMA_ID: String = "formal_political_simulation_v2"
const LEGACY_SCHEMA_ID: String = "formal_political_simulation_v1"
const BASIS_POINTS: int = 10000
const HISTORY_LIMIT: int = 512
const DAYS_PER_YEAR: int = 365
const PHASES: Array[String] = [
	"stable", "strained", "crisis", "transition_possible", "reconstituting",
]

var polity_states: Dictionary = {}
var transition_history: Array[Dictionary] = []
var phase_history: Array[Dictionary] = []
var historical_boundary_history: Array[Dictionary] = []
var initialization_error: String = ""
var _polity_records: Dictionary = {}
var _historically_active_ids: Dictionary = {}
var _authority_catalog_fingerprint: String = ""
var _last_day_index: int = -1


func configure(inputs: Dictionary, initial_day_index: int = 0) -> bool:
	initialization_error = ""
	polity_states.clear()
	transition_history.clear()
	phase_history.clear()
	historical_boundary_history.clear()
	_historically_active_ids.clear()
	var authority := inputs.get("authority", {}) as Dictionary
	_polity_records = (authority.get("records", {}) as Dictionary).duplicate(true)
	var polity_economy_links := inputs.get("polity_economy_links", {}) as Dictionary
	var active_ids := _id_set(authority.get("active_ids", []))
	var introduced_ids := _id_set(authority.get("introduced_ids", []))
	var catalog_identity := authority.get("catalog_identity", {}) as Dictionary
	_authority_catalog_fingerprint = str(
		catalog_identity.get("fingerprint", "")
	)
	_last_day_index = initial_day_index
	if (
		_polity_records.is_empty()
		or active_ids.is_empty()
		or introduced_ids.is_empty()
		or _authority_catalog_fingerprint.is_empty()
		or int(authority.get("day_index", -1)) != initial_day_index
		or initial_day_index < 0
	):
		return _fail("正式政治模拟缺少政治单元目录")
	for polity_id: String in _sorted_keys(_polity_records):
		var record := _polity_records[polity_id] as Dictionary
		if str(record.get("entity_id", record.get("id", ""))) != polity_id:
			return _fail("正式政治单元ID无效：%s" % polity_id)
		record["economy_entity_id"] = str(
			polity_economy_links.get(polity_id, "")
		)
		_polity_records[polity_id] = record
	for polity_id: String in _sorted_keys(active_ids):
		_historically_active_ids[polity_id] = true
	for polity_id: String in _sorted_keys(introduced_ids):
		if not _polity_records.has(polity_id):
			return _fail("正式政治权威引用未知政治单元：%s" % polity_id)
		polity_states[polity_id] = _initial_state(
			_polity_records[polity_id] as Dictionary,
			initial_day_index
		)
		if not _historically_active_ids.has(polity_id):
			var state := polity_states[polity_id] as Dictionary
			state["historical_evidence_status"] = "expired_continuation"
			state["simulation_lineage"] = "emergent_continuation"
			state["historical_expiration_day"] = _historical_expiration_day(
				_polity_records[polity_id] as Dictionary
			)
			state["authority_origin"] = "historical_inheritance"
			polity_states[polity_id] = state
	var initial_states := polity_states.duplicate(true)
	for polity_id: String in _sorted_keys(polity_states):
		var state := polity_states[polity_id] as Dictionary
		state["authority_actors"] = _authority_actors(
			state, initial_states, _profile_for(state)
		)
		polity_states[polity_id] = state
	return _validate_candidate(
		polity_states,
		transition_history,
		_last_day_index,
		_historically_active_ids,
		introduced_ids
	)


func settle_day(day_index: int, inputs: Dictionary) -> bool:
	if day_index <= _last_day_index:
		return true
	if day_index != _last_day_index + 1:
		return false
	var economies := inputs.get("economies", {}) as Dictionary
	var authority := inputs.get("authority", {}) as Dictionary
	var boundary := _synchronize_authority(authority, day_index)
	if not bool(boundary.get("success", false)):
		return false
	var previous_states := boundary.get("states", {}) as Dictionary
	var candidate_active_ids := boundary.get("active_ids", {}) as Dictionary
	var candidate_introduced_ids := boundary.get("introduced_ids", {}) as Dictionary
	var candidate := previous_states.duplicate(true)
	var day_transitions: Array[Dictionary] = []
	var day_phase_changes: Array[Dictionary] = []
	for polity_id: String in _sorted_keys(previous_states):
		var previous := previous_states[polity_id] as Dictionary
		var record := _polity_records[polity_id] as Dictionary
		var economy_id := str(record.get("economy_entity_id", ""))
		var observation := _economic_observation(
			economies.get(economy_id, {}) as Dictionary,
			previous
		)
		var result := _advance_polity(
			previous, previous_states, observation, day_index
		)
		var next_state := result.get("state", {}) as Dictionary
		candidate[polity_id] = next_state
		var previous_phase := str(previous.get("phase", "stable"))
		var next_phase := str(next_state.get("phase", "stable"))
		if previous_phase != next_phase:
			day_phase_changes.append({
				"polity_id": polity_id,
				"day_index": day_index,
				"from_phase": previous_phase,
				"to_phase": next_phase,
				"legitimacy_bp": int(next_state.get("legitimacy_bp", 0)),
				"administrative_capacity_bp": int(
					next_state.get("administrative_capacity_bp", 0)
				),
				"reform_pressure_bp": int(
					next_state.get("reform_pressure_bp", 0)
				),
				"crisis_pressure_bp": int(
					next_state.get("crisis_pressure_bp", 0)
				),
			})
		var transition := result.get("transition", {}) as Dictionary
		if not transition.is_empty():
			day_transitions.append(transition)
	var candidate_history := transition_history.duplicate(true)
	for transition: Dictionary in day_transitions:
		candidate_history.append(transition)
	while candidate_history.size() > HISTORY_LIMIT:
		candidate_history.pop_front()
	var candidate_phase_history := phase_history.duplicate(true)
	for phase_change: Dictionary in day_phase_changes:
		candidate_phase_history.append(phase_change)
	while candidate_phase_history.size() > HISTORY_LIMIT:
		candidate_phase_history.pop_front()
	var candidate_boundary_history := historical_boundary_history.duplicate(true)
	for event: Dictionary in DataRecordUtils.to_dictionary_array(
		boundary.get("events", [])
	):
		candidate_boundary_history.append(event)
	while candidate_boundary_history.size() > HISTORY_LIMIT:
		candidate_boundary_history.pop_front()
	if (
			not _validate_candidate(
				candidate,
				candidate_history,
				day_index,
				candidate_active_ids,
				candidate_introduced_ids
			)
		or not _validate_phase_history(
			candidate_phase_history, candidate, day_index
		)
		or not _validate_boundary_history(
			candidate_boundary_history, candidate, day_index
		)
	):
		return false
	polity_states = candidate
	transition_history = candidate_history
	phase_history = candidate_phase_history
	historical_boundary_history = candidate_boundary_history
	_historically_active_ids = candidate_active_ids
	_last_day_index = day_index
	return true


func _synchronize_authority(authority: Dictionary, day_index: int) -> Dictionary:
	var catalog_identity := authority.get("catalog_identity", {}) as Dictionary
	if (
		int(authority.get("day_index", -1)) != day_index
		or str(catalog_identity.get("fingerprint", "")) != (
			_authority_catalog_fingerprint
		)
		or not authority.get("active_ids", []) is Array
		or not authority.get("introduced_ids", []) is Array
	):
		return {"success": false}
	var next_active_ids := _id_set(authority.get("active_ids", []))
	var introduced_ids := _id_set(authority.get("introduced_ids", []))
	if next_active_ids.is_empty() or introduced_ids.is_empty():
		return {"success": false}
	for polity_id: String in _sorted_keys(introduced_ids):
		if not _polity_records.has(polity_id):
			return {"success": false}
	for polity_id: String in _sorted_keys(next_active_ids):
		if not introduced_ids.has(polity_id):
			return {"success": false}
	var states := polity_states.duplicate(true)
	var events: Array[Dictionary] = []
	for polity_id: String in _sorted_keys(next_active_ids):
		if states.has(polity_id):
			var existing := states[polity_id] as Dictionary
			existing["historical_evidence_status"] = "valid"
			states[polity_id] = existing
			continue
		var record := _polity_records[polity_id] as Dictionary
		states[polity_id] = _initial_state(record, day_index)
		events.append({
			"event_type": "historical_activation",
			"polity_id": polity_id,
			"day_index": day_index,
			"date": str(authority.get("date", "")),
			"valid_from": str(record.get("valid_from", "")),
			"source_path": str(
				(catalog_identity.get("source_path", ""))
			),
		})
	for polity_id: String in _sorted_keys(states):
		if next_active_ids.has(polity_id):
			continue
		var state := states[polity_id] as Dictionary
		if str(state.get("historical_evidence_status", "")) == "valid":
			var record := _polity_records[polity_id] as Dictionary
			state["historical_evidence_status"] = "expired_continuation"
			state["simulation_lineage"] = "emergent_continuation"
			state["historical_expiration_day"] = day_index
			if str(state.get("authority_origin", "")) == "historical_evidence":
				state["authority_origin"] = "historical_inheritance"
			events.append({
				"event_type": "historical_expiration",
				"polity_id": polity_id,
				"day_index": day_index,
				"date": str(authority.get("date", "")),
				"valid_to": str(record.get("valid_to", "")),
				"continuation": true,
				"source_path": str(
					catalog_identity.get("source_path", "")
				),
			})
		states[polity_id] = state
	if _sorted_keys(states) != _sorted_keys(introduced_ids):
		return {"success": false}
	var reference_states := states.duplicate(true)
	for polity_id: String in _sorted_keys(states):
		var state := states[polity_id] as Dictionary
		state["authority_actors"] = _authority_actors(
			state, reference_states, _profile_for(state)
		)
		states[polity_id] = state
	return {
		"success": true,
		"states": states,
		"active_ids": next_active_ids,
		"introduced_ids": introduced_ids,
		"events": events,
	}


func world_summary() -> Dictionary:
	var phase_counts: Dictionary = {}
	var legitimacy_total := 0
	var stability_total := 0
	var capacity_total := 0
	var transition_total := 0
	for raw_state: Variant in polity_states.values():
		var state := raw_state as Dictionary
		var phase := str(state.get("phase", "stable"))
		phase_counts[phase] = int(phase_counts.get(phase, 0)) + 1
		legitimacy_total += int(state.get("legitimacy_bp", 0))
		stability_total += int(state.get("stability_bp", 0))
		capacity_total += int(state.get("administrative_capacity_bp", 0))
		transition_total += int(state.get("transition_count", 0))
	var count := maxi(1, polity_states.size())
	return {
		"political_polity_count": polity_states.size(),
		"political_last_day_index": _last_day_index,
		"political_phase_counts": phase_counts,
		"average_legitimacy_bp": legitimacy_total / count,
		"average_stability_bp": stability_total / count,
		"average_administrative_capacity_bp": capacity_total / count,
		"institutional_transition_count": transition_total,
		"recorded_phase_change_count": phase_history.size(),
		"historically_valid_political_unit_count": (
			_historically_active_ids.size()
		),
		"recorded_historical_boundary_count": historical_boundary_history.size(),
	}


func polity_summary(polity_id: String) -> Dictionary:
	return (polity_states.get(polity_id, {}) as Dictionary).duplicate(true)


func simulated_polity_ids() -> Array[String]:
	return _sorted_keys(polity_states)


func economy_modifiers() -> Dictionary:
	var weighted: Dictionary = {}
	for polity_id: String in _sorted_keys(polity_states):
		var record := _polity_records[polity_id] as Dictionary
		var economy_id := str(record.get("economy_entity_id", ""))
		if economy_id.is_empty():
			continue
		var state := polity_states[polity_id] as Dictionary
		var area := maxf(1.0, float(record.get("area_km2", 1.0)))
		var administration := int(
			state.get("administrative_capacity_bp", 6000)
		)
		var stability := int(state.get("stability_bp", 6000))
		var efficiency := clampi(
			10000
				+ (administration - 6000) * 18 / 100
				+ (stability - 6000) * 12 / 100,
			FormalWorldEconomyService.MIN_POLITICAL_PRODUCTION_EFFICIENCY_BP,
			FormalWorldEconomyService.MAX_POLITICAL_PRODUCTION_EFFICIENCY_BP
		)
		var row := weighted.get(economy_id, {
			"weighted_efficiency": 0.0,
			"area": 0.0,
		}) as Dictionary
		row["weighted_efficiency"] = float(
			row.get("weighted_efficiency", 0.0)
		) + float(efficiency) * area
		row["area"] = float(row.get("area", 0.0)) + area
		weighted[economy_id] = row
	var result: Dictionary = {}
	for economy_id: String in _sorted_keys(weighted):
		var row := weighted[economy_id] as Dictionary
		result[economy_id] = {
			"production_efficiency_bp": int(round(
				float(row.get("weighted_efficiency", 0.0))
				/ maxf(1.0, float(row.get("area", 1.0)))
			)),
		}
	return result


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"last_day_index": _last_day_index,
		"polity_states": polity_states.duplicate(true),
		"transition_history": transition_history.duplicate(true),
		"phase_history": phase_history.duplicate(true),
		"historical_boundary_history": historical_boundary_history.duplicate(true),
		"authority_catalog_fingerprint": _authority_catalog_fingerprint,
	}


func restore_persistent_state(state: Dictionary, authority: Dictionary) -> bool:
	var schema_id := str(state.get("schema_id", ""))
	var catalog_identity := authority.get("catalog_identity", {}) as Dictionary
	if (
		schema_id not in [LEGACY_SCHEMA_ID, SCHEMA_ID]
		or not state.get("polity_states", {}) is Dictionary
		or not state.get("transition_history", []) is Array
		or not state.get("phase_history", []) is Array
		or not authority.get("active_ids", []) is Array
		or not authority.get("introduced_ids", []) is Array
		or str(catalog_identity.get("fingerprint", "")) != (
			_authority_catalog_fingerprint
		)
		or (
			schema_id == SCHEMA_ID
			and (
				not state.get("historical_boundary_history", []) is Array
				or str(state.get("authority_catalog_fingerprint", "")) != (
					_authority_catalog_fingerprint
				)
			)
		)
	):
		return false
	var day_index := int(state.get("last_day_index", -2))
	if int(authority.get("day_index", -1)) != day_index:
		return false
	var expected_active := _id_set(authority.get("active_ids", []))
	var expected_introduced := _id_set(authority.get("introduced_ids", []))
	var candidate := (state.get("polity_states", {}) as Dictionary).duplicate(true)
	if schema_id == LEGACY_SCHEMA_ID:
		candidate = _migrate_legacy_candidate(
			candidate, expected_active, expected_introduced
		)
		if candidate.is_empty():
			return false
	var history := DataRecordUtils.to_dictionary_array(
		state.get("transition_history", [])
	)
	var restored_phase_history := DataRecordUtils.to_dictionary_array(
		state.get("phase_history", [])
	)
	if schema_id == LEGACY_SCHEMA_ID:
		history = _history_for_candidate(history, candidate)
		restored_phase_history = _history_for_candidate(
			restored_phase_history, candidate
		)
	var restored_boundary_history := DataRecordUtils.to_dictionary_array(
		state.get("historical_boundary_history", [])
	)
	if not _validate_candidate(
		candidate,
		history,
		day_index,
		expected_active,
		expected_introduced
	):
		return false
	if not _validate_phase_history(restored_phase_history, candidate, day_index):
		return false
	if not _validate_boundary_history(
		restored_boundary_history, candidate, day_index
	):
		return false
	polity_states = candidate
	transition_history = history
	phase_history = restored_phase_history
	historical_boundary_history = restored_boundary_history
	_historically_active_ids = expected_active
	_last_day_index = day_index
	return true


func _migrate_legacy_candidate(
	source: Dictionary,
	historically_active_ids: Dictionary,
	introduced_ids: Dictionary
) -> Dictionary:
	if introduced_ids.is_empty():
		return {}
	var migrated: Dictionary = {}
	for polity_id: String in _sorted_keys(introduced_ids):
		if not source.get(polity_id, {}) is Dictionary:
			return {}
		var state := (source[polity_id] as Dictionary).duplicate(true)
		var record := _polity_records[polity_id] as Dictionary
		var profile := _relationship_profile(
			str(record.get("relationship", "independent_state")),
			str(record.get("status", "sovereign"))
		)
		var historically_valid := historically_active_ids.has(polity_id)
		state.erase("controller_id")
		state["historical_controller_id"] = str(record.get("controller_id", ""))
		state["effective_controller_id"] = str(record.get("controller_id", ""))
		state["local_autonomy_bp"] = int(profile.get("autonomy_bp", BASIS_POINTS))
		state["controller_access_bp"] = int(
			profile.get("controller_access_bp", 0)
		)
		state["historical_evidence_status"] = (
			"valid" if historically_valid else "expired_continuation"
		)
		state["simulation_lineage"] = (
			"historically_activated"
			if historically_valid
			else "emergent_continuation"
		)
		state["historical_activation_day"] = _historical_activation_day(record)
		state["historical_expiration_day"] = (
			-1 if historically_valid else _historical_expiration_day(record)
		)
		state["authority_origin"] = (
			"historical_evidence"
			if historically_valid
			else "historical_inheritance"
		)
		migrated[polity_id] = state
	var reference_states := migrated.duplicate(true)
	for polity_id: String in _sorted_keys(migrated):
		var state := migrated[polity_id] as Dictionary
		state["authority_actors"] = _authority_actors(
			state, reference_states, _profile_for(state)
		)
		migrated[polity_id] = state
	return migrated


func _history_for_candidate(
	history: Array[Dictionary], candidate: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in history:
		if candidate.has(str(record.get("polity_id", ""))):
			result.append(record)
	return result


func _initial_state(record: Dictionary, initial_day_index: int) -> Dictionary:
	var relationship := str(record.get("relationship", "independent_state"))
	var status := str(record.get("status", "sovereign"))
	var profile := _relationship_profile(relationship, status)
	var inherited_days := _continuity_days_at(
		str(record.get("valid_from", "1900-01-01")),
		initial_day_index
	)
	var continuity := inherited_days
	var continuity_score := _continuity_score(continuity, 0)
	var institution := clampi(
		int(profile.get("institution_base_bp", 5000))
			+ maxi(0, continuity_score - 5000) / 5,
		1500,
		9000
	)
	var authority_coverage := maxi(
		int(profile.get("autonomy_bp", 10000)),
		int(profile.get("controller_access_bp", 0))
	)
	var administration := _harmonic_mean([
		institution, authority_coverage, 6500,
	])
	var legitimacy := clampi(
		_harmonic_mean([institution, 6000, continuity_score]), 2500, 8000
	)
	var stability := _harmonic_mean([administration, institution, legitimacy])
	return {
		"polity_id": str(record.get("entity_id", record.get("id", ""))),
		"historical_controller_id": str(record.get("controller_id", "")),
		"effective_controller_id": str(record.get("controller_id", "")),
		"authority_origin": "historical_evidence",
		"local_autonomy_bp": int(profile.get("autonomy_bp", BASIS_POINTS)),
		"controller_access_bp": int(profile.get("controller_access_bp", 0)),
		"relationship": relationship,
		"status": status,
		"historical_evidence_status": "valid",
		"simulation_lineage": "historically_activated",
		"historical_activation_day": _historical_activation_day(record),
		"historical_expiration_day": -1,
		"last_settlement_day": initial_day_index,
		"legitimacy_bp": legitimacy,
		"administrative_capacity_bp": administration,
		"institutional_strength_bp": institution,
		"stability_bp": stability,
		"hardship_pressure_bp": 0,
		"reform_pressure_bp": 0,
		"resistance_pressure_bp": 0,
		"crisis_pressure_bp": 0,
		"transition_readiness_bp": 0,
		"mobilized_resistance_power_bp": 0,
		"phase": "stable",
		"phase_persistence_days": 0,
		"strain_days": 0,
		"crisis_days": 0,
		"readiness_days": 0,
		"recovery_days": 0,
		"continuity_days": continuity,
		"transition_count": 0,
		"last_transition_day": -1,
		"previous_price_index": 0,
		"authority_actors": [],
		"drivers": {
			"economic_observation_available": false,
			"inherited_continuity_days": inherited_days,
			"autonomy_bp": int(profile.get("autonomy_bp", 10000)),
			"controller_access_bp": int(profile.get("controller_access_bp", 0)),
		},
	}


func _advance_polity(
	previous: Dictionary,
	previous_states: Dictionary,
	observation: Dictionary,
	day_index: int
) -> Dictionary:
	var state := previous.duplicate(true)
	var profile := _profile_for(state)
	var fulfillment := int(observation.get("fulfillment_bp", BASIS_POINTS))
	var shortage := BASIS_POINTS - fulfillment
	var price_pressure := int(observation.get("price_pressure_bp", 0))
	var hardship_target := clampi(shortage * 3 / 4 + price_pressure / 4, 0, BASIS_POINTS)
	var hardship := _approach(
		int(previous.get("hardship_pressure_bp", 0)),
		hardship_target,
		14 if hardship_target > int(previous.get("hardship_pressure_bp", 0)) else 60
	)
	var continuity_days := int(previous.get("continuity_days", 0)) + 1
	var transition_count := int(previous.get("transition_count", 0))
	var continuity_score := _continuity_score(continuity_days, transition_count)
	var previous_crisis := int(previous.get("crisis_pressure_bp", 0))
	var institution_target := clampi(
		int(profile.get("institution_base_bp", 5000))
			+ maxi(0, continuity_score - 5000) / 4
			+ (int(previous.get("legitimacy_bp", 5000)) - 5000) / 10
			- previous_crisis / 5,
		1000,
		9500
	)
	var institution := _approach(
		int(previous.get("institutional_strength_bp", 5000)),
		institution_target,
		720
	)
	var authority_coverage := _absolute_authority_coverage(previous)
	var delivery_capacity := (
		fulfillment
		if bool(observation.get("available", false))
		else int(previous.get("administrative_capacity_bp", 5000))
	)
	var administration_target := clampi(
		_harmonic_mean([institution, delivery_capacity, authority_coverage])
			- previous_crisis / 4,
		800,
		9500
	)
	var previous_administration := int(
		previous.get("administrative_capacity_bp", 5000)
	)
	var administration := _approach(
		previous_administration,
		administration_target,
		90 if administration_target < previous_administration else 240
	)
	var performance := _geometric_mean([
		delivery_capacity, administration, institution,
	])
	var institutional_floor := mini(administration, institution)
	var authority_mismatch := _controller_share(previous) * (
		BASIS_POINTS - int(profile.get("autonomy_bp", BASIS_POINTS))
	) / BASIS_POINTS
	var legitimacy_target := clampi(
		performance * 55 / 100
			+ institutional_floor * 25 / 100
			+ continuity_score * 20 / 100
			- hardship * 35 / 100
			- authority_mismatch * 15 / 100,
		500,
		9500
	)
	var previous_legitimacy := int(previous.get("legitimacy_bp", 5000))
	var legitimacy := _approach(
		previous_legitimacy,
		legitimacy_target,
		90 if legitimacy_target < previous_legitimacy else 240
	)
	state["legitimacy_bp"] = legitimacy
	state["administrative_capacity_bp"] = administration
	state["institutional_strength_bp"] = institution
	state["hardship_pressure_bp"] = hardship
	state["continuity_days"] = continuity_days
	state["authority_actors"] = _authority_actors(
		state, previous_states, profile
	)
	var controller_share := _controller_share(state)
	var grievance := clampi((6500 - legitimacy) * 2 + hardship / 2, 0, BASIS_POINTS)
	var institutional_viability := _geometric_mean([administration, institution])
	var reform_target := grievance * institutional_viability / BASIS_POINTS
	var resistance_target := clampi(
		grievance * (5000 + controller_share / 2) / BASIS_POINTS
			+ hardship / 4,
		0,
		BASIS_POINTS
	)
	var reform := _approach(
		int(previous.get("reform_pressure_bp", 0)), reform_target, 45
	)
	var resistance := _approach(
		int(previous.get("resistance_pressure_bp", 0)), resistance_target, 30
	)
	var weakness := BASIS_POINTS - _harmonic_mean([
		legitimacy, administration, institution,
	])
	var crisis_target := _geometric_mean([
		maxi(1, resistance), maxi(1, grievance), maxi(1, weakness),
	])
	var crisis := _approach(
		previous_crisis,
		crisis_target,
		30 if crisis_target > previous_crisis else 120
	)
	var transition_capacity := maxi(institutional_viability, reform)
	var structural_pressure := maxi(reform, crisis)
	var readiness_target := _geometric_mean([
		maxi(1, structural_pressure),
		maxi(1, resistance),
		maxi(1, transition_capacity),
	])
	var readiness := _approach(
		int(previous.get("transition_readiness_bp", 0)),
		readiness_target,
		60 if readiness_target > int(previous.get("transition_readiness_bp", 0)) else 180
	)
	state["reform_pressure_bp"] = reform
	state["resistance_pressure_bp"] = resistance
	state["crisis_pressure_bp"] = crisis
	state["transition_readiness_bp"] = readiness
	state["mobilized_resistance_power_bp"] = resistance * (
		BASIS_POINTS - legitimacy / 2
	) / BASIS_POINTS
	_update_persistence(state, previous)
	var transition := _maybe_transition(state, day_index)
	if not transition.is_empty():
		state["authority_actors"] = _authority_actors(
			state, previous_states, profile
		)
	var stability_target := clampi(
		_harmonic_mean([legitimacy, administration, institution])
			- crisis * 35 / 100
			- resistance * 15 / 100,
		0,
		BASIS_POINTS
	)
	state["stability_bp"] = _approach(
		int(previous.get("stability_bp", 5000)), stability_target, 45
	)
	state["last_settlement_day"] = day_index
	state["previous_price_index"] = int(observation.get("price_index", 0))
	state["drivers"] = {
		"economic_observation_available": bool(observation.get("available", false)),
		"fulfillment_bp": fulfillment,
		"shortage_bp": shortage,
		"price_pressure_bp": price_pressure,
		"hardship_target_bp": hardship_target,
		"continuity_score_bp": continuity_score,
		"institution_target_bp": institution_target,
		"administration_target_bp": administration_target,
		"delivery_capacity_bp": delivery_capacity,
		"performance_bottleneck_bp": performance,
		"authority_mismatch_bp": authority_mismatch,
		"legitimacy_target_bp": legitimacy_target,
		"grievance_bp": grievance,
		"reform_target_bp": reform_target,
		"resistance_target_bp": resistance_target,
		"crisis_target_bp": crisis_target,
		"readiness_target_bp": readiness_target,
		"stability_target_bp": stability_target,
	}
	return {"state": state, "transition": transition}


func _update_persistence(state: Dictionary, previous: Dictionary) -> void:
	var strain_signal := maxi(
		int(state.get("reform_pressure_bp", 0)),
		int(state.get("resistance_pressure_bp", 0))
	)
	var strain_days := (
		int(previous.get("strain_days", 0)) + 1
		if strain_signal >= 4200 else maxi(0, int(previous.get("strain_days", 0)) - 1)
	)
	var crisis_condition := (
		int(state.get("crisis_pressure_bp", 0)) >= 6000
		and int(state.get("legitimacy_bp", 0)) < 4800
		and int(state.get("administrative_capacity_bp", 0)) < 6500
	)
	var crisis_days := (
		int(previous.get("crisis_days", 0)) + 1
		if crisis_condition else maxi(0, int(previous.get("crisis_days", 0)) - 1)
	)
	var readiness_condition := (
		int(state.get("transition_readiness_bp", 0)) >= 6200
		and int(state.get("institutional_strength_bp", 0)) >= 3000
		and (crisis_days >= 45 or int(state.get("reform_pressure_bp", 0)) >= 6800)
	)
	var readiness_days := (
		int(previous.get("readiness_days", 0)) + 1
		if readiness_condition else maxi(0, int(previous.get("readiness_days", 0)) - 2)
	)
	var recovering := (
		strain_signal < 3000
		and int(state.get("crisis_pressure_bp", 0)) < 3000
		and int(state.get("legitimacy_bp", 0)) >= 5000
	)
	var recovery_days := (
		int(previous.get("recovery_days", 0)) + 1 if recovering else 0
	)
	var previous_phase := str(previous.get("phase", "stable"))
	var phase := previous_phase
	if readiness_days >= 60:
		phase = "transition_possible"
	elif crisis_days >= 45:
		phase = "crisis"
	elif (
		strain_days >= 30
		and (
			previous_phase == "stable"
			or (previous_phase == "crisis" and crisis_days == 0)
			or (previous_phase == "transition_possible" and readiness_days == 0)
		)
	):
		phase = "strained"
	elif recovery_days >= 60:
		phase = "stable"
	elif previous_phase == "reconstituting" and recovery_days >= 30:
		phase = "strained"
	state["strain_days"] = strain_days
	state["crisis_days"] = crisis_days
	state["readiness_days"] = readiness_days
	state["recovery_days"] = recovery_days
	state["phase"] = phase
	state["phase_persistence_days"] = (
		int(previous.get("phase_persistence_days", 0)) + 1
		if phase == previous_phase else 1
	)


func _maybe_transition(state: Dictionary, day_index: int) -> Dictionary:
	var last_transition := int(state.get("last_transition_day", -1))
	var cooldown_complete := (
		last_transition < 0 or day_index - last_transition >= 5 * DAYS_PER_YEAR
	)
	if (
		str(state.get("phase", "")) != "transition_possible"
		or int(state.get("readiness_days", 0)) < 180
		or int(state.get("transition_readiness_bp", 0)) < 7200
		or not cooldown_complete
	):
		return {}
	var reform := int(state.get("reform_pressure_bp", 0))
	var resistance := int(state.get("resistance_pressure_bp", 0))
	var crisis := int(state.get("crisis_pressure_bp", 0))
	var trigger_legitimacy := int(state.get("legitimacy_bp", 0))
	var trigger_administration := int(
		state.get("administrative_capacity_bp", 0)
	)
	var previous_effective_controller := str(
		state.get("effective_controller_id", "")
	)
	var previous_local_autonomy := int(state.get("local_autonomy_bp", 0))
	var previous_controller_access := int(
		state.get("controller_access_bp", 0)
	)
	var mode := "institutional_reform" if reform >= crisis else "authority_realignment"
	state["transition_count"] = int(state.get("transition_count", 0)) + 1
	state["last_transition_day"] = day_index
	state["continuity_days"] = 0
	state["phase"] = "reconstituting"
	state["phase_persistence_days"] = 1
	state["readiness_days"] = 0
	state["transition_readiness_bp"] = int(
		state.get("transition_readiness_bp", 0)
	) * 45 / 100
	if mode == "institutional_reform":
		state["institutional_strength_bp"] = clampi(
			int(state.get("institutional_strength_bp", 0)) + 350, 0, BASIS_POINTS
		)
		state["legitimacy_bp"] = clampi(
			int(state.get("legitimacy_bp", 0)) + 250, 0, BASIS_POINTS
		)
		state["reform_pressure_bp"] = reform * 55 / 100
		state["resistance_pressure_bp"] = int(
			state.get("resistance_pressure_bp", 0)
		) * 75 / 100
	else:
		var authority_shift := clampi(
			(resistance + crisis - reform) / 8,
			300,
			1200
		)
		state["local_autonomy_bp"] = clampi(
			previous_local_autonomy + authority_shift,
			0,
			BASIS_POINTS
		)
		state["controller_access_bp"] = clampi(
			previous_controller_access - authority_shift,
			0,
			BASIS_POINTS
		)
		var local_share := BASIS_POINTS - _controller_share(state)
		if (
			not previous_effective_controller.is_empty()
			and int(state.get("controller_access_bp", 0)) <= 1500
			and local_share >= 6000
		):
			state["effective_controller_id"] = ""
		state["authority_origin"] = "simulation_realign"
		state["simulation_lineage"] = "emergent_transition"
		state["institutional_strength_bp"] = clampi(
			int(state.get("institutional_strength_bp", 0)) - 500, 0, BASIS_POINTS
		)
		state["legitimacy_bp"] = clampi(
			int(state.get("legitimacy_bp", 0)) - 300, 0, BASIS_POINTS
		)
		state["crisis_pressure_bp"] = crisis * 75 / 100
	return {
		"polity_id": str(state.get("polity_id", "")),
		"day_index": day_index,
		"transition_mode": mode,
		"trigger_legitimacy_bp": trigger_legitimacy,
		"trigger_administrative_capacity_bp": trigger_administration,
		"trigger_reform_pressure_bp": reform,
		"trigger_crisis_pressure_bp": crisis,
		"previous_effective_controller_id": previous_effective_controller,
		"effective_controller_id": str(
			state.get("effective_controller_id", "")
		),
		"previous_local_autonomy_bp": previous_local_autonomy,
		"local_autonomy_bp": int(state.get("local_autonomy_bp", 0)),
		"previous_controller_access_bp": previous_controller_access,
		"controller_access_bp": int(state.get("controller_access_bp", 0)),
	}


func _economic_observation(economy: Dictionary, previous: Dictionary) -> Dictionary:
	var totals := economy.get("daily_totals", {}) as Dictionary
	var available := (
		not economy.is_empty()
		and not totals.is_empty()
		and int(economy.get("last_settlement_hour", 0)) > 0
	)
	var fulfillment := int(totals.get("fulfillment_bp", BASIS_POINTS))
	var prices := economy.get("prices", {}) as Dictionary
	var price_index := 0
	if not prices.is_empty():
		for raw_price: Variant in prices.values():
			price_index += int(raw_price)
		price_index /= prices.size()
	var previous_price := int(previous.get("previous_price_index", 0))
	var price_pressure := 0
	if available and previous_price > 0 and price_index > previous_price:
		price_pressure = clampi(
			(price_index - previous_price) * BASIS_POINTS / previous_price,
			0,
			4000
		)
	return {
		"available": available,
		"fulfillment_bp": clampi(fulfillment, 0, BASIS_POINTS),
		"price_index": price_index,
		"price_pressure_bp": price_pressure,
	}


func _authority_actors(
	state: Dictionary, reference_states: Dictionary, profile: Dictionary
) -> Array[Dictionary]:
	var polity_id := str(state.get("polity_id", ""))
	var autonomy := int(state.get(
		"local_autonomy_bp", profile.get("autonomy_bp", BASIS_POINTS)
	))
	var local_base := _geometric_mean([
		int(state.get("legitimacy_bp", 0)),
		int(state.get("administrative_capacity_bp", 0)),
		int(state.get("institutional_strength_bp", 0)),
	])
	var local_power := local_base * (3500 + autonomy * 65 / 100) / BASIS_POINTS
	var actors: Array[Dictionary] = [{
		"actor_id": "local:%s" % polity_id,
		"actor_type": "local_institutions",
		"authority_entity_id": polity_id,
		"absolute_power_bp": clampi(local_power, 0, BASIS_POINTS),
		"influence_share_bp": BASIS_POINTS,
	}]
	var controller_id := str(state.get("effective_controller_id", ""))
	var controller_access := int(state.get(
		"controller_access_bp", profile.get("controller_access_bp", 0)
	))
	if not controller_id.is_empty() and controller_access > 0:
		var controller := reference_states.get(controller_id, {}) as Dictionary
		var controller_strength := 5000
		if not controller.is_empty():
			controller_strength = _geometric_mean([
				int(controller.get("legitimacy_bp", 5000)),
				int(controller.get("administrative_capacity_bp", 5000)),
				int(controller.get("stability_bp", 5000)),
			])
		var controller_power := controller_strength * controller_access / BASIS_POINTS
		actors.append({
			"actor_id": "controller:%s" % controller_id,
			"actor_type": "controller_authority",
			"authority_entity_id": controller_id,
			"absolute_power_bp": clampi(controller_power, 0, BASIS_POINTS),
			"influence_share_bp": 0,
		})
	var total_power := 0
	for actor: Dictionary in actors:
		total_power += int(actor.get("absolute_power_bp", 0))
	var remaining_share := BASIS_POINTS
	for index: int in range(actors.size()):
		var actor := actors[index]
		var share := (
			BASIS_POINTS / actors.size()
			if total_power <= 0
			else int(actor.get("absolute_power_bp", 0)) * BASIS_POINTS / total_power
		)
		if index == actors.size() - 1:
			share = remaining_share
		else:
			share = mini(remaining_share, share)
			remaining_share -= share
		actor["influence_share_bp"] = share
		actors[index] = actor
	return actors


func _absolute_authority_coverage(state: Dictionary) -> int:
	var combined_failure := BASIS_POINTS
	for actor: Dictionary in DataRecordUtils.to_dictionary_array(
		state.get("authority_actors", [])
	):
		var power := clampi(int(actor.get("absolute_power_bp", 0)), 0, BASIS_POINTS)
		combined_failure = combined_failure * (BASIS_POINTS - power) / BASIS_POINTS
	return clampi(BASIS_POINTS - combined_failure, 1000, BASIS_POINTS)


func _controller_share(state: Dictionary) -> int:
	for actor: Dictionary in DataRecordUtils.to_dictionary_array(
		state.get("authority_actors", [])
	):
		if str(actor.get("actor_type", "")) == "controller_authority":
			return int(actor.get("influence_share_bp", 0))
	return 0


func _profile_for(state: Dictionary) -> Dictionary:
	var result := _relationship_profile(
		str(state.get("relationship", "independent_state")),
		str(state.get("status", "sovereign"))
	)
	result["autonomy_bp"] = int(state.get(
		"local_autonomy_bp", result.get("autonomy_bp", BASIS_POINTS)
	))
	result["controller_access_bp"] = int(state.get(
		"controller_access_bp", result.get("controller_access_bp", 0)
	))
	return result


func _relationship_profile(relationship: String, status: String) -> Dictionary:
	var result := {
		"autonomy_bp": 10000,
		"controller_access_bp": 0,
		"institution_base_bp": 6100,
	}
	match relationship:
		"belligerent_state":
			result = {"autonomy_bp": 8500, "controller_access_bp": 0, "institution_base_bp": 3800}
		"self_governing_dominion":
			result = {"autonomy_bp": 8200, "controller_access_bp": 2800, "institution_base_bp": 6500}
		"protected_state":
			result = {"autonomy_bp": 6500, "controller_access_bp": 4800, "institution_base_bp": 5500}
		"protected_territory":
			result = {"autonomy_bp": 4200, "controller_access_bp": 6800, "institution_base_bp": 4700}
		"crown_colony":
			result = {"autonomy_bp": 2600, "controller_access_bp": 8600, "institution_base_bp": 5500}
		"military_occupation":
			result = {"autonomy_bp": 1600, "controller_access_bp": 9400, "institution_base_bp": 3300}
		"administered_territory":
			result = {"autonomy_bp": 2600, "controller_access_bp": 8400, "institution_base_bp": 4600}
		"dual_control":
			result = {"autonomy_bp": 3500, "controller_access_bp": 7000, "institution_base_bp": 4300}
		"controlled_territory":
			result = {"autonomy_bp": 2800, "controller_access_bp": 8500, "institution_base_bp": 4800}
	if status == "occupied":
		result["autonomy_bp"] = mini(int(result.get("autonomy_bp", 0)), 2200)
		result["institution_base_bp"] = mini(
			int(result.get("institution_base_bp", 0)), 3900
		)
	elif status == "contested":
		result["institution_base_bp"] = mini(
			int(result.get("institution_base_bp", 0)), 4200
		)
	return result


func _continuity_score(days: int, transition_count: int) -> int:
	var years := maxf(0.0, float(days) / float(DAYS_PER_YEAR))
	var saturation := int(round(8500.0 * (1.0 - exp(-years / 12.0))))
	return clampi(1500 + saturation - mini(2500, transition_count * 350), 500, 9500)


func _continuity_days_at(valid_from: String, day_index: int) -> int:
	var parts := valid_from.split("-")
	if parts.size() != 3:
		return 0
	var year := int(parts[0])
	var month := clampi(int(parts[1]), 1, 12)
	var day := clampi(
		int(parts[2]), 1, V2DateTime.days_in_month(year, month)
	)
	var valid_day := V2DateTime.absolute_day_index(year, month, day)
	var scenario_day := V2DateTime.absolute_day_index(1900, 1, 1) + day_index
	return maxi(0, scenario_day - valid_day)


func _approach(current: int, target: int, time_constant_days: int) -> int:
	if current == target:
		return current
	var delta := target - current
	var step := maxi(
		1, ceili(float(absi(delta)) / float(maxi(1, time_constant_days)))
	)
	var direction := 1 if delta > 0 else -1
	return clampi(current + direction * step, 0, BASIS_POINTS)


func _harmonic_mean(values: Array[int]) -> int:
	var reciprocal_sum := 0.0
	for value: int in values:
		reciprocal_sum += 1.0 / maxf(1.0, float(value))
	return clampi(int(round(float(values.size()) / reciprocal_sum)), 0, BASIS_POINTS)


func _geometric_mean(values: Array[int]) -> int:
	var log_sum := 0.0
	for value: int in values:
		log_sum += log(maxf(1.0, float(value)))
	return clampi(int(round(exp(log_sum / float(values.size())))), 0, BASIS_POINTS)


func _validate_candidate(
	candidate: Dictionary,
	history: Array[Dictionary],
	day_index: int,
	historically_active_ids: Dictionary,
	introduced_ids: Dictionary
) -> bool:
	if (
		candidate.size() != introduced_ids.size()
		or day_index < 0
	):
		return false
	for polity_id: String in _sorted_keys(historically_active_ids):
		if not introduced_ids.has(polity_id):
			return false
	for polity_id: String in _sorted_keys(candidate):
		if not introduced_ids.has(polity_id) or not _polity_records.has(polity_id):
			return false
		if not candidate.get(polity_id, {}) is Dictionary:
			return false
		var state := candidate[polity_id] as Dictionary
		var record := _polity_records[polity_id] as Dictionary
		var last_transition_day := int(state.get("last_transition_day", -2))
		var historically_valid := historically_active_ids.has(polity_id)
		var evidence_status := str(
			state.get("historical_evidence_status", "")
		)
		var effective_controller := str(
			state.get("effective_controller_id", "")
		)
		if (
			str(state.get("polity_id", "")) != polity_id
			or str(state.get("historical_controller_id", "")) != str(
				record.get("controller_id", "")
			)
			or (
				not effective_controller.is_empty()
				and effective_controller != str(
					record.get("controller_id", "")
				)
			)
			or str(state.get("relationship", "")) != str(
				record.get("relationship", "")
			)
			or str(state.get("status", "")) != str(record.get("status", ""))
			or evidence_status != (
				"valid" if historically_valid else "expired_continuation"
			)
			or int(state.get("historical_activation_day", -1)) != (
				_historical_activation_day(record)
			)
			or int(state.get("historical_expiration_day", -2)) != (
				-1 if historically_valid else _historical_expiration_day(record)
			)
			or str(state.get("authority_origin", "")) not in [
				"historical_evidence",
				"historical_inheritance",
				"simulation_realign",
			]
			or (
				str(state.get("authority_origin", "")) == "historical_evidence"
				and not historically_valid
			)
			or (
				effective_controller != str(record.get("controller_id", ""))
				and str(state.get("authority_origin", "")) != "simulation_realign"
			)
			or str(state.get("simulation_lineage", "")) not in [
				"historically_activated",
				"emergent_continuation",
				"emergent_transition",
			]
			or str(state.get("phase", "")) not in PHASES
			or int(state.get("last_settlement_day", -2)) != day_index
			or int(state.get("continuity_days", -1)) < 0
			or int(state.get("transition_count", -1)) < 0
			or last_transition_day < -1
			or last_transition_day > day_index
			or not state.get("drivers", {}) is Dictionary
		):
			return false
		for authority_field: String in [
			"local_autonomy_bp", "controller_access_bp",
		]:
			var authority_value := int(state.get(authority_field, -1))
			if authority_value < 0 or authority_value > BASIS_POINTS:
				return false
		for counter: String in [
			"phase_persistence_days", "strain_days", "crisis_days",
			"readiness_days", "recovery_days",
		]:
			if int(state.get(counter, -1)) < 0:
				return false
		for field: String in [
			"legitimacy_bp", "administrative_capacity_bp",
			"institutional_strength_bp", "stability_bp",
			"hardship_pressure_bp", "reform_pressure_bp",
			"resistance_pressure_bp", "crisis_pressure_bp",
			"transition_readiness_bp", "mobilized_resistance_power_bp",
		]:
			var value := int(state.get(field, -1))
			if value < 0 or value > BASIS_POINTS:
				return false
		var actors := DataRecordUtils.to_dictionary_array(
			state.get("authority_actors", [])
		)
		if actors.is_empty():
			return false
		var actor_ids: Dictionary = {}
		var influence_total := 0
		var local_count := 0
		var controller_count := 0
		for actor: Dictionary in actors:
			var actor_id := str(actor.get("actor_id", ""))
			var actor_type := str(actor.get("actor_type", ""))
			if (
				actor_id.is_empty()
				or actor_ids.has(actor_id)
				or int(actor.get("absolute_power_bp", -1)) < 0
				or int(actor.get("absolute_power_bp", -1)) > BASIS_POINTS
				or int(actor.get("influence_share_bp", -1)) < 0
				or int(actor.get("influence_share_bp", -1)) > BASIS_POINTS
			):
				return false
			actor_ids[actor_id] = true
			influence_total += int(actor.get("influence_share_bp", 0))
			if actor_type == "local_institutions":
				local_count += 1
				if str(actor.get("authority_entity_id", "")) != polity_id:
					return false
			elif actor_type == "controller_authority":
				controller_count += 1
				if str(actor.get("authority_entity_id", "")) != str(
					state.get("effective_controller_id", "")
				):
					return false
			else:
				return false
		var expected_controller_count := (
			1
			if (
				not effective_controller.is_empty()
				and int(_profile_for(state).get("controller_access_bp", 0)) > 0
			)
			else 0
		)
		if (
			local_count != 1
			or controller_count != expected_controller_count
			or influence_total != BASIS_POINTS
		):
			return false
	if history.size() > HISTORY_LIMIT:
		return false
	for transition: Dictionary in history:
		if (
			not candidate.has(str(transition.get("polity_id", "")))
			or int(transition.get("day_index", -1)) < 0
			or int(transition.get("day_index", -1)) > day_index
			or str(transition.get("transition_mode", "")) not in [
				"institutional_reform", "authority_realignment",
			]
		):
			return false
	return true


func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in dictionary:
		result.append(str(raw_key))
	result.sort()
	return result


func _id_set(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	for entity_id: String in DataRecordUtils.to_string_array(value):
		result[entity_id] = true
	return result


func _validate_phase_history(
	history: Array[Dictionary], candidate: Dictionary, day_index: int
) -> bool:
	if history.size() > HISTORY_LIMIT:
		return false
	for record: Dictionary in history:
		if (
			not candidate.has(str(record.get("polity_id", "")))
			or int(record.get("day_index", -1)) < 0
			or int(record.get("day_index", -1)) > day_index
			or str(record.get("from_phase", "")) not in PHASES
			or str(record.get("to_phase", "")) not in PHASES
			or str(record.get("from_phase", "")) == str(record.get("to_phase", ""))
		):
			return false
	return true


func _validate_boundary_history(
	history: Array[Dictionary], candidate: Dictionary, day_index: int
) -> bool:
	if history.size() > HISTORY_LIMIT:
		return false
	for record: Dictionary in history:
		var polity_id := str(record.get("polity_id", ""))
		var event_type := str(record.get("event_type", ""))
		if (
			not candidate.has(polity_id)
			or int(record.get("day_index", -1)) < 0
			or int(record.get("day_index", -1)) > day_index
			or event_type not in [
				"historical_activation", "historical_expiration",
			]
		):
			return false
	return true


func _historical_activation_day(record: Dictionary) -> int:
	return maxi(0, int(record.get("valid_from_day_index", -1)))


func _historical_expiration_day(record: Dictionary) -> int:
	return int(record.get("expiration_day_index", -1))


func _fail(message: String) -> bool:
	initialization_error = message
	return false
