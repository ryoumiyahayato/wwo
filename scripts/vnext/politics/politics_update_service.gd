class_name VNextPoliticsUpdateService
extends RefCounted

## Deterministic political simulation over authoritative elapsed days.
## A multi-day call follows exactly the same daily micro-steps as partitioned calls.


const PRESSURE_SCALE: float = 12.0
const FORCE_DELTA_LIMIT: float = 18.0
const POLICY_REVIEW_COOLDOWN: int = 90
const POLICY_CHANGE_MARGIN: float = 4.0
const EMERGENCY_POLICY_PRESSURE: float = 70.0
const POLICY_PRIORITY_SIGNAL_THRESHOLD: float = 65.0
const POLICY_PRIORITY_BONUS: float = 10.0
const STRAINED_STREAK: int = 30
const CRISIS_STREAK: int = 90
const GOVERNMENT_CHANGE_STREAK: int = 180
const RECOVERY_TO_STABLE_STREAK: int = 90
const CRISIS_SUPPORT_THRESHOLD: float = 46.0
const CRISIS_CONTROL_THRESHOLD: float = 32.0
const CRISIS_LEGITIMACY_THRESHOLD: float = 38.0
const CRISIS_STABILITY_THRESHOLD: float = 42.0
const CRITICAL_SUPPORT_THRESHOLD: float = 35.0
const CRITICAL_CONTROL_THRESHOLD: float = 26.0
const CRITICAL_STABILITY_THRESHOLD: float = 30.0
const MAX_HISTORY: int = 96

const ECONOMIC_WEIGHTS: Dictionary = {
	"price_pressure": 0.24,
	"unemployment_pressure": 0.26,
	"fiscal_pressure": 0.22,
	"shortage_pressure": 0.20,
	"growth_signal": 0.08,
}
const WAR_WEIGHTS: Dictionary = {
	"war_pressure": 0.35,
	"casualty_pressure": 0.30,
	"mobilization_pressure": 0.15,
	"military_result_signal": 0.20,
}
const REGIME_PROCEDURAL_BASELINES: Dictionary = {
	"absolute_monarchy": 42.0,
	"constitutional_monarchy": 58.0,
	"parliamentary_monarchy": 72.0,
	"parliamentary_republic": 74.0,
	"presidential_republic": 64.0,
	"federal_republic": 70.0,
	"military_rule": 38.0,
	"imperial_bureaucracy": 46.0,
	"colonial_administration": 34.0,
}

enum {
	MONTH_DAYS = 30,
	POLICY_REVIEW_COOLDOWN_DAYS = 90,
	STRAINED_DAYS = 30,
	CRISIS_DAYS = 90,
	GOVERNMENT_CHANGE_DAYS = 180,
	RECOVERY_TO_STABLE_DAYS = 90,
	TRANSITION_MIN_DAYS = 120,
	MIN_INITIAL_TENURE_DAYS = 180,
	TRANSITION_COOLDOWN_DAYS = 365,
	RETURN_GOVERNMENT_PENALTY_DAYS = 720,
	CHALLENGER_MANDATE_THRESHOLD = 55,
}


func update(state: VNextStatePolitics, pressure_input: VNextPoliticsPressureInput) -> Dictionary:
	if state == null or not state.is_valid():
		return _fail("invalid_state", "a valid state politics object is required")
	if pressure_input == null or not pressure_input.is_valid():
		return _fail("invalid_pressure_input", "a valid political pressure input is required")

	var candidate := state.snapshot()
	var economic_pressure := _economic_pressure(pressure_input)
	var war_pressure := _war_pressure(pressure_input)
	var total_pressure := clampf(economic_pressure * 0.58 + war_pressure * 0.42, 0.0, 100.0)
	var policy_changes: Array[Dictionary] = []
	var government_changes: Array[Dictionary] = []
	var daily_input := pressure_input.snapshot()
	daily_input["period_days"] = 1

	for _day: int in range(pressure_input.period_days()):
		var step := _advance_one_day(candidate, pressure_input, daily_input, total_pressure)
		if not bool(step.get("success", false)):
			return step
		candidate = step.get("candidate", {}) as Dictionary
		for change: Variant in step.get("policy_changes", []) as Array:
			policy_changes.append((change as Dictionary).duplicate(true))
		var government_change: Dictionary = step.get("government_change", {}) as Dictionary
		if not government_change.is_empty():
			government_changes.append(government_change.duplicate(true))

	if not state.restore(candidate):
		return _fail("state_commit_rejected", "political update produced an invalid state")

	var last_government_change: Dictionary = {}
	if not government_changes.is_empty():
		last_government_change = government_changes.back().duplicate(true)
	return {
		"success": true,
		"period_index": state.period_index(),
		"elapsed_days": pressure_input.period_days(),
		"economic_pressure": economic_pressure,
		"war_pressure": war_pressure,
		"political_pressure": total_pressure,
		"government_support": state.government_support(),
		"legitimacy": state.legitimacy(),
		"stability": state.stability(),
		"control_capacity": state.capacity("control"),
		"crisis_stage": state.crisis_stage(),
		"government_viable": state.government_is_viable(),
		"supporting_force_ids": state.supporting_force_ids(),
		"opposing_force_ids": state.opposing_force_ids(),
		"active_policy_ids": state.active_policy_ids(),
		"policy_changes": policy_changes,
		"government_crisis": state.crisis_stage() in ["strained", "crisis", "transition"],
		"government_changed": not government_changes.is_empty(),
		"government_change": last_government_change,
		"government_changes": government_changes,
		"snapshot": state.snapshot(),
	}


