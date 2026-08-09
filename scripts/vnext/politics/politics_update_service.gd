class_name VNextPoliticsUpdateService
extends RefCounted

## Calculates one bounded political update from an explicit input boundary.
## It emits policy choices and political consequences; economy and military
## systems remain responsible for producing the input signals.

const PRESSURE_SCALE: float = 12.0
const FORCE_DELTA_LIMIT: float = 18.0
const POLICY_REVIEW_COOLDOWN: int = 3
const POLICY_CHANGE_MARGIN: float = 4.0
const EMERGENCY_POLICY_PRESSURE: float = 70.0
const POLICY_PRIORITY_SIGNAL_THRESHOLD: float = 65.0
const POLICY_PRIORITY_BONUS: float = 10.0
const STRAINED_STREAK: int = 2
const CRISIS_STREAK: int = 4
const GOVERNMENT_CHANGE_STREAK: int = 6
const RECOVERY_TO_STABLE_STREAK: int = 3
const CRISIS_SUPPORT_THRESHOLD: float = 46.0
const CRISIS_CONTROL_THRESHOLD: float = 32.0
const CRISIS_LEGITIMACY_THRESHOLD: float = 38.0
const CRISIS_STABILITY_THRESHOLD: float = 42.0
const CRITICAL_SUPPORT_THRESHOLD: float = 35.0
const CRITICAL_CONTROL_THRESHOLD: float = 22.0
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
	"absolute_monarchy": 48.0,
	"constitutional_monarchy": 64.0,
	"parliamentary_monarchy": 70.0,
	"parliamentary_republic": 68.0,
	"presidential_republic": 60.0,
	"federal_republic": 66.0,
	"military_rule": 42.0,
	"imperial_bureaucracy": 50.0,
	"colonial_administration": 38.0,
}


