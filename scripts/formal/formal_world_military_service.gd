class_name FormalWorldMilitaryService
extends RefCounted
## Stateful national military capability derived from the formal economy.
##
## This service owns posture/readiness inertia and cached assessments. Economy
## owns population, production, inventories and transport. The shared vNext
## capability model owns the deterministic conversion and projection maths.

const SCHEMA_ID: String = "formal_world_military_state_v1"
const WORLD_SUMMARY_SCHEMA_ID: String = "formal_world_military_summary_v1"
const HOURS_PER_DAY: int = 24
const HISTORY_LIMIT: int = 366

# Capability units are an internal comparison scale, not personnel counts.
const CAPABILITY_SCALE: float = 100.0
const ECONOMIC_OUTPUT_REFERENCE: float = 1000000000.0
const STEEL_OUTPUT_REFERENCE: float = 100000.0
const ENERGY_OUTPUT_REFERENCE: float = 5000000.0
const PEACETIME_MOBILIZATION_MINIMUM: float = 0.08
const PEACETIME_MOBILIZATION_RANGE: float = 0.18
const MOBILIZATION_GAIN_PER_DAY: float = 0.025
const MOBILIZATION_RELEASE_PER_DAY: float = 0.04
const READINESS_RECOVERY_PER_DAY: float = 0.018
const READINESS_LOSS_PER_DAY: float = 0.055
const PREPARATION_GAIN_PER_DAY: float = 0.02
const PREPARATION_LOSS_PER_DAY: float = 0.035
const FATIGUE_GAIN_PER_DAY: float = 0.018
const FATIGUE_RECOVERY_PER_DAY: float = 0.025

var states: Dictionary = {}
var assessments: Dictionary = {}
var history: Array[Dictionary] = []
var initialization_error: String = ""

var _economy: FormalWorldEconomyService
var _model := VNextMilitaryCapabilityModel.new()
var _logistics := FormalWorldMilitaryLogistics.new()
var _last_settlement_hour: int = 0


func configure(economy_service: FormalWorldEconomyService, source_hour: int) -> bool:
	states.clear()
	assessments.clear()
	history.clear()
	initialization_error = ""
	_last_settlement_hour = source_hour
	if economy_service == null or source_hour < 0:
		return _fail("正式军事能力需要经济服务和非负权威时间")
	_economy = economy_service
	if not _logistics.configure(_economy, _model):
		return _fail("正式军事后勤无法绑定经济和运输权威状态")
	for entity_id: String in _economy.economy_entity_ids():
		var economy_state := _economy.country_summary(entity_id)
		if economy_state.is_empty():
			return _fail("军事能力缺少经济实体：%s" % entity_id)
		var structural := _logistics.structural_factors(economy_state)
		var peacetime_target := _peacetime_mobilization_target(structural)
		var readiness_target := _readiness_target(economy_state, structural)
		states[entity_id] = {
			"entity_id": entity_id,
			"mobilization_level": peacetime_target,
			"mobilization_target": peacetime_target,
			"readiness": readiness_target,
			"preparation": 0.2,
			"preparation_target": 0.2,
			"fatigue": 0.0,
			# Formal politics and military institutions do not yet exist. Values of
			# one are deliberately non-binding rather than invented country scores.
			"political_support": 1.0,
			"organization_quality": 1.0,
			"command_effectiveness": 1.0,
			"institution_source": "not_integrated_not_applied",
			"last_settlement_hour": source_hour,
		}
	if not _refresh_assessments(source_hour):
		return false
	return _validate_state(source_hour)


func set_operational_posture(
	entity_id: String,
	mobilization_target: float,
	preparation_target: float
) -> bool:
	var economy_id := _resolve_economy_id(entity_id)
	if (
		economy_id.is_empty()
		or not _is_unit(mobilization_target)
		or not _is_unit(preparation_target)
	):
		return false
	var state := states[economy_id] as Dictionary
	state["mobilization_target"] = mobilization_target
	state["preparation_target"] = preparation_target
	states[economy_id] = state
	return true