func _advance_one_day(
	candidate: Dictionary,
	input: VNextPoliticsPressureInput,
	daily_input: Dictionary,
	total_pressure: float
) -> Dictionary:
	var next_day := int(candidate.get("period_index", 0)) + 1
	if next_day > VNextStatePolitics.MAX_ELAPSED_DAYS:
		return _fail("elapsed_day_overflow", "political elapsed-day bound exceeded")
	var current_group_id := str(candidate.get("government_group_id", ""))
	var forces := _sorted_forces(candidate.get("forces", []) as Array)
	var active := _sorted_active(candidate.get("active_policies", []) as Array)
	var policies := _sorted_policies(candidate.get("policies", []) as Array)

	for index: int in range(forces.size()):
		var force := forces[index]
		var old_support := float(force.get("government_support", 0.0))
		var monthly_delta := _force_external_delta(force, input)
		monthly_delta += _force_policy_delta(force, active, policies)
		var support_delta := monthly_delta / float(MONTH_DAYS)
		if total_pressure < 25.0:
			support_delta += (float(force.get("base_government_support", old_support)) - old_support) * 0.002
		if input.growth_signal() > 0.0:
			support_delta += input.growth_signal() * 0.0004
		var daily_delta_limit := FORCE_DELTA_LIMIT / float(MONTH_DAYS)
		support_delta = clampf(support_delta, -daily_delta_limit, daily_delta_limit)
		var new_support := clampf(old_support + support_delta, -100.0, 100.0)
		force["government_support"] = new_support
		force["last_support_delta"] = support_delta
		var support_history := (force.get("support_history", []) as Array).duplicate(true)
		support_history.append({"period": next_day, "support": new_support, "delta": support_delta})
		while support_history.size() > VNextStatePolitics.MAX_FORCE_HISTORY:
			support_history.pop_front()
		force["support_history"] = support_history
		forces[index] = force
	candidate["forces"] = forces
	candidate["period_index"] = next_day
	candidate["last_pressure_input"] = daily_input.duplicate(true)

	var capacity := _update_capacity(candidate.get("capacity", {}) as Dictionary, input, total_pressure)
	candidate["capacity"] = capacity
	var control := float(capacity.get("control", 0.0))
	candidate["active_policies"] = _update_active_policy_implementation(candidate, control)
	var policy_changes := _review_policies(candidate, input, total_pressure, control)
	active = _sorted_active(candidate.get("active_policies", []) as Array)

	var weighted_support := _weighted_support(forces)
	var coalition_cohesion := _governing_cohesion(forces, current_group_id)
	var policy_fit := _policy_fit(candidate, active, policies)
	var policy_burden := _policy_burden(active, policies)
	var leader_effect := _stable_actor_effect(str(candidate.get("government_leader_id", "")), 3.0)
	var institution_effect := _stable_actor_effect(str(candidate.get("government_id", "")), 2.0)
	var procedural_baseline := clampf(
		float(REGIME_PROCEDURAL_BASELINES.get(str(candidate.get("regime_type", "")), 50.0)) + institution_effect,
		0.0,
		100.0
	)
	var corruption := float(capacity.get("corruption", 0.0))
	var legitimacy_target := clampf(
		weighted_support * 0.25
			+ control * 0.20
			+ policy_fit * 0.17
			+ coalition_cohesion * 0.10
			+ procedural_baseline * 0.13
			+ (100.0 - corruption) * 0.15
			- total_pressure * 0.28
			+ input.military_result_signal() * 0.08
			+ leader_effect,
		0.0,
		100.0
	)
	var legitimacy := lerpf(float(candidate.get("legitimacy", 0.0)), legitimacy_target, _daily_alpha(0.20))
	var stability_target := clampf(
		legitimacy * 0.27
			+ control * 0.28
			+ weighted_support * 0.22
			+ policy_fit * 0.10
			+ coalition_cohesion * 0.08
			- total_pressure * 0.42
			- policy_burden * 0.12
			+ input.military_result_signal() * 0.05
			+ leader_effect * 0.5,
		0.0,
		100.0
	)
	var stability := lerpf(float(candidate.get("stability", 0.0)), stability_target, _daily_alpha(0.22))
	candidate["legitimacy"] = clampf(legitimacy, 0.0, 100.0)
	candidate["stability"] = clampf(stability, 0.0, 100.0)
	candidate["government_support"] = weighted_support

	var unstable := _is_unstable(weighted_support, control, legitimacy, stability, coalition_cohesion, leader_effect, total_pressure)
	var instability_days := int(candidate.get("instability_streak", 0)) + 1 if unstable else maxi(0, int(candidate.get("instability_streak", 0)) - 1)
	var recovery_days := int(candidate.get("recovery_streak", 0)) + 1 if not unstable else 0
	candidate["instability_streak"] = instability_days
	candidate["recovery_streak"] = recovery_days
	var days_since_change := _days_since_last_change(candidate, next_day)
	candidate["crisis_stage"] = _next_crisis_stage(
		str(candidate.get("crisis_stage", "stable")), unstable, instability_days,
		recovery_days, days_since_change
	)

	var government_change: Dictionary = {}
	if (
		instability_days >= GOVERNMENT_CHANGE_DAYS
		and weighted_support < 48.0
		and str(candidate.get("crisis_stage", "")) == "crisis"
		and _transition_allowed(candidate, next_day)
	):
		var challenger := _select_challenger(candidate, total_pressure)
		if not challenger.is_empty():
			government_change = _apply_government_change(candidate, challenger, total_pressure)
			forces = _sorted_forces(candidate.get("forces", []) as Array)
			weighted_support = _weighted_support(forces)
			candidate["government_support"] = weighted_support

	var final_capacity := candidate.get("capacity", {}) as Dictionary
	candidate["government_viability"] = (
		weighted_support >= VNextStatePolitics.VIABILITY_SUPPORT_THRESHOLD
		and float(final_capacity.get("control", 0.0)) >= VNextStatePolitics.VIABILITY_CONTROL_THRESHOLD
		and float(candidate.get("legitimacy", 0.0)) >= VNextStatePolitics.VIABILITY_LEGITIMACY_THRESHOLD
		and float(candidate.get("stability", 0.0)) >= VNextStatePolitics.VIABILITY_STABILITY_THRESHOLD
	)
	return {
		"success": true,
		"candidate": candidate,
		"policy_changes": policy_changes,
		"government_change": government_change,
	}


