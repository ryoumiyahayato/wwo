extends SceneTree
## Read-only timing probe for the full Alpha three-year simulation.
##
## Every override delegates exactly once to the existing implementation and only
## records elapsed microseconds and call counts after the call returns.

const YEARS: int = 3
const HOURS: int = YEARS * 365 * 24
const DAYS: int = YEARS * 365
const EXPECTED_RANDOM_SEED: int = 1_001_900
const EXPECTED_WORLD_SUMMARY: Dictionary = {
	"active_shock_count": 0,
	"commodity_count": 67,
	"employed": 3_126_243,
	"fulfillment_bp": 183,
	"household_consumed_units": 171.845730907564,
	"household_demand_units": 9409.548393021,
	"international_export_units": 0.0,
	"international_import_units": 0.0,
	"labor_force": 4_025_290,
	"luxury_commodity_count": 7,
	"population": 8_930_000,
	"production_site_count": 49,
	"region_count": 8,
	"unemployed": 899_047,
	"unemployment_bp": 2233,
	"unmet_units": 9237.70266211344,
}

var test := AlphaTestCase.new()


class ProfileRecorder:
	extends RefCounted

	var calls: Dictionary = {}
	var elapsed_usec: Dictionary = {}


	func record(stage: String, started_usec: int) -> void:
		calls[stage] = int(calls.get(stage, 0)) + 1
		elapsed_usec[stage] = (
			int(elapsed_usec.get(stage, 0))
			+ Time.get_ticks_usec() - started_usec
		)


	func report() -> Dictionary:
		return {
			"calls": calls.duplicate(true),
			"elapsed_usec": elapsed_usec.duplicate(true),
		}


