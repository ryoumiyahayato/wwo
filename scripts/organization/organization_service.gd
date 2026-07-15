class_name OrganizationService
extends RefCounted
## Runtime membership, positions and permission indexes for validated organizations.

signal membership_changed(character_id: String, organization_id: String)
signal position_changed(character_id: String, organization_id: String, position_id: String)

var organizations: Dictionary = {}
var _positions_by_character: Dictionary = {}


func _init(source_organizations: Dictionary) -> void:
	for raw_id: Variant in source_organizations:
		var source: OrganizationData = source_organizations[raw_id] as OrganizationData
		var organization := OrganizationData.from_dict(source.to_dict())
		organizations[organization.id] = organization


func get_organization(organization_id: String) -> OrganizationData:
	return organizations.get(organization_id) as OrganizationData


func get_organization_ids() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in organizations:
		ids.append(str(raw_id))
	ids.sort()
	return ids


func get_types() -> Array[String]:
	var values: Dictionary = {}
	for raw_organization: Variant in organizations.values():
		values[(raw_organization as OrganizationData).type] = true
	var output: Array[String] = []
	for raw_type: Variant in values:
		output.append(str(raw_type))
	output.sort()
	return output


func join_organization(character: CharacterData, organization_id: String) -> bool:
	var organization: OrganizationData = get_organization(organization_id)
	if character == null or organization == null or character.country_id != organization.country_id:
		return false
	var entry_position: String = str(organization.position_structure.get("entry_position", ""))
	if entry_position.is_empty():
		return false
	if organization.member_ids.has(character.id):
		if not get_position_id(character.id, organization_id).is_empty():
			return true
		return assign_position(character, organization_id, entry_position)
	if not has_entry_vacancy(organization_id):
		return false
	organization.member_ids.append(character.id)
	organization.member_ids.sort()
	if not character.organization_ids.has(organization_id):
		character.organization_ids.append(organization_id)
		character.organization_ids.sort()
	if not assign_position(character, organization_id, entry_position):
		organization.member_ids.erase(character.id)
		character.organization_ids.erase(organization_id)
		return false
	membership_changed.emit(character.id, organization_id)
	return true


func has_entry_vacancy(organization_id: String) -> bool:
	var organization: OrganizationData = get_organization(organization_id)
	if organization == null:
		return false
	var entry_position: String = str(
		organization.position_structure.get("entry_position", "")
	)
	var positions: Dictionary = organization.position_structure.get(
		"positions", {}
	) as Dictionary
	var entry: Dictionary = positions.get(entry_position, {}) as Dictionary
	var holders: Array[String] = DataRecordUtils.to_string_array(
		entry.get("holder_ids", [])
	)
	return (
		not entry_position.is_empty()
		and not entry.is_empty()
		and holders.size() < int(entry.get("slots", 0))
	)


func leave_organization(character: CharacterData, organization_id: String) -> bool:
	var organization: OrganizationData = get_organization(organization_id)
	if character == null or organization == null or not organization.member_ids.has(character.id):
		return false
	_remove_from_current_position(character.id, organization)
	organization.member_ids.erase(character.id)
	character.organization_ids.erase(organization_id)
	if organization.leader_character_id == character.id:
		organization.leader_character_id = ""
	var index: Dictionary = _positions_by_character.get(character.id, {}) as Dictionary
	index.erase(organization_id)
	if index.is_empty():
		_positions_by_character.erase(character.id)
	else:
		_positions_by_character[character.id] = index
		var remaining_ids: Array[String] = []
		for raw_id: Variant in index:
			remaining_ids.append(str(raw_id))
		remaining_ids.sort()
		character.public_position = get_position_name(character.id, remaining_ids[0])
	if index.is_empty():
		character.public_position = ""
	membership_changed.emit(character.id, organization_id)
	return true


func assign_position(
	character: CharacterData, organization_id: String, position_id: String
) -> bool:
	var organization: OrganizationData = get_organization(organization_id)
	if character == null or organization == null or not organization.member_ids.has(character.id):
		return false
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	if not positions.has(position_id):
		return false
	var position: Dictionary = positions[position_id] as Dictionary
	var holders: Array[String] = DataRecordUtils.to_string_array(position.get("holder_ids", []))
	var current_position: String = get_position_id(character.id, organization_id)
	if current_position == position_id:
		return true
	if holders.size() >= int(position.get("slots", 0)):
		return false
	_remove_from_current_position(character.id, organization)
	holders.append(character.id)
	holders.sort()
	position["holder_ids"] = holders
	positions[position_id] = position
	organization.position_structure["positions"] = positions
	var index: Dictionary = _positions_by_character.get(character.id, {}) as Dictionary
	index[organization_id] = position_id
	_positions_by_character[character.id] = index
	character.public_position = str(position.get("name", position_id))
	if position_id == str(organization.position_structure.get("leader_position", "")):
		organization.leader_character_id = character.id
	position_changed.emit(character.id, organization_id, position_id)
	return true


func get_position_id(character_id: String, organization_id: String) -> String:
	var index: Dictionary = _positions_by_character.get(character_id, {}) as Dictionary
	return str(index.get(organization_id, ""))


func get_position_name(character_id: String, organization_id: String) -> String:
	var organization: OrganizationData = get_organization(organization_id)
	var position_id: String = get_position_id(character_id, organization_id)
	if organization == null or position_id.is_empty():
		return ""
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	var position: Dictionary = positions.get(position_id, {}) as Dictionary
	return str(position.get("name", position_id))


