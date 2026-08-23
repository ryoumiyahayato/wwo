class_name VNextMilitaryCapabilityModel
extends RefCounted
## Shared deterministic military-capability mathematics.
##
## Runtime owners supply authoritative population, economy, industry,
## institutions, readiness and logistics facts. This model converts them into
## explainable capability layers without owning a clock, map or inventory.

const ASSESSMENT_SCHEMA_ID: String = "military_capability_assessment_v1"
const PROJECTION_SCHEMA_ID: String = "military_operational_projection_v1"
const MINIMUM_NUMERIC_COMPONENT: float = 0.000001


func combine_bottlenecks(terms: Array[Dictionary], order: float = -1.5) -> float:
	## Public composition boundary for authoritative adapters that need to reduce
	## several differently-scaled facts into one constrained capability pillar.
	if order >= -0.01:
		return 0.0
	return _generalized_bottleneck(terms, order)


func assess_country(input: Dictionary) -> Dictionary:
	var error: String = _country_input_error(input)
	if not error.is_empty():
		return _failure("invalid_country_input", error)

	var country_id: String = str(input.get("country_id", ""))
	var force_state: Dictionary = input.get("force_state", {}) as Dictionary
	var institutions: Dictionary = input.get("institutions", {}) as Dictionary
	var population_units: float = float(input.get("manpower_capability_units", 0.0))
	var economic_units: float = float(input.get("economic_capability_units", 0.0))
	var industrial_units: float = float(input.get("industrial_capability_units", 0.0))
	var fiscal_units: float = float(input.get("fiscal_capability_units", 0.0))

	# A negative-order generalized mean is a smooth bottleneck. A weak pillar
	# cannot be hidden by adding strength elsewhere, but no estimate creates a
	# discontinuous hard minimum.
	var potential: float = _generalized_bottleneck([
		{"value": population_units, "weight": 0.34},
		{"value": economic_units, "weight": 0.22},
		{"value": industrial_units, "weight": 0.30},
		{"value": fiscal_units, "weight": 0.14},
	], -1.35)

	var mobilization_level: float = _unit(float(force_state.get("mobilization_level", 0.0)))
	var equipment_ratio: float = _unit(float(force_state.get("equipment_ratio", 0.0)))
	var administration_ratio: float = _unit(float(force_state.get("administration_ratio", 0.0)))
	var available_conversion: float = _complementarity([
		{"value": mobilization_level, "weight": 0.45},
		{"value": equipment_ratio, "weight": 0.35},
		{"value": administration_ratio, "weight": 0.20},
	])
	var available: float = potential * available_conversion

	var readiness: float = _unit(float(force_state.get("readiness", 0.0)))
	var sustainment: float = _unit(float(force_state.get("sustainment_ratio", 0.0)))
	var cohesion: float = _unit(float(force_state.get("cohesion", 0.0)))
	var political_support: float = _unit(float(force_state.get("political_support", 0.0)))
	var command: float = _unit(float(institutions.get("command_effectiveness", 0.0)))
	var organization: float = _unit(float(institutions.get("organization_quality", 0.0)))
	var operational_conversion: float = _complementarity([
		{"value": readiness, "weight": 0.24},
		{"value": sustainment, "weight": 0.24},
		{"value": organization, "weight": 0.18},
		{"value": command, "weight": 0.18},
		{"value": cohesion, "weight": 0.08},
		{"value": political_support, "weight": 0.08},
	])
	var operational: float = available * operational_conversion

	var report: Dictionary = {
		"success": true,
		"schema_id": ASSESSMENT_SCHEMA_ID,
		"country_id": country_id,
		"source_hour": int(input.get("source_hour", 0)),
		"potential_capability": potential,
		"available_capability": available,
		"operational_effectiveness": operational,
		"readiness": readiness,
		"sustainment_ratio": sustainment,
		"mobilization_level": mobilization_level,
		"equipment_ratio": equipment_ratio,
		"administration_ratio": administration_ratio,
		"command_effectiveness": command,
		"organization_quality": organization,
		"cohesion": cohesion,
		"political_support": political_support,
		"economic_burden": _safe_ratio(available, maxf(economic_units, fiscal_units)),
		"manpower_burden": _safe_ratio(available, population_units),
		"conversion": {
			"potential_to_available": available_conversion,
			"available_to_operational": operational_conversion,
		},
		"potential_components": {
			"manpower": population_units,
			"economy": economic_units,
			"industry": industrial_units,
			"fiscal": fiscal_units,
		},
		"available_components": {
			"mobilization": mobilization_level,
			"equipment": equipment_ratio,
			"administration": administration_ratio,
		},
		"operational_components": {
			"readiness": readiness,
			"sustainment": sustainment,
			"organization": organization,
			"command": command,
			"cohesion": cohesion,
			"political_support": political_support,
		},
		"bottlenecks": _ordered_bottlenecks({
			"manpower": _relative_component(population_units, potential),
			"economy": _relative_component(economic_units, potential),
			"industry": _relative_component(industrial_units, potential),
			"fiscal": _relative_component(fiscal_units, potential),
			"mobilization": mobilization_level,
			"equipment": equipment_ratio,
			"administration": administration_ratio,
			"readiness": readiness,
			"sustainment": sustainment,
			"organization": organization,
			"command": command,
			"cohesion": cohesion,
			"political_support": political_support,
		}),
		"source_status": (input.get("source_status", {}) as Dictionary).duplicate(true),
		"source_details": (input.get("source_details", {}) as Dictionary).duplicate(true),
	}
	if not is_valid_assessment(report):
		return _failure("invalid_assessment", "Capability calculation violated bounded invariants.")
	return report