class ProfiledCommodityMarket:
	extends AlphaCommodityMarketService

	var recorder := ProfileRecorder.new()


	func settle_day(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super.settle_day(total_hour)
		recorder.record("commodity_market_settle_day", started_usec)
		return result


	func _apply_spoilage() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._apply_spoilage()
		recorder.record("commodity_apply_spoilage", started_usec)


	func _reset_local_services() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._reset_local_services()
		recorder.record("commodity_reset_local_services", started_usec)


	func _run_production(total_hour: int) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._run_production(total_hour)
		recorder.record("commodity_run_production", started_usec)


	func _run_local_consumption() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._run_local_consumption()
		recorder.record("commodity_run_local_consumption", started_usec)


	func _enforce_all_warehouse_capacity() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._enforce_all_warehouse_capacity()
		recorder.record("commodity_enforce_warehouse_capacity", started_usec)


	func _update_prices() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._update_prices()
		recorder.record("commodity_update_prices", started_usec)


	func _update_employment() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._update_employment()
		recorder.record("commodity_update_employment", started_usec)


class ProfiledEconomyIntegration:
	extends AlphaEconomyIntegrationService

	var recorder := ProfileRecorder.new()


	func deliver_due_shipments(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super.deliver_due_shipments(total_hour)
		recorder.record("deliver_due_shipments", started_usec)
		return result


	func settle_day(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super.settle_day(total_hour)
		recorder.record("economy_integration_settle_day", started_usec)
		return result


	func _reset_daily_limits() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._reset_daily_limits()
		recorder.record("integration_reset_daily_limits", started_usec)


	func _settle_household_consumption(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super._settle_household_consumption(
			total_hour
		)
		recorder.record("integration_household_consumption", started_usec)
		return result


	func _settle_enterprises(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super._settle_enterprises(total_hour)
		recorder.record("integration_enterprises", started_usec)
		return result


	func _schedule_shortage_shipments(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super._schedule_shortage_shipments(total_hour)
		recorder.record("integration_schedule_shipments", started_usec)
		return result


	func _settle_government_procurement(total_hour: int) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super._settle_government_procurement(
			total_hour
		)
		recorder.record("integration_government_procurement", started_usec)
		return result


	func _adjust_exchange_rates() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._adjust_exchange_rates()
		recorder.record("integration_adjust_exchange_rates", started_usec)


	func _sync_labor_market() -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._sync_labor_market()
		recorder.record("integration_sync_labor_market", started_usec)


class ProfiledWorldDynamics:
	extends AlphaWorldDynamicsService

	var recorder := ProfileRecorder.new()


	func process_boundaries(
		total_hour: int, active_characters: Dictionary
	) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super.process_boundaries(
			total_hour, active_characters
		)
		recorder.record("world_dynamics_process_boundaries", started_usec)
		return result


class ProfiledAlphaAi:
	extends AlphaAiService

	var recorder := ProfileRecorder.new()


	func process_person_day(
		character: CharacterData, known: Dictionary, total_hour: int
	) -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super.process_person_day(
			character, known, total_hour
		)
		recorder.record("alpha_ai_process_person_day", started_usec)
		return result


class ProfiledAlphaSimulation:
	extends AlphaSimulationService

	var recorder := ProfileRecorder.new()


	func _settle_hour(total_hour: int) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._settle_hour(total_hour)
		recorder.record("settle_hour_total", started_usec)


	func _legacy_cash_snapshot() -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super._legacy_cash_snapshot()
		recorder.record("legacy_cash_snapshot", started_usec)
		return result


	func _reconcile_legacy_cash(before: Dictionary, total_hour: int) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._reconcile_legacy_cash(before, total_hour)
		recorder.record("legacy_cash_reconcile", started_usec)


	func _capture_economy_day_state() -> Dictionary:
		var started_usec: int = Time.get_ticks_usec()
		var result: Dictionary = super._capture_economy_day_state()
		recorder.record("economy_day_snapshot", started_usec)
		return result


	func _process_active_ai(total_hour: int) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._process_active_ai(total_hour)
		recorder.record("active_ai", started_usec)


	func _settle_due_development(total_hour: int) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._settle_due_development(total_hour)
		recorder.record("development_settlement", started_usec)


	func _process_background_hour(total_hour: int) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._process_background_hour(total_hour)
		recorder.record("background_people_hour", started_usec)


	func _plan_life_needs(start_hour: int, reason: String) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._plan_life_needs(start_hour, reason)
		recorder.record("plan_life_needs", started_usec)


	func _replace_fixed_commutes(start_hour: int, reason: String) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._replace_fixed_commutes(start_hour, reason)
		recorder.record("replace_fixed_commutes", started_usec)


	func _apply_activity_location(
		person_id: String, activity: Dictionary, total_hour: int
	) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._apply_activity_location(person_id, activity, total_hour)
		recorder.record("active_activity_location", started_usec)


	func _record_employment_hour(
		person_id: String,
		total_hour: int,
		activity_type: String,
		activity: Dictionary,
		condition_rules: Dictionary
	) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._record_employment_hour(
			person_id, total_hour, activity_type, activity, condition_rules
		)
		recorder.record("active_employment_hour", started_usec)


	func _apply_activity_condition(
		person_id: String,
		activity_type: String,
		activity: Dictionary,
		total_hour: int
	) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._apply_activity_condition(
			person_id, activity_type, activity, total_hour
		)
		recorder.record("active_activity_condition", started_usec)


	func _complete_activity(
		person_id: String, activity: Dictionary, total_hour: int
	) -> void:
		var started_usec: int = Time.get_ticks_usec()
		super._complete_activity(person_id, activity, total_hour)
		recorder.record("active_activity_completion", started_usec)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var process_started_usec: int = Time.get_ticks_usec()
	var simulation := ProfiledAlphaSimulation.new()
	var commodity_market := ProfiledCommodityMarket.new()
	var economy_integration := ProfiledEconomyIntegration.new()
	var world_dynamics := ProfiledWorldDynamics.new()
	var alpha_ai := ProfiledAlphaAi.new()
	simulation.commodity_market = commodity_market
	simulation.economy_integration = economy_integration
	simulation.world_dynamics = world_dynamics
	simulation.alpha_ai = alpha_ai

	var initialize_started_usec: int = Time.get_ticks_usec()
	var initialized: bool = simulation.initialize()
	var initialize_usec: int = Time.get_ticks_usec() - initialize_started_usec
	test.expect(initialized, "profiled Alpha simulation initializes")
	test.equal(
		simulation.random.get_seed(),
		EXPECTED_RANDOM_SEED,
		"Alpha fixture uses the expected deterministic random seed"
	)

	var advance_started_usec: int = Time.get_ticks_usec()
	simulation.advance_hours(HOURS)
	var advance_usec: int = Time.get_ticks_usec() - advance_started_usec
	test.equal(
		simulation.alpha_hours_processed,
		HOURS,
		"profile covers every hour in the three-year simulation"
	)
	test.equal(
		simulation.recorder.calls.get("settle_hour_total", 0),
		HOURS,
		"hour timing wrapper records every simulated hour"
	)
	test.equal(
		simulation.recorder.calls.get("economy_day_snapshot", 0),
		DAYS,
		"daily rollback snapshot timing records every simulated day"
	)
	test.equal(
		commodity_market.recorder.calls.get(
			"commodity_market_settle_day", 0
		),
		DAYS,
		"commodity timing records every daily settlement"
	)
	test.equal(
		economy_integration.recorder.calls.get(
			"economy_integration_settle_day", 0
		),
		DAYS,
		"integration timing records every daily settlement"
	)

	var summary: Dictionary = simulation.commodity_market.world_summary()
	var expected_summary_difference: Dictionary = _first_difference(
		EXPECTED_WORLD_SUMMARY, summary, "$.world_summary", 0.000000001
	)
	if not expected_summary_difference.is_empty():
		print(
			"ALPHA_PROFILE_SUMMARY_FIRST_DIFFERENCE=%s"
			% JSON.stringify(expected_summary_difference)
		)
	test.expect(
		expected_summary_difference.is_empty(),
		"timing wrappers preserve the established three-year world summary"
	)
	test.expect(
		bool(simulation.validate_alpha_integrity().get("success", false)),
		"profiled three-year state remains internally valid"
	)
	test.expect(
		bool(simulation.commodity_market.validate_integrity().get(
			"success", false
		)),
		"profiled commodity state remains internally valid"
	)

	var state_capture_started_usec: int = Time.get_ticks_usec()
	var state: Dictionary = simulation.get_alpha_persistent_state()
	var state_capture_usec: int = (
		Time.get_ticks_usec() - state_capture_started_usec
	)
	var serialize_started_usec: int = Time.get_ticks_usec()
	var serialized_state: String = JSON.stringify(state)
	var serialize_usec: int = Time.get_ticks_usec() - serialize_started_usec
	var state_hash: String = serialized_state.sha256_text()
	var expected_restored_state: Dictionary = state.duplicate(true)

	var restored := AlphaSimulationService.new()
	var restore_initialize_started_usec: int = Time.get_ticks_usec()
	var restored_initialized: bool = restored.initialize()
	var restore_initialize_usec: int = (
		Time.get_ticks_usec() - restore_initialize_started_usec
	)
	test.expect(restored_initialized, "restore target initializes")
	var restore_started_usec: int = Time.get_ticks_usec()
	var restore_result: V2LifeLoopResult = restored.restore_alpha_state(state)
	var restore_usec: int = Time.get_ticks_usec() - restore_started_usec
	test.expect(restore_result.success, "three-year state restores successfully")

	var restored_capture_started_usec: int = Time.get_ticks_usec()
	var restored_state: Dictionary = restored.get_alpha_persistent_state()
	var restored_capture_usec: int = (
		Time.get_ticks_usec() - restored_capture_started_usec
	)
	var restored_serialize_started_usec: int = Time.get_ticks_usec()
	var restored_serialized_state: String = JSON.stringify(restored_state)
	var restored_serialize_usec: int = (
		Time.get_ticks_usec() - restored_serialize_started_usec
	)
	var restored_state_hash: String = restored_serialized_state.sha256_text()
	var state_difference: Dictionary = _first_difference(
		expected_restored_state, restored_state, "$"
	)
	var normalized_source_json: String = JSON.stringify(
		_normalized_state(expected_restored_state)
	)
	var normalized_restored_json: String = JSON.stringify(
		_normalized_state(restored_state)
	)
	if not state_difference.is_empty():
		print(
			"ALPHA_PROFILE_STATE_FIRST_DIFFERENCE=%s"
			% JSON.stringify(state_difference)
		)
	test.expect(
		normalized_source_json == normalized_restored_json,
		"save and restore preserve the normalized deterministic state"
	)
	test.equal(
		restored_serialized_state.to_utf8_buffer().size(),
		serialized_state.to_utf8_buffer().size(),
		"save and restored state have equal serialized byte counts"
	)
	var restored_summary_difference: Dictionary = _first_difference(
		summary,
		restored.commodity_market.world_summary(),
		"$.world_summary"
	)
	test.expect(
		restored_summary_difference.is_empty(),
		"save and restore preserve the exact world summary"
	)

	var direct_stage_usec: int = 0
	for stage: String in [
		"legacy_cash_snapshot",
		"legacy_cash_reconcile",
		"economy_day_snapshot",
		"active_ai",
		"development_settlement",
		"background_people_hour",
		"plan_life_needs",
		"replace_fixed_commutes",
		"active_activity_location",
		"active_employment_hour",
		"active_activity_condition",
		"active_activity_completion",
	]:
		direct_stage_usec += int(simulation.recorder.elapsed_usec.get(stage, 0))
	direct_stage_usec += int(commodity_market.recorder.elapsed_usec.get(
		"commodity_market_settle_day", 0
	))
	direct_stage_usec += int(economy_integration.recorder.elapsed_usec.get(
		"deliver_due_shipments", 0
	))
	direct_stage_usec += int(economy_integration.recorder.elapsed_usec.get(
		"economy_integration_settle_day", 0
	))
	direct_stage_usec += int(world_dynamics.recorder.elapsed_usec.get(
		"world_dynamics_process_boundaries", 0
	))
	var settle_hour_total_usec: int = int(
		simulation.recorder.elapsed_usec.get("settle_hour_total", 0)
	)
	var report: Dictionary = {
		"fixture": {
			"years": YEARS,
			"hours": HOURS,
			"days": DAYS,
			"random_seed": simulation.random.get_seed(),
			"preset_id": simulation.launch_preset_id,
		},
		"timing_usec": {
			"process_total": Time.get_ticks_usec() - process_started_usec,
			"initialize": initialize_usec,
			"advance_hours": advance_usec,
			"settle_hour_total": settle_hour_total_usec,
			"settle_hour_unattributed": maxi(
				0, settle_hour_total_usec - direct_stage_usec
			),
			"state_capture": state_capture_usec,
			"state_serialize": serialize_usec,
			"restore_initialize": restore_initialize_usec,
			"restore_apply": restore_usec,
			"restored_state_capture": restored_capture_usec,
			"restored_state_serialize": restored_serialize_usec,
		},
		"simulation": simulation.recorder.report(),
		"commodity_market": commodity_market.recorder.report(),
		"economy_integration": economy_integration.recorder.report(),
		"world_dynamics": world_dynamics.recorder.report(),
		"alpha_ai": alpha_ai.recorder.report(),
		"state": {
			"serialized_bytes": serialized_state.to_utf8_buffer().size(),
			"sha256": state_hash,
			"restored_sha256": restored_state_hash,
			"normalized_sha256": normalized_source_json.sha256_text(),
			"normalized_restored_sha256": (
				normalized_restored_json.sha256_text()
			),
			"first_difference": state_difference,
		},
		"world_summary": summary,
	}
	print("ALPHA_THREE_YEAR_STAGE_PROFILE=%s" % JSON.stringify(report))
	test.finish(self, "Alpha three-year stage profile")


func _first_difference(
	expected: Variant,
	actual: Variant,
	path: String,
	float_epsilon: float = 0.0
) -> Dictionary:
	if typeof(expected) != typeof(actual):
		return _difference(path, expected, actual, "type")
	match typeof(expected):
		TYPE_DICTIONARY:
			var expected_dictionary: Dictionary = expected as Dictionary
			var actual_dictionary: Dictionary = actual as Dictionary
			if expected_dictionary.size() != actual_dictionary.size():
				return _difference(
					path,
					expected_dictionary.size(),
					actual_dictionary.size(),
					"dictionary_size"
				)
			for key: Variant in expected_dictionary:
				if not actual_dictionary.has(key):
					return _difference(
						"%s.%s" % [path, str(key)],
						expected_dictionary[key],
						null,
						"missing_key"
					)
				var nested: Dictionary = _first_difference(
					expected_dictionary[key],
					actual_dictionary[key],
					"%s.%s" % [path, str(key)],
					float_epsilon
				)
				if not nested.is_empty():
					return nested
		TYPE_ARRAY:
			var expected_array: Array = expected as Array
			var actual_array: Array = actual as Array
			if expected_array.size() != actual_array.size():
				return _difference(
					path,
					expected_array.size(),
					actual_array.size(),
					"array_size"
				)
			for index: int in range(expected_array.size()):
				var nested: Dictionary = _first_difference(
					expected_array[index],
					actual_array[index],
					"%s[%d]" % [path, index],
					float_epsilon
				)
				if not nested.is_empty():
					return nested
		_:
			if (
				typeof(expected) == TYPE_FLOAT
				and absf(float(expected) - float(actual)) <= float_epsilon
			):
				return {}
			if expected != actual:
				return _difference(path, expected, actual, "value")
	return {}


func _difference(
	path: String, expected: Variant, actual: Variant, reason: String
) -> Dictionary:
	return {
		"path": path,
		"reason": reason,
		"expected_type": typeof(expected),
		"actual_type": typeof(actual),
		"expected": expected,
		"actual": actual,
	}


func _normalized_state(value: Variant, key_name: String = "") -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value as Dictionary
			var normalized: Dictionary = {}
			for key: Variant in source:
				var normalized_key: String = str(key)
				if normalized_key == "alpha_maximum_hour_usec":
					continue
				normalized[normalized_key] = _normalized_state(
					source[key], normalized_key
				)
			return normalized
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item: Variant in value as Array:
				normalized_array.append(_normalized_state(item))
			if key_name == "processed_keys":
				normalized_array.sort()
			return normalized_array
		_:
			return value