func has_permission(
	character_id: String, organization_id: String, permission_id: String
) -> bool:
	var organization: OrganizationData = get_organization(organization_id)
	var position_id: String = get_position_id(character_id, organization_id)
	if organization == null or position_id.is_empty():
		return false
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	var position: Dictionary = positions.get(position_id, {}) as Dictionary
	var permissions: Array[String] = DataRecordUtils.to_string_array(
		position.get("permissions", [])
	)
	return permissions.has(permission_id)


func get_character_permissions(character_id: String) -> Array[String]:
	var output: Array[String] = []
	var index: Dictionary = _positions_by_character.get(character_id, {}) as Dictionary
	for raw_organization_id: Variant in index:
		var organization_id: String = str(raw_organization_id)
		var organization: OrganizationData = get_organization(organization_id)
		if organization == null:
			continue
		var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
		var position: Dictionary = positions.get(str(index[organization_id]), {}) as Dictionary
		for permission: String in DataRecordUtils.to_string_array(position.get("permissions", [])):
			if not output.has(permission):
				output.append(permission)
	output.sort()
	return output


func get_persistent_state() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for organization_id: String in get_organization_ids():
		output.append((organizations[organization_id] as OrganizationData).to_dict())
	return output


func restore_persistent_state(records: Array) -> bool:
	var restored: Dictionary = {}
	var positions_by_character: Dictionary = {}
	if records.size() != organizations.size():
		return false
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			return false
		var organization := OrganizationData.from_dict(raw_record as Dictionary)
		var source: OrganizationData = organizations.get(organization.id) as OrganizationData
		if source == null or restored.has(organization.id):
			return false
		if not _matches_immutable_structure(organization, source):
			return false
		if organization.size < 0.0 or organization.resources < 0.0 or organization.influence < 0.0 or organization.influence > 1.0:
			return false
		var unique_members: Dictionary = {}
		for member_id: String in organization.member_ids:
			if member_id.is_empty() or unique_members.has(member_id):
				return false
			unique_members[member_id] = true
		var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
		var source_positions: Dictionary = source.position_structure.get("positions", {}) as Dictionary
		if positions.size() != source_positions.size():
			return false
		for raw_position_id: Variant in positions:
			var position_id: String = str(raw_position_id)
			if not source_positions.has(position_id) or not positions[position_id] is Dictionary:
				return false
			var position: Dictionary = positions[position_id] as Dictionary
			var source_position: Dictionary = source_positions[position_id] as Dictionary
			if not _matches_position_structure(position, source_position):
				return false
			var position_holders: Array[String] = DataRecordUtils.to_string_array(
				position.get("holder_ids", [])
			)
			if position_holders.size() > int(source_position.get("slots", 0)):
				return false
			var unique_holders: Dictionary = {}
			for character_id: String in position_holders:
				if not unique_members.has(character_id) or unique_holders.has(character_id):
					return false
				unique_holders[character_id] = true
				var index: Dictionary = positions_by_character.get(character_id, {}) as Dictionary
				if index.has(organization.id):
					return false
				index[organization.id] = position_id
				positions_by_character[character_id] = index
		var leader_position_id: String = str(source.position_structure.get("leader_position", ""))
		var leader_holders: Array[String] = []
		if positions.has(leader_position_id):
			leader_holders = DataRecordUtils.to_string_array(
				(positions[leader_position_id] as Dictionary).get("holder_ids", [])
			)
		if not organization.leader_character_id.is_empty():
			if not unique_members.has(organization.leader_character_id) or not leader_holders.has(organization.leader_character_id):
				return false
		elif not leader_holders.is_empty():
			return false
		restored[organization.id] = organization
	if restored.is_empty():
		return false
	organizations = restored
	_positions_by_character = positions_by_character
	return true


func _matches_immutable_structure(
	organization: OrganizationData,
	source: OrganizationData
) -> bool:
	return (
		organization.name == source.name
		and organization.type == source.type
		and organization.country_id == source.country_id
		and organization.region_id == source.region_id
		and organization.public_stance == source.public_stance
		and organization.organization_relations == source.organization_relations
		and str(organization.position_structure.get("entry_position", "")) == str(source.position_structure.get("entry_position", ""))
		and str(organization.position_structure.get("leader_position", "")) == str(source.position_structure.get("leader_position", ""))
	)


func _matches_position_structure(position: Dictionary, source: Dictionary) -> bool:
	return (
		str(position.get("name", "")) == str(source.get("name", ""))
		and int(position.get("level", -1)) == int(source.get("level", -1))
		and int(position.get("slots", -1)) == int(source.get("slots", -1))
		and DataRecordUtils.to_string_array(position.get("permissions", [])) == DataRecordUtils.to_string_array(source.get("permissions", []))
	)


func _remove_from_current_position(
	character_id: String, organization: OrganizationData
) -> void:
	var current_position: String = get_position_id(character_id, organization.id)
	if current_position.is_empty():
		return
	if organization.leader_character_id == character_id:
		organization.leader_character_id = ""
	var positions: Dictionary = organization.position_structure.get("positions", {}) as Dictionary
	var position: Dictionary = positions.get(current_position, {}) as Dictionary
	var holders: Array[String] = DataRecordUtils.to_string_array(position.get("holder_ids", []))
	holders.erase(character_id)
	position["holder_ids"] = holders
	positions[current_position] = position
	organization.position_structure["positions"] = positions