func update(
	state: VNextStatePolitics, pressure_input: VNextPoliticsPressureInput
) -> Dictionary:
	if state == null or not state.is_valid():
		return _fail("invalid_state", "a valid state politics object is required")
	if pressure_input == null or not pressure_input.is_valid():
		return _fail("invalid_pressure_input", "a valid political pressure input is required")

	var before: Dictionary = state.snapshot()
	var candidate: Dictionary = before.duplicate(true)
	var input_snapshot: Dictionary = pressure_input.snapshot()
	var economic_pressure: float = _economic_pressure(pressure_input)
	var war_pressure: float = _war_pressure(pressure_input)
	var total_pressure: float = clampf(
		economic_pressure * 0.58 + war_pressure * 0.42,
		0.0,
		100.0
	)
	var next_period: int = int(candidate.get("period_index", 0)) + 1
	var old_government_group_id: String = str(candidate.get("government_group_id", ""))

	var forces: Array = (candidate.get("forces", []) as Array).duplicate(true)
	var active_policies: Array = (candidate.get("active_policies", []) as Array).duplicate(true)
	var policies: Array = (candidate.get("policies", []) as Array).duplicate(true)
	for index: int in range(forces.size()):
		var force: Dictionary = forces[index] as Dictionary
		var old_support: float = float(force.get("government_support", 0.0))
		var support_delta: float = _force_external_delta(force, pressure_input)
		support_delta += _force_policy_delta(force, active_policies, policies)
		if total_pressure < 25.0:
			support_delta += (
				float(force.get("base_government_support", old_support)) - old_support
			) * 0.06
		if pressure_input.growth_signal() > 0.0:
			support_delta += pressure_input.growth_signal() * 0.012
		support_delta = clampf(support_delta, -FORCE_DELTA_LIMIT, FORCE_DELTA_LIMIT)
		var new_support: float = clampf(old_support + support_delta, -100.0, 100.0)
		force["government_support"] = new_support
		force["last_support_delta"] = support_delta
		var support_history: Array = (force.get("support_history", []) as Array).duplicate(true)
		support_history.append({
			"period": next_period,
			"support": new_support,
			"delta": support_delta,
		})
		while support_history.size() > VNextStatePolitics.MAX_FORCE_HISTORY:
			support_history.pop_front()
		force["support_history"] = support_history
		forces[index] = force
	candidate["forces"] = forces
	candidate["period_index"] = next_period
	candidate["last_pressure_input"] = input_snapshot

	var weighted_support: float = _weighted_support(forces)
	var capacity: Dictionary = _update_capacity(
		candidate.get("capacity", {}) as Dictionary,
		pressure_input,
		total_pressure
	)
	candidate["capacity"] = capacity
	var control: float = float(capacity.get("control", 0.0))
	var policy_changes: Array[Dictionary] = _review_policies(
		candidate, pressure_input, total_pressure, control
	)
	active_policies = (candidate.get("active_policies", []) as Array).duplicate(true)
	var policy_fit: float = _policy_fit(forces, active_policies, policies)
	var policy_burden: float = _policy_burden(active_policies, policies)

	var procedural_baseline: float = float(
		REGIME_PROCEDURAL_BASELINES.get(str(candidate.get("regime_type", "")), 50.0)
	)
	var corruption: float = float(capacity.get("corruption", 0.0))
	var legitimacy_target: float = clampf(
		weighted_support * 0.30
			+ control * 0.22
			+ policy_fit * 0.18
			+ procedural_baseline * 0.15
			+ (100.0 - corruption) * 0.15
			- total_pressure * 0.28
			+ pressure_input.military_result_signal() * 0.08,
		0.0,
		100.0
	)
	var legitimacy: float = lerpf(
		float(candidate.get("legitimacy", 0.0)), legitimacy_target, 0.20
	)
	var stability_target: float = clampf(
		legitimacy * 0.30
			+ control * 0.30
			+ weighted_support * 0.25
			+ policy_fit * 0.15
			- total_pressure * 0.45
			- policy_burden * 0.15
			+ pressure_input.military_result_signal() * 0.05,
		0.0,
		100.0
	)
	var stability: float = lerpf(
		float(candidate.get("stability", 0.0)), stability_target, 0.22
	)
	candidate["legitimacy"] = clampf(legitimacy, 0.0, 100.0)
	candidate["stability"] = clampf(stability, 0.0, 100.0)
	candidate["government_support"] = weighted_support

	var unstable: bool = _is_unstable(weighted_support, control, legitimacy, stability)
	var old_instability_streak: int = int(candidate.get("instability_streak", 0))
	var instability_streak: int = old_instability_streak + 1 if unstable else maxi(0, old_instability_streak - 1)
	var recovery_streak: int = (
		int(candidate.get("recovery_streak", 0)) + 1
		if not unstable
		else 0
	)
	candidate["instability_streak"] = instability_streak
	candidate["recovery_streak"] = recovery_streak

	var crisis_stage: String = _next_crisis_stage(
		str(candidate.get("crisis_stage", "stable")),
		unstable,
		instability_streak,
		recovery_streak,
		weighted_support,
		control,
		legitimacy,
		stability
	)
	candidate["crisis_stage"] = crisis_stage

	var government_change: Dictionary = {}
	if (
		instability_streak >= GOVERNMENT_CHANGE_STREAK
		and weighted_support < 48.0
		and crisis_stage == "crisis"
	):
		var challenger: Dictionary = _select_challenger(
			forces, old_government_group_id
		)
		if not challenger.is_empty():
			government_change = _apply_government_change(
				candidate, challenger, old_government_group_id, next_period, total_pressure
			)
			forces = candidate.get("forces", []) as Array
			weighted_support = _weighted_support(forces)
			candidate["government_support"] = weighted_support
			candidate["instability_streak"] = 0
			candidate["recovery_streak"] = 0
			candidate["crisis_stage"] = "transition"

	var final_control: float = float((candidate.get("capacity", {}) as Dictionary).get("control", 0.0))
	candidate["government_viability"] = (
		weighted_support >= CRISIS_SUPPORT_THRESHOLD
		and final_control >= CRISIS_CONTROL_THRESHOLD
		and float(candidate.get("legitimacy", 0.0)) >= CRISIS_LEGITIMACY_THRESHOLD
		and float(candidate.get("stability", 0.0)) >= CRISIS_STABILITY_THRESHOLD
	)
	if not state.restore(candidate):
		return _fail("state_commit_rejected", "political update produced an invalid state")

	var changed: bool = not government_change.is_empty()
	return {
		"success": true,
		"period_index": state.period_index(),
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
		"government_changed": changed,
		"government_change": government_change,
		"snapshot": state.snapshot(),
	}


func _economic_pressure(input: VNextPoliticsPressureInput) -> float:
	var result: float = 0.0
	for signal_key: String in [
		"price_pressure",
		"unemployment_pressure",
		"fiscal_pressure",
		"shortage_pressure",
	]:
		result += maxf(0.0, input.economic_signal_value(signal_key)) * float(
			ECONOMIC_WEIGHTS.get(signal_key, 0.0)
		)
	result += maxf(0.0, -input.growth_signal()) * float(
		ECONOMIC_WEIGHTS.get("growth_signal", 0.0)
	)
	return clampf(result, 0.0, 100.0)


