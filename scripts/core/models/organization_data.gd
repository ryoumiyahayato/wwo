class_name OrganizationData
extends RefCounted

var id: String
var name: String
var type: String
var country_id: String
var region_id: String
var size: float
var resources: float
var influence: float
var public_stance: String
var leader_character_id: String
var member_ids: Array[String]
var position_structure: Dictionary
var organization_relations: Dictionary


static func from_dict(data: Dictionary) -> OrganizationData:
	var model := OrganizationData.new()
	model.id = str(data.get("id", ""))
	model.name = str(data.get("name", ""))
	model.type = str(data.get("type", ""))
	model.country_id = str(data.get("country_id", ""))
	model.region_id = str(data.get("region_id", ""))
	model.size = float(data.get("size", 0.0))
	model.resources = float(data.get("resources", 0.0))
	model.influence = float(data.get("influence", 0.0))
	model.public_stance = str(data.get("public_stance", ""))
	model.leader_character_id = str(data.get("leader_character_id", ""))
	model.member_ids = DataRecordUtils.to_string_array(data.get("member_ids", []))
	model.position_structure = DataRecordUtils.to_dictionary(data.get("position_structure", {}))
	model.organization_relations = DataRecordUtils.to_dictionary(data.get("organization_relations", {}))
	return model


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type": type,
		"country_id": country_id,
		"region_id": region_id,
		"size": size,
		"resources": resources,
		"influence": influence,
		"public_stance": public_stance,
		"leader_character_id": leader_character_id,
		"member_ids": member_ids.duplicate(),
		"position_structure": position_structure.duplicate(true),
		"organization_relations": organization_relations.duplicate(true),
	}