func _economic_pressure(input: VNextPoliticsPressureInput) -> float:
	var result := 0.0
	for signal_key: String in ["price_pressure", "unemployment_pressure", "fiscal_pressure", "shortage_pressure"]:
		result += maxf(0.0, input.economic_signal_value(signal_key)) * float(ECONOMIC_WEIGHTS.get(signal_key, 0.0))
	result += maxf(0.0, -input.growth_signal()) * float(ECONOMIC_WEIGHTS.get("growth_signal", 0.0))
	return clampf(result, 0.0, 100.0)


func _war_pressure(input: VNextPoliticsPressureInput) -> float:
	var result := 0.0
	result += maxf(0.0, input.war_pressure()) * float(WAR_WEIGHTS["war_pressure"])
	result += maxf(0.0, input.casualty_pressure()) * float(WAR_WEIGHTS["casualty_pressure"])
	result += maxf(0.0, input.mobilization_pressure()) * float(WAR_WEIGHTS["mobilization_pressure"])
	result += maxf(0.0, -input.military_result_signal()) * float(WAR_WEIGHTS["military_result_signal"])
	return clampf(result, 0.0, 100.0)


func _force_external_delta(force: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var response := force.get("pressure_response", {}) as Dictionary
	var result := 0.0
	for signal_key: String in VNextStatePolitics.PRESSURE_SIGNAL_KEYS:
		var signal_value := input.economic_signal_value(signal_key) if signal_key in VNextPoliticsPressureInput.ECONOMIC_SIGNAL_KEYS else input.war_signal_value(signal_key)
		result += signal_value * float(response.get(signal_key, 0.0))
	return clampf(result / PRESSURE_SCALE, -18.0, 18.0)


func _force_policy_delta(force: Dictionary, active_policies: Array, policies: Array) -> float:
	var result := 0.0
	var preferences := force.get("policy_preferences", {}) as Dictionary
	for active: Dictionary in _sorted_active(active_policies):
		var policy := _policy_by_id(policies, str(active.get("policy_id", "")))
		if policy.is_empty():
			continue
		var domain := str(policy.get("domain", ""))
		var preference := float(preferences.get(domain, 0.0))
		var alignment := _position_alignment(preference, float(policy.get("position", 0.0)))
		result += alignment * float(active.get("implementation_strength", 0.0)) * 2.0
	return clampf(result, -6.0, 6.0)


func _update_capacity(old_capacity: Dictionary, input: VNextPoliticsPressureInput, total_pressure: float) -> Dictionary:
	var old_admin := float(old_capacity.get("administrative", 0.0))
	var old_enforcement := float(old_capacity.get("enforcement", 0.0))
	var old_fiscal := float(old_capacity.get("fiscal", 0.0))
	var old_corruption := float(old_capacity.get("corruption", 0.0))
	var old_control := float(old_capacity.get("control", 0.0))
	var positive_growth := maxf(0.0, input.growth_signal())
	var admin_target := clampf(old_admin - total_pressure * 0.08 + positive_growth * 0.035, 0.0, 100.0)
	var enforcement_target := clampf(
		old_enforcement - total_pressure * 0.06 + input.mobilization_pressure() * 0.035 - input.casualty_pressure() * 0.025,
		0.0, 100.0
	)
	var fiscal_target := clampf(old_fiscal - input.fiscal_pressure() * 0.10 - total_pressure * 0.025 + positive_growth * 0.04, 0.0, 100.0)
	var corruption_target := clampf(old_corruption + input.fiscal_pressure() * 0.065 + input.shortage_pressure() * 0.035 - old_admin * 0.012, 0.0, 100.0)
	var control_target := clampf(
		admin_target * 0.30 + enforcement_target * 0.25 + fiscal_target * 0.20
			+ (100.0 - corruption_target) * 0.10 + old_control * 0.15 - total_pressure * 0.32,
		0.0, 100.0
	)
	return {
		"administrative": lerpf(old_admin, admin_target, _daily_alpha(0.20)),
		"enforcement": lerpf(old_enforcement, enforcement_target, _daily_alpha(0.20)),
		"fiscal": lerpf(old_fiscal, fiscal_target, _daily_alpha(0.20)),
		"corruption": lerpf(old_corruption, corruption_target, _daily_alpha(0.20)),
		"control": lerpf(old_control, control_target, _daily_alpha(0.25)),
	}


func _update_active_policy_implementation(candidate: Dictionary, control: float) -> Array[Dictionary]:
	var active := _sorted_active(candidate.get("active_policies", []) as Array)
	var policies := _sorted_policies(candidate.get("policies", []) as Array)
	var forces := _sorted_forces(candidate.get("forces", []) as Array)
	var group_id := str(candidate.get("government_group_id", ""))
	var leader_effect := _stable_actor_effect(str(candidate.get("government_leader_id", "")), 3.0)
	for index: int in range(active.size()):
		var item := active[index]
		var policy := _policy_by_id(policies, str(item.get("policy_id", "")))
		if policy.is_empty():
			continue
		var alignment := _policy_governing_alignment(policy, forces, group_id)
		var target := clampf((control / 100.0) * (0.72 + alignment * 0.0028) + leader_effect * 0.005, 0.10, 1.0)
		item["implementation_strength"] = lerpf(float(item.get("implementation_strength", 0.0)), target, 0.01)
		active[index] = item
	return active


func _review_policies(candidate: Dictionary, input: VNextPoliticsPressureInput, total_pressure: float, control: float) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var period := int(candidate.get("period_index", 0))
	var last_review := int(candidate.get("last_policy_review_period", -1))
	if period - last_review < POLICY_REVIEW_COOLDOWN_DAYS:
		return changes
	candidate["last_policy_review_period"] = period
	var forces := _sorted_forces(candidate.get("forces", []) as Array)
	var policies := _sorted_policies(candidate.get("policies", []) as Array)
	var active := _sorted_active(candidate.get("active_policies", []) as Array)
	for index: int in range(active.size()):
		var active_item := active[index]
		active_item["last_review_period"] = period
		active[index] = active_item
	candidate["active_policies"] = active

	var best_policy: Dictionary = {}
	var best_score := -1.0e30
	for policy: Dictionary in policies:
		if control < float(policy.get("required_control", 0.0)) * 0.45:
			continue
		var score := _policy_score(policy, candidate, input, total_pressure)
		if score > best_score or (is_equal_approx(score, best_score) and str(policy.get("policy_id", "")) < str(best_policy.get("policy_id", "~"))):
			best_score = score
			best_policy = policy
	if best_policy.is_empty():
		return changes
	var current_score := _active_policy_score(active, policies, candidate, input, total_pressure)
	var current_same_policy := false
	for active_item: Dictionary in active:
		if str(active_item.get("policy_id", "")) == str(best_policy.get("policy_id", "")):
			current_same_policy = true
			break
	var should_change := (
		active.is_empty()
		or (not current_same_policy and best_score >= current_score + POLICY_CHANGE_MARGIN)
		or (total_pressure >= EMERGENCY_POLICY_PRESSURE and not current_same_policy and best_score >= current_score + 2.0)
	)
	if not should_change:
		return changes

	var best_domain := str(best_policy.get("domain", ""))
	var replaced_policy_id := ""
	for index: int in range(active.size()):
		var old_active := active[index]
		var old_policy := _policy_by_id(policies, str(old_active.get("policy_id", "")))
		if str(old_policy.get("domain", "")) == best_domain:
			replaced_policy_id = str(old_active.get("policy_id", ""))
			active[index] = _new_active_policy(str(best_policy.get("policy_id", "")), period, control, candidate)
			break
	if replaced_policy_id.is_empty():
		if active.size() >= 4:
			active.pop_front()
		active.append(_new_active_policy(str(best_policy.get("policy_id", "")), period, control, candidate))
	candidate["active_policies"] = _sorted_active(active)
	var history := (candidate.get("policy_history", []) as Array).duplicate(true)
	history.append({
		"period": period,
		"action": "adopted",
		"policy_id": best_policy.get("policy_id", ""),
		"replaced_policy_id": replaced_policy_id,
		"political_pressure": total_pressure,
		"support_score": best_score,
	})
	while history.size() > MAX_HISTORY:
		history.pop_front()
	candidate["policy_history"] = history
	changes.append({
		"action": "adopted",
		"policy_id": best_policy.get("policy_id", ""),
		"replaced_policy_id": replaced_policy_id,
		"score": best_score,
		"period": period,
	})
	return changes


func _policy_score(policy: Dictionary, candidate: Dictionary, input: VNextPoliticsPressureInput, total_pressure: float) -> float:
	var forces := _sorted_forces(candidate.get("forces", []) as Array)
	var alignment := _policy_governing_alignment(policy, forces, str(candidate.get("government_group_id", "")))
	var urgency := _policy_pressure_fit(policy, input)
	var relief := _policy_relief_fit(policy, input)
	var fiscal_penalty := float(policy.get("fiscal_demand", 0.0)) * (0.35 + input.fiscal_pressure() / 180.0)
	var emergency_bonus := total_pressure * 0.08 if total_pressure >= 60.0 else 0.0
	var leader_effect := _stable_actor_effect(str(candidate.get("government_leader_id", "")), 3.0)
	return alignment * 0.54 + urgency * 0.24 + relief * 0.22 - fiscal_penalty * 0.12 + emergency_bonus + _policy_priority_bonus(policy, input) + leader_effect * 0.8


func _active_policy_score(active: Array, policies: Array, candidate: Dictionary, input: VNextPoliticsPressureInput, total_pressure: float) -> float:
	if active.is_empty():
		return 0.0
	var total := 0.0
	var count := 0
	for active_item: Dictionary in _sorted_active(active):
		var policy := _policy_by_id(policies, str(active_item.get("policy_id", "")))
		if policy.is_empty():
			continue
		total += _policy_score(policy, candidate, input, total_pressure)
		count += 1
	return total / float(maxi(1, count))


func _policy_priority_bonus(policy: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var reliefs := policy.get("political_relief", {}) as Dictionary
	var bonus := 0.0
	for key: String in _sorted_keys(reliefs):
		var signal_value := input.economic_signal_value(key)
		if key in VNextPoliticsPressureInput.WAR_SIGNAL_KEYS:
			signal_value = input.war_signal_value(key)
		if key == "growth_signal":
			signal_value = -signal_value
		if signal_value >= POLICY_PRIORITY_SIGNAL_THRESHOLD and float(reliefs.get(key, 0.0)) >= 40.0:
			bonus = maxf(bonus, POLICY_PRIORITY_BONUS)
	return bonus


func _policy_governing_alignment(policy: Dictionary, forces: Array, current_group_id: String) -> float:
	var total_weight := 0.0
	var weighted_alignment := 0.0
	var domain := str(policy.get("domain", ""))
	var position := float(policy.get("position", 0.0))
	for force: Dictionary in _sorted_forces(forces):
		var force_id := str(force.get("force_id", ""))
		var support := float(force.get("government_support", 0.0))
		var weight := 0.0
		if force_id == current_group_id:
			weight = maxf(8.0, float(force.get("influence", 0.0)) * 1.8)
		elif support >= VNextStatePolitics.FORCE_SUPPORT_THRESHOLD:
			weight = float(force.get("influence", 0.0)) * clampf((support + 20.0) / 120.0, 0.15, 0.75)
		if weight <= 0.0:
			continue
		var preference := float((force.get("policy_preferences", {}) as Dictionary).get(domain, 0.0))
		total_weight += weight
		weighted_alignment += weight * _position_alignment(preference, position)
	if total_weight <= 0.0:
		return 50.0
	return clampf((weighted_alignment / total_weight + 1.0) * 50.0, 0.0, 100.0)


func _governing_cohesion(forces: Array, current_group_id: String) -> float:
	var incumbent := _force_by_id(forces, current_group_id)
	if incumbent.is_empty():
		return 0.0
	var total_weight := maxf(1.0, float(incumbent.get("influence", 0.0)))
	var weighted := total_weight * 100.0
	for force: Dictionary in _sorted_forces(forces):
		if str(force.get("force_id", "")) == current_group_id:
			continue
		var support := float(force.get("government_support", 0.0))
		if support < VNextStatePolitics.FORCE_SUPPORT_THRESHOLD:
			continue
		var weight := float(force.get("influence", 0.0)) * clampf(support / 100.0, 0.1, 1.0)
		weighted += weight * _force_pair_alignment(incumbent, force)
		total_weight += weight
	return clampf(weighted / maxf(1.0, total_weight), 0.0, 100.0)


func _policy_pressure_fit(policy: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var targets := policy.get("pressure_targets", {}) as Dictionary
	var total_weight := 0.0
	var score := 0.0
	for key: String in _sorted_keys(targets):
		var weight := float(targets.get(key, 0.0))
		var signal_value := input.economic_signal_value(key)
		if key in VNextPoliticsPressureInput.WAR_SIGNAL_KEYS:
			signal_value = input.war_signal_value(key)
		if key == "growth_signal":
			signal_value = -signal_value
		score += maxf(0.0, signal_value) * weight
		total_weight += weight
	return 0.0 if total_weight <= 0.0 else clampf(score / total_weight, 0.0, 100.0)


func _policy_relief_fit(policy: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var reliefs := policy.get("political_relief", {}) as Dictionary
	var total_weight := 0.0
	var score := 0.0
	for key: String in _sorted_keys(reliefs):
		var relief := float(reliefs.get(key, 0.0))
		var signal_value := input.economic_signal_value(key)
		if key in VNextPoliticsPressureInput.WAR_SIGNAL_KEYS:
			signal_value = input.war_signal_value(key)
		if key == "growth_signal":
			signal_value = -signal_value
		score += maxf(0.0, signal_value) * relief
		total_weight += relief
	return 0.0 if total_weight <= 0.0 else clampf(score / total_weight, 0.0, 100.0)


func _policy_fit(candidate: Dictionary, active_policies: Array, policies: Array) -> float:
	if active_policies.is_empty():
		return 35.0
	var total := 0.0
	var count := 0
	var forces := candidate.get("forces", []) as Array
	var group_id := str(candidate.get("government_group_id", ""))
	for active: Dictionary in _sorted_active(active_policies):
		var policy := _policy_by_id(policies, str(active.get("policy_id", "")))
		if policy.is_empty():
			continue
		total += _policy_governing_alignment(policy, forces, group_id)
		count += 1
	return total / float(maxi(1, count))


func _policy_burden(active_policies: Array, policies: Array) -> float:
	if active_policies.is_empty():
		return 0.0
	var burden := 0.0
	var count := 0
	for active: Dictionary in _sorted_active(active_policies):
		var policy := _policy_by_id(policies, str(active.get("policy_id", "")))
		if policy.is_empty():
			continue
		burden += (float(policy.get("fiscal_demand", 0.0)) + float(policy.get("administrative_demand", 0.0))) * 0.5 * float(active.get("implementation_strength", 0.0))
		count += 1
	return clampf(burden / float(maxi(1, count)), 0.0, 100.0)


func _new_active_policy(policy_id: String, period: int, control: float, candidate: Dictionary) -> Dictionary:
	var policy := _policy_by_id(candidate.get("policies", []) as Array, policy_id)
	var alignment := _policy_governing_alignment(policy, candidate.get("forces", []) as Array, str(candidate.get("government_group_id", "")))
	var leader_effect := _stable_actor_effect(str(candidate.get("government_leader_id", "")), 3.0)
	var strength := clampf((control / 100.0) * (0.72 + alignment * 0.0028) + leader_effect * 0.005, 0.15, 1.0)
	return {
		"policy_id": policy_id,
		"started_period": period,
		"implementation_strength": strength,
		"last_review_period": period,
		"status": "implementing",
	}


func _is_unstable(weighted_support: float, control: float, legitimacy: float, stability: float, coalition_cohesion: float, leader_effect: float, total_pressure: float) -> bool:
	var resilience := clampf((coalition_cohesion - 50.0) * 0.04 + leader_effect * 0.8, -6.0, 6.0)
	return (
		total_pressure >= 45.0
		or weighted_support < CRISIS_SUPPORT_THRESHOLD - resilience
		or control < CRISIS_CONTROL_THRESHOLD - resilience * 0.6
		or legitimacy < CRISIS_LEGITIMACY_THRESHOLD - resilience * 0.7
		or stability < CRISIS_STABILITY_THRESHOLD - resilience * 0.7
	)


func _next_crisis_stage(old_stage: String, unstable: bool, instability_days: int, recovery_days: int, days_since_change: int) -> String:
	if old_stage == "transition" and days_since_change < TRANSITION_MIN_DAYS:
		return "transition"
	if instability_days >= CRISIS_DAYS:
		return "crisis"
	if unstable or instability_days >= STRAINED_DAYS:
		return "strained"
	if old_stage == "crisis" and recovery_days < RECOVERY_TO_STABLE_DAYS:
		return "strained"
	if old_stage == "transition" and recovery_days < RECOVERY_TO_STABLE_DAYS:
		return "transition"
	return "stable"


func _transition_allowed(candidate: Dictionary, current_day: int) -> bool:
	var history := _sorted_history(candidate.get("government_change_history", []) as Array)
	if history.is_empty():
		return current_day >= MIN_INITIAL_TENURE_DAYS
	var last_day := int(history.back().get("period", 0))
	return current_day - last_day >= TRANSITION_COOLDOWN_DAYS


func _days_since_last_change(candidate: Dictionary, current_day: int) -> int:
	var history := _sorted_history(candidate.get("government_change_history", []) as Array)
	if history.is_empty():
		return current_day
	return maxi(0, current_day - int(history.back().get("period", current_day)))


func _select_challenger(candidate: Dictionary, total_pressure: float) -> Dictionary:
	var forces := _sorted_forces(candidate.get("forces", []) as Array)
	var current_group_id := str(candidate.get("government_group_id", ""))
	var best: Dictionary = {}
	var best_score := -1.0e30
	for force: Dictionary in forces:
		var force_id := str(force.get("force_id", ""))
		if force_id == current_group_id or not bool(force.get("government_eligible", false)):
			continue
		var opposition := clampf(50.0 - float(force.get("government_support", 0.0)) * 0.5, 0.0, 100.0)
		if opposition < 35.0:
			continue
		var power := (
			float(force.get("influence", 0.0)) * 0.40
			+ float(force.get("institutional_access", 0.0)) * 0.35
			+ float(force.get("mobilization_capacity", 0.0)) * 0.25
		)
		var coalition := _challenger_coalition_feasibility(force, forces, current_group_id)
		var procedure := _challenger_procedure_score(candidate, force, total_pressure)
		var mandate := power * 0.30 + opposition * 0.25 + coalition * 0.30 + procedure * 0.15
		mandate -= _return_government_penalty(candidate, force_id)
		mandate = clampf(mandate, 0.0, 100.0)
		if mandate > best_score or (is_equal_approx(mandate, best_score) and force_id < str((best.get("force", {}) as Dictionary).get("force_id", "~"))):
			best_score = mandate
			best = {
				"force": force.duplicate(true),
				"mandate_score": mandate,
				"procedure_score": procedure,
				"coalition_score": coalition,
			}
	if best_score < CHALLENGER_MANDATE_THRESHOLD:
		return {}
	return best


func _challenger_coalition_feasibility(challenger: Dictionary, forces: Array, current_group_id: String) -> float:
	var total_weight := maxf(1.0, float(challenger.get("influence", 0.0)))
	var weighted := total_weight * 100.0
	for force: Dictionary in _sorted_forces(forces):
		var force_id := str(force.get("force_id", ""))
		if force_id == str(challenger.get("force_id", "")) or force_id == current_group_id:
			continue
		var incumbent_support := float(force.get("government_support", 0.0))
		if incumbent_support > 35.0:
			continue
		var opposition_factor := clampf((50.0 - incumbent_support) / 100.0, 0.15, 1.0)
		var weight := float(force.get("influence", 0.0)) * opposition_factor
		weighted += weight * _force_pair_alignment(challenger, force)
		total_weight += weight
	return clampf(weighted / maxf(1.0, total_weight), 0.0, 100.0)


func _challenger_procedure_score(candidate: Dictionary, challenger: Dictionary, total_pressure: float) -> float:
	var regime_base := float(REGIME_PROCEDURAL_BASELINES.get(str(candidate.get("regime_type", "")), 50.0))
	var institutional := float(challenger.get("institutional_access", 0.0))
	var mobilization := float(challenger.get("mobilization_capacity", 0.0))
	var institution_effect := _stable_actor_effect(str(candidate.get("government_id", "")), 2.0)
	var score := regime_base * 0.50 + institutional * 0.32 + mobilization * 0.12 + total_pressure * 0.06 + institution_effect
	return clampf(score, 0.0, 100.0)


func _return_government_penalty(candidate: Dictionary, challenger_id: String) -> float:
	var history := _sorted_history(candidate.get("government_change_history", []) as Array)
	if history.is_empty():
		return 0.0
	var last: Dictionary = history.back() as Dictionary
	if challenger_id != str(last.get("old_government_group_id", "")):
		return 0.0
	var age := int(candidate.get("period_index", 0)) - int(last.get("period", 0))
	return 100.0 if age < RETURN_GOVERNMENT_PENALTY_DAYS else 0.0


func _apply_government_change(candidate: Dictionary, challenger_result: Dictionary, total_pressure: float) -> Dictionary:
	var challenger := challenger_result.get("force", {}) as Dictionary
	var new_group_id := str(challenger.get("force_id", ""))
	var old_group_id := str(candidate.get("government_group_id", ""))
	var old_leader_id := str(candidate.get("government_leader_id", ""))
	var new_leader_id := str(challenger.get("leader_id", ""))
	var period := int(candidate.get("period_index", 0))
	var mandate := float(challenger_result.get("mandate_score", 0.0))
	var procedure := float(challenger_result.get("procedure_score", 0.0))
	var coalition := float(challenger_result.get("coalition_score", 0.0))

	candidate["government_group_id"] = new_group_id
	candidate["government_leader_id"] = new_leader_id
	var forces := _sorted_forces(candidate.get("forces", []) as Array)
	for index: int in range(forces.size()):
		var force := forces[index]
		var old_support := float(force.get("government_support", 0.0))
		var baseline := _support_baseline_for_new_government(force, challenger, old_group_id, new_group_id, mandate)
		force["base_government_support"] = baseline
		force["government_support"] = baseline
		force["last_support_delta"] = baseline - old_support
		var support_history := (force.get("support_history", []) as Array).duplicate(true)
		var rebase_record: Dictionary = {"period": period, "support": baseline, "delta": baseline - old_support}
		if not support_history.is_empty() and int((support_history.back() as Dictionary).get("period", -1)) == period:
			support_history[support_history.size() - 1] = rebase_record
		else:
			support_history.append(rebase_record)
		while support_history.size() > VNextStatePolitics.MAX_FORCE_HISTORY:
			support_history.pop_front()
		force["support_history"] = support_history
		forces[index] = force
	candidate["forces"] = forces

	var transition_legitimacy := clampf(25.0 + mandate * 0.35 + procedure * 0.14 + coalition * 0.12 - total_pressure * 0.10, 20.0, 75.0)
	candidate["legitimacy"] = lerpf(float(candidate.get("legitimacy", 0.0)), transition_legitimacy, 0.55)
	candidate["stability"] = maxf(20.0, float(candidate.get("stability", 0.0)) * 0.92)
	candidate["instability_streak"] = 0
	candidate["recovery_streak"] = 0
	candidate["crisis_stage"] = "transition"
	candidate["last_policy_review_period"] = maxi(0, period - POLICY_REVIEW_COOLDOWN_DAYS)

	var change_record := {
		"period": period,
		"reason": "sustained_government_failure",
		"old_government_group_id": old_group_id,
		"new_government_group_id": new_group_id,
		"old_leader_id": old_leader_id,
		"new_leader_id": new_leader_id,
		"political_pressure": total_pressure,
		"mandate_score": mandate,
		"procedure_score": procedure,
		"coalition_score": coalition,
	}
	var history := (candidate.get("government_change_history", []) as Array).duplicate(true)
	history.append(change_record)
	while history.size() > VNextStatePolitics.MAX_GOVERNMENT_CHANGE_HISTORY:
		history.pop_front()
	candidate["government_change_history"] = history
	return change_record


func _support_baseline_for_new_government(force: Dictionary, challenger: Dictionary, old_group_id: String, new_group_id: String, mandate: float) -> float:
	var force_id := str(force.get("force_id", ""))
	if force_id == new_group_id:
		return clampf(58.0 + (mandate - 50.0) * 0.45, 55.0, 82.0)
	var alignment := _force_pair_alignment(force, challenger)
	var old_support := float(force.get("government_support", 0.0))
	var opposition_transfer := clampf(-old_support * 0.18, -12.0, 18.0)
	var baseline := (alignment - 50.0) * 1.10 + opposition_transfer + (mandate - 50.0) * 0.10
	if force_id == old_group_id:
		baseline = minf(-20.0, baseline - 18.0)
	return clampf(baseline, -75.0, 65.0)


func _force_pair_alignment(left: Dictionary, right: Dictionary) -> float:
	var left_preferences := left.get("policy_preferences", {}) as Dictionary
	var right_preferences := right.get("policy_preferences", {}) as Dictionary
	var total := 0.0
	for domain: String in VNextStatePolitics.POLICY_DOMAINS:
		total += (_position_alignment(float(left_preferences.get(domain, 0.0)), float(right_preferences.get(domain, 0.0))) + 1.0) * 50.0
	return clampf(total / float(VNextStatePolitics.POLICY_DOMAINS.size()), 0.0, 100.0)


func _weighted_support(forces: Array) -> float:
	var total_influence := 0.0
	var weighted := 0.0
	for force: Dictionary in _sorted_forces(forces):
		var influence := float(force.get("influence", 0.0))
		total_influence += influence
		weighted += influence * ((float(force.get("government_support", 0.0)) + 100.0) / 2.0)
	return 0.0 if total_influence <= 0.0 else clampf(weighted / total_influence, 0.0, 100.0)


func _policy_by_id(policies: Array, policy_id: String) -> Dictionary:
	for policy: Dictionary in _sorted_policies(policies):
		if str(policy.get("policy_id", "")) == policy_id:
			return policy
	return {}


func _force_by_id(forces: Array, force_id: String) -> Dictionary:
	for force: Dictionary in _sorted_forces(forces):
		if str(force.get("force_id", "")) == force_id:
			return force
	return {}


func _position_alignment(left: float, right: float) -> float:
	return clampf(1.0 - absf(left - right) / 100.0, -1.0, 1.0)


func _stable_actor_effect(stable_id: String, maximum_abs: float) -> float:
	var checksum := 0
	for byte_value: int in stable_id.to_utf8_buffer():
		checksum = (checksum * 31 + byte_value) % 9973
	var normalized := (float(checksum % 2001) / 1000.0) - 1.0
	return clampf(normalized * maximum_abs, -maximum_abs, maximum_abs)


func _daily_alpha(monthly_alpha: float) -> float:
	return 1.0 - pow(1.0 - monthly_alpha, 1.0 / float(MONTH_DAYS))


func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in dictionary.keys():
		result.append(str(raw_key))
	result.sort()
	return result


func _sorted_forces(forces: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_force: Variant in forces:
		if typeof(raw_force) == TYPE_DICTIONARY:
			result.append((raw_force as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("force_id", "")) < str(right.get("force_id", ""))
	)
	return result


func _sorted_policies(policies: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_policy: Variant in policies:
		if typeof(raw_policy) == TYPE_DICTIONARY:
			result.append((raw_policy as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("policy_id", "")) < str(right.get("policy_id", ""))
	)
	return result


func _sorted_active(active: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_active: Variant in active:
		if typeof(raw_active) == TYPE_DICTIONARY:
			result.append((raw_active as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("policy_id", "")) < str(right.get("policy_id", ""))
	)
	return result


func _sorted_history(history: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_record: Variant in history:
		if typeof(raw_record) == TYPE_DICTIONARY:
			result.append((raw_record as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_period := int(left.get("period", 0))
		var right_period := int(right.get("period", 0))
		if left_period != right_period:
			return left_period < right_period
		return str(left.get("new_government_group_id", left.get("policy_id", ""))) < str(right.get("new_government_group_id", right.get("policy_id", "")))
	)
	return result


func _fail(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "message": message}