func _war_pressure(input: VNextPoliticsPressureInput) -> float:
	var result: float = 0.0
	result += maxf(0.0, input.war_pressure()) * float(WAR_WEIGHTS["war_pressure"])
	result += maxf(0.0, input.casualty_pressure()) * float(WAR_WEIGHTS["casualty_pressure"])
	result += maxf(0.0, input.mobilization_pressure()) * float(
		WAR_WEIGHTS["mobilization_pressure"]
	)
	result += maxf(0.0, -input.military_result_signal()) * float(
		WAR_WEIGHTS["military_result_signal"]
	)
	return clampf(result, 0.0, 100.0)


func _force_external_delta(
	force: Dictionary, input: VNextPoliticsPressureInput
) -> float:
	var response: Dictionary = force.get("pressure_response", {}) as Dictionary
	var result: float = 0.0
	for signal_key: String in VNextStatePolitics.PRESSURE_SIGNAL_KEYS:
		var signal_value: float = (
			input.economic_signal_value(signal_key)
			if signal_key in VNextPoliticsPressureInput.ECONOMIC_SIGNAL_KEYS
			else input.war_signal_value(signal_key)
		)
		result += signal_value * float(response.get(signal_key, 0.0))
	return clampf(result / PRESSURE_SCALE, -FORCE_DELTA_LIMIT, FORCE_DELTA_LIMIT)


func _force_policy_delta(
	force: Dictionary, active_policies: Array, policies: Array
) -> float:
	var result: float = 0.0
	var preferences: Dictionary = force.get("policy_preferences", {}) as Dictionary
	for raw_active: Variant in active_policies:
		var active: Dictionary = raw_active as Dictionary
		var policy: Dictionary = _policy_by_id(
			policies, str(active.get("policy_id", ""))
		)
		if policy.is_empty():
			continue
		var domain: String = str(policy.get("domain", ""))
		var preference: float = float(preferences.get(domain, 0.0))
		var alignment: float = _position_alignment(
			preference, float(policy.get("position", 0.0))
		)
		result += alignment * float(active.get("implementation_strength", 0.0)) * 2.0
	return clampf(result, -6.0, 6.0)


func _update_capacity(
	old_capacity: Dictionary,
	input: VNextPoliticsPressureInput,
	total_pressure: float
) -> Dictionary:
	var old_admin: float = float(old_capacity.get("administrative", 0.0))
	var old_enforcement: float = float(old_capacity.get("enforcement", 0.0))
	var old_fiscal: float = float(old_capacity.get("fiscal", 0.0))
	var old_corruption: float = float(old_capacity.get("corruption", 0.0))
	var old_control: float = float(old_capacity.get("control", 0.0))
	var positive_growth: float = maxf(0.0, input.growth_signal())
	var admin_target: float = clampf(
		old_admin - total_pressure * 0.08 + positive_growth * 0.035, 0.0, 100.0
	)
	var enforcement_target: float = clampf(
		old_enforcement
			- total_pressure * 0.06
			+ input.mobilization_pressure() * 0.035
			- input.casualty_pressure() * 0.025,
		0.0,
		100.0
	)
	var fiscal_target: float = clampf(
		old_fiscal
			- input.fiscal_pressure() * 0.10
			- total_pressure * 0.025
			+ positive_growth * 0.04,
		0.0,
		100.0
	)
	var corruption_target: float = clampf(
		old_corruption
			+ input.fiscal_pressure() * 0.065
			+ input.shortage_pressure() * 0.035
			- old_admin * 0.012,
		0.0,
		100.0
	)
	var control_target: float = clampf(
		admin_target * 0.30
			+ enforcement_target * 0.25
			+ fiscal_target * 0.20
			+ (100.0 - corruption_target) * 0.10
			+ old_control * 0.15
			- total_pressure * 0.32,
		0.0,
		100.0
	)
	return {
		"administrative": lerpf(old_admin, admin_target, 0.20),
		"enforcement": lerpf(old_enforcement, enforcement_target, 0.20),
		"fiscal": lerpf(old_fiscal, fiscal_target, 0.20),
		"corruption": lerpf(old_corruption, corruption_target, 0.20),
		"control": lerpf(old_control, control_target, 0.25),
	}


