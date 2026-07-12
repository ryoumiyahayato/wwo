class_name SuccessionCandidateData
extends RefCounted

var character_id: String
var name: String
var role_label: String
var score: float
var relationship_id: String = ""
var shared_organization_ids: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"name": name,
		"role_label": role_label,
		"score": score,
		"relationship_id": relationship_id,
		"shared_organization_ids": shared_organization_ids.duplicate(),
	}

