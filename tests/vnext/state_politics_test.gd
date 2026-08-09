extends SceneTree

const GENERATOR = preload("res://tests/vnext/politics_variable_state_generator.gd")
const FIXTURE_PATH: String = "res://data/vnext/politics/state_politics_1900.json"

var checks: int = 0
var failures: int = 0
var service := VNextPoliticsUpdateService.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_fixture_and_identity_contract()
	_test_pressure_input_json_round_trip()
	_test_state_json_round_trip_and_transactional_restore()
	_test_policies_and_external_pressure()
	_test_ten_year_normal_run()
	_test_severe_pressure_crisis_and_recovery()
	print("VNext state politics: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_fixture_and_identity_contract() -> void:
	var state := _load_fixture()
	_check(state != null, "1900 political fixture creates a valid state")
	if state == null:
		return
	_check(state.is_valid(), "political state satisfies its complete invariant")
	_equal(state.state_id(), "state:loran_federation", "state uses a canonical state ID")
	_equal(state.regime_type(), "federal_republic", "state exposes the regime type")
	_equal(state.government_id(), "organization:loran_government", "state exposes the governing institution")
	_equal(state.government_group_id(), "organization:loran_government_group", "state exposes the governing group")
	_equal(state.government_leader_id(), "person:loran_premier", "state exposes the government leader")
	_check(VNextStableId.is_valid("state:loran_federation"), "state IDs are accepted by the shared stable ID contract")
	_check(VNextStableId.is_valid("policy:loran_labor_relief"), "policy IDs are accepted by the shared stable ID contract")
	_check(state.supporting_force_ids().has("organization:loran_government_group"), "the government group is initially a supporting force")
	_check(state.political_forces().size() >= 7, "state models several organized political forces")
	_check(state.active_policy_ids().has("policy:loran_balanced_budget"), "state starts with an executing policy")
	_check(state.government_is_viable(), "initial government is viable")


func _test_pressure_input_json_round_trip() -> void:
	var source := VNextPoliticsPressureInput.create(
		30, 61.0, 72.0, 44.0, 38.0, -12.0, 70.0, 32.0, 55.0, -20.0
	)
	_check(source != null and source.is_valid(), "pressure input accepts bounded economic and war signals")
	if source == null:
		return
	var parser := JSON.new()
	_check(parser.parse(JSON.stringify(source.snapshot())) == OK, "pressure input snapshot is JSON serializable")
	var restored := VNextPoliticsPressureInput.from_snapshot(parser.data as Dictionary)
	_check(restored != null and restored.is_valid(), "pressure input restores after JSON round trip")
	if restored != null:
		_equal(restored.snapshot(), source.snapshot(), "pressure input JSON round trip preserves all signals")
	_check(
		VNextPoliticsPressureInput.create(0) == null,
		"zero-length political update is rejected"
	)
	_check(
		VNextPoliticsPressureInput.create(30, 101.0) == null,
		"out-of-range economic pressure is rejected"
	)


func _test_state_json_round_trip_and_transactional_restore() -> void:
	var source := _load_fixture()
	if source == null:
		return
	var snapshot: Dictionary = source.snapshot()
	var parser := JSON.new()
	_check(parser.parse(JSON.stringify(snapshot)) == OK, "state snapshot is JSON serializable")
	var restored := VNextStatePolitics.new()
	_check(restored.restore(parser.data as Dictionary), "fresh state restores a complete JSON snapshot")
	if restored.is_valid():
		var difference: String = _first_semantic_difference(restored.snapshot(), snapshot)
		if not difference.is_empty():
			print("JSON_DIFFERENCE=" + difference)
		_check(difference.is_empty(), "state JSON round trip preserves political structure")
	var before: Dictionary = restored.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid["government_leader_id"] = "organization:not_a_person"
	_check(not restored.restore(invalid), "invalid state restore is rejected")
	_equal(restored.snapshot(), before, "rejected state restore does not mutate the current state")
	var missing: Dictionary = before.duplicate(true)
	missing.erase("forces")
	_check(not restored.restore(missing), "incomplete state restore is rejected")
	_equal(restored.snapshot(), before, "incomplete restore leaves state unchanged")


func _test_policies_and_external_pressure() -> void:
	var state := _load_fixture()
	if state == null:
		return
	var before_support: float = state.government_support()
	var before_stability: float = state.stability()
	var changed_policy: bool = false
	var high_unemployment := VNextPoliticsPressureInput.create(
		30, 68.0, 92.0, 58.0, 45.0, -35.0
	)
	for period: int in range(8):
		var result: Dictionary = service.update(state, high_unemployment)
		_check(bool(result.get("success", false)), "political update succeeds under economic pressure %d" % period)
		if not bool(result.get("success", false)):
			return
		if not (result.get("policy_changes", []) as Array).is_empty():
			changed_policy = true

	_check(state.government_support() < before_support, "economic pressure changes government support")
	_check(state.stability() < before_stability, "economic pressure changes political stability")
	_check(
		state.active_policy_ids().has("policy:loran_labor_relief")
		or state.active_policy_ids().has("policy:loran_social_spending"),
		"economic pressure selects a labor or social relief policy"
	)
	_check(state.opposing_force_ids().size() > 0, "pressure can create visible organized opposition")

	var war_state := _load_fixture()
	if war_state == null:
		return
	var war_input := VNextPoliticsPressureInput.create(
		30, 10.0, 12.0, 55.0, 22.0, -8.0, 94.0, 86.0, 90.0, -75.0
	)



	var war_observed_change: bool = false
	var war_result: Dictionary = {}
	for war_period: int in range(3):
		war_result = service.update(war_state, war_input)
		_check(bool(war_result.get("success", false)), "war pressure enters politics through the input boundary %d" % war_period)
		if not bool(war_result.get("success", false)):
			return
		war_observed_change = war_observed_change or war_state.active_policy_ids().has("policy:loran_military_mobilization") or war_state.crisis_stage() != "stable"
	_check(float(war_result.get("war_pressure", 0.0)) > float(war_result.get("economic_pressure", 0.0)), "war and economic pressure remain separate signals")
	_check(war_observed_change, "sustained war pressure either produces a military policy decision or visible political strain")

func _test_ten_year_normal_run() -> void:
	var state := _load_fixture()
	if state == null:
		return
	var initial_government_group: String = state.government_group_id()
	var initial_leader: String = state.government_leader_id()
	for period: int in range(120):
		var input: VNextPoliticsPressureInput = GENERATOR.normal_input(1900, period)
		var result: Dictionary = service.update(state, input)
		_check(bool(result.get("success", false)), "normal long-run update succeeds at period %d" % period)
		if not bool(result.get("success", false)):
			return
		if period % 12 == 0:
			_check(state.is_valid(), "normal long-run state stays valid at year boundary %d" % (period / 12))
	_check(state.period_index() == 120, "normal run advances ten years of monthly political periods")
	_equal(state.government_group_id(), initial_government_group, "normal conditions do not randomly replace the government")
	_equal(state.government_leader_id(), initial_leader, "normal conditions preserve the government leader")
	_check(state.government_change_history().is_empty(), "normal conditions produce no government-change history")
	_check(state.policy_history().size() <= 96, "long-run policy history remains bounded")
	_check(state.stability() >= 35.0, "normal conditions do not collapse political stability")


func _test_severe_pressure_crisis_and_recovery() -> void:
	var state := _load_fixture()
	if state == null:
		return
	var initial_group: String = state.government_group_id()
	var severe := GENERATOR.severe_input()
	var lowest_stability: float = state.stability()
	var observed_crisis: bool = false
	var observed_change: bool = false
	for period: int in range(10):
		var result: Dictionary = service.update(state, severe)
		_check(bool(result.get("success", false)), "severe pressure update succeeds at period %d" % period)
		if not bool(result.get("success", false)):
			return
		lowest_stability = minf(lowest_stability, state.stability())
		observed_crisis = observed_crisis or state.crisis_stage() in ["strained", "crisis", "transition"]
		observed_change = observed_change or bool(result.get("government_changed", false))
	_check(observed_crisis, "sustained severe pressure creates a political crisis state")
	_check(lowest_stability < 60.0, "sustained severe pressure lowers stability materially")
	_check(observed_change or state.instability_streak() >= 4, "severe pressure changes government viability or records persistent failure")
	if observed_change:
		_check(state.government_group_id() != initial_group, "government change selects a different political force")
		_check(state.government_change_history().size() == 1, "government change records an explicit causal history")

	var stability_after_shock: float = state.stability()
	var recovery := GENERATOR.recovery_input()
	for period: int in range(36):
		var result: Dictionary = service.update(state, recovery)
		_check(bool(result.get("success", false)), "recovery update succeeds at period %d" % period)
		if not bool(result.get("success", false)):
			return
	_check(state.stability() > stability_after_shock, "removing the shock allows stability to recover")
	_check(state.is_valid(), "recovered political state remains valid")
	_check(
		state.crisis_stage() in ["stable", "strained", "transition"],
		"recovery does not leave an invalid crisis lock"
	)


func _load_fixture() -> VNextStatePolitics:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		_check(false, "political fixture file can be opened")
		return null
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	_check(parse_error == OK and parser.data is Dictionary, "political fixture is valid JSON")
	if parse_error != OK or not parser.data is Dictionary:
		return null
	var state := VNextStatePolitics.create_from_config(parser.data as Dictionary)
	if state == null:
		_check(false, "political fixture passes state validation")
	return state



func _first_semantic_difference(actual: Variant, expected: Variant, path: String = "$" ) -> String:
	var actual_type: int = typeof(actual)
	var expected_type: int = typeof(expected)
	if (actual_type == TYPE_INT or actual_type == TYPE_FLOAT) and (expected_type == TYPE_INT or expected_type == TYPE_FLOAT):
		return "" if is_equal_approx(float(actual), float(expected)) else "%s numeric values differ" % path
	if actual_type != expected_type:
		return "%s types differ" % path
	if actual is Dictionary:
		var actual_dictionary: Dictionary = actual as Dictionary
		var expected_dictionary: Dictionary = expected as Dictionary
		if actual_dictionary.size() != expected_dictionary.size():
			return "%s dictionary sizes differ" % path
		for key: Variant in expected_dictionary.keys():
			if not actual_dictionary.has(key):
				return "%s missing key %s" % [path, str(key)]
			var difference: String = _first_semantic_difference(
				actual_dictionary[key], expected_dictionary[key], "%s.%s" % [path, str(key)]
			)
			if not difference.is_empty():
				return difference
		return ""
	if actual is Array:
		var actual_array: Array = actual as Array
		var expected_array: Array = expected as Array
		if actual_array.size() != expected_array.size():
			return "%s array sizes differ" % path
		for index: int in range(expected_array.size()):
			var difference: String = _first_semantic_difference(
				actual_array[index], expected_array[index], "%s[%d]" % [path, index]
			)
			if not difference.is_empty():
				return difference
		return ""
	return "" if actual == expected else "%s values differ" % path

func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