func _review_policies(
	candidate: Dictionary,
	input: VNextPoliticsPressureInput,
	total_pressure: float,
	control: float
) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var period: int = int(candidate.get("period_index", 0))
	var last_review: int = int(candidate.get("last_policy_review_period", -1))
	if period - last_review < POLICY_REVIEW_COOLDOWN:
		return changes
	var forces: Array = candidate.get("forces", []) as Array
	var policies: Array = candidate.get("policies", []) as Array
	var active: Array = candidate.get("active_policies", []) as Array
	var best_policy: Dictionary = {}
	var best_score: float = -1.0e30
	for raw_policy: Variant in policies:
		var policy: Dictionary = raw_policy as Dictionary
		if control < float(policy.get("required_control", 0.0)) * 0.45:
			continue
		var score: float = _policy_score(policy, forces, input, total_pressure)
		if score > best_score or (
			is_equal_approx(score, best_score)
			and str(policy.get("policy_id", "")) < str(best_policy.get("policy_id", "~"))
		):
			best_score = score
			best_policy = policy
	if best_policy.is_empty():
		return changes
	var current_score: float = _active_policy_score(
		active, policies, forces, input, total_pressure
	)
	var current_same_policy: bool = false
	for raw_active: Variant in active:
		if str((raw_active as Dictionary).get("policy_id", "")) == str(best_policy.get("policy_id", "")):
			current_same_policy = true
			break
	var should_change: bool = (
		active.is_empty()
		or (
			not current_same_policy
			and best_score >= current_score + POLICY_CHANGE_MARGIN
		)
		or (
			total_pressure >= EMERGENCY_POLICY_PRESSURE
			and not current_same_policy
			and best_score >= current_score + 2.0
		)
	)
	if not should_change:
		return changes
	var best_domain: String = str(best_policy.get("domain", ""))
	var replaced_policy_id: String = ""
	for index: int in range(active.size()):
		var active_policy: Dictionary = active[index] as Dictionary
		var old_policy: Dictionary = _policy_by_id(
			policies, str(active_policy.get("policy_id", ""))
		)
		if str(old_policy.get("domain", "")) == best_domain:
			replaced_policy_id = str(active_policy.get("policy_id", ""))
			active[index] = _new_active_policy(str(best_policy.get("policy_id", "")), period, control)
			break
	if replaced_policy_id.is_empty():
		if active.size() >= 4:
			active.pop_front()
		active.append(_new_active_policy(str(best_policy.get("policy_id", "")), period, control))
	candidate["active_policies"] = active
	candidate["last_policy_review_period"] = period
	var history: Array = (candidate.get("policy_history", []) as Array).duplicate(true)
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
	})
	return changes


func _policy_score(
	policy: Dictionary,
	forces: Array,
	input: VNextPoliticsPressureInput,
	total_pressure: float
) -> float:
	var alignment: float = _policy_coalition_alignment(policy, forces)
	var urgency: float = _policy_pressure_fit(policy, input)
	var relief: float = _policy_relief_fit(policy, input)
	var fiscal_penalty: float = float(policy.get("fiscal_demand", 0.0)) * (
		0.35 + input.fiscal_pressure() / 180.0
	)
	var emergency_bonus: float = total_pressure * 0.08 if total_pressure >= 60.0 else 0.0
	return alignment * 0.42 + urgency * 0.30 + relief * 0.28 - fiscal_penalty * 0.12 + emergency_bonus + _policy_priority_bonus(policy, input)