func set_institutional_context(entity_id: String, context: Dictionary) -> bool:
	## Explicit adapter for a future authoritative politics/organization owner.
	## A source ID is mandatory so guessed institutional values cannot enter state.
	var economy_id := _resolve_economy_id(entity_id)
	if economy_id.is_empty() or str(context.get("source_id", "")).is_empty():
		return false
	for field_name: String in [
		"political_support", "organization_quality", "command_effectiveness",
	]:
		if not _is_unit(context.get(field_name, -1.0)):
			return false
	var state := states[economy_id] as Dictionary
	state["political_support"] = float(context["political_support"])
	state["organization_quality"] = float(context["organization_quality"])
	state["command_effectiveness"] = float(context["command_effectiveness"])
	state["institution_source"] = str(context["source_id"])
	states[economy_id] = state
	return _refresh_assessment(economy_id, _last_settlement_hour)


func settle_day(settlement_hour: int) -> Dictionary:
	if (
		_economy == null
		or settlement_hour <= _last_settlement_hour
		or settlement_hour % HOURS_PER_DAY != 0
	):
		return world_summary()
	var elapsed_days := float(settlement_hour - _last_settlement_hour) / float(
		HOURS_PER_DAY
	)
	for entity_id: String in _sorted_state_ids():
		var economy_state := _economy.country_summary(entity_id)
		var structural := _logistics.structural_factors(economy_state)
		var state := states[entity_id] as Dictionary
		var mobilization := float(state.get("mobilization_level", 0.0))
		var mobilization_target := float(state.get("mobilization_target", 0.0))
		state["mobilization_level"] = _approach_asymmetric(
			mobilization,
			mobilization_target,
			MOBILIZATION_GAIN_PER_DAY * elapsed_days,
			MOBILIZATION_RELEASE_PER_DAY * elapsed_days
		)
		var readiness_target := _readiness_target(economy_state, structural)
		# High mobilization consumes training, maintenance and supply headroom.
		readiness_target *= 1.0 - 0.24 * maxf(
			0.0, float(state["mobilization_level"]) - 0.55
		) / 0.45
		state["readiness"] = _approach_asymmetric(
			float(state.get("readiness", 0.0)),
			clampf(readiness_target, 0.0, 1.0),
			READINESS_RECOVERY_PER_DAY * elapsed_days,
			READINESS_LOSS_PER_DAY * elapsed_days
		)
		state["preparation"] = _approach_asymmetric(
			float(state.get("preparation", 0.0)),
			float(state.get("preparation_target", 0.0)),
			PREPARATION_GAIN_PER_DAY * elapsed_days,
			PREPARATION_LOSS_PER_DAY * elapsed_days
		)
		var shortage := 1.0 - _logistics.economy_fulfillment(economy_state)
		var fatigue_target := clampf(
			maxf(0.0, float(state["mobilization_level"]) - 0.45) * 0.8
			+ shortage * 0.5,
			0.0,
			1.0
		)
		state["fatigue"] = _approach_asymmetric(
			float(state.get("fatigue", 0.0)),
			fatigue_target,
			FATIGUE_GAIN_PER_DAY * elapsed_days,
			FATIGUE_RECOVERY_PER_DAY * elapsed_days
		)
		state["last_settlement_hour"] = settlement_hour
		states[entity_id] = state
	_last_settlement_hour = settlement_hour
	if not _refresh_assessments(settlement_hour):
		return world_summary()
	var summary := world_summary()
	summary["day_index"] = int(settlement_hour / HOURS_PER_DAY)
	history.append(summary)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	return summary


func country_assessment(entity_id: String) -> Dictionary:
	var economy_id := _resolve_economy_id(entity_id)
	return (assessments.get(economy_id, {}) as Dictionary).duplicate(true)


func project_capability(
	origin_entity_id: String,
	target_entity_id: String,
	operational_context: Dictionary = {}
) -> Dictionary:
	var origin_id := _resolve_economy_id(origin_entity_id)
	var target_id := _resolve_economy_id(target_entity_id)
	if origin_id.is_empty() or target_id.is_empty():
		return _failure("unknown_operational_area", "起点或目标没有正式高细节经济")
	var assessment := assessments.get(origin_id, {}) as Dictionary
	if not VNextMilitaryCapabilityModel.is_valid_assessment(assessment):
		return _failure("missing_assessment", "起点没有有效军事能力评估")
	var logistics_context := _logistics.build_projection_context(
		origin_id, target_id, origin_entity_id, target_entity_id, assessment
	)
	if logistics_context.is_empty():
		return _failure("missing_logistics_context", "无法生成正式军事后勤上下文")
	var context := operational_context.duplicate(true)
	var state := states[origin_id] as Dictionary
	if not context.has("preparation"):
		context["preparation"] = float(state.get("preparation", 0.0))
	if not context.has("terrain_combat_factor"):
		context["terrain_combat_factor"] = 1.0
	if not context.has("defensive_preparation"):
		context["defensive_preparation"] = (
			float(state.get("preparation", 0.0)) if origin_id == target_id else 0.0
		)
	if not context.has("role"):
		context["role"] = "defend" if origin_id == target_id else "attack"
	var result := _model.project_to_area(assessment, logistics_context, context)
	if bool(result.get("success", false)):
		result["source_status"] = {
			"transport": "authoritative_formal_route_topology",
			"infrastructure": "authoritative_historical_economy",
			"terrain": "not_integrated_not_applied",
		}
	return result


