class_name ActionDefinitionData
extends RefCounted

var id: String
var name: String
var category: String
var total_work: float
var base_progress_per_hour: float
var primary_skill: String
var secondary_skills: Array[String]
var aptitude_modifier_weight: float
var position_permission_required: String
var organization_support_weight: float
var relationship_support_weight: float
var funding_weight: float
var preparation_weight: float
var state_modifier_weight: float
var base_target_resistance: float
var interruption_conditions: Array[String]
var success_threshold: float
var guaranteed_success_threshold: float
var success_result: Dictionary
var failure_result: Dictionary


static func from_dict(data: Dictionary) -> ActionDefinitionData:
	var model := ActionDefinitionData.new()
	model.id = str(data["id"])
	model.name = str(data["name"])
	model.category = str(data["category"])
	model.total_work = float(data["total_work"])
	model.base_progress_per_hour = float(data["base_progress_per_hour"])
	model.primary_skill = str(data["primary_skill"])
	model.secondary_skills = DataRecordUtils.to_string_array(data["secondary_skills"])
	model.aptitude_modifier_weight = float(data["aptitude_modifier_weight"])
	model.position_permission_required = str(data["position_permission_required"])
	model.organization_support_weight = float(data["organization_support_weight"])
	model.relationship_support_weight = float(data["relationship_support_weight"])
	model.funding_weight = float(data["funding_weight"])
	model.preparation_weight = float(data["preparation_weight"])
	model.state_modifier_weight = float(data["state_modifier_weight"])
	model.base_target_resistance = float(data["base_target_resistance"])
	model.interruption_conditions = DataRecordUtils.to_string_array(data["interruption_conditions"])
	model.success_threshold = float(data["success_threshold"])
	model.guaranteed_success_threshold = float(data["guaranteed_success_threshold"])
	model.success_result = DataRecordUtils.to_dictionary(data["success_result"])
	model.failure_result = DataRecordUtils.to_dictionary(data["failure_result"])
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"category": category,
		"total_work": total_work,
		"base_progress_per_hour": base_progress_per_hour,
		"primary_skill": primary_skill,
		"secondary_skills": secondary_skills.duplicate(),
		"aptitude_modifier_weight": aptitude_modifier_weight,
		"position_permission_required": position_permission_required,
		"organization_support_weight": organization_support_weight,
		"relationship_support_weight": relationship_support_weight,
		"funding_weight": funding_weight,
		"preparation_weight": preparation_weight,
		"state_modifier_weight": state_modifier_weight,
		"base_target_resistance": base_target_resistance,
		"interruption_conditions": interruption_conditions.duplicate(),
		"success_threshold": success_threshold,
		"guaranteed_success_threshold": guaranteed_success_threshold,
		"success_result": success_result.duplicate(true),
		"failure_result": failure_result.duplicate(true),
	}
