extends SceneTree

const GENERATOR = preload("res://tests/vnext/politics_variable_state_generator.gd")
const FIXTURE_PATH: String = "res://data/vnext/politics/state_politics_1900.json"

var checks: int = 0
var failures: int = 0
var service := VNextPoliticsUpdateService.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_government_history_validation_matrix()
	_test_sustained_severe_pressure_does_not_become_timer_clock()
	_test_historical_return_floor_decays_away()
	_test_repeat_return_responds_to_political_improvement()
	_test_approximate_tie_boundaries()
	_test_return_penalty_elapsed_partition()
	_test_recovery_can_stabilize()
	_test_mixed_decade_determinism_and_resume()
	print("VNext state politics R4: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _test_government_history_validation_matrix() -> void:
	var base := _load_fixture()
	var target := _load_fixture()
	if base == null or target == null:
		return

	var empty := base.snapshot()
	empty["government_change_history"] = []
	_check(target.restore(empty), "history legal: empty history restores")

	var one := base.snapshot()
	one["period_index"] = 200
	one["government_group_id"] = "organization:loran_labor_caucus"
	one["government_leader_id"] = "person:loran_labor_leader"
	one["government_change_history"] = [
		_transition_record(
			100,
			"organization:loran_government_group",
			"person:loran_premier",
			"organization:loran_labor_caucus",
			"person:loran_labor_leader"
		),
	]
	_check(target.restore(one), "history legal: one transition restores")

	var valid := _synthetic_multi_transition_snapshot(base.snapshot())
	_check(target.restore(valid), "history legal: multiple transitions restore")
	var canonical := target.snapshot()
	var permuted := valid.duplicate(true)
	var permuted_history := (permuted.get("government_change_history", []) as Array).duplicate(true)
	permuted_history.reverse()
	permuted["government_change_history"] = permuted_history
	_check(target.restore(permuted), "history legal: permuted valid history restores")
	_equal(_first_semantic_difference(target.snapshot(), canonical), "", "history legal: permutation canonicalizes identically")

	var raw_variants: Array[Dictionary] = [
		{"label": "string first", "value": "malformed", "position": 0},
		{"label": "integer middle", "value": 123, "position": 1},
		{"label": "null middle", "value": null, "position": 1},
		{"label": "array final", "value": ["nested"], "position": 2},
		{"label": "string final", "value": "malformed", "position": 2},
	]
	for case: Dictionary in raw_variants:
		var malformed := valid.duplicate(true)
		var history := (malformed.get("government_change_history", []) as Array).duplicate(true)
		history.insert(int(case.get("position", 0)), case.get("value"))
		malformed["government_change_history"] = history
		_assert_restore_rejected_unchanged(target, malformed, "history illegal raw Variant: %s" % str(case.get("label", "")))

	var missing_field := valid.duplicate(true)
	var missing_history := (missing_field.get("government_change_history", []) as Array).duplicate(true)
	var missing_record := (missing_history[0] as Dictionary).duplicate(true)
	missing_record.erase("reason")
	missing_history[0] = missing_record
	missing_field["government_change_history"] = missing_history
	_assert_restore_rejected_unchanged(target, missing_field, "history illegal: missing required field")

	var invalid_government := valid.duplicate(true)
	var invalid_government_history := (invalid_government.get("government_change_history", []) as Array).duplicate(true)
	var invalid_first := (invalid_government_history[0] as Dictionary).duplicate(true)
	var invalid_second := (invalid_government_history[1] as Dictionary).duplicate(true)
	invalid_first["new_government_group_id"] = "organization:not_in_force_catalog"
	invalid_second["old_government_group_id"] = "organization:not_in_force_catalog"
	invalid_government_history[0] = invalid_first
	invalid_government_history[1] = invalid_second
	invalid_government["government_change_history"] = invalid_government_history
	_assert_restore_rejected_unchanged(target, invalid_government, "history illegal: invalid government reference")

	var invalid_leader_reference := valid.duplicate(true)
	var invalid_leader_history := (invalid_leader_reference.get("government_change_history", []) as Array).duplicate(true)
	var invalid_leader_record := (invalid_leader_history[0] as Dictionary).duplicate(true)
	invalid_leader_record["new_leader_id"] = "person:loran_conservative_leader"
	invalid_leader_history[0] = invalid_leader_record
	invalid_leader_reference["government_change_history"] = invalid_leader_history
	_assert_restore_rejected_unchanged(target, invalid_leader_reference, "history illegal: authoritative leader reference mismatch")

	var broken_government_chain := valid.duplicate(true)
	var broken_government_history := (broken_government_chain.get("government_change_history", []) as Array).duplicate(true)
	var broken_government_second := (broken_government_history[1] as Dictionary).duplicate(true)
	broken_government_second["old_government_group_id"] = "organization:loran_conservative_bloc"
	broken_government_second["old_leader_id"] = "person:loran_conservative_leader"
	broken_government_history[1] = broken_government_second
	broken_government_chain["government_change_history"] = broken_government_history
	_assert_restore_rejected_unchanged(target, broken_government_chain, "history illegal: broken government chain")

	var broken_leader_chain := valid.duplicate(true)
	var broken_leader_history := (broken_leader_chain.get("government_change_history", []) as Array).duplicate(true)
	var broken_leader_second := (broken_leader_history[1] as Dictionary).duplicate(true)
	broken_leader_second["old_leader_id"] = "person:loran_conservative_leader"
	broken_leader_history[1] = broken_leader_second
	broken_leader_chain["government_change_history"] = broken_leader_history
	_assert_restore_rejected_unchanged(target, broken_leader_chain, "history illegal: broken leader chain")

	var duplicate_transition := valid.duplicate(true)
	var duplicate_history := (duplicate_transition.get("government_change_history", []) as Array).duplicate(true)
	duplicate_history.append((duplicate_history[1] as Dictionary).duplicate(true))
	duplicate_transition["government_change_history"] = duplicate_history
	_assert_restore_rejected_unchanged(target, duplicate_transition, "history illegal: duplicate transition")

	var same_period := valid.duplicate(true)
	var same_period_history := (same_period.get("government_change_history", []) as Array).duplicate(true)
	var same_period_second := (same_period_history[1] as Dictionary).duplicate(true)
	same_period_second["period"] = int((same_period_history[0] as Dictionary).get("period", 0))
	same_period_history[1] = same_period_second
	same_period["government_change_history"] = same_period_history
	_assert_restore_rejected_unchanged(target, same_period, "history illegal: same-period contradiction")

	var non_numeric := valid.duplicate(true)
	var non_numeric_history := (non_numeric.get("government_change_history", []) as Array).duplicate(true)
	var non_numeric_second := (non_numeric_history[1] as Dictionary).duplicate(true)
	non_numeric_second["period"] = "500"
	non_numeric_history[1] = non_numeric_second
	non_numeric["government_change_history"] = non_numeric_history
	_assert_restore_rejected_unchanged(target, non_numeric, "history illegal: non-numeric period")

	var non_increasing := valid.duplicate(true)
	var non_increasing_history := (non_increasing.get("government_change_history", []) as Array).duplicate(true)
	var non_increasing_second := (non_increasing_history[1] as Dictionary).duplicate(true)
	non_increasing_second["period"] = 50
	non_increasing_history[1] = non_increasing_second
	non_increasing["government_change_history"] = non_increasing_history
	_assert_restore_rejected_unchanged(target, non_increasing, "history illegal: non-increasing chronology")

	var final_group_mismatch := valid.duplicate(true)
	final_group_mismatch["government_group_id"] = "organization:loran_conservative_bloc"
	final_group_mismatch["government_leader_id"] = "person:loran_conservative_leader"
	_assert_restore_rejected_unchanged(target, final_group_mismatch, "history illegal: final government mismatch")

	var final_leader_mismatch := valid.duplicate(true)
	final_leader_mismatch["government_leader_id"] = "person:loran_marshal_counterfactual"
	var mismatch_forces := final_leader_mismatch.get("forces", []) as Array
	for index: int in range(mismatch_forces.size()):
		var force := (mismatch_forces[index] as Dictionary).duplicate(true)
		if str(force.get("force_id", "")) == "organization:loran_military_command":
			force["leader_id"] = "person:loran_marshal_counterfactual"
		mismatch_forces[index] = force
	final_leader_mismatch["forces"] = mismatch_forces
	_assert_restore_rejected_unchanged(target, final_leader_mismatch, "history illegal: final leader mismatch")

	var malformed_nested := valid.duplicate(true)
	var malformed_nested_history := (malformed_nested.get("government_change_history", []) as Array).duplicate(true)
	var malformed_nested_record := (malformed_nested_history[0] as Dictionary).duplicate(true)
	malformed_nested_record["mandate_score"] = {"malformed": true}
	malformed_nested_history[0] = malformed_nested_record
	malformed_nested["government_change_history"] = malformed_nested_history
	_assert_restore_rejected_unchanged(target, malformed_nested, "history illegal: malformed nested score")


func _test_sustained_severe_pressure_does_not_become_timer_clock() -> void:
	var first := VNextStatePolitics.create_from_config(_limited_challenger_config())
	var replay := VNextStatePolitics.create_from_config(_limited_challenger_config())
	_check(first != null and replay != null, "two-government sustained-pressure fixtures are valid")
	if first == null or replay == null:
		return
	var initial_group := first.government_group_id()
	var first_run := _advance_severe(first, 3650)
	var replay_run := _advance_severe_daily(replay, 3650)
	_check(bool(first_run.get("success", false)) and bool(replay_run.get("success", false)), "3650-day sustained severe chunked and daily runs complete")
	var evidence := first_run.get("transitions", []) as Array
	_check(evidence.size() >= 2, "sustained severe pressure permits multiple transition windows")
	var comeback := false
	var exact_cooldown_alternations := 0
	var max_exact_cooldown_alternations := 0
	var same_period_alternations := 0
	var max_same_period_alternations := 0
	var last_alternating_gap := -1
	for index: int in range(evidence.size()):
		var item := evidence[index] as Dictionary
		if str(item.get("new", "")) == initial_group:
			comeback = true
		_check(float(item.get("mandate", 0.0)) >= VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD, "transition has mandate evidence at day %d" % int(item.get("period", 0)))
		_check(float(item.get("coalition", 0.0)) > 0.0, "transition has coalition feasibility at day %d" % int(item.get("period", 0)))
		_check(float(item.get("procedure", 0.0)) > 0.0, "transition has procedural legality at day %d" % int(item.get("period", 0)))
		if index > 0:
			var previous := evidence[index - 1] as Dictionary
			var gap := int(item.get("period", 0)) - int(previous.get("period", 0))
			var alternates := str(previous.get("old", "")) == str(item.get("new", "")) and str(previous.get("new", "")) == str(item.get("old", ""))
			if alternates and gap == VNextPoliticsUpdateService.TRANSITION_COOLDOWN_DAYS:
				exact_cooldown_alternations += 1
				max_exact_cooldown_alternations = maxi(max_exact_cooldown_alternations, exact_cooldown_alternations)
			else:
				exact_cooldown_alternations = 0
			if alternates:
				if gap == last_alternating_gap:
					same_period_alternations += 1
				else:
					same_period_alternations = 1
				last_alternating_gap = gap
				max_same_period_alternations = maxi(max_same_period_alternations, same_period_alternations)
			else:
				same_period_alternations = 0
				last_alternating_gap = -1
			_check(gap >= VNextPoliticsUpdateService.TRANSITION_COOLDOWN_DAYS, "transition spacing respects cooldown at evidence index %d" % index)
	_check(comeback, "former government can still make a politically eligible comeback")
	_check(max_exact_cooldown_alternations < 3, "constant severe pressure never accumulates a long exact-cooldown A/B run")
	_check(max_same_period_alternations < 3, "constant severe pressure does not settle into a repeated fixed-period A/B attractor")
	_check(first.is_valid(), "3650-day sustained severe final state remains valid")
	_check(is_finite(first.legitimacy()) and first.legitimacy() >= 0.0 and first.legitimacy() <= 100.0, "3650-day sustained severe legitimacy stays bounded")
	_check(is_finite(first.stability()) and first.stability() >= 0.0 and first.stability() <= 100.0, "3650-day sustained severe stability stays bounded")
	_equal(_first_semantic_difference(first.snapshot(), replay.snapshot()), "", "3650-day severe large-vs-daily partition is equivalent")
	_equal(_transition_signature(evidence), _transition_signature(replay_run.get("transitions", []) as Array), "sustained-pressure transition evidence is partition invariant")
	print("R4 sustained transition evidence: %s" % JSON.stringify(evidence))


func _test_historical_return_floor_decays_away() -> void:
	var seed := VNextStatePolitics.create_from_config(_limited_challenger_config())
	if seed == null:
		_check(false, "historical-floor fixture is valid")
		return
	var base := seed.snapshot()
	var first_entry := _transition_record(
		100,
		"organization:loran_government_group",
		"person:loran_premier",
		"organization:loran_labor_caucus",
		"person:loran_labor_leader"
	)
	first_entry["mandate_score"] = 80.0
	var displacement := _transition_record(
		500,
		"organization:loran_labor_caucus",
		"person:loran_labor_leader",
		"organization:loran_government_group",
		"person:loran_premier"
	)
	displacement["mandate_score"] = 72.0
	base["government_change_history"] = [first_entry, displacement]
	base["government_group_id"] = "organization:loran_government_group"
	base["government_leader_id"] = "person:loran_premier"
	base["instability_streak"] = 200
	base["recovery_streak"] = 0
	base["crisis_stage"] = "crisis"
	var forces := base.get("forces", []) as Array
	for index: int in range(forces.size()):
		var force := (forces[index] as Dictionary).duplicate(true)
		var force_id := str(force.get("force_id", ""))
		if force_id == "organization:loran_government_group":
			force["influence"] = 50.0
			force["government_support"] = -80.0
			force["base_government_support"] = -80.0
		elif force_id == "organization:loran_labor_caucus":
			force["influence"] = 50.0
			force["government_support"] = 0.0
			force["base_government_support"] = 0.0
			force["institutional_access"] = 45.0
			force["mobilization_capacity"] = 45.0
			force["government_eligible"] = true
		forces[index] = force
	base["forces"] = forces

	var requirements: Array[float] = []
	for age: int in [365, 500, 719, 720, 721]:
		var aged := base.duplicate(true)
		aged["period_index"] = 500 + age
		requirements.append(service._repeat_return_required_mandate(aged, 80.0))
	_check(requirements[0] > requirements[1] and requirements[1] > requirements[2] and requirements[2] > requirements[3], "historical mandate uplift decays monotonically before the horizon")
	_equal(requirements[3], float(VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD), "historical mandate uplift is zero at the 720-day horizon")
	_equal(requirements[4], float(VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD), "historical mandate uplift remains zero after the horizon")
	for required: float in requirements:
		_check(required >= float(VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD) and required <= VNextPoliticsUpdateService.REPEAT_RETURN_MANDATE_BENCHMARK_CAP + VNextPoliticsUpdateService.REPEAT_RETURN_MANDATE_MARGIN, "historical return requirement stays bounded")

	var recent := base.duplicate(true)
	recent["period_index"] = 500 + VNextPoliticsUpdateService.TRANSITION_COOLDOWN_DAYS
	var recent_result := service._select_challenger(recent, 100.0)
	_check(recent_result.is_empty(), "recent direct return can be blocked by bounded historical hysteresis even when crisis removes the return penalty")

	var horizon := base.duplicate(true)
	horizon["period_index"] = 500 + VNextPoliticsUpdateService.RETURN_GOVERNMENT_PENALTY_DAYS
	var horizon_result := service._select_challenger(horizon, 100.0)
	_check(not horizon_result.is_empty(), "former government is ordinarily eligible once historical hysteresis expires")
	if not horizon_result.is_empty():
		var current_mandate := float(horizon_result.get("mandate_score", 0.0))
		_check(current_mandate >= VNextPoliticsUpdateService.CHALLENGER_MANDATE_THRESHOLD, "expired-horizon current mandate clears normal threshold")
		_check(current_mandate < 80.0, "expired-horizon current mandate is below stale prior entry mandate")
		_check(float(horizon_result.get("coalition_score", 0.0)) > 0.0, "expired-horizon challenger has valid coalition evidence")
		_check(float(horizon_result.get("procedure_score", 0.0)) > 0.0, "expired-horizon challenger has valid procedure evidence")

	var public_state := VNextStatePolitics.new()
	_check(public_state.restore(horizon), "expired-horizon liveness snapshot restores through public state path")
	var transition_result := service.update(public_state, GENERATOR.severe_input(1))
	_check(bool(transition_result.get("success", false)), "expired-horizon public update succeeds")
	_check(bool(transition_result.get("government_changed", false)), "expired historical floor permits a real public-path government transition")
	_equal(public_state.government_group_id(), "organization:loran_labor_caucus", "former government actually returns after finite hysteresis horizon")
	_check(public_state.is_valid(), "post-return state and government history remain valid")
	print("R4 historical return requirements [365,500,719,720,721]: %s" % JSON.stringify(requirements))


func _test_repeat_return_responds_to_political_improvement() -> void:
	var state := VNextStatePolitics.create_from_config(_limited_challenger_config())
	if state == null:
		_check(false, "repeat-return fixture is valid")
		return
	var run := _advance_severe(state, 910)
	_check(bool(run.get("success", false)), "repeat-return fixture reaches third potential transition window")
	var history := state.government_change_history()
	_check(history.size() == 2, "unchanged repeated conditions do not trigger a third timer-driven reversal at day 910")
	if history.size() != 2:
		return
	var pressure := float(run.get("last_pressure", 0.0))
	_check(service._select_challenger(state.snapshot(), pressure).is_empty(), "repeat-return candidate without renewed mandate is rejected after cooldown")

	var improved := state.snapshot()
	var forces := improved.get("forces", []) as Array
	for index: int in range(forces.size()):
		var force := (forces[index] as Dictionary).duplicate(true)
		if str(force.get("force_id", "")) == "organization:loran_labor_caucus":
			force["institutional_access"] = 100.0
			force["mobilization_capacity"] = 100.0
		forces[index] = force
	improved["forces"] = forces
	_check(state.restore(improved), "real political capability improvement restores through public state path")
	var renewed := service._select_challenger(state.snapshot(), pressure)
	_check(not renewed.is_empty(), "renewed political mandate reopens repeat-return eligibility")
	if not renewed.is_empty():
		_check(float(renewed.get("mandate_score", 0.0)) > VNextPoliticsUpdateService.REPEAT_RETURN_MANDATE_BENCHMARK_CAP, "renewed return clears bounded prior-mandate benchmark")
	var transition_result := service.update(state, GENERATOR.severe_input(1))
	_check(bool(transition_result.get("government_changed", false)), "politically improved former government can return without waiting for another timer horizon")
	_equal(state.government_group_id(), "organization:loran_labor_caucus", "repeat comeback remains legal when political conditions improve")


func _test_approximate_tie_boundaries() -> void:
	_test_policy_tie_boundary()
	_test_challenger_tie_boundary()


func _test_policy_tie_boundary() -> void:
	var config := _load_fixture_config()
	var template: Dictionary = {}
	for raw_policy: Variant in config.get("policies", []) as Array:
		if str((raw_policy as Dictionary).get("policy_id", "")) == "policy:loran_labor_relief":
			template = (raw_policy as Dictionary).duplicate(true)
			break
	if template.is_empty():
		_check(false, "policy tie template exists")
		return
	var input := VNextPoliticsPressureInput.create(180, 70.0, 96.0, 45.0, 30.0, -25.0)

	var inside_a := template.duplicate(true)
	inside_a["policy_id"] = "policy:a_inside_tie"
	inside_a["name"] = "A inside tie"
	inside_a["fiscal_demand"] = float(template.get("fiscal_demand", 0.0)) + 0.000001
	var inside_z := template.duplicate(true)
	inside_z["policy_id"] = "policy:z_inside_tie"
	inside_z["name"] = "Z inside tie"
	var scoring_state := VNextStatePolitics.create_from_config(_policy_pair_config(config, inside_a, inside_z, false))
	if scoring_state == null:
		_check(false, "inside-epsilon policy fixture is valid")
		return
	var inside_a_score := service._policy_score(inside_a, scoring_state.snapshot(), input, 50.0)
	var inside_z_score := service._policy_score(inside_z, scoring_state.snapshot(), input, 50.0)
	_check(inside_a_score != inside_z_score and is_equal_approx(inside_a_score, inside_z_score), "policy inside epsilon uses unequal approximate-equal scores")
	var inside_first := VNextStatePolitics.create_from_config(_policy_pair_config(config, inside_a, inside_z, false))
	var inside_reversed := VNextStatePolitics.create_from_config(_policy_pair_config(config, inside_a, inside_z, true))
	service.update(inside_first, input)
	service.update(inside_reversed, input)
	_check(inside_first.active_policy_ids().has("policy:a_inside_tie"), "policy inside epsilon uses lexical stable-ID tie-break")
	_equal(inside_first.active_policy_ids(), inside_reversed.active_policy_ids(), "policy inside-epsilon winner is permutation invariant")

	var outside_a := template.duplicate(true)
	outside_a["policy_id"] = "policy:a_outside_lower"
	outside_a["name"] = "A outside lower"
	outside_a["fiscal_demand"] = float(template.get("fiscal_demand", 0.0)) + 10.0
	var outside_z := template.duplicate(true)
	outside_z["policy_id"] = "policy:z_outside_higher"
	outside_z["name"] = "Z outside higher"
	var outside_scoring := VNextStatePolitics.create_from_config(_policy_pair_config(config, outside_a, outside_z, false))
	if outside_scoring == null:
		_check(false, "outside-epsilon policy fixture is valid")
		return
	var outside_a_score := service._policy_score(outside_a, outside_scoring.snapshot(), input, 50.0)
	var outside_z_score := service._policy_score(outside_z, outside_scoring.snapshot(), input, 50.0)
	_check(outside_z_score > outside_a_score and not is_equal_approx(outside_z_score, outside_a_score), "policy outside epsilon has a genuine higher lexical-disadvantaged score")
	var outside_first := VNextStatePolitics.create_from_config(_policy_pair_config(config, outside_a, outside_z, false))
	var outside_reversed := VNextStatePolitics.create_from_config(_policy_pair_config(config, outside_a, outside_z, true))
	service.update(outside_first, input)
	service.update(outside_reversed, input)
	_check(outside_first.active_policy_ids().has("policy:z_outside_higher"), "policy outside epsilon chooses genuinely higher score over lexical ID")
	_equal(outside_first.active_policy_ids(), outside_reversed.active_policy_ids(), "policy outside-epsilon winner is permutation invariant")


func _test_challenger_tie_boundary() -> void:
	var incumbent := _minimal_challenger_force("organization:incumbent_test", "person:incumbent_test", 20.0, 80.0, false)
	var base_candidate := {
		"regime_type": "federal_republic",
		"government_id": "organization:test_government",
		"government_group_id": "organization:incumbent_test",
		"period_index": 500,
		"government_change_history": [],
	}

	var inside_a := _minimal_challenger_force("organization:a_inside_challenger", "person:a_inside_challenger", 40.0, -50.0, true)
	var inside_z := _minimal_challenger_force("organization:z_inside_challenger", "person:z_inside_challenger", 40.000001, -50.0, true)
	var only_a := base_candidate.duplicate(true)
	only_a["forces"] = [incumbent, inside_a]
	var only_z := base_candidate.duplicate(true)
	only_z["forces"] = [incumbent, inside_z]
	var inside_a_score := float(service._select_challenger(only_a, 50.0).get("mandate_score", 0.0))
	var inside_z_score := float(service._select_challenger(only_z, 50.0).get("mandate_score", 0.0))
	_check(inside_a_score != inside_z_score and is_equal_approx(inside_a_score, inside_z_score), "challenger inside epsilon uses unequal approximate-equal scores")
	var combined_inside_a := base_candidate.duplicate(true)
	combined_inside_a["forces"] = [inside_z, incumbent, inside_a]
	var combined_inside_b := base_candidate.duplicate(true)
	combined_inside_b["forces"] = [inside_a, inside_z, incumbent]
	var inside_result_a := service._select_challenger(combined_inside_a, 50.0)
	var inside_result_b := service._select_challenger(combined_inside_b, 50.0)
	_equal(str((inside_result_a.get("force", {}) as Dictionary).get("force_id", "")), "organization:a_inside_challenger", "challenger inside epsilon uses lexical stable-ID tie-break")
	_equal(inside_result_a, inside_result_b, "challenger inside-epsilon winner is permutation invariant")

	var outside_a := _minimal_challenger_force("organization:a_outside_lower", "person:a_outside_lower", 40.0, -50.0, true)
	var outside_z := _minimal_challenger_force("organization:z_outside_higher", "person:z_outside_higher", 55.0, -50.0, true)
	var outside_only_a := base_candidate.duplicate(true)
	outside_only_a["forces"] = [incumbent, outside_a]
	var outside_only_z := base_candidate.duplicate(true)
	outside_only_z["forces"] = [incumbent, outside_z]
	var outside_a_score := float(service._select_challenger(outside_only_a, 50.0).get("mandate_score", 0.0))
	var outside_z_score := float(service._select_challenger(outside_only_z, 50.0).get("mandate_score", 0.0))
	_check(outside_z_score > outside_a_score and not is_equal_approx(outside_z_score, outside_a_score), "challenger outside epsilon has a genuine higher lexical-disadvantaged score")
	var combined_outside_a := base_candidate.duplicate(true)
	combined_outside_a["forces"] = [outside_z, incumbent, outside_a]
	var combined_outside_b := base_candidate.duplicate(true)
	combined_outside_b["forces"] = [outside_a, outside_z, incumbent]
	var outside_result_a := service._select_challenger(combined_outside_a, 50.0)
	var outside_result_b := service._select_challenger(combined_outside_b, 50.0)
	_equal(str((outside_result_a.get("force", {}) as Dictionary).get("force_id", "")), "organization:z_outside_higher", "challenger outside epsilon chooses genuinely higher score over lexical ID")
	_equal(outside_result_a, outside_result_b, "challenger outside-epsilon winner is permutation invariant")


func _test_return_penalty_elapsed_partition() -> void:
	var source := VNextStatePolitics.create_from_config(_limited_challenger_config())
	if source == null:
		_check(false, "return-penalty partition source is valid")
		return
	var first_result := service.update(source, GENERATOR.severe_input(366))
	_check(bool(first_result.get("success", false)) and source.government_change_history().size() == 1, "return-penalty partition source reaches one transition")
	if source.government_change_history().size() != 1:
		return
	var baseline := source.snapshot()
	var last := source.government_change_history().back() as Dictionary
	var last_period := int(last.get("period", 0))
	var former_id := str(last.get("old_government_group_id", ""))
	var penalties: Array[float] = []
	for age: int in [0, 365, 719, 720, 721]:
		var candidate := baseline.duplicate(true)
		candidate["period_index"] = last_period + age
		penalties.append(service._return_government_penalty(candidate, former_id, 0.0))
	_check(is_equal_approx(penalties[0], 18.0), "return penalty day 0 starts at bounded maximum")
	_check(penalties[0] >= penalties[1] and penalties[1] > penalties[2] and penalties[2] > 0.0, "return penalty decreases monotonically through day 719")
	_equal(penalties[3], 0.0, "return penalty is zero at day 720")
	_equal(penalties[4], 0.0, "return penalty remains zero after day 720")
	for penalty: float in penalties:
		_check(penalty >= 0.0 and penalty <= 18.0, "return penalty stays bounded and non-negative")
	print("R3 return penalty boundaries [0,365,719,720,721]: %s" % JSON.stringify(penalties))

	var coarse := VNextStatePolitics.new()
	var daily := VNextStatePolitics.new()
	_check(coarse.restore(baseline) and daily.restore(baseline), "partition paths restore identical transition baseline")
	var coarse_a := service.update(coarse, GENERATOR.recovery_input(365))
	var coarse_b := service.update(coarse, GENERATOR.recovery_input(355))
	_check(bool(coarse_a.get("success", false)) and bool(coarse_b.get("success", false)), "365+355 legal coarse partition succeeds")
	var daily_success := true
	for _day: int in range(720):
		if not bool(service.update(daily, GENERATOR.recovery_input(1)).get("success", false)):
			daily_success = false
			break
	_check(daily_success, "720x1 legal fine partition succeeds")
	_equal(_first_semantic_difference(coarse.snapshot(), daily.snapshot()), "", "365+355 equals 720x1 for complete political state")
	_equal(coarse.government_group_id(), daily.government_group_id(), "partition equivalence preserves government")
	_equal(coarse.government_leader_id(), daily.government_leader_id(), "partition equivalence preserves leader")
	_check(is_equal_approx(coarse.legitimacy(), daily.legitimacy()) and is_equal_approx(coarse.stability(), daily.stability()), "partition equivalence preserves legitimacy and stability")
	_equal(coarse.crisis_stage(), daily.crisis_stage(), "partition equivalence preserves crisis state")
	_equal(coarse.active_policy_ids(), daily.active_policy_ids(), "partition equivalence preserves deterministic policy state")


func _test_recovery_can_stabilize() -> void:
	var state := _load_fixture()
	if state == null:
		return
	var severe := service.update(state, GENERATOR.severe_input(120))
	_check(bool(severe.get("success", false)), "controlled crisis phase completes")
	_check(state.crisis_stage() in ["strained", "crisis"], "controlled pressure can develop a political crisis before transition eligibility")
	var shock_stability := state.stability()
	var recovered := _advance_recovery(state, 1200)
	_check(bool(recovered.get("success", false)), "controlled recovery phase completes")
	_check(state.stability() > shock_stability, "pressure removal improves stability after the controlled crisis")
	_equal(state.crisis_stage(), "stable", "sufficient recovery can return politics to stable state")


func _test_mixed_decade_determinism_and_resume() -> void:
	var continuous := VNextStatePolitics.create_from_config(_limited_challenger_config())
	var replay := VNextStatePolitics.create_from_config(_limited_challenger_config())
	if continuous == null or replay == null:
		_check(false, "mixed-decade fixtures are valid")
		return
	var continuous_severe := _advance_severe(continuous, 1200)
	var replay_severe := _advance_severe(replay, 1200)
	_check(bool(continuous_severe.get("success", false)) and bool(replay_severe.get("success", false)), "mixed decade severe phase completes")
	var severe_history := continuous.government_change_history()
	_check(severe_history.size() >= 2, "mixed decade severe phase develops crisis and government transition")
	for index: int in range(1, severe_history.size()):
		var gap := int((severe_history[index] as Dictionary).get("period", 0)) - int((severe_history[index - 1] as Dictionary).get("period", 0))
		_check(gap >= VNextPoliticsUpdateService.TRANSITION_COOLDOWN_DAYS, "mixed decade has no transition spam at index %d" % index)
	_check(is_finite(continuous.legitimacy()) and continuous.legitimacy() >= 0.0 and continuous.legitimacy() <= 100.0, "severe-phase legitimacy remains finite and bounded")
	_check(is_finite(continuous.stability()) and continuous.stability() >= 0.0 and continuous.stability() <= 100.0, "severe-phase stability remains finite and bounded")

	var midpoint_snapshot := continuous.snapshot()
	var resumed := VNextStatePolitics.new()
	_check(resumed.restore(midpoint_snapshot), "mixed decade midpoint snapshot restores")
	var recovery_days := 900
	var recovery_result := _advance_recovery(continuous, recovery_days)
	var replay_recovery := _advance_recovery(replay, recovery_days)
	var resumed_recovery := _advance_recovery(resumed, recovery_days)
	_check(bool(recovery_result.get("success", false)) and bool(replay_recovery.get("success", false)) and bool(resumed_recovery.get("success", false)), "mixed decade recovery phase completes")

	var remaining := 3650 - 1200 - recovery_days
	var tail_ok := _advance_recovery(continuous, remaining)
	var replay_tail := _advance_recovery(replay, remaining)
	var resumed_tail := _advance_recovery(resumed, remaining)
	_check(bool(tail_ok.get("success", false)) and bool(replay_tail.get("success", false)) and bool(resumed_tail.get("success", false)), "mixed decade reaches exactly 3650 elapsed days")
	_equal(continuous.period_index(), 3650, "mixed decade final period is 3650")
	_equal(_first_semantic_difference(continuous.snapshot(), replay.snapshot()), "", "mixed decade full replay is deterministic")
	_equal(_first_semantic_difference(continuous.snapshot(), resumed.snapshot()), "", "mixed decade snapshot/resume matches continuous path")
	_check(continuous.is_valid(), "mixed decade final state remains valid")
	_check(is_finite(continuous.legitimacy()) and is_finite(continuous.stability()), "mixed decade final political values remain finite")
	print("R3 mixed-decade severe transition sequence: %s" % JSON.stringify(_transition_signature(continuous_severe.get("transitions", []) as Array)))


func _advance_severe(state: VNextStatePolitics, days: int) -> Dictionary:
	var remaining := days
	var transitions: Array[Dictionary] = []
	var last_pressure := 0.0
	while remaining > 0:
		var step := mini(366, remaining)
		var result := service.update(state, GENERATOR.severe_input(step))
		if not bool(result.get("success", false)):
			return {"success": false, "transitions": transitions, "last_pressure": last_pressure}
		last_pressure = float(result.get("political_pressure", 0.0))
		for raw_change: Variant in result.get("government_changes", []) as Array:
			var change := raw_change as Dictionary
			transitions.append({
				"period": int(change.get("period", 0)),
				"old": str(change.get("old_government_group_id", "")),
				"new": str(change.get("new_government_group_id", "")),
				"mandate": float(change.get("mandate_score", 0.0)),
				"coalition": float(change.get("coalition_score", 0.0)),
				"procedure": float(change.get("procedure_score", 0.0)),
				"pressure": float(change.get("political_pressure", 0.0)),
			})
		remaining -= step
	return {"success": true, "transitions": transitions, "last_pressure": last_pressure}


func _advance_severe_daily(state: VNextStatePolitics, days: int) -> Dictionary:
	var transitions: Array[Dictionary] = []
	var last_pressure := 0.0
	for _day: int in range(days):
		var result := service.update(state, GENERATOR.severe_input(1))
		if not bool(result.get("success", false)):
			return {"success": false, "transitions": transitions, "last_pressure": last_pressure}
		last_pressure = float(result.get("political_pressure", 0.0))
		for raw_change: Variant in result.get("government_changes", []) as Array:
			var change := raw_change as Dictionary
			transitions.append({
				"period": int(change.get("period", 0)),
				"old": str(change.get("old_government_group_id", "")),
				"new": str(change.get("new_government_group_id", "")),
				"mandate": float(change.get("mandate_score", 0.0)),
				"coalition": float(change.get("coalition_score", 0.0)),
				"procedure": float(change.get("procedure_score", 0.0)),
				"pressure": float(change.get("political_pressure", 0.0)),
			})
	return {"success": true, "transitions": transitions, "last_pressure": last_pressure}


func _advance_recovery(state: VNextStatePolitics, days: int) -> Dictionary:
	var remaining := days
	while remaining > 0:
		var step := mini(366, remaining)
		var result := service.update(state, GENERATOR.recovery_input(step))
		if not bool(result.get("success", false)):
			return {"success": false}
		remaining -= step
	return {"success": true}


func _assert_restore_rejected_unchanged(state: VNextStatePolitics, candidate: Dictionary, label: String) -> void:
	var before := state.snapshot()
	_check(not state.restore(candidate), label + " rejects")
	_equal(_first_semantic_difference(state.snapshot(), before), "", label + " is transactional")


func _policy_pair_config(base: Dictionary, first: Dictionary, second: Dictionary, reverse: bool) -> Dictionary:
	var config := base.duplicate(true)
	var pair: Array = [first.duplicate(true), second.duplicate(true)]
	if reverse:
		pair.reverse()
	config["policies"] = pair
	config["active_policy_ids"] = []
	return config


func _synthetic_multi_transition_snapshot(base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	result["period_index"] = 600
	result["government_group_id"] = "organization:loran_military_command"
	result["government_leader_id"] = "person:loran_marshal"
	result["government_change_history"] = [
		_transition_record(100, "organization:loran_government_group", "person:loran_premier", "organization:loran_labor_caucus", "person:loran_labor_leader"),
		_transition_record(500, "organization:loran_labor_caucus", "person:loran_labor_leader", "organization:loran_military_command", "person:loran_marshal"),
	]
	return result


func _transition_record(period: int, old_group: String, old_leader: String, new_group: String, new_leader: String) -> Dictionary:
	return {
		"period": period,
		"reason": "sustained_government_failure",
		"old_government_group_id": old_group,
		"new_government_group_id": new_group,
		"old_leader_id": old_leader,
		"new_leader_id": new_leader,
		"political_pressure": 80.0,
		"mandate_score": 70.0,
		"procedure_score": 65.0,
		"coalition_score": 60.0,
	}


func _limited_challenger_config() -> Dictionary:
	var config := _load_fixture_config()
	var selected: Array = []
	for raw_force: Variant in config.get("forces", []) as Array:
		var force := (raw_force as Dictionary).duplicate(true)
		var force_id := str(force.get("force_id", ""))
		if force_id == "organization:loran_government_group":
			force["influence"] = 50.0
			force["government_support"] = 80.0
			force["base_government_support"] = 80.0
			selected.append(force)
		elif force_id == "organization:loran_labor_caucus":
			force["influence"] = 50.0
			force["government_support"] = -60.0
			force["base_government_support"] = -60.0
			selected.append(force)
	config["forces"] = selected
	return config


func _minimal_challenger_force(force_id: String, leader_id: String, influence: float, support: float, eligible: bool) -> Dictionary:
	var preferences := {}
	for domain: String in VNextStatePolitics.POLICY_DOMAINS:
		preferences[domain] = 0.0
	return {
		"force_id": force_id,
		"leader_id": leader_id,
		"influence": influence,
		"government_support": support,
		"institutional_access": 70.0,
		"mobilization_capacity": 70.0,
		"government_eligible": eligible,
		"policy_preferences": preferences,
	}


func _transition_signature(evidence: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_item: Variant in evidence:
		var item := raw_item as Dictionary
		result.append("%d:%s>%s" % [int(item.get("period", 0)), str(item.get("old", "")), str(item.get("new", ""))])
	return result


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
