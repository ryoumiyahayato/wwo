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
	_test_pressure_input_and_elapsed_day_bounds()
	_test_partition_equivalence()
	_test_policy_cooldown_days()
	_test_governing_composition_counterfactuals()
	_test_leader_effect_is_finite_and_deterministic()
	_test_crisis_and_transition_day_semantics()
	_test_transition_selection_and_no_ping_pong()
	_test_strict_transactional_restore()
	_test_numeric_history_order()
	_test_determinism_and_input_permutation()
	_test_near_tie_policy_decision()
	_test_decade_stability_and_midpoint_resume()
	print("VNext state politics R1: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_fixture_and_identity_contract() -> void:
	var state := _load_fixture()
	_check(state != null, "1900 political fixture creates a valid state")
	if state == null:
		return
	_check(state.is_valid(), "political state satisfies its complete invariant")
	_equal(state.state_id(), "state:loran_federation", "state uses a canonical state ID")
	_equal(state.regime_type(), "federal_republic", "state exposes regime type")
	_equal(state.government_id(), "organization:loran_government", "state exposes governing institution")
	_equal(state.government_group_id(), "organization:loran_government_group", "state exposes governing group")
	_equal(state.government_leader_id(), "person:loran_premier", "state exposes government leader")
	_check(VNextStableId.is_valid("state:loran_federation"), "shared stable ID accepts state IDs")
	_check(VNextStableId.is_valid("policy:loran_labor_relief"), "shared stable ID accepts policy IDs")
	_check(state.supporting_force_ids().has("organization:loran_government_group"), "incumbent starts as a supporting force")
	_check(state.political_forces().size() >= 7, "fixture contains multiple organized political forces")
	_check(state.active_policy_ids().has("policy:loran_balanced_budget"), "fixture starts with an executing policy")
	_check(state.government_is_viable(), "initial government is viable")
	_equal(state.period_index(), 0, "initial elapsed-day index is zero")


func _test_pressure_input_and_elapsed_day_bounds() -> void:
	var source := VNextPoliticsPressureInput.create(366, 61.0, 72.0, 44.0, 38.0, -12.0, 70.0, 32.0, 55.0, -20.0)
	_check(source != null and source.is_valid(), "366-day boundary is accepted")
	if source == null:
		return
	var parser := JSON.new()
	_check(parser.parse(JSON.stringify(source.snapshot())) == OK, "pressure snapshot is JSON serializable")
	var restored := VNextPoliticsPressureInput.from_snapshot(parser.data as Dictionary)
	_check(restored != null and restored.is_valid(), "pressure snapshot restores")
	if restored != null:
		_equal(restored.snapshot(), source.snapshot(), "pressure JSON round trip preserves period_days and signals")
	_check(VNextPoliticsPressureInput.create(0) == null, "zero-day update is rejected")
	_check(VNextPoliticsPressureInput.create(367) == null, "period above 366 days is rejected")
	_check(VNextPoliticsPressureInput.create(30, 101.0) == null, "out-of-range signal is rejected")

	var one_day := _load_fixture()
	var thirty_day := _load_fixture()
	if one_day == null or thirty_day == null:
		return
	_check(bool(service.update(one_day, GENERATOR.normal_input(1900, 0, 1)).get("success", false)), "1-day update succeeds")
	_equal(one_day.period_index(), 1, "1-day update advances one elapsed day")
	_check(bool(service.update(thirty_day, GENERATOR.normal_input(1900, 0, 30)).get("success", false)), "30-day update succeeds")
	_equal(thirty_day.period_index(), 30, "30-day update advances thirty elapsed days")


func _test_partition_equivalence() -> void:
	var combined := _load_fixture()
	var split := _load_fixture()
	if combined == null or split == null:
		return
	var combined_input := VNextPoliticsPressureInput.create(30, 68.0, 92.0, 58.0, 45.0, -35.0, 12.0, 5.0, 8.0, -4.0)
	var one_day_input := VNextPoliticsPressureInput.create(1, 68.0, 92.0, 58.0, 45.0, -35.0, 12.0, 5.0, 8.0, -4.0)
	_check(bool(service.update(combined, combined_input).get("success", false)), "combined 30-day update succeeds")
	for day: int in range(30):
		var result := service.update(split, one_day_input)
		_check(bool(result.get("success", false)), "partitioned 1-day update succeeds at day %d" % day)
	_equal(_first_semantic_difference(combined.snapshot(), split.snapshot()), "", "30x1 day equals 1x30 days")

	var split_interval := _load_fixture()
	var combined_interval := _load_fixture()
	if split_interval == null or combined_interval == null:
		return
	var input_10 := VNextPoliticsPressureInput.create(10, 20.0, 35.0, 18.0, 12.0, 4.0, 10.0, 4.0, 3.0, 1.0)
	var input_20 := VNextPoliticsPressureInput.create(20, 20.0, 35.0, 18.0, 12.0, 4.0, 10.0, 4.0, 3.0, 1.0)
	var input_30 := VNextPoliticsPressureInput.create(30, 20.0, 35.0, 18.0, 12.0, 4.0, 10.0, 4.0, 3.0, 1.0)
	service.update(split_interval, input_10)
	service.update(split_interval, input_20)
	service.update(combined_interval, input_30)
	_equal(_first_semantic_difference(split_interval.snapshot(), combined_interval.snapshot()), "", "10+20 day split equals combined 30-day interval")

	var year_combined := _load_fixture()
	var year_split := _load_fixture()
	if year_combined == null or year_split == null:
		return
	var year_input := VNextPoliticsPressureInput.create(366, 12.0, 16.0, 14.0, 10.0, 8.0, 0.0, 0.0, 0.0, 4.0)
	var year_day := VNextPoliticsPressureInput.create(1, 12.0, 16.0, 14.0, 10.0, 8.0, 0.0, 0.0, 0.0, 4.0)
	_check(bool(service.update(year_combined, year_input).get("success", false)), "366-day combined update succeeds")
	for day: int in range(366):
		var result := service.update(year_split, year_day)
		if not bool(result.get("success", false)):
			_check(false, "366-day partition failed at day %d" % day)
			return
	_equal(_first_semantic_difference(year_combined.snapshot(), year_split.snapshot()), "", "366x1 day equals 1x366 days")


func _test_policy_cooldown_days() -> void:
	var state := _load_fixture()
	if state == null:
		return
	var pressure_89 := VNextPoliticsPressureInput.create(89, 75.0, 94.0, 55.0, 40.0, -30.0)
	_check(bool(service.update(state, pressure_89).get("success", false)), "89-day policy interval succeeds")
	_equal(state.last_policy_review_period(), 0, "policy review cooldown has not elapsed at day 89")
	var pressure_1 := VNextPoliticsPressureInput.create(1, 75.0, 94.0, 55.0, 40.0, -30.0)
	_check(bool(service.update(state, pressure_1).get("success", false)), "day 90 policy update succeeds")
	_equal(state.last_policy_review_period(), 90, "policy review occurs at 90 elapsed days")
	service.update(state, VNextPoliticsPressureInput.create(89, 75.0, 94.0, 55.0, 40.0, -30.0))
	_equal(state.last_policy_review_period(), 90, "policy review does not repeat before another 90 days")
	service.update(state, pressure_1)
	_equal(state.last_policy_review_period(), 180, "policy review cooldown is measured in days")


func _test_governing_composition_counterfactuals() -> void:
	var labor_config := _config_with_government("organization:loran_labor_caucus")
	var military_config := _config_with_government("organization:loran_military_command")
	var labor_state := VNextStatePolitics.create_from_config(labor_config)
	var military_state := VNextStatePolitics.create_from_config(military_config)
	_check(labor_state != null and military_state != null, "counterfactual governing coalitions create valid states")
	if labor_state == null or military_state == null:
		return
	var mixed_pressure := VNextPoliticsPressureInput.create(180, 65.0, 85.0, 55.0, 45.0, -30.0, 75.0, 45.0, 62.0, -25.0)
	_check(bool(service.update(labor_state, mixed_pressure).get("success", false)), "labor coalition counterfactual runs")
	_check(bool(service.update(military_state, mixed_pressure).get("success", false)), "military coalition counterfactual runs")
	_check(labor_state.active_policy_ids() != military_state.active_policy_ids(), "different governing coalitions produce different policy tendencies")
	_check(labor_state.government_support() != military_state.government_support(), "governing composition changes support dynamics")
	_check(labor_state.legitimacy() != military_state.legitimacy(), "governing composition changes legitimacy")

	var opposition_config := _load_fixture_config()
	var forces := opposition_config.get("forces", []) as Array
	for index: int in range(forces.size()):
		var force := forces[index] as Dictionary
		if str(force.get("force_id", "")) == "organization:loran_labor_caucus":
			force["influence"] = 80.0
			force["government_support"] = -80.0
			force["base_government_support"] = -80.0
		elif str(force.get("force_id", "")) == "organization:loran_government_group":
			force["influence"] = 12.0
			force["government_support"] = 80.0
			force["base_government_support"] = 80.0
		forces[index] = force
	opposition_config["forces"] = forces
	var opposition_state := VNextStatePolitics.create_from_config(opposition_config)
	_check(opposition_state != null, "high-influence opposition fixture remains valid")
	if opposition_state != null:
		service.update(opposition_state, VNextPoliticsPressureInput.create(90, 15.0, 18.0, 10.0, 8.0, 6.0))
		_check(not opposition_state.active_policy_ids().has("policy:loran_labor_relief"), "high global opposition influence does not dominate governing policy by itself")


func _test_leader_effect_is_finite_and_deterministic() -> void:
	var base_config := _load_fixture_config()
	var alt_config := base_config.duplicate(true)
	alt_config["government_leader_id"] = "person:loran_premier_counterfactual"
	var alt_forces := alt_config.get("forces", []) as Array
	for index: int in range(alt_forces.size()):
		var force := alt_forces[index] as Dictionary
		if str(force.get("force_id", "")) == "organization:loran_government_group":
			force["leader_id"] = "person:loran_premier_counterfactual"
		alt_forces[index] = force
	alt_config["forces"] = alt_forces
	var base_a := VNextStatePolitics.create_from_config(base_config)
	var base_b := VNextStatePolitics.create_from_config(base_config)
	var alt := VNextStatePolitics.create_from_config(alt_config)
	_check(base_a != null and base_b != null and alt != null, "leader counterfactuals create valid states")
	if base_a == null or base_b == null or alt == null:
		return
	var input := VNextPoliticsPressureInput.create(180, 25.0, 35.0, 20.0, 15.0, 5.0, 12.0, 4.0, 5.0, 2.0)
	service.update(base_a, input)
	service.update(base_b, input)
	service.update(alt, input)
	_equal(_first_semantic_difference(base_a.snapshot(), base_b.snapshot()), "", "same leader produces deterministic replay")
	_check(not is_equal_approx(base_a.legitimacy(), alt.legitimacy()), "leader identity has a finite operational effect")
	_check(absf(base_a.legitimacy() - alt.legitimacy()) < 12.0, "leader effect remains bounded rather than dominating politics")


func _test_crisis_and_transition_day_semantics() -> void:
	var economic := _load_fixture()
	var war := _load_fixture()
	if economic == null or war == null:
		return
	var initial_economic_support := economic.government_support()
	var initial_war_stability := war.stability()
	service.update(economic, GENERATOR.economic_crisis_input(120))
	service.update(war, GENERATOR.war_crisis_input(120))
	_check(economic.government_support() < initial_economic_support, "sustained economic crisis lowers governing support")
	_check(economic.crisis_stage() in ["strained", "crisis"], "sustained economic crisis progresses by elapsed days")
	_check(war.stability() < initial_war_stability, "sustained war crisis lowers stability")
	_check(war.crisis_stage() in ["strained", "crisis"], "sustained war crisis progresses by elapsed days")
	_check(economic.instability_streak() > 0 and economic.instability_streak() <= 120, "economic crisis duration is represented in days")
	_check(war.instability_streak() > 0 and war.instability_streak() <= 120, "war crisis duration is represented in days")

	var crisis := _load_fixture()
	if crisis == null:
		return
	service.update(crisis, GENERATOR.severe_input(210))
	_check(crisis.period_index() == 210, "severe crisis consumes authoritative elapsed days")
	_check(crisis.crisis_stage() in ["crisis", "transition"], "long severe crisis reaches crisis or transition")
	var after_shock := crisis.stability()
	service.update(crisis, GENERATOR.recovery_input(180))
	_check(crisis.stability() > after_shock, "crisis recovery improves stability after shock removal")
	_check(crisis.recovery_streak() > 0 or crisis.crisis_stage() == "transition", "recovery duration is tracked in elapsed days")


func _test_transition_selection_and_no_ping_pong() -> void:
	var state := _load_fixture()
	if state == null:
		return
	var initial_group := state.government_group_id()
	var result := service.update(state, GENERATOR.severe_input(366))
	_check(bool(result.get("success", false)), "366-day severe transition interval succeeds")
	var history := state.government_change_history()
	_check(history.size() >= 1, "sustained failure can produce a government transition")
	if history.is_empty():
		return
	var first := history[0]
	_check(str(first.get("new_government_group_id", "")) != initial_group, "transition selects a different government group")
	_check(float(first.get("mandate_score", 0.0)) >= VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD, "transition records an explicit mandate threshold")
	_check(float(first.get("coalition_score", 0.0)) > 0.0, "transition records coalition feasibility")
	_check(float(first.get("procedure_score", 0.0)) > 0.0, "transition records regime procedure")

	var count_after_first := history.size()
	service.update(state, GENERATOR.severe_input(180))
	_equal(state.government_change_history().size(), count_after_first, "transition cooldown prevents immediate repeated replacement")

	var long_state := _load_fixture()
	if long_state == null:
		return
	for block: int in range(6):
		service.update(long_state, GENERATOR.severe_input(366))
		service.update(long_state, GENERATOR.recovery_input(180))
	var long_history := long_state.government_change_history()
	_check(long_history.size() >= 2, "long horizon permits repeated politically explained transitions")
	for index: int in range(1, long_history.size()):
		var previous := long_history[index - 1]
		var current := long_history[index]
		var immediate_return := (
			str(current.get("new_government_group_id", "")) == str(previous.get("old_government_group_id", ""))
			and int(current.get("period", 0)) - int(previous.get("period", 0)) < VNextPoliticsUpdateService.RETURN_GOVERNMENT_PENALTY_DAYS
		)
		_check(not immediate_return, "transition history has no mechanical short-horizon ping-pong at index %d" % index)


func _test_strict_transactional_restore() -> void:
	var state := _load_fixture()
	if state == null:
		return
	service.update(state, GENERATOR.normal_input(1900, 0, 30))
	var before := state.snapshot()

	var mismatch := before.duplicate(true)
	mismatch["government_support"] = clampf(float(mismatch.get("government_support", 0.0)) + 1.0, 0.0, 100.0)
	_check(not state.restore(mismatch), "top-level support inconsistent with nested forces is rejected")
	_equal(_first_semantic_difference(state.snapshot(), before), "", "support mismatch restore is transactional")

	var viability_mismatch := before.duplicate(true)
	viability_mismatch["government_viability"] = not bool(viability_mismatch.get("government_viability", false))
	_check(not state.restore(viability_mismatch), "viability inconsistent with thresholds is rejected")
	_equal(_first_semantic_difference(state.snapshot(), before), "", "viability mismatch does not partially mutate state")

	var stale_force := before.duplicate(true)
	stale_force["government_group_id"] = "organization:missing_force"
	_check(not state.restore(stale_force), "stale force reference is rejected")

	var stale_policy := before.duplicate(true)
	var active := stale_policy.get("active_policies", []) as Array
	var active_item := (active[0] as Dictionary).duplicate(true)
	active_item["policy_id"] = "policy:missing_policy"
	active[0] = active_item
	stale_policy["active_policies"] = active
	_check(not state.restore(stale_policy), "stale policy reference is rejected")

	var stale_leader := before.duplicate(true)
	stale_leader["government_leader_id"] = "person:missing_leader"
	_check(not state.restore(stale_leader), "stale leader reference is rejected")

	var malformed_history := before.duplicate(true)
	malformed_history["policy_history"] = [{"period": 1, "policy_id": "policy:loran_balanced_budget"}]
	_check(not state.restore(malformed_history), "malformed policy history is rejected")

	var invalid_period := before.duplicate(true)
	invalid_period["period_index"] = -1
	_check(not state.restore(invalid_period), "invalid elapsed period is rejected")
	_equal(_first_semantic_difference(state.snapshot(), before), "", "all invalid restores leave current state unchanged")


func _test_numeric_history_order() -> void:
	var state := _load_fixture()
	if state == null:
		return
	service.update(state, GENERATOR.normal_input(1900, 0, 30))
	var snapshot := state.snapshot()
	snapshot["policy_history"] = [
		_history_record(10, "policy:loran_balanced_budget"),
		_history_record(2, "policy:loran_balanced_budget"),
		_history_record(12, "policy:loran_balanced_budget"),
	]
	_check(state.restore(snapshot), "valid unsorted numeric policy history restores")
	var history := state.policy_history()
	_equal(int(history[0].get("period", -1)), 2, "history sorts period 2 before period 10")
	_equal(int(history[1].get("period", -1)), 10, "history sorts period 10 numerically")
	_equal(int(history[2].get("period", -1)), 12, "history sorts period 12 numerically")


func _test_determinism_and_input_permutation() -> void:
	var config_a := _load_fixture_config()
	var config_b := config_a.duplicate(true)
	var reversed_forces := (config_b.get("forces", []) as Array).duplicate(true)
	reversed_forces.reverse()
	var reversed_policies := (config_b.get("policies", []) as Array).duplicate(true)
	reversed_policies.reverse()
	config_b["forces"] = reversed_forces
	config_b["policies"] = reversed_policies
	var state_a := VNextStatePolitics.create_from_config(config_a)
	var state_b := VNextStatePolitics.create_from_config(config_b)
	_check(state_a != null and state_b != null, "permuted fixture order creates valid states")
	if state_a == null or state_b == null:
		return
	_equal(_first_semantic_difference(state_a.snapshot(), state_b.snapshot()), "", "initial state canonicalizes force and policy order")
	for period: int in range(12):
		var input := GENERATOR.normal_input(31337, period, 30)
		service.update(state_a, input)
		service.update(state_b, input)
	_equal(_first_semantic_difference(state_a.snapshot(), state_b.snapshot()), "", "permuted input order produces deterministic replay")

	var replay_a := _load_fixture()
	var replay_b := _load_fixture()
	if replay_a == null or replay_b == null:
		return
	for period: int in range(24):
		var replay_input := GENERATOR.normal_input(777, period, 30)
		service.update(replay_a, replay_input)
		service.update(replay_b, replay_input)
	_equal(_first_semantic_difference(replay_a.snapshot(), replay_b.snapshot()), "", "same input sequence replays deterministically")


func _test_near_tie_policy_decision() -> void:
	var config_a := _load_fixture_config()
	var policies := config_a.get("policies", []) as Array
	var template: Dictionary = {}
	for raw_policy: Variant in policies:
		if str((raw_policy as Dictionary).get("policy_id", "")) == "policy:loran_labor_relief":
			template = (raw_policy as Dictionary).duplicate(true)
			break
	if template.is_empty():
		_check(false, "near-tie policy template exists")
		return
	var a_policy := template.duplicate(true)
	a_policy["policy_id"] = "policy:a_near_tie"
	a_policy["name"] = "A near tie"
	var z_policy := template.duplicate(true)
	z_policy["policy_id"] = "policy:z_near_tie"
	z_policy["name"] = "Z near tie"
	policies.append(z_policy)
	policies.append(a_policy)
	config_a["policies"] = policies
	var config_b := config_a.duplicate(true)
	var reverse := (config_b.get("policies", []) as Array).duplicate(true)
	reverse.reverse()
	config_b["policies"] = reverse
	var state_a := VNextStatePolitics.create_from_config(config_a)
	var state_b := VNextStatePolitics.create_from_config(config_b)
	_check(state_a != null and state_b != null, "near-tie policy fixtures are valid")
	if state_a == null or state_b == null:
		return
	var input := VNextPoliticsPressureInput.create(180, 70.0, 96.0, 45.0, 30.0, -25.0)
	service.update(state_a, input)
	service.update(state_b, input)
	_equal(_first_semantic_difference(state_a.snapshot(), state_b.snapshot()), "", "near-tie policy choice is deterministic under input permutation")
	_check(state_a.active_policy_ids().has("policy:a_near_tie"), "near-tie policy decision uses stable lexical ID tie-break")


func _test_decade_stability_and_midpoint_resume() -> void:
	var continuous := _load_fixture()
	var replay := _load_fixture()
	if continuous == null or replay == null:
		return
	var initial_group := continuous.government_group_id()
	var midpoint_snapshot: Dictionary = {}
	for period: int in range(121):
		var input := GENERATOR.normal_input(1900, period, 30)
		var result := service.update(continuous, input)
		_check(bool(result.get("success", false)), "decade normal update succeeds at block %d" % period)
		if period == 59:
			midpoint_snapshot = continuous.snapshot()
	var tail_input := GENERATOR.normal_input(1900, 121, 20)
	service.update(continuous, tail_input)
	_equal(continuous.period_index(), 3650, "decade simulation advances exactly 3650 days")
	_equal(continuous.government_group_id(), initial_group, "normal low-pressure decade does not randomly replace government")
	_check(continuous.government_change_history().is_empty(), "normal decade has no spurious government transitions")
	_check(continuous.stability() >= 35.0, "normal decade remains politically stable")
	_check(continuous.is_valid(), "decade final state remains valid")

	_check(not midpoint_snapshot.is_empty() and replay.restore(midpoint_snapshot), "midpoint snapshot resumes transactionally")
	for period: int in range(60, 121):
		service.update(replay, GENERATOR.normal_input(1900, period, 30))
	service.update(replay, tail_input)
	_equal(_first_semantic_difference(continuous.snapshot(), replay.snapshot()), "", "snapshot midpoint resume matches continuous deterministic decade")


func _config_with_government(group_id: String) -> Dictionary:
	var config := _load_fixture_config()
	var forces := config.get("forces", []) as Array
	var chosen_leader := ""
	for raw_force: Variant in forces:
		var force := raw_force as Dictionary
		if str(force.get("force_id", "")) == group_id:
			chosen_leader = str(force.get("leader_id", ""))
			break
	config["government_group_id"] = group_id
	config["government_leader_id"] = chosen_leader
	for index: int in range(forces.size()):
		var force := forces[index] as Dictionary
		var force_id := str(force.get("force_id", ""))
		var support := -15.0
		if force_id == group_id:
			support = 82.0
		elif group_id == "organization:loran_labor_caucus":
			if force_id in ["organization:loran_liberal_league", "organization:loran_regional_union"]:
				support = 42.0
			elif force_id == "organization:loran_government_group":
				support = -28.0
		elif group_id == "organization:loran_military_command":
			if force_id in ["organization:loran_conservative_bloc", "organization:loran_land_industry"]:
				support = 44.0
			elif force_id == "organization:loran_labor_caucus":
				support = -45.0
		force["government_support"] = support
		force["base_government_support"] = support
		forces[index] = force
	config["forces"] = forces
	return config


func _history_record(period: int, policy_id: String) -> Dictionary:
	return {
		"period": period,
		"action": "adopted",
		"policy_id": policy_id,
		"replaced_policy_id": "",
		"political_pressure": 10.0,
		"support_score": 50.0,
	}


func _load_fixture() -> VNextStatePolitics:
	var config := _load_fixture_config()
	if config.is_empty():
		return null
	var state := VNextStatePolitics.create_from_config(config)
	if state == null:
		_check(false, "political fixture passes state validation")
	return state


func _load_fixture_config() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		_check(false, "political fixture file can be opened")
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	_check(parse_error == OK and parser.data is Dictionary, "political fixture is valid JSON")
	if parse_error != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _first_semantic_difference(actual: Variant, expected: Variant, path: String = "$") -> String:
	var actual_type := typeof(actual)
	var expected_type := typeof(expected)
	if (actual_type == TYPE_INT or actual_type == TYPE_FLOAT) and (expected_type == TYPE_INT or expected_type == TYPE_FLOAT):
		return "" if is_equal_approx(float(actual), float(expected)) else "%s numeric values differ" % path
	if actual_type != expected_type:
		return "%s types differ" % path
	if actual is Dictionary:
		var actual_dictionary := actual as Dictionary
		var expected_dictionary := expected as Dictionary
		if actual_dictionary.size() != expected_dictionary.size():
			return "%s dictionary sizes differ" % path
		var keys: Array[String] = []
		for raw_key: Variant in expected_dictionary.keys():
			keys.append(str(raw_key))
		keys.sort()
		for key: String in keys:
			if not actual_dictionary.has(key):
				return "%s missing key %s" % [path, key]
			var difference := _first_semantic_difference(actual_dictionary[key], expected_dictionary[key], "%s.%s" % [path, key])
			if not difference.is_empty():
				return difference
		return ""
	if actual is Array:
		var actual_array := actual as Array
		var expected_array := expected as Array
		if actual_array.size() != expected_array.size():
			return "%s array sizes differ" % path
		for index: int in range(expected_array.size()):
			var difference := _first_semantic_difference(actual_array[index], expected_array[index], "%s[%d]" % [path, index])
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