func _policy_priority_bonus(policy: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var reliefs: Dictionary = policy.get("political_relief", {}) as Dictionary
	var bonus: float = 0.0
	for raw_key: Variant in reliefs.keys():
		var key: String = str(raw_key)
		var signal_value: float = input.economic_signal_value(key)
		if key in VNextPoliticsPressureInput.WAR_SIGNAL_KEYS:
			signal_value = input.war_signal_value(key)
		if key == "growth_signal":
			signal_value = -signal_value
		if signal_value >= POLICY_PRIORITY_SIGNAL_THRESHOLD and float(reliefs.get(key, 0.0)) >= 40.0:
			bonus = maxf(bonus, POLICY_PRIORITY_BONUS)
	return bonus

func _active_policy_score(
	active: Array,
	policies: Array,
	forces: Array,
	input: VNextPoliticsPressureInput,
	total_pressure: float
) -> float:
	if active.is_empty():
		return 0.0
	var total: float = 0.0
	for raw_active: Variant in active:
		var policy: Dictionary = _policy_by_id(
			policies, str((raw_active as Dictionary).get("policy_id", ""))
		)
		if policy.is_empty():
			continue
		total += _policy_score(policy, forces, input, total_pressure)
	return total / float(maxi(1, active.size()))


func _policy_coalition_alignment(policy: Dictionary, forces: Array) -> float:
	var total_influence: float = 0.0
	var weighted_alignment: float = 0.0
	var domain: String = str(policy.get("domain", ""))
	var position: float = float(policy.get("position", 0.0))
	for raw_force: Variant in forces:
		var force: Dictionary = raw_force as Dictionary
		var influence: float = float(force.get("influence", 0.0))
		var preference: float = float(
			(force.get("policy_preferences", {}) as Dictionary).get(domain, 0.0)
		)
		total_influence += influence
		weighted_alignment += influence * _position_alignment(preference, position)
	if total_influence <= 0.0:
		return 0.0
	return clampf((weighted_alignment / total_influence + 1.0) * 50.0, 0.0, 100.0)


func _policy_pressure_fit(policy: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var targets: Dictionary = policy.get("pressure_targets", {}) as Dictionary
	var total_weight: float = 0.0
	var score: float = 0.0
	for raw_key: Variant in targets.keys():
		var key: String = str(raw_key)
		var weight: float = float(targets.get(key, 0.0))
		var signal_value: float = input.economic_signal_value(key)
		if key in VNextPoliticsPressureInput.WAR_SIGNAL_KEYS:
			signal_value = input.war_signal_value(key)
		if key == "growth_signal":
			signal_value = -signal_value
		score += maxf(0.0, signal_value) * weight
		total_weight += weight
	if total_weight <= 0.0:
		return 0.0
	return clampf(score / total_weight, 0.0, 100.0)


func _policy_relief_fit(policy: Dictionary, input: VNextPoliticsPressureInput) -> float:
	var reliefs: Dictionary = policy.get("political_relief", {}) as Dictionary
	var total_weight: float = 0.0
	var score: float = 0.0
	for raw_key: Variant in reliefs.keys():
		var key: String = str(raw_key)
		var relief: float = float(reliefs.get(key, 0.0))
		var signal_value: float = input.economic_signal_value(key)
		if key in VNextPoliticsPressureInput.WAR_SIGNAL_KEYS:
			signal_value = input.war_signal_value(key)
		if key == "growth_signal":
			signal_value = -signal_value
		score += maxf(0.0, signal_value) * relief
		total_weight += relief
	if total_weight <= 0.0:
		return 0.0
	return clampf(score / total_weight, 0.0, 100.0)


func _policy_fit(forces: Array, active_policies: Array, policies: Array) -> float:
	if active_policies.is_empty():
		return 35.0
	var total: float = 0.0
	var count: int = 0
	for raw_active: Variant in active_policies:
		var policy: Dictionary = _policy_by_id(
			policies, str((raw_active as Dictionary).get("policy_id", ""))
		)
		if policy.is_empty():
			continue
		total += _policy_coalition_alignment(policy, forces)
		count += 1
	return total / float(maxi(1, count))


func _policy_burden(active_policies: Array, policies: Array) -> float:
	if active_policies.is_empty():
		return 0.0
	var burden: float = 0.0
	for raw_active: Variant in active_policies:
		var active: Dictionary = raw_active as Dictionary
		var policy: Dictionary = _policy_by_id(policies, str(active.get("policy_id", "")))
		if policy.is_empty():
			continue
		burden += (
				float(policy.get("fiscal_demand", 0.0))
				+ float(policy.get("administrative_demand", 0.0))
			) * 0.5 * float(active.get("implementation_strength", 0.0))
	return clampf(burden / float(maxi(1, active_policies.size())), 0.0, 100.0)


func _new_active_policy(policy_id: String, period: int, control: float) -> Dictionary:
	return {
		"policy_id": policy_id,
		"started_period": period,
		"implementation_strength": clampf(control / 100.0, 0.15, 1.0),
		"last_review_period": period,
		"status": "implementing",
	}


func _policy_by_id(policies: Array, policy_id: String) -> Dictionary:
	for raw_policy: Variant in policies:
		var policy: Dictionary = raw_policy as Dictionary
		if str(policy.get("policy_id", "")) == policy_id:
			return policy
	return {}


func _position_alignment(left: float, right: float) -> float:
	return clampf(1.0 - absf(left - right) / 100.0, -1.0, 1.0)


func _is_unstable(
	weighted_support: float,
	control: float,
	legitimacy: float,
	stability: float
) -> bool:
	return (
		weighted_support < CRISIS_SUPPORT_THRESHOLD
		or control < CRISIS_CONTROL_THRESHOLD
		or legitimacy < CRISIS_LEGITIMACY_THRESHOLD
		or stability < CRISIS_STABILITY_THRESHOLD
	)


func _next_crisis_stage(
	old_stage: String,
	unstable: bool,
	instability_streak: int,
	recovery_streak: int,
	weighted_support: float,
	control: float,
	legitimacy: float,
	stability: float
) -> String:
	var critical: bool = (
		weighted_support < CRITICAL_SUPPORT_THRESHOLD
		or control < CRITICAL_CONTROL_THRESHOLD
		or stability < CRITICAL_STABILITY_THRESHOLD
	)
	if critical or instability_streak >= CRISIS_STREAK:
		return "crisis"
	if unstable or instability_streak >= STRAINED_STREAK:
		return "strained"
	if old_stage == "transition" and recovery_streak < RECOVERY_TO_STABLE_STREAK:
		return "transition"
	if old_stage == "crisis" and recovery_streak < RECOVERY_TO_STABLE_STREAK:
		return "strained"
	return "stable"


func _select_challenger(forces: Array, current_group_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0e30
	for raw_force: Variant in forces:
		var force: Dictionary = raw_force as Dictionary
		var force_id: String = str(force.get("force_id", ""))
		if (
			force_id == current_group_id
			or not bool(force.get("government_eligible", false))
		):
			continue
		var power: float = (
			float(force.get("influence", 0.0)) * 0.45
			+ float(force.get("institutional_access", 0.0)) * 0.35
			+ float(force.get("mobilization_capacity", 0.0)) * 0.20
		)
		var coalition_support: float = (
			float(force.get("base_government_support", 0.0)) + 100.0
		) * 0.5
		var score: float = power * 0.72 + coalition_support * 0.28
		if score > best_score or (
			is_equal_approx(score, best_score)
			and force_id < str(best.get("force_id", "~"))
		):
			best_score = score
			best = force.duplicate(true)
	if best_score < 42.0:
		return {}
	return best


func _apply_government_change(
	candidate: Dictionary,
	challenger: Dictionary,
	old_group_id: String,
	period: int,
	total_pressure: float
) -> Dictionary:
	var new_group_id: String = str(challenger.get("force_id", ""))
	var old_leader_id: String = str(candidate.get("government_leader_id", ""))
	candidate["government_group_id"] = new_group_id
	candidate["government_leader_id"] = challenger.get("leader_id", "")
	candidate["legitimacy"] = maxf(25.0, float(candidate.get("legitimacy", 0.0)) - 5.0)
	var forces: Array = candidate.get("forces", []) as Array
	for index: int in range(forces.size()):
		var force: Dictionary = forces[index] as Dictionary
		var force_id: String = str(force.get("force_id", ""))
		if force_id == new_group_id:
			force["government_support"] = maxf(
				35.0, float(force.get("government_support", 0.0)) + 35.0
			)
		elif force_id == old_group_id:
			force["government_support"] = minf(
				-15.0, float(force.get("government_support", 0.0)) - 20.0
			)
		forces[index] = force
	candidate["forces"] = forces
	var change_record: Dictionary = {
		"period": period,
		"reason": "sustained_government_failure",
		"old_government_group_id": old_group_id,
		"new_government_group_id": new_group_id,
		"old_leader_id": old_leader_id,
		"new_leader_id": challenger.get("leader_id", ""),
		"political_pressure": total_pressure,
	}
	var history: Array = (candidate.get("government_change_history", []) as Array).duplicate(true)
	history.append(change_record)
	while history.size() > VNextStatePolitics.MAX_GOVERNMENT_CHANGE_HISTORY:
		history.pop_front()
	candidate["government_change_history"] = history
	return change_record


func _weighted_support(forces: Array) -> float:
	var total_influence: float = 0.0
	var weighted: float = 0.0
	for raw_force: Variant in forces:
		var force: Dictionary = raw_force as Dictionary
		var influence: float = float(force.get("influence", 0.0))
		total_influence += influence
		weighted += influence * ((float(force.get("government_support", 0.0)) + 100.0) / 2.0)
	if total_influence <= 0.0:
		return 0.0
	return clampf(weighted / total_influence, 0.0, 100.0)


func _fail(error_code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"message": message,
	}