func operational_advantage(
	attacker_entity_id: String,
	defender_entity_id: String,
	target_entity_id: String,
	attacker_context: Dictionary = {},
	defender_context: Dictionary = {}
) -> Dictionary:
	var attacker_options := attacker_context.duplicate(true)
	attacker_options["role"] = "attack"
	var defender_options := defender_context.duplicate(true)
	defender_options["role"] = "defend"
	var attacker := project_capability(
		attacker_entity_id, target_entity_id, attacker_options
	)
	var defender := project_capability(
		defender_entity_id, target_entity_id, defender_options
	)
	var comparison := _model.compare_operational_contexts(attacker, defender)
	if bool(comparison.get("success", false)):
		comparison["attacker"] = attacker
		comparison["defender"] = defender
		comparison["target_id"] = target_entity_id
	return comparison


func world_summary() -> Dictionary:
	var potential := 0.0
	var available := 0.0
	var operational := 0.0
	var readiness_total := 0.0
	var lowest_readiness := 1.0
	var lowest_readiness_id := ""
	for entity_id: String in _sorted_assessment_ids():
		var assessment := assessments[entity_id] as Dictionary
		potential += float(assessment.get("potential_capability", 0.0))
		available += float(assessment.get("available_capability", 0.0))
		operational += float(assessment.get("operational_effectiveness", 0.0))
		var readiness := float(assessment.get("readiness", 0.0))
		readiness_total += readiness
		if readiness < lowest_readiness:
			lowest_readiness = readiness
			lowest_readiness_id = entity_id
	return {
		"schema_id": WORLD_SUMMARY_SCHEMA_ID,
		"total_hour": _last_settlement_hour,
		"assessment_count": assessments.size(),
		"potential_capability": potential,
		"available_capability": available,
		"operational_effectiveness": operational,
		"average_readiness": (
			readiness_total / float(assessments.size())
			if not assessments.is_empty() else 0.0
		),
		"lowest_readiness": lowest_readiness if not assessments.is_empty() else 0.0,
		"lowest_readiness_entity_id": lowest_readiness_id,
	}


func get_persistent_state() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"total_hour": _last_settlement_hour,
		"states": states.duplicate(true),
		"history": history.duplicate(true),
	}


func restore_persistent_state(
	state: Dictionary,
	economy_service: FormalWorldEconomyService,
	authoritative_hour: int
) -> bool:
	var saved_settlement_hour := int(state.get("total_hour", -1))
	if (
		str(state.get("schema_id", "")) != SCHEMA_ID
		or saved_settlement_hour < 0
		or saved_settlement_hour > authoritative_hour
		or authoritative_hour - saved_settlement_hour >= HOURS_PER_DAY
		or not state.get("states", {}) is Dictionary
		or not state.get("history", []) is Array
	):
		return false
	var candidate_states := (state.get("states", {}) as Dictionary).duplicate(true)
	if economy_service == null or candidate_states.size() != economy_service.economy_entity_ids().size():
		return false
	_economy = economy_service
	if not _logistics.configure(_economy, _model):
		return false
	for entity_id: String in economy_service.economy_entity_ids():
		if not candidate_states.get(entity_id, {}) is Dictionary:
			return false
		if not _military_state_valid(candidate_states[entity_id] as Dictionary, entity_id, saved_settlement_hour):
			return false
	var candidate_history := DataRecordUtils.to_dictionary_array(state.get("history", []))
	while candidate_history.size() > HISTORY_LIMIT:
		candidate_history.pop_front()
	var previous_states := states
	var previous_assessments := assessments
	var previous_history := history
	var previous_hour := _last_settlement_hour
	states = candidate_states
	history = candidate_history
	_last_settlement_hour = saved_settlement_hour
	if not _refresh_assessments(saved_settlement_hour) or not _validate_state(saved_settlement_hour):
		states = previous_states
		assessments = previous_assessments
		history = previous_history
		_last_settlement_hour = previous_hour
		return false
	return true