func project_to_area(
	assessment: Dictionary,
	logistics_context: Dictionary,
	operational_context: Dictionary = {}
) -> Dictionary:
	if not is_valid_assessment(assessment):
		return _failure("invalid_assessment", "A valid country capability assessment is required.")
	var context_error: String = _logistics_context_error(logistics_context)
	if not context_error.is_empty():
		return _failure("invalid_logistics_context", context_error)

	var operational: float = float(assessment.get("operational_effectiveness", 0.0))
	var required_supply: float = maxf(
		0.0,
		operational * float(logistics_context.get("supply_units_per_capability", 0.0))
	)
	var deliverable_supply: float = maxf(0.0, float(logistics_context.get("deliverable_supply", 0.0)))
	var raw_supply_ratio: float = (
		1.0 if required_supply <= MINIMUM_NUMERIC_COMPONENT
		else deliverable_supply / required_supply
	)
	var supply_ratio: float = clampf(raw_supply_ratio, 0.0, 1.0)
	var supply_conversion: float = _supply_degradation_curve(supply_ratio)
	var access_ratio: float = _unit(float(logistics_context.get("access_ratio", 0.0)))
	var infrastructure_ratio: float = _unit(float(logistics_context.get("infrastructure_ratio", 0.0)))
	var terrain_supply_ratio: float = _unit(float(logistics_context.get("terrain_supply_ratio", 0.0)))
	var distance_hours: float = maxf(0.0, float(logistics_context.get("distance_hours", 0.0)))
	var distance_reference_hours: float = maxf(
		1.0, float(logistics_context.get("distance_reference_hours", 1.0))
	)
	var distance_ratio: float = 1.0 / (1.0 + distance_hours / distance_reference_hours)
	var mobility: float = _complementarity([
		{"value": access_ratio, "weight": 0.30},
		{"value": infrastructure_ratio, "weight": 0.25},
		{"value": terrain_supply_ratio, "weight": 0.15},
		{"value": distance_ratio, "weight": 0.15},
		{"value": supply_conversion, "weight": 0.15},
	])
	var preparation: float = _unit(float(operational_context.get("preparation", 0.5)))
	var preparation_conversion: float = lerpf(0.78, 1.0, preparation)
	var terrain_combat_factor: float = clampf(
		float(operational_context.get("terrain_combat_factor", 1.0)), 0.35, 1.75
	)
	var defensive_preparation: float = _unit(
		float(operational_context.get("defensive_preparation", 0.0))
	)
	var role: String = str(operational_context.get("role", "attack"))
	if role not in ["attack", "defend"]:
		return _failure("invalid_role", "Operational role must be attack or defend.")
	var positional_factor: float = terrain_combat_factor
	if role == "defend":
		positional_factor *= lerpf(1.0, 1.45, defensive_preparation)
	else:
		positional_factor = 1.0 / maxf(1.0, terrain_combat_factor)
	var projected: float = operational * mobility * supply_conversion
	projected *= preparation_conversion * positional_factor

	var report: Dictionary = {
		"success": true,
		"schema_id": PROJECTION_SCHEMA_ID,
		"country_id": str(assessment.get("country_id", "")),
		"source_hour": int(assessment.get("source_hour", 0)),
		"origin_id": str(logistics_context.get("origin_id", "")),
		"target_id": str(logistics_context.get("target_id", "")),
		"role": role,
		"potential_capability": float(assessment.get("potential_capability", 0.0)),
		"available_capability": float(assessment.get("available_capability", 0.0)),
		"operational_effectiveness": operational,
		"projectable_capability": maxf(0.0, projected),
		"required_supply": required_supply,
		"deliverable_supply": deliverable_supply,
		"supply_ratio": supply_ratio,
		"supply_conversion": supply_conversion,
		"mobility": mobility,
		"distance_hours": distance_hours,
		"access_ratio": access_ratio,
		"infrastructure_ratio": infrastructure_ratio,
		"terrain_supply_ratio": terrain_supply_ratio,
		"terrain_combat_factor": terrain_combat_factor,
		"preparation": preparation,
		"defensive_preparation": defensive_preparation,
		"positional_factor": positional_factor,
		"route": (logistics_context.get("route", {}) as Dictionary).duplicate(true),
		"bottlenecks": _ordered_bottlenecks({
			"access": access_ratio,
			"infrastructure": infrastructure_ratio,
			"terrain_supply": terrain_supply_ratio,
			"distance": distance_ratio,
			"supply": supply_conversion,
		}),
	}
	if not is_valid_projection(report):
		return _failure("invalid_projection", "Projection calculation violated bounded invariants.")
	return report


