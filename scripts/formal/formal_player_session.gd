class_name FormalPlayerSession
extends RefCounted
## Formal product player identity and organization authorization. Employment is
## intentionally stored separately from membership and position appointment.

const CONFIG_PATH := "res://data/formal/formal_player_session_1900.json"
const SNAPSHOT_SCHEMA_ID := "formal_player_session_v1"

var organization_core: VNextOrganizationCore
var player: Dictionary = {}
var organization: Dictionary = {}
var employment: Dictionary = {}
var decision: Dictionary = {}
var last_action: Dictionary = {}
var initialization_error: String = ""


func configure() -> bool:
	initialization_error = ""
	var document := _read_document(CONFIG_PATH)
	if document.is_empty():
		return false
	if str(document.get("schema_id", "")) != "formal_player_session_1900_v1":
		return _fail("正式玩家会话配置 Schema 无效")
	player = (document.get("player", {}) as Dictionary).duplicate(true)
	organization = (document.get("organization", {}) as Dictionary).duplicate(true)
	employment = (document.get("employment", {}) as Dictionary).duplicate(true)
	decision = (document.get("decision", {}) as Dictionary).duplicate(true)
	if not _configure_organization_core():
		return false
	last_action = {}
	return _validate_session()


func is_authorized_for_decision() -> bool:
	return (
		organization_core != null
		and organization_core.is_member(
			str(organization.get("organization_id", "")),
			str(player.get("person_id", ""))
		)
		and organization_core.is_authorized(
			str(player.get("person_id", "")),
			str(organization.get("organization_id", "")),
			str(organization.get("capability_id", ""))
		)
	)


func player_summary() -> Dictionary:
	var output := player.duplicate(true)
	var organization_id := str(organization.get("organization_id", ""))
	var person_id := str(player.get("person_id", ""))
	output["organization_id"] = organization_id
	output["organization_name_zh"] = str(organization.get("name_zh", ""))
	output["position_id"] = str(organization.get("position_id", ""))
	output["position_title_zh"] = str(organization.get("position_title_zh", ""))
	output["membership_active"] = organization_core.is_member(
		organization_id, person_id
	)
	output["employment"] = employment.duplicate(true)
	output["capability_id"] = str(organization.get("capability_id", ""))
	output["authorized"] = is_authorized_for_decision()
	return output


func decision_summary() -> Dictionary:
	var output := decision.duplicate(true)
	output["authorized"] = is_authorized_for_decision()
	output["last_action"] = last_action.duplicate(true)
	return output


func record_action(action: Dictionary) -> bool:
	if (
		not is_authorized_for_decision()
		or str(action.get("action_id", "")) != str(decision.get("action_id", ""))
		or str(action.get("shipment_id", "")).is_empty()
	):
		return false
	last_action = action.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"player_id": str(player.get("person_id", "")),
		"organization_id": str(organization.get("organization_id", "")),
		"employment": employment.duplicate(true),
		"organization": organization_core.snapshot(),
		"last_action": last_action.duplicate(true),
	}


func restore(snapshot_value: Dictionary) -> bool:
	if (
		str(snapshot_value.get("schema_id", "")) != SNAPSHOT_SCHEMA_ID
		or str(snapshot_value.get("player_id", "")) != str(player.get("person_id", ""))
		or str(snapshot_value.get("organization_id", ""))
		!= str(organization.get("organization_id", ""))
		or not snapshot_value.get("employment", {}) is Dictionary
		or not snapshot_value.get("organization", {}) is Dictionary
		or not snapshot_value.get("last_action", {}) is Dictionary
	):
		return false
	var candidate_core := VNextOrganizationCore.create(
		[str(player.get("person_id", ""))],
		[str(organization.get("place_id", ""))]
	)
	if candidate_core == null or not candidate_core.restore(
		snapshot_value.get("organization", {}) as Dictionary
	):
		return false
	var candidate_employment := (
		(snapshot_value.get("employment", {}) as Dictionary).duplicate(true)
	)
	var candidate_action := (
		(snapshot_value.get("last_action", {}) as Dictionary).duplicate(true)
	)
	if (
		candidate_employment != employment
		or (
			not candidate_action.is_empty()
			and (
				str(candidate_action.get("action_id", ""))
				!= str(decision.get("action_id", ""))
				or str(candidate_action.get("shipment_id", "")).is_empty()
			)
		)
	):
		return false
	organization_core = candidate_core
	last_action = candidate_action
	return _validate_session()


func _configure_organization_core() -> bool:
	var person_id := str(player.get("person_id", ""))
	var place_id := str(organization.get("place_id", ""))
	var organization_id := str(organization.get("organization_id", ""))
	var capability_id := str(organization.get("capability_id", ""))
	var position_id := str(organization.get("position_id", ""))
	organization_core = VNextOrganizationCore.create([person_id], [place_id])
	if organization_core == null:
		return _fail("无法建立正式组织授权目录")
	if not organization_core.register_organization(
		organization_id,
		str(organization.get("organization_kind", "")),
		place_id
	):
		return _fail("无法登记正式玩家组织")
	if not organization_core.define_capability(organization_id, capability_id):
		return _fail("无法登记正式玩家组织能力")
	if not organization_core.define_position(
		organization_id,
		position_id,
		str(organization.get("position_title_zh", "")),
		1,
		[capability_id]
	):
		return _fail("无法登记正式玩家岗位")
	if not organization_core.add_member(organization_id, person_id):
		return _fail("无法登记正式玩家成员关系")
	if not organization_core.create_appointment(
		organization_id,
		str(organization.get("appointment_id", "")),
		person_id,
		position_id,
		true
	):
		return _fail("无法登记正式玩家岗位任命")
	return true


func _validate_session() -> bool:
	if (
		organization_core == null
		or not organization_core.is_valid()
		or not is_authorized_for_decision()
		or str(employment.get("employer_organization_id", ""))
		!= str(organization.get("organization_id", ""))
		or not bool(employment.get("active", false))
	):
		return _fail("正式玩家会话、雇佣或组织授权无效")
	return true


func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取正式玩家会话配置：%s" % path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		_fail("正式玩家会话配置 JSON 无效：%s" % path)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _fail(message: String) -> bool:
	initialization_error = message
	return false