func _refresh_assessments(source_hour: int) -> bool:
	var next_assessments: Dictionary = {}
	for entity_id: String in _sorted_state_ids():
		var military_state := states[entity_id] as Dictionary
		var economy_state := _economy.country_summary(entity_id)
		var assessment := _assessment_input(entity_id, economy_state, military_state, source_hour)
		var report := _model.assess_country(assessment)
		if not bool(report.get("success", false)):
			return _fail("军事能力评估失败：%s：%s" % [entity_id, str(report.get("message", ""))])
		next_assessments[entity_id] = report
	assessments = next_assessments
	return true


func _refresh_assessment(entity_id: String, source_hour: int) -> bool:
	var economy_state := _economy.country_summary(entity_id)
	var report := _model.assess_country(_assessment_input(
		entity_id, economy_state, states[entity_id] as Dictionary, source_hour
	))
	if not bool(report.get("success", false)):
		return false
	assessments[entity_id] = report
	return true


func _assessment_input(
	entity_id: String,
	economy_state: Dictionary,
	military_state: Dictionary,
	source_hour: int
) -> Dictionary:
	var structural := _logistics.structural_factors(economy_state)
	var population_millions := maxf(
		0.0, float(economy_state.get("population", 0)) / 1000000.0
	)
	var economic_output := float(economy_state.get("population", 0)) * float(
		economy_state.get("income_per_capita", 0)
	)
	var manpower_units := sqrt(population_millions) * CAPABILITY_SCALE
	var economic_units := sqrt(
		maxf(0.0, economic_output) / ECONOMIC_OUTPUT_REFERENCE
	) * CAPABILITY_SCALE
	var production := economy_state.get("production", {}) as Dictionary
	var industrial_mass := sqrt(
		population_millions
		* maxf(0.0, float(production.get("industrial_capacity_index", 0)) / 100.0)
	) * CAPABILITY_SCALE
	var steel_units := sqrt(
		maxf(0.0, float(production.get("steel_output_tonnes", 0)))
		/ STEEL_OUTPUT_REFERENCE
	) * CAPABILITY_SCALE
	var energy_units := sqrt(
		maxf(0.0, float(production.get("primary_energy_coal_equivalent_tonnes", 0)))
		/ ENERGY_OUTPUT_REFERENCE
	) * CAPABILITY_SCALE
	# Imports and low-steel equipment can substitute for a limited share of a
	# domestic heavy-industry bottleneck; they cannot erase it.
	steel_units = maxf(steel_units, industrial_mass * 0.18)
	energy_units = maxf(energy_units, industrial_mass * 0.25)
	var industrial_units := _model.combine_bottlenecks([
		{"value": industrial_mass, "weight": 0.48},
		{"value": steel_units, "weight": 0.28},
		{"value": energy_units, "weight": 0.24},
	], -1.45)
	var fulfillment := _logistics.economy_fulfillment(economy_state)
	var military_stock := _military_stock_support(economy_state)
	var fiscal_units := economic_units * (0.55 + 0.45 * fulfillment)
	var equipment_ratio := _model.combine_bottlenecks([
		{"value": float(structural.get("industry", 0.0)), "weight": 0.42},
		{"value": military_stock, "weight": 0.30},
		{"value": fulfillment, "weight": 0.15},
		{"value": float(structural.get("infrastructure", 0.0)), "weight": 0.13},
	], -1.7)
	var sustainment := _model.combine_bottlenecks([
		{"value": fulfillment, "weight": 0.42},
		{"value": float(structural.get("industry", 0.0)), "weight": 0.23},
		{"value": float(structural.get("infrastructure", 0.0)), "weight": 0.20},
		{"value": military_stock, "weight": 0.15},
	], -1.7)
	return {
		"country_id": entity_id,
		"source_hour": source_hour,
		"manpower_capability_units": manpower_units,
		"economic_capability_units": economic_units,
		"industrial_capability_units": industrial_units,
		"fiscal_capability_units": fiscal_units,
		"force_state": {
			"mobilization_level": float(military_state.get("mobilization_level", 0.0)),
			"equipment_ratio": equipment_ratio,
			"administration_ratio": float(structural.get("administration", 0.0)),
			"readiness": float(military_state.get("readiness", 0.0)),
			"sustainment_ratio": sustainment,
			"cohesion": 1.0 - float(military_state.get("fatigue", 0.0)),
			"political_support": float(military_state.get("political_support", 1.0)),
		},
		"institutions": {
			"command_effectiveness": float(military_state.get("command_effectiveness", 1.0)),
			"organization_quality": float(military_state.get("organization_quality", 1.0)),
		},
		"source_status": {
			"population": "authoritative_historical_economy",
			"economy": "authoritative_formal_market",
			"industry": "authoritative_historical_production",
			"infrastructure": "authoritative_historical_transport",
			"politics": str(military_state.get("institution_source", "not_integrated_not_applied")),
			"organization": str(military_state.get("institution_source", "not_integrated_not_applied")),
			"technology": "not_available_not_applied",
		},
		"source_details": {
			"population": int(economy_state.get("population", 0)),
			"income_per_capita": int(economy_state.get("income_per_capita", 0)),
			"industrial_capacity_ratio": float(structural.get("industry", 0.0)),
			"infrastructure_ratio": float(structural.get("infrastructure", 0.0)),
			"market_fulfillment_ratio": fulfillment,
			"military_goods_stock_ratio": military_stock,
		},
	}