func compare_operational_contexts(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	if not is_valid_projection(attacker) or not is_valid_projection(defender):
		return _failure("invalid_projection", "Two valid operational projections are required.")
	var attacker_value: float = float(attacker.get("projectable_capability", 0.0))
	var defender_value: float = float(defender.get("projectable_capability", 0.0))
	return {
		"success": true,
		"attacker_projected_capability": attacker_value,
		"defender_projected_capability": defender_value,
		"relative_advantage": attacker_value / maxf(MINIMUM_NUMERIC_COMPONENT, defender_value),
		"attacker_supply_pressure": 1.0 - float(attacker.get("supply_ratio", 0.0)),
		"defender_supply_pressure": 1.0 - float(defender.get("supply_ratio", 0.0)),
		"attacker_bottlenecks": (attacker.get("bottlenecks", []) as Array).duplicate(true),
		"defender_bottlenecks": (defender.get("bottlenecks", []) as Array).duplicate(true),
	}


func formation_effectiveness(
	formation: VNextMilitaryFormation,
	role: String,
	terrain_factor: float,
	city_factor: float = 1.0,
	preparation: float = 1.0,
	minimum_supply_factor: float = 0.35
) -> Dictionary:
	if (
		formation == null
		or not formation.is_valid()
		or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE
		or role not in ["attack", "defend"]
	):
		return {}
	var training_and_organization: float = (
		0.45 + formation.training * 0.20 + formation.organization * 0.35
	)
	var morale: float = 0.45 + formation.morale * 0.55
	var supply: float = maxf(minimum_supply_factor, 0.35 + formation.supply_level * 0.65)
	var readiness: float = training_and_organization * morale * supply
	var positional: float
	if role == "defend":
		positional = maxf(0.35, terrain_factor) * maxf(0.35, city_factor)
		positional *= maxf(1.0, formation.defense_posture)
	else:
		positional = 1.0 / maxf(1.0, terrain_factor)
	var preparation_factor: float = lerpf(0.80, 1.0, _unit(preparation))
	var potential: float = float(formation.personnel) * formation.equipment_factor()
	var available: float = potential * readiness
	return {
		"formation_id": formation.formation_id,
		"country_id": formation.country_id,
		"potential_capability": potential,
		"available_capability": available,
		"operational_effectiveness": available * positional * preparation_factor,
		"components": {
			"equipment": formation.equipment_factor(),
			"training_and_organization": training_and_organization,
			"morale": morale,
			"supply": supply,
			"readiness": readiness,
			"position": positional,
			"preparation": preparation_factor,
		},
	}


static func is_valid_assessment(value: Dictionary) -> bool:
	if value.get("schema_id", "") != ASSESSMENT_SCHEMA_ID:
		return false
	if str(value.get("country_id", "")).is_empty() or int(value.get("source_hour", -1)) < 0:
		return false
	for field_name: String in [
		"potential_capability", "available_capability", "operational_effectiveness",
		"readiness", "sustainment_ratio",
		"mobilization_level", "equipment_ratio", "command_effectiveness",
		"administration_ratio", "organization_quality", "cohesion",
		"political_support", "economic_burden", "manpower_burden",
	]:
		var number: float = float(value.get(field_name, -1.0))
		if not is_finite(number) or number < 0.0:
			return false
	for field_name: String in [
		"readiness", "sustainment_ratio", "mobilization_level", "equipment_ratio",
		"administration_ratio", "command_effectiveness", "organization_quality",
		"cohesion", "political_support", "economic_burden", "manpower_burden",
	]:
		if float(value.get(field_name, -1.0)) > 1.0:
			return false
	if float(value.get("available_capability", 0.0)) > float(value.get("potential_capability", 0.0)) + 0.000001:
		return false
	if float(value.get("operational_effectiveness", 0.0)) > float(value.get("available_capability", 0.0)) + 0.000001:
		return false
	return _bottlenecks_valid(value.get("bottlenecks", []))


static func is_valid_projection(value: Dictionary) -> bool:
	if value.get("schema_id", "") != PROJECTION_SCHEMA_ID:
		return false
	if str(value.get("country_id", "")).is_empty() or int(value.get("source_hour", -1)) < 0:
		return false
	for field_name: String in [
		"potential_capability", "available_capability", "operational_effectiveness",
		"projectable_capability", "required_supply", "deliverable_supply",
		"supply_ratio", "supply_conversion", "mobility", "distance_hours",
		"access_ratio", "infrastructure_ratio", "terrain_supply_ratio",
		"terrain_combat_factor", "preparation", "defensive_preparation",
		"positional_factor",
	]:
		var number: float = float(value.get(field_name, -1.0))
		if not is_finite(number) or number < 0.0:
			return false
	for field_name: String in [
		"supply_ratio", "supply_conversion", "mobility", "access_ratio",
		"infrastructure_ratio", "terrain_supply_ratio", "preparation",
		"defensive_preparation",
	]:
		if float(value.get(field_name, -1.0)) > 1.0:
			return false
	return _bottlenecks_valid(value.get("bottlenecks", []))


func _country_input_error(input: Dictionary) -> String:
	if str(input.get("country_id", "")).is_empty() or int(input.get("source_hour", -1)) < 0:
		return "Country ID and a non-negative source hour are required."
	for field_name: String in [
		"manpower_capability_units", "economic_capability_units",
		"industrial_capability_units", "fiscal_capability_units",
	]:
		var value: float = float(input.get(field_name, -1.0))
		if not is_finite(value) or value < 0.0:
			return "%s must be finite and non-negative." % field_name
	for dictionary_name: String in ["force_state", "institutions", "source_status"]:
		if not input.get(dictionary_name) is Dictionary:
			return "%s must be a dictionary." % dictionary_name
	if input.has("source_details") and not input.get("source_details") is Dictionary:
		return "source_details must be a dictionary."
	var force_state: Dictionary = input.get("force_state", {}) as Dictionary
	for field_name: String in [
		"mobilization_level", "equipment_ratio", "administration_ratio",
		"readiness", "sustainment_ratio", "cohesion", "political_support",
	]:
		if not _is_unit_value(force_state.get(field_name, -1.0)):
			return "force_state.%s must be in 0..1." % field_name
	var institutions: Dictionary = input.get("institutions", {}) as Dictionary
	for field_name: String in ["command_effectiveness", "organization_quality"]:
		if not _is_unit_value(institutions.get(field_name, -1.0)):
			return "institutions.%s must be in 0..1." % field_name
	return ""


func _logistics_context_error(context: Dictionary) -> String:
	if str(context.get("origin_id", "")).is_empty() or str(context.get("target_id", "")).is_empty():
		return "Origin and target IDs are required."
	for field_name: String in [
		"deliverable_supply", "supply_units_per_capability", "distance_hours",
		"distance_reference_hours",
	]:
		var value: float = float(context.get(field_name, -1.0))
		if not is_finite(value) or value < 0.0:
			return "%s must be finite and non-negative." % field_name
	for field_name: String in ["access_ratio", "infrastructure_ratio", "terrain_supply_ratio"]:
		if not _is_unit_value(context.get(field_name, -1.0)):
			return "%s must be in 0..1." % field_name
	if not context.get("route", {}) is Dictionary:
		return "route must be a dictionary."
	return ""


func _generalized_bottleneck(terms: Array[Dictionary], order: float) -> float:
	var weighted_sum: float = 0.0
	var total_weight: float = 0.0
	for term: Dictionary in terms:
		var value: float = maxf(MINIMUM_NUMERIC_COMPONENT, float(term.get("value", 0.0)))
		var weight: float = maxf(0.0, float(term.get("weight", 0.0)))
		if weight <= 0.0:
			continue
		weighted_sum += weight * pow(value, order)
		total_weight += weight
	if total_weight <= 0.0:
		return 0.0
	return maxf(0.0, pow(weighted_sum / total_weight, 1.0 / order))


func _complementarity(terms: Array[Dictionary]) -> float:
	return clampf(_generalized_bottleneck(terms, -2.0), 0.0, 1.0)


func _supply_degradation_curve(supply_ratio: float) -> float:
	var ratio: float = _unit(supply_ratio)
	if ratio < 0.5:
		return 2.0 * ratio * ratio
	var shortage: float = 1.0 - ratio
	return clampf(1.0 - 2.0 * shortage * shortage, 0.0, 1.0)


func _ordered_bottlenecks(values: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id: Variant in values.keys():
		result.append({"id": str(raw_id), "ratio": _unit(float(values[raw_id]))})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_value: float = float(left.get("ratio", 0.0))
		var right_value: float = float(right.get("ratio", 0.0))
		if not is_equal_approx(left_value, right_value):
			return left_value < right_value
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return result


static func _bottlenecks_valid(raw_value: Variant) -> bool:
	if not raw_value is Array:
		return false
	var previous_ratio: float = -1.0
	for raw_record: Variant in raw_value as Array:
		if not raw_record is Dictionary:
			return false
		var record: Dictionary = raw_record as Dictionary
		var ratio: float = float(record.get("ratio", -1.0))
		if str(record.get("id", "")).is_empty() or not is_finite(ratio) or ratio < 0.0 or ratio > 1.0:
			return false
		if ratio + 0.0000001 < previous_ratio:
			return false
		previous_ratio = ratio
	return true


func _relative_component(value: float, reference: float) -> float:
	if reference <= MINIMUM_NUMERIC_COMPONENT:
		return 0.0 if value <= MINIMUM_NUMERIC_COMPONENT else 1.0
	return clampf(value / reference, 0.0, 1.0)


func _safe_ratio(numerator: float, denominator: float) -> float:
	if denominator <= MINIMUM_NUMERIC_COMPONENT:
		return 0.0 if numerator <= MINIMUM_NUMERIC_COMPONENT else 1.0
	return clampf(numerator / denominator, 0.0, 1.0)


static func _is_unit_value(raw_value: Variant) -> bool:
	var value: float = float(raw_value)
	return is_finite(value) and value >= 0.0 and value <= 1.0


func _unit(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message}
