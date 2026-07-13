class_name SocialSaveValidator
extends RefCounted


func validate(society: SocietySimulationService) -> String:
	var character_ids: Array[String] = _get_all_character_ids(society.roster)
	var expected_organizations: Dictionary = {}
	for organization_id: String in society.organizations.get_organization_ids():
		var organization: OrganizationData = society.organizations.get_organization(organization_id)
		for member_id: String in organization.member_ids:
			var memberships: Array[String] = DataRecordUtils.to_string_array(expected_organizations.get(member_id, []))
			memberships.append(organization_id)
			expected_organizations[member_id] = memberships
	var expected_relationships: Dictionary = {}
	for raw_relationship: Variant in society.relationships.relationships.values():
		var relationship: RelationshipData = raw_relationship as RelationshipData
		for character_id: String in [relationship.character_a_id, relationship.character_b_id]:
			var ids: Array[String] = DataRecordUtils.to_string_array(expected_relationships.get(character_id, []))
			ids.append(relationship.id)
			expected_relationships[character_id] = ids
	for character_id: String in character_ids:
		var character: Variant = society.roster.get_public_character(character_id)
		if character == null:
			return "人物公开记录不存在：%s" % character_id
		var actual_organizations: Array[String] = _get_organization_ids(character)
		var error: String = _validate_exact_index(
			actual_organizations,
			DataRecordUtils.to_string_array(expected_organizations.get(character_id, [])),
			"人物 %s 的组织索引" % character_id
		)
		if not error.is_empty():
			return error
		error = _validate_exact_index(
			_get_relationship_ids(character),
			DataRecordUtils.to_string_array(expected_relationships.get(character_id, [])),
			"人物 %s 的关系索引" % character_id
		)
		if not error.is_empty():
			return error
		if not actual_organizations.is_empty():
			var position_names: Array[String] = []
			for organization_id: String in actual_organizations:
				var position_name: String = society.organizations.get_position_name(character_id, organization_id)
				if not position_name.is_empty():
					position_names.append(position_name)
			if position_names.is_empty():
				return "人物 %s 已加入组织但没有正式职位" % character_id
			var public_position: String = _get_public_position(character)
			if public_position.is_empty() or not position_names.has(public_position):
				return "人物 %s 的公开职位与组织职位不一致" % character_id
	return ""


static func _get_all_character_ids(roster: CharacterRosterService) -> Array[String]:
	var ids: Array[String] = []
	for source: Dictionary in [roster.background_characters, roster.active_characters, roster.exited_characters]:
		for raw_id: Variant in source:
			ids.append(str(raw_id))
	ids.sort()
	return ids


static func _get_organization_ids(character: Variant) -> Array[String]:
	if character is CharacterData:
		return DataRecordUtils.to_string_array((character as CharacterData).organization_ids)
	if character is BackgroundCharacterData:
		return DataRecordUtils.to_string_array((character as BackgroundCharacterData).organization_ids)
	return []


static func _get_relationship_ids(character: Variant) -> Array[String]:
	if character is CharacterData:
		return DataRecordUtils.to_string_array((character as CharacterData).relationship_ids)
	if character is BackgroundCharacterData:
		return DataRecordUtils.to_string_array((character as BackgroundCharacterData).relationship_ids)
	return []


static func _get_public_position(character: Variant) -> String:
	if character is CharacterData:
		return (character as CharacterData).public_position
	if character is BackgroundCharacterData:
		return (character as BackgroundCharacterData).public_position
	return ""


static func _validate_exact_index(actual: Array[String], expected: Array[String], label: String) -> String:
	var seen: Dictionary = {}
	for id: String in actual:
		if id.is_empty() or seen.has(id):
			return "%s 包含空值或重复值" % label
		seen[id] = true
	var actual_sorted: Array[String] = actual.duplicate()
	var expected_sorted: Array[String] = expected.duplicate()
	actual_sorted.sort()
	expected_sorted.sort()
	return "" if actual_sorted == expected_sorted else "%s 与权威服务不一致" % label