func _readiness_target(economy_state: Dictionary, structural: Dictionary) -> float:
	return _model.combine_bottlenecks([
		{"value": _logistics.economy_fulfillment(economy_state), "weight": 0.34},
		{"value": float(structural.get("industry", 0.0)), "weight": 0.27},
		{"value": float(structural.get("infrastructure", 0.0)), "weight": 0.23},
		{"value": _military_stock_support(economy_state), "weight": 0.16},
	], -1.8)


func _military_stock_support(economy_state: Dictionary) -> float:
	var inventory := economy_state.get("inventory", {}) as Dictionary
	var small_arms := maxf(0.0, float(inventory.get("small_arms", 0.0)))
	var ammunition := maxf(0.0, float(inventory.get("ammunition", 0.0)))
	return _model.combine_bottlenecks([
		{"value": small_arms / (small_arms + 20.0), "weight": 0.45},
		{"value": ammunition / (ammunition + 20.0), "weight": 0.55},
	], -1.8)


func _peacetime_mobilization_target(structural: Dictionary) -> float:
	var support := _model.combine_bottlenecks([
		{"value": float(structural.get("industry", 0.0)), "weight": 0.50},
		{"value": float(structural.get("administration", 0.0)), "weight": 0.50},
	], -1.5)
	return PEACETIME_MOBILIZATION_MINIMUM + PEACETIME_MOBILIZATION_RANGE * support


func _resolve_economy_id(entity_id: String) -> String:
	if states.has(entity_id):
		return entity_id
	var economy_id := _economy.economy_entity_for_polity(entity_id) if _economy != null else ""
	return economy_id if states.has(economy_id) else ""


func _validate_state(authoritative_hour: int) -> bool:
	if states.size() != assessments.size() or states.size() != _economy.economy_entity_ids().size():
		return false
	for entity_id: String in _sorted_state_ids():
		if not _military_state_valid(states[entity_id] as Dictionary, entity_id, authoritative_hour):
			return false
		if not VNextMilitaryCapabilityModel.is_valid_assessment(assessments[entity_id] as Dictionary):
			return false
	return true


func _military_state_valid(state: Dictionary, entity_id: String, authoritative_hour: int) -> bool:
	if (
		str(state.get("entity_id", "")) != entity_id
		or int(state.get("last_settlement_hour", -1)) != authoritative_hour
		or str(state.get("institution_source", "")).is_empty()
	):
		return false
	for field_name: String in [
		"mobilization_level", "mobilization_target", "readiness",
		"preparation", "preparation_target", "fatigue", "political_support",
		"organization_quality", "command_effectiveness",
	]:
		if not _is_unit(state.get(field_name, -1.0)):
			return false
	return true


func _sorted_state_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in states.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func _sorted_assessment_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in assessments.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids


func _approach_asymmetric(
	current: float,
	target: float,
	positive_step: float,
	negative_step: float
) -> float:
	var step := positive_step if target > current else negative_step
	return move_toward(current, target, step)


func _is_unit(raw_value: Variant) -> bool:
	var value := float(raw_value)
	return is_finite(value) and value >= 0.0 and value <= 1.0


func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": message}


func _fail(message: String) -> bool:
	initialization_error = message
	return false
