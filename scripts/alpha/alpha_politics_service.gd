class_name AlphaPoliticsService
extends RefCounted
## Organization/position/policy/corruption rules layered on the unified organization authority.

const PUBLIC_SPENDING_ID: String = "system:public_spending"
const POSITION_PERMISSION_SET: Array[String] = [
	"organization_member",
	"campaign_support",
	"appoint_position",
	"remove_position",
	"contract_sign",
	"budget_spend",
	"policy_labor",
	"policy_enterprise",
	"policy_credit",
	"policy_budget",
	"investigation_control",
	"asset_disposal",
	"command_staff",
]
const VALID_POSITION_LOSS_CAUSES: Array[String] = [
	"resignation",
	"term_expired",
	"organization_change",
	"illegal_conduct",
	"vote_lost",
	"removed",
]

var organization_states: Dictionary = {}
var position_packages: Dictionary = {}
var appointments: Dictionary = {}
var factions: Dictionary = {}
var issues: Dictionary = {}
var policies: Dictionary = {}
var policy_implementations: Dictionary = {}
var support_records: Dictionary = {}
var political_exchanges: Dictionary = {}
var corruption_cases: Dictionary = {}
var investigations: Dictionary = {}
var public_events: Array[Dictionary] = []
var obligations: Dictionary = {}
var _organizations: OrganizationService
var _economy: AlphaEconomyService
var _world: AlphaWorldService
var _config: AlphaConfig
var _processed_keys: Dictionary = {}
var _next_faction_sequence: int = 1
var _next_policy_sequence: int = 1
var _next_corruption_sequence: int = 1
var _next_investigation_sequence: int = 1


func configure(
	config: AlphaConfig,
	organizations: OrganizationService,
	economy: AlphaEconomyService,
	world: AlphaWorldService
) -> bool:
	_config = config
	_organizations = organizations
	_economy = economy
	_world = world
	organization_states.clear()
	position_packages.clear()
	appointments.clear()
	factions.clear()
	issues.clear()
	policies.clear()
	policy_implementations.clear()
	support_records.clear()
	political_exchanges.clear()
	corruption_cases.clear()
	investigations.clear()
	public_events.clear()
	obligations.clear()
	_processed_keys.clear()
	_next_faction_sequence = 1
	_next_policy_sequence = 1
	_next_corruption_sequence = 1
	_next_investigation_sequence = 1
	if not _economy.entity_profiles.has(PUBLIC_SPENDING_ID):
		if not bool(_economy.register_entity(
			PUBLIC_SPENDING_ID, "system", 5_000_000
		).get("success", false)):
			return false
	for raw_addition: Variant in config.organization_additions():
		if not _register_organization_addition(raw_addition as Dictionary):
			return false
	for raw_issue: Variant in config.issue_records():
		var issue: Dictionary = raw_issue as Dictionary
		issues[str(issue.get("issue_id", ""))] = issue.duplicate(true)
	for raw_policy: Variant in config.policy_records():
		var policy: Dictionary = raw_policy as Dictionary
		policies[str(policy.get("policy_id", ""))] = policy.duplicate(true)
	for organization_id: String in _organizations.get_organization_ids():
		var organization: OrganizationData = _organizations.get_organization(
			organization_id
		)
		if organization != null and organization.type == "news":
			organization.type = "press"
		_initialize_organization_state(organization_id)
	return (
		issues.size() >= 8
		and policies.size() >= 8
		and _count_type("political") >= 4
	)


func join_organization(
	idempotency_key: String,
	character: CharacterData,
	organization_id: String,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true, "organization_id": organization_id})
	if not _organizations.join_organization(character, organization_id):
		return _fail("join_rejected", "人物国籍、组织容量或入口职位不允许加入")
	var position_id: String = _organizations.get_position_id(
		character.id, organization_id
	)
	_record_appointment(character.id, organization_id, position_id, total_hour)
	_processed_keys[idempotency_key] = organization_id
	return _ok({
		"organization_id": organization_id,
		"position_id": position_id,
		"character_id": character.id,
	})


func leave_organization(
	idempotency_key: String,
	character: CharacterData,
	organization_id: String,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true})
	var old_position: String = _organizations.get_position_id(
		character.id, organization_id
	)
	if not _organizations.leave_organization(character, organization_id):
		return _fail("leave_rejected", "人物不是该组织成员")
	_close_appointment(
		character.id, organization_id, old_position, total_hour, "organization_change"
	)
	_processed_keys[idempotency_key] = organization_id
	return _ok({"organization_id": organization_id, "old_position_id": old_position})


func create_faction(
	idempotency_key: String,
	parent_organization_id: String,
	founder: CharacterData,
	name: String,
	agenda_issue_ids: Array,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"faction": (factions.get(existing_id, {}) as Dictionary).duplicate(true),
			"duplicate": true,
		})
	var organization: OrganizationData = _organizations.get_organization(
		parent_organization_id
	)
	if (
		organization == null
		or organization.type != "political"
		or founder == null
		or founder.id not in organization.member_ids
		or name.is_empty()
		or agenda_issue_ids.is_empty()
	):
		return _fail("invalid_faction", "派别必须由政治组织成员围绕实际议题建立")
	for issue_id: String in DataRecordUtils.to_string_array(agenda_issue_ids):
		if not issues.has(issue_id):
			return _fail("issue_missing", "派别议程引用未知议题")
	var faction_id: String = "faction:alpha:%d" % _next_faction_sequence
	_next_faction_sequence += 1
	var faction: Dictionary = {
		"faction_id": faction_id,
		"parent_organization_id": parent_organization_id,
		"name": name,
		"founder_id": founder.id,
		"member_ids": [founder.id],
		"agenda_issue_ids": DataRecordUtils.to_string_array(agenda_issue_ids),
		"resources": 0,
		"support": 10,
		"created_hour": total_hour,
		"status": "active",
	}
	factions[faction_id] = faction
	var state: Dictionary = organization_states[parent_organization_id] as Dictionary
	(state["faction_ids"] as Array).append(faction_id)
	organization_states[parent_organization_id] = state
	_processed_keys[idempotency_key] = faction_id
	return _ok({"faction": faction.duplicate(true), "duplicate": false})


func join_faction(
	idempotency_key: String, faction_id: String, character: CharacterData
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"faction": (factions.get(faction_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var faction: Dictionary = factions.get(faction_id, {}) as Dictionary
	var organization: OrganizationData = _organizations.get_organization(
		str(faction.get("parent_organization_id", ""))
	)
	if (
		faction.is_empty()
		or character == null
		or organization == null
		or character.id not in organization.member_ids
	):
		return _fail("faction_join_rejected", "人物必须先是派别所属组织成员")
	var members: Array = faction.get("member_ids", []) as Array
	if character.id not in members:
		members.append(character.id)
		members.sort()
	faction["member_ids"] = members
	factions[faction_id] = faction
	_processed_keys[idempotency_key] = faction_id
	return _ok({"faction": faction.duplicate(true)})


func campaign_for_support(
	idempotency_key: String,
	candidate: CharacterData,
	supporter: CharacterData,
	organization_id: String,
	issue_id: String,
	effort: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true})
	var organization: OrganizationData = _organizations.get_organization(organization_id)
	if (
		candidate == null
		or supporter == null
		or organization == null
		or candidate.id not in organization.member_ids
		or supporter.id not in organization.member_ids
		or not issues.has(issue_id)
		or effort <= 0
	):
		return _fail("invalid_campaign", "争取支持必须发生在实际成员和议题之间")
	var candidate_position: String = _organizations.get_position_id(
		candidate.id, organization_id
	)
	var package: Dictionary = position_packages.get(
		_position_key(organization_id, candidate_position), {}
	) as Dictionary
	var influence: int = int(package.get("level", 1)) * 4
	var points: int = clampi(
		effort / 5
		+ int(candidate.skills.get("public_speaking", 0)) / 10
		+ int(candidate.hidden_aptitudes.get("social_perception", 50)) / 20
		+ influence,
		1,
		30
	)
	var key: String = _support_key(organization_id, candidate.id, supporter.id)
	support_records[key] = clampi(int(support_records.get(key, 0)) + points, -100, 100)
	_processed_keys[idempotency_key] = key
	return _ok({
		"support_key": key,
		"support": support_records[key],
		"issue_id": issue_id,
	})


func contest_position(
	idempotency_key: String,
	candidate: CharacterData,
	organization_id: String,
	position_id: String,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true, "position_id": position_id})
	var organization: OrganizationData = _organizations.get_organization(organization_id)
	if (
		candidate == null
		or organization == null
		or candidate.id not in organization.member_ids
	):
		return _fail("position_contest_rejected", "候选人不是该组织成员")
	var positions: Dictionary = organization.position_structure.get(
		"positions", {}
	) as Dictionary
	if not positions.has(position_id):
		return _fail("position_missing", "争取的职位不存在")
	var position: Dictionary = positions[position_id] as Dictionary
	var required_support: int = 20 + int(position.get("level", 1)) * 10
	var support_total: int = 0
	for member_id: String in organization.member_ids:
		if member_id == candidate.id:
			continue
		support_total += int(support_records.get(
			_support_key(organization_id, candidate.id, member_id), 0
		))
	support_total += int(candidate.skills.get("political_activity", 0)) / 2
	var result_status: String = "won" if support_total >= required_support else "lost"
	if result_status == "lost":
		_processed_keys[idempotency_key] = "lost"
		return _ok({
			"result": "lost",
			"support_total": support_total,
			"required_support": required_support,
		})
	var old_position: String = _organizations.get_position_id(
		candidate.id, organization_id
	)
	if not _organizations.assign_position(candidate, organization_id, position_id):
		return _fail("position_unavailable", "职位槽位已满或任职条件改变")
	_close_appointment(
		candidate.id, organization_id, old_position, total_hour, "vote_lost"
	)
	_record_appointment(candidate.id, organization_id, position_id, total_hour)
	_processed_keys[idempotency_key] = position_id
	return _ok({
		"result": "won",
		"support_total": support_total,
		"required_support": required_support,
		"position_id": position_id,
	})


func appoint_to_position(
	idempotency_key: String,
	appointing_character_id: String,
	candidate: CharacterData,
	organization_id: String,
	position_id: String,
	total_hour: int
) -> Dictionary:
	if not _has_extended_permission(
		appointing_character_id, organization_id, "appoint_position"
	):
		return _fail("appointment_permission_denied", "任命者没有任命权限")
	var old_position: String = _organizations.get_position_id(
		candidate.id, organization_id
	)
	if not _organizations.assign_position(candidate, organization_id, position_id):
		return _fail("appointment_failed", "候选人、职位或槽位无效")
	_close_appointment(
		candidate.id, organization_id, old_position, total_hour, "removed"
	)
	_record_appointment(candidate.id, organization_id, position_id, total_hour)
	_processed_keys[idempotency_key] = position_id
	return _ok({"position_id": position_id, "candidate_id": candidate.id})


func lose_position(
	idempotency_key: String,
	character: CharacterData,
	organization_id: String,
	cause: String,
	total_hour: int,
	remover_id: String = ""
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true})
	if cause not in VALID_POSITION_LOSS_CAUSES or character == null:
		return _fail("invalid_position_loss", "职位失去原因无效")
	var old_position: String = _organizations.get_position_id(
		character.id, organization_id
	)
	var organization: OrganizationData = _organizations.get_organization(organization_id)
	if organization == null or old_position.is_empty():
		return _fail("position_missing", "人物当前没有该组织职位")
	if (
		cause not in ["resignation", "term_expired", "illegal_conduct", "vote_lost"]
		and (
			remover_id.is_empty()
			or not _has_extended_permission(
				remover_id, organization_id, "remove_position"
			)
		)
	):
		return _fail("removal_permission_denied", "罢免者没有罢免权限")
	var entry_position: String = str(
		organization.position_structure.get("entry_position", "")
	)
	if old_position != entry_position:
		if not _organizations.assign_position(character, organization_id, entry_position):
			return _fail("position_loss_failed", "无法恢复为普通成员职位")
	_close_appointment(character.id, organization_id, old_position, total_hour, cause)
	_record_appointment(character.id, organization_id, entry_position, total_hour)
	_processed_keys[idempotency_key] = entry_position
	return _ok({
		"old_position_id": old_position,
		"new_position_id": entry_position,
		"cause": cause,
	})


func expire_terms(total_hour: int, characters_by_id: Dictionary) -> Array[String]:
	var expired: Array[String] = []
	for raw_key: Variant in appointments.keys():
		var key: String = str(raw_key)
		var appointment: Dictionary = appointments[key] as Dictionary
		if (
			str(appointment.get("status", "")) == "active"
			and int(appointment.get("end_hour", total_hour + 1)) <= total_hour
		):
			var character_id: String = str(appointment.get("character_id", ""))
			var character: CharacterData = characters_by_id.get(character_id) as CharacterData
			if character != null:
				var result: Dictionary = lose_position(
					"term_expire:%s:%d" % [key, total_hour],
					character,
					str(appointment.get("organization_id", "")),
					"term_expired",
					total_hour
				)
				if bool(result.get("success", false)):
					expired.append(key)
	return expired


func propose_policy(
	idempotency_key: String,
	actor: CharacterData,
	organization_id: String,
	policy_id: String,
	target_region_ids: Array,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"implementation": (
				policy_implementations.get(existing_id, {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	var policy: Dictionary = policies.get(policy_id, {}) as Dictionary
	var organization: OrganizationData = _organizations.get_organization(organization_id)
	if (
		actor == null
		or policy.is_empty()
		or organization == null
		or organization.country_id != str(policy.get("country_id", ""))
		or not _has_extended_permission(
			actor.id, organization_id, str(policy.get("legal_permission", ""))
		)
		or target_region_ids.is_empty()
	):
		return _fail("policy_permission_denied", "政策法定权限、国家或目标地区无效")
	for region_id: String in DataRecordUtils.to_string_array(target_region_ids):
		var region: Dictionary = _world.regions.get(region_id, {}) as Dictionary
		if str(region.get("country_id", "")) != organization.country_id:
			return _fail("policy_jurisdiction_error", "政策目标超出组织法定辖区")
	var implementation_id: String = "policy_implementation:alpha:%d" % _next_policy_sequence
	_next_policy_sequence += 1
	var issue: Dictionary = issues.get(str(policy.get("issue_id", "")), {}) as Dictionary
	var implementation: Dictionary = {
		"implementation_id": implementation_id,
		"policy_id": policy_id,
		"issue_id": policy.get("issue_id", ""),
		"actor_id": actor.id,
		"organization_id": organization_id,
		"target_region_ids": DataRecordUtils.to_string_array(target_region_ids),
		"proposed_hour": total_hour,
		"status": "authorized",
		"legal_permission": true,
		"actual_compliance": clampi(55 + roundi(organization.influence * 30.0), 20, 95),
		"execution_capacity": clampi(45 + roundi(organization.size * 2.0), 25, 90),
		"funding_ratio": 0,
		"staffing": 65,
		"infrastructure": _average_infrastructure(target_region_ids),
		"external_resistance": clampi(
			int(issue.get("pressure", 50)) / 3
			+ (issue.get("opposing_interests", []) as Array).size() * 6,
			5,
			70
		),
		"budget_cost_centimes": int(policy.get("budget_cost", 0)),
		"spent_centimes": 0,
		"progress": 0,
		"applied_effects": {},
		"support_reactions": [],
		"opposition_reactions": [],
	}
	policy_implementations[implementation_id] = implementation
	var state: Dictionary = organization_states[organization_id] as Dictionary
	(state["policy_ids"] as Array).append(implementation_id)
	(state["current_matter_ids"] as Array).append(implementation_id)
	organization_states[organization_id] = state
	_processed_keys[idempotency_key] = implementation_id
	return _ok({"implementation": implementation.duplicate(true), "duplicate": false})


func fund_and_start_policy(
	idempotency_key: String, implementation_id: String, total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"implementation": (policy_implementations.get(implementation_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var implementation: Dictionary = policy_implementations.get(
		implementation_id, {}
	) as Dictionary
	if str(implementation.get("status", "")) != "authorized":
		return _fail("policy_not_authorized", "政策尚未获得法定授权或已经启动")
	var cost: int = int(implementation.get("budget_cost_centimes", 0))
	var organization_id: String = str(implementation.get("organization_id", ""))
	var available: int = _economy.ledger.owner_cash(organization_id)
	var spending: int = mini(cost, available)
	if spending <= 0:
		implementation["status"] = "failed"
		implementation["failure_reason"] = "没有可调用预算"
		policy_implementations[implementation_id] = implementation
		return _ok({"implementation": implementation.duplicate(true)})
	var transfer: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		organization_id,
		PUBLIC_SPENDING_ID,
		spending,
		"policy_budget",
		"fact:policy_funded:%s" % implementation_id,
		"政策执行预算"
	)
	if not bool(transfer.get("success", false)):
		return transfer
	implementation["spent_centimes"] = spending
	implementation["funding_ratio"] = spending * 100 / maxi(1, cost)
	implementation["status"] = "implementing"
	implementation["started_hour"] = total_hour
	policy_implementations[implementation_id] = implementation
	_processed_keys[idempotency_key] = implementation_id
	return _ok({"implementation": implementation.duplicate(true)})


func advance_policy(
	idempotency_key: String,
	implementation_id: String,
	total_hour: int,
	weeks: int = 1
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"implementation": (policy_implementations.get(implementation_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var implementation: Dictionary = policy_implementations.get(
		implementation_id, {}
	) as Dictionary
	if str(implementation.get("status", "")) != "implementing" or weeks <= 0:
		return _fail("policy_not_implementing", "政策不处于执行状态")
	var bottleneck: int = 100
	for factor: int in [
		int(implementation.get("actual_compliance", 0)),
		int(implementation.get("execution_capacity", 0)),
		int(implementation.get("funding_ratio", 0)),
		int(implementation.get("staffing", 0)),
		int(implementation.get("infrastructure", 0)),
		100 - int(implementation.get("external_resistance", 0)),
	]:
		bottleneck = mini(bottleneck, factor)
	var progress_delta: int = maxi(1, bottleneck * weeks / 4)
	implementation["progress"] = mini(
		100, int(implementation.get("progress", 0)) + progress_delta
	)
	implementation["last_advanced_hour"] = total_hour
	if int(implementation["progress"]) >= 100:
		_complete_policy(implementation, total_hour)
	policy_implementations[implementation_id] = implementation
	_processed_keys[idempotency_key] = implementation_id
	return _ok({"implementation": implementation.duplicate(true), "progress_delta": progress_delta})


func lobby(
	idempotency_key: String,
	lobbyist_id: String,
	target_character_id: String,
	organization_id: String,
	issue_id: String,
	payment_centimes: int,
	total_hour: int
) -> Dictionary:
	if not issues.has(issue_id) or payment_centimes < 0:
		return _fail("invalid_lobby", "游说议题或费用无效")
	if payment_centimes > 0:
		var payment: Dictionary = _economy.ledger.transfer(
			"ledger:%s" % idempotency_key,
			total_hour,
			lobbyist_id,
			target_character_id,
			payment_centimes,
			"lobbying_service",
			"fact:lobby:%s:%d" % [issue_id, total_hour],
			"议题游说费用"
		)
		if not bool(payment.get("success", false)):
			return payment
	var key: String = _support_key(
		organization_id, lobbyist_id, target_character_id
	)
	support_records[key] = clampi(int(support_records.get(key, 0)) + 8, -100, 100)
	_processed_keys[idempotency_key] = key
	return _ok({"issue_id": issue_id, "support": support_records[key]})


func political_exchange(
	idempotency_key: String,
	first_party_id: String,
	second_party_id: String,
	organization_id: String,
	offered_support: String,
	requested_support: String,
	total_hour: int
) -> Dictionary:
	var contract_result: Dictionary = _economy.contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:service",
		[
			{"party_id": first_party_id, "role": "proposer"},
			{"party_id": second_party_id, "role": "counterparty"},
		],
		{
			"kind": "political_exchange",
			"organization_id": organization_id,
			"offered_support": offered_support,
			"requested_support": requested_support,
		},
		0,
		total_hour,
		total_hour + 90 * 24,
		{"document_ids": ["document:political_exchange:%s" % idempotency_key]}
	)
	if not bool(contract_result.get("success", false)):
		return contract_result
	var contract: Dictionary = (contract_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	_economy.contracts.activate(
		"activate:%s" % idempotency_key, contract_id, total_hour
	)
	political_exchanges[contract_id] = {
		"contract_id": contract_id,
		"first_party_id": first_party_id,
		"second_party_id": second_party_id,
		"organization_id": organization_id,
		"offered_support": offered_support,
		"requested_support": requested_support,
		"status": "active",
	}
	_processed_keys[idempotency_key] = contract_id
	return _ok({"exchange": political_exchanges[contract_id], "contract": _economy.contracts.contracts[contract_id]})


func perform_corruption(
	idempotency_key: String,
	action_id: String,
	actor: CharacterData,
	public_organization_id: String,
	beneficiary_id: String,
	benefit_amount_centimes: int,
	total_hour: int,
	witness_ids: Array,
	subject: Dictionary = {}
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"corruption_case": (
				corruption_cases.get(existing_id, {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	var action: Dictionary = _corruption_action(action_id)
	if (
		action.is_empty()
		or actor == null
		or beneficiary_id.is_empty()
		or benefit_amount_centimes <= 0
		or witness_ids.is_empty()
		or not _has_extended_permission(
			actor.id,
			public_organization_id,
			str(action.get("required_permission", ""))
		)
	):
		return _fail("corruption_unavailable", "腐败行为缺少职位权限、受益者、资金或知情者")
	var case_id: String = "corruption_case:alpha:%d" % _next_corruption_sequence
	_next_corruption_sequence += 1
	var transaction_result: Dictionary
	var contract_id: String = ""
	var asset_id: String = str(subject.get("asset_id", ""))
	match action_id:
		"corruption:accept_benefit":
			transaction_result = _economy.ledger.transfer(
				"ledger:%s" % idempotency_key,
				total_hour,
				beneficiary_id,
				actor.id,
				benefit_amount_centimes,
				"corrupt_benefit",
				"fact:corruption:%s" % case_id,
				"职位持有者接受利益"
			)
		"corruption:steer_contract":
			var steered: Dictionary = _create_steered_contract(
				idempotency_key,
				public_organization_id,
				beneficiary_id,
				benefit_amount_centimes,
				total_hour
			)
			if not bool(steered.get("success", false)):
				return steered
			transaction_result = (
				steered.get("data", {}) as Dictionary
			).get("payment", {}) as Dictionary
			contract_id = str((steered.get("data", {}) as Dictionary).get(
				"contract_id", ""
			))
		"corruption:cheap_asset":
			if asset_id.is_empty():
				return _fail("corrupt_asset_missing", "低价取得资产必须引用具体资产")
			transaction_result = _economy.assets.sell(
				idempotency_key,
				total_hour,
				asset_id,
				public_organization_id,
				beneficiary_id,
				benefit_amount_centimes
			)
		_:
			transaction_result = _economy.ledger.transfer(
				"ledger:%s" % idempotency_key,
				total_hour,
				public_organization_id,
				beneficiary_id,
				benefit_amount_centimes,
				"corrupt_public_spending",
				"fact:corruption:%s" % case_id,
				str(action.get("name", "职位利益输送"))
			)
	if not bool(transaction_result.get("success", false)):
		return transaction_result
	var transaction_id: String = _extract_transaction_id(transaction_result)
	var document_id: String = "document:corruption:%s" % case_id
	var evidence_ids: Array[String] = [
		"evidence:fund_flow:%s" % case_id,
		"evidence:document:%s" % case_id,
	]
	for witness_id: String in DataRecordUtils.to_string_array(witness_ids):
		evidence_ids.append("evidence:witness:%s:%s" % [case_id, witness_id])
	var obligation_key: String = "%s|%s" % [beneficiary_id, actor.id]
	obligations[obligation_key] = int(obligations.get(obligation_key, 0)) + 20
	var corruption_case: Dictionary = {
		"case_id": case_id,
		"action_id": action_id,
		"actor_id": actor.id,
		"public_organization_id": public_organization_id,
		"beneficiary_id": beneficiary_id,
		"benefit_amount_centimes": benefit_amount_centimes,
		"transaction_id": transaction_id,
		"contract_id": contract_id,
		"asset_id": asset_id,
		"document_id": document_id,
		"witness_ids": DataRecordUtils.to_string_array(witness_ids),
		"evidence_ids": evidence_ids,
		"obligation_key": obligation_key,
		"subject": subject.duplicate(true),
		"created_hour": total_hour,
		"concealment": 0,
		"status": "undiscovered",
	}
	corruption_cases[case_id] = corruption_case
	_processed_keys[idempotency_key] = case_id
	return _ok({"corruption_case": corruption_case.duplicate(true), "duplicate": false})


func conceal_corruption(
	idempotency_key: String,
	case_id: String,
	actor_id: String,
	bribe_recipient_id: String,
	cost_centimes: int,
	total_hour: int
) -> Dictionary:
	var corruption_case: Dictionary = corruption_cases.get(case_id, {}) as Dictionary
	if (
		str(corruption_case.get("actor_id", "")) != actor_id
		or cost_centimes <= 0
	):
		return _fail("concealment_rejected", "掩盖者或费用无效")
	var payment: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		actor_id,
		bribe_recipient_id,
		cost_centimes,
		"evidence_concealment",
		"fact:concealment:%s" % case_id,
		"掩盖证据支出"
	)
	if not bool(payment.get("success", false)):
		return payment
	corruption_case["concealment"] = mini(
		80, int(corruption_case.get("concealment", 0)) + 25
	)
	corruption_case["concealment_transaction_id"] = _extract_transaction_id(payment)
	corruption_cases[case_id] = corruption_case
	_processed_keys[idempotency_key] = case_id
	return _ok({"corruption_case": corruption_case.duplicate(true)})


func investigate_corruption(
	idempotency_key: String,
	case_id: String,
	investigator: CharacterData,
	investigating_organization_id: String,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"investigation": (
				investigations.get(existing_id, {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	var corruption_case: Dictionary = corruption_cases.get(case_id, {}) as Dictionary
	if corruption_case.is_empty() or investigator == null:
		return _fail("investigation_target_missing", "调查目标或调查者不存在")
	var skill: int = int(investigator.skills.get("investigation", 0))
	var reasoning: int = int(investigator.hidden_aptitudes.get("reasoning", 50))
	var evidence_strength: int = (
		(corruption_case.get("evidence_ids", []) as Array).size() * 12
		+ (corruption_case.get("witness_ids", []) as Array).size() * 8
		+ skill / 2
		+ reasoning / 4
		- int(corruption_case.get("concealment", 0))
	)
	var status: String = (
		"substantiated"
		if evidence_strength >= 70
		else "partial" if evidence_strength >= 45
		else "insufficient"
	)
	var investigation_id: String = "investigation:alpha:%d" % _next_investigation_sequence
	_next_investigation_sequence += 1
	var investigation: Dictionary = {
		"investigation_id": investigation_id,
		"case_id": case_id,
		"investigator_id": investigator.id,
		"investigating_organization_id": investigating_organization_id,
		"started_hour": total_hour,
		"evidence_strength": evidence_strength,
		"discovered_evidence_ids": (
			(corruption_case.get("evidence_ids", []) as Array).duplicate()
			if status != "insufficient"
			else []
		),
		"status": status,
		"resolution": {},
	}
	investigations[investigation_id] = investigation
	if status in ["substantiated", "partial"]:
		corruption_case["status"] = "discovered"
		corruption_cases[case_id] = corruption_case
	_processed_keys[idempotency_key] = investigation_id
	return _ok({"investigation": investigation.duplicate(true), "duplicate": false})


func resolve_investigation(
	idempotency_key: String,
	investigation_id: String,
	actor: CharacterData,
	total_hour: int
) -> Dictionary:
	var investigation: Dictionary = investigations.get(
		investigation_id, {}
	) as Dictionary
	if str(investigation.get("status", "")) != "substantiated":
		return _fail("evidence_insufficient", "证据不足以产生正式处分")
	var corruption_case: Dictionary = corruption_cases[
		str(investigation.get("case_id", ""))
	] as Dictionary
	if actor == null or actor.id != str(corruption_case.get("actor_id", "")):
		return _fail("actor_mismatch", "处分对象与腐败行为人不一致")
	var organization_id: String = str(
		corruption_case.get("public_organization_id", "")
	)
	var position_loss: Dictionary = lose_position(
		"position_loss:%s" % idempotency_key,
		actor,
		organization_id,
		"illegal_conduct",
		total_hour
	)
	var fine: int = mini(
		_economy.ledger.owner_cash(actor.id),
		maxi(1, int(corruption_case.get("benefit_amount_centimes", 0)) / 2)
	)
	var fine_transaction_id: String = ""
	if fine > 0:
		var fine_result: Dictionary = _economy.ledger.transfer(
			"fine:%s" % idempotency_key,
			total_hour,
			actor.id,
			PUBLIC_SPENDING_ID,
			fine,
			"corruption_penalty",
			"fact:corruption_penalty:%s" % investigation_id,
			"腐败调查罚没"
		)
		if bool(fine_result.get("success", false)):
			fine_transaction_id = _extract_transaction_id(fine_result)
	var obligation_key: String = str(corruption_case.get("obligation_key", ""))
	obligations[obligation_key] = mini(0, int(obligations.get(obligation_key, 0)) - 30)
	var public_event: Dictionary = {
		"event_id": "public_event:scandal:%s" % investigation_id,
		"kind": "public_scandal",
		"actor_id": actor.id,
		"organization_id": organization_id,
		"beneficiary_id": corruption_case.get("beneficiary_id", ""),
		"actual_result": "证据成立，职位和资产受到处分",
		"long_term_effect": "组织支持下降并形成公开调查记录",
		"total_hour": total_hour,
	}
	public_events.append(public_event)
	investigation["status"] = "resolved"
	investigation["resolution"] = {
		"position_lost": bool(position_loss.get("success", false)),
		"fine_centimes": fine,
		"fine_transaction_id": fine_transaction_id,
		"public_event_id": public_event["event_id"],
	}
	investigations[investigation_id] = investigation
	corruption_case["status"] = "resolved"
	corruption_cases[str(investigation.get("case_id", ""))] = corruption_case
	_processed_keys[idempotency_key] = investigation_id
	return _ok({
		"investigation": investigation.duplicate(true),
		"position_loss": position_loss,
		"public_event": public_event,
	})


func validate_integrity() -> Dictionary:
	for raw_state: Variant in organization_states.values():
		var state: Dictionary = raw_state as Dictionary
		var organization_id: String = str(state.get("organization_id", ""))
		if (
			_organizations.get_organization(organization_id) == null
			or _economy.ledger.cash_account_id(organization_id).is_empty()
		):
			return _fail("politics_organization_missing", "政治组织扩展引用不闭合")
	for raw_implementation: Variant in policy_implementations.values():
		var implementation: Dictionary = raw_implementation as Dictionary
		if (
			not policies.has(str(implementation.get("policy_id", "")))
			or not organization_states.has(
				str(implementation.get("organization_id", ""))
			)
		):
			return _fail("policy_reference_missing", "政策引用不闭合")
	for raw_case: Variant in corruption_cases.values():
		var corruption_case: Dictionary = raw_case as Dictionary
		if (
			str(corruption_case.get("transaction_id", "")).is_empty()
			and str(corruption_case.get("asset_id", "")).is_empty()
		):
			return _fail("corruption_fund_flow_missing", "腐败行为没有资金或资产流")
		if (
			str(corruption_case.get("document_id", "")).is_empty()
			or (corruption_case.get("witness_ids", []) as Array).is_empty()
			or (corruption_case.get("evidence_ids", []) as Array).is_empty()
		):
			return _fail("corruption_evidence_missing", "腐败证据链不完整")
	return _ok({
		"organizations": organization_states.size(),
		"issues": issues.size(),
		"policies": policies.size(),
		"policy_implementations": policy_implementations.size(),
		"corruption_cases": corruption_cases.size(),
		"investigations": investigations.size(),
	})


func get_persistent_state() -> Dictionary:
	return {
		"organization_states": organization_states.duplicate(true),
		"position_packages": position_packages.duplicate(true),
		"appointments": appointments.duplicate(true),
		"factions": factions.duplicate(true),
		"policy_implementations": policy_implementations.duplicate(true),
		"support_records": support_records.duplicate(true),
		"political_exchanges": political_exchanges.duplicate(true),
		"corruption_cases": corruption_cases.duplicate(true),
		"investigations": investigations.duplicate(true),
		"public_events": public_events.duplicate(true),
		"obligations": obligations.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_faction_sequence": _next_faction_sequence,
		"next_policy_sequence": _next_policy_sequence,
		"next_corruption_sequence": _next_corruption_sequence,
		"next_investigation_sequence": _next_investigation_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	for field: String in [
		"organization_states",
		"position_packages",
		"appointments",
		"factions",
		"policy_implementations",
		"support_records",
		"political_exchanges",
		"corruption_cases",
		"investigations",
		"obligations",
		"processed_keys",
	]:
		if not state.get(field, {}) is Dictionary:
			return false
	organization_states = (state["organization_states"] as Dictionary).duplicate(true)
	position_packages = (state["position_packages"] as Dictionary).duplicate(true)
	appointments = (state["appointments"] as Dictionary).duplicate(true)
	factions = (state["factions"] as Dictionary).duplicate(true)
	policy_implementations = (state["policy_implementations"] as Dictionary).duplicate(true)
	support_records = (state["support_records"] as Dictionary).duplicate(true)
	political_exchanges = (state["political_exchanges"] as Dictionary).duplicate(true)
	corruption_cases = (state["corruption_cases"] as Dictionary).duplicate(true)
	investigations = (state["investigations"] as Dictionary).duplicate(true)
	public_events = DataRecordUtils.to_dictionary_array(
		state.get("public_events", [])
	)
	obligations = (state["obligations"] as Dictionary).duplicate(true)
	_processed_keys = (state["processed_keys"] as Dictionary).duplicate(true)
	_next_faction_sequence = int(state.get("next_faction_sequence", 0))
	_next_policy_sequence = int(state.get("next_policy_sequence", 0))
	_next_corruption_sequence = int(state.get("next_corruption_sequence", 0))
	_next_investigation_sequence = int(state.get("next_investigation_sequence", 0))
	return (
		_next_faction_sequence >= 1
		and _next_policy_sequence >= 1
		and _next_corruption_sequence >= 1
		and _next_investigation_sequence >= 1
		and bool(validate_integrity().get("success", false))
	)


func _register_organization_addition(record: Dictionary) -> bool:
	var organization_id: String = str(record.get("organization_id", ""))
	if _organizations.get_organization(organization_id) != null:
		return true
	var entry_position: String = str(record.get("entry_position", "member"))
	var leader_position: String = str(record.get("leader_position", "leader"))
	var positions: Dictionary = {}
	positions[entry_position] = {
		"name": "普通成员",
		"level": 1,
		"slots": 128,
		"permissions": ["organization_member"],
		"holder_ids": [],
	}
	positions["executive"] = {
		"name": "执行委员",
		"level": 2,
		"slots": 12,
		"permissions": [
			"organization_member",
			"campaign_support",
			"contract_sign",
			"budget_spend",
			"policy_labor",
			"policy_enterprise",
			"policy_credit",
			"policy_budget",
			"investigation_control",
			"asset_disposal",
			"command_staff",
		],
		"holder_ids": [],
	}
	positions[leader_position] = {
		"name": "组织负责人",
		"level": 3,
		"slots": 1,
		"permissions": POSITION_PERMISSION_SET.duplicate(),
		"holder_ids": [],
	}
	var organization := OrganizationData.from_dict({
		"id": organization_id,
		"name": record.get("name", organization_id),
		"type": record.get("type", "public"),
		"country_id": record.get("country_id", ""),
		"region_id": record.get("region_id", ""),
		"size": 8.0,
		"resources": 50000.0,
		"influence": 0.45,
		"public_stance": "declared",
		"leader_character_id": "",
		"member_ids": [],
		"position_structure": {
			"entry_position": entry_position,
			"leader_position": leader_position,
			"positions": positions,
		},
		"organization_relations": {},
	})
	return _organizations.register_runtime_organization(organization)


func _initialize_organization_state(organization_id: String) -> void:
	var organization: OrganizationData = _organizations.get_organization(organization_id)
	if organization == null:
		return
	if not _economy.entity_profiles.has(organization_id):
		_economy.register_entity(
			organization_id,
			"organization",
			100000 if organization.type == "government" else 30000,
			{
				"income_monthly_centimes": 12000,
				"reputation": 55,
				"region_id": organization.region_id,
			}
		)
	var budget_fields: Array[String] = _budget_fields(organization.country_id)
	organization_states[organization_id] = {
		"organization_id": organization_id,
		"asset_ids": _owned_asset_ids(organization_id),
		"ledger_account_id": _economy.ledger.cash_account_id(organization_id),
		"contract_ids": [],
		"policy_ids": [],
		"current_matter_ids": [],
		"external_relations": organization.organization_relations.duplicate(true),
		"jurisdiction": {
			"country_id": organization.country_id,
			"region_id": organization.region_id,
		},
		"charter": {
			"entry_position": organization.position_structure.get("entry_position", ""),
			"leader_position": organization.position_structure.get("leader_position", ""),
		},
		"operating_policies": {},
		"budget_fields": budget_fields,
		"public_stance": organization.public_stance,
		"faction_ids": [],
	}
	var positions: Dictionary = organization.position_structure.get(
		"positions", {}
	) as Dictionary
	var leader_position: String = str(
		organization.position_structure.get("leader_position", "")
	)
	var entry_position: String = str(
		organization.position_structure.get("entry_position", "")
	)
	for raw_position_id: Variant in positions:
		var position_id: String = str(raw_position_id)
		var position: Dictionary = positions[position_id] as Dictionary
		var level: int = int(position.get("level", 1))
		var base_permissions: Array[String] = DataRecordUtils.to_string_array(
			position.get("permissions", [])
		)
		var extended: Array[String] = base_permissions.duplicate()
		if position_id == leader_position:
			for permission: String in POSITION_PERMISSION_SET:
				if permission not in extended:
					extended.append(permission)
		elif position_id != entry_position and organization.type == "government":
			for permission: String in [
				"contract_sign",
				"budget_spend",
				"policy_labor",
				"policy_enterprise",
				"policy_credit",
				"policy_budget",
				"investigation_control",
				"command_staff",
			]:
				if permission not in extended:
					extended.append(permission)
		position["permissions"] = extended
		positions[position_id] = position
		position_packages[_position_key(organization_id, position_id)] = {
			"organization_id": organization_id,
			"position_id": position_id,
			"level": level,
			"jurisdiction": {
				"country_id": organization.country_id,
				"region_id": organization.region_id,
			},
			"information_access": ["public", "organization_internal"] if level >= 2 else ["public"],
			"budget_limit_centimes": 100000 if level >= 3 else 20000 if level >= 2 else 0,
			"command_levels": maxi(0, level - 1),
			"appointment_right": level >= 3,
			"removal_right": level >= 3,
			"contract_signing": "contract_sign" in extended,
			"policy_permissions": _filter_policy_permissions(extended),
			"responsibilities": ["charter", "budget", "law"] if level >= 2 else ["membership"],
			"term_hours": 365 * 24 if organization.type in ["government", "political"] else 0,
			"gain_conditions": ["appointment_or_vote"],
			"loss_conditions": VALID_POSITION_LOSS_CAUSES.duplicate(),
			"permissions": extended,
		}
	organization.position_structure["positions"] = positions


func _record_appointment(
	character_id: String,
	organization_id: String,
	position_id: String,
	total_hour: int
) -> void:
	if position_id.is_empty():
		return
	var package: Dictionary = position_packages.get(
		_position_key(organization_id, position_id), {}
	) as Dictionary
	var term_hours: int = int(package.get("term_hours", 0))
	var key: String = "%s|%s|%s|%d" % [
		character_id, organization_id, position_id, total_hour,
	]
	appointments[key] = {
		"appointment_id": key,
		"character_id": character_id,
		"organization_id": organization_id,
		"position_id": position_id,
		"start_hour": total_hour,
		"end_hour": total_hour + term_hours if term_hours > 0 else -1,
		"status": "active",
		"loss_cause": "",
	}


func _close_appointment(
	character_id: String,
	organization_id: String,
	position_id: String,
	total_hour: int,
	cause: String
) -> void:
	if position_id.is_empty():
		return
	var keys: Array[String] = []
	for raw_key: Variant in appointments:
		keys.append(str(raw_key))
	keys.sort()
	keys.reverse()
	for key: String in keys:
		var appointment: Dictionary = appointments[key] as Dictionary
		if (
			str(appointment.get("character_id", "")) == character_id
			and str(appointment.get("organization_id", "")) == organization_id
			and str(appointment.get("position_id", "")) == position_id
			and str(appointment.get("status", "")) == "active"
		):
			appointment["status"] = "ended"
			appointment["ended_hour"] = total_hour
			appointment["loss_cause"] = cause
			appointments[key] = appointment
			return


func _complete_policy(implementation: Dictionary, total_hour: int) -> void:
	var policy: Dictionary = policies[str(implementation.get("policy_id", ""))] as Dictionary
	var effects: Dictionary = policy.get("effects", {}) as Dictionary
	for region_id: String in DataRecordUtils.to_string_array(
		implementation.get("target_region_ids", [])
	):
		_world.apply_region_effects(region_id, effects)
		if _economy.markets.has(region_id):
			var market: Dictionary = _economy.markets[region_id] as Dictionary
			if effects.has("credit_rate_index"):
				market["credit_environment"] = clampi(
					int(market.get("credit_environment", 50))
					- int(effects["credit_rate_index"]),
					10,
					100
				)
			_economy.markets[region_id] = market
	var issue: Dictionary = issues[str(implementation.get("issue_id", ""))] as Dictionary
	var supporters: Array = issue.get("supporting_interests", []) as Array
	var opponents: Array = issue.get("opposing_interests", []) as Array
	implementation["status"] = "completed"
	implementation["completed_hour"] = total_hour
	implementation["applied_effects"] = effects.duplicate(true)
	implementation["support_reactions"] = supporters.duplicate()
	implementation["opposition_reactions"] = opponents.duplicate()
	public_events.append({
		"event_id": "public_event:policy:%s" % implementation.get("implementation_id", ""),
		"kind": "policy_implemented",
		"actor_id": implementation.get("actor_id", ""),
		"organization_id": implementation.get("organization_id", ""),
		"actual_result": "政策经过权限、服从、能力、资金、基础设施和阻力后生效",
		"long_term_effect": effects.duplicate(true),
		"total_hour": total_hour,
	})


func _create_steered_contract(
	idempotency_key: String,
	public_organization_id: String,
	beneficiary_id: String,
	amount_centimes: int,
	total_hour: int
) -> Dictionary:
	var result: Dictionary = _economy.contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:service",
		[
			{"party_id": public_organization_id, "role": "client"},
			{"party_id": beneficiary_id, "role": "provider"},
		],
		{"kind": "steered_public_contract"},
		amount_centimes,
		total_hour,
		total_hour + 60 * 24,
		{"document_ids": ["document:steered_contract:%s" % idempotency_key]}
	)
	if not bool(result.get("success", false)):
		return result
	var contract: Dictionary = (result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	_economy.contracts.activate(
		"activate:%s" % idempotency_key, contract_id, total_hour
	)
	var payment: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		public_organization_id,
		beneficiary_id,
		amount_centimes,
		"steered_public_contract",
		"fact:steered_contract:%s" % contract_id,
		"关联企业公共合同付款"
	)
	if not bool(payment.get("success", false)):
		return payment
	_economy.contracts.record_delivery(
		"delivery:%s" % idempotency_key,
		contract_id,
		total_hour,
		10000,
		"evidence:questionable_delivery:%s" % contract_id
	)
	var transaction: Dictionary = (payment.get("data", {}) as Dictionary).get(
		"transaction", {}
	) as Dictionary
	_economy.contracts.record_payment(
		"payment:%s" % idempotency_key,
		contract_id,
		total_hour,
		str(transaction.get("transaction_id", "")),
		amount_centimes
	)
	return _ok({"contract_id": contract_id, "payment": payment})


func _has_extended_permission(
	character_id: String, organization_id: String, permission: String
) -> bool:
	var position_id: String = _organizations.get_position_id(
		character_id, organization_id
	)
	var package: Dictionary = position_packages.get(
		_position_key(organization_id, position_id), {}
	) as Dictionary
	return permission in DataRecordUtils.to_string_array(package.get("permissions", []))


func _corruption_action(action_id: String) -> Dictionary:
	for raw_action: Variant in _config.politics().get("corruption_actions", []) as Array:
		var action: Dictionary = raw_action as Dictionary
		if str(action.get("action_id", "")) == action_id:
			return action
	return {}


func _budget_fields(country_id: String) -> Array[String]:
	for raw_record: Variant in _config.politics().get("budget_fields", []) as Array:
		var record: Dictionary = raw_record as Dictionary
		if str(record.get("country_id", "")) == country_id:
			return DataRecordUtils.to_string_array(record.get("fields", []))
	return []


func _owned_asset_ids(owner_id: String) -> Array[String]:
	var result: Array[String] = []
	for raw_asset: Variant in _economy.assets.assets.values():
		var asset: Dictionary = raw_asset as Dictionary
		var asset_id: String = str(asset.get("asset_id", ""))
		if _economy.assets.owner_share(asset_id, owner_id) > 0:
			result.append(asset_id)
	result.sort()
	return result


func _average_infrastructure(region_ids: Array) -> int:
	var total: int = 0
	var count: int = 0
	for region_id: String in DataRecordUtils.to_string_array(region_ids):
		var region: Dictionary = _world.regions.get(region_id, {}) as Dictionary
		if region.is_empty():
			continue
		total += 60 + int(region.get("wage_index", 100)) / 5
		count += 1
	return clampi(total / maxi(1, count), 20, 95)


func _count_type(organization_type: String) -> int:
	var count: int = 0
	for raw_organization: Variant in _organizations.organizations.values():
		if (raw_organization as OrganizationData).type == organization_type:
			count += 1
	return count


static func _filter_policy_permissions(permissions: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for permission: String in permissions:
		if permission.begins_with("policy_"):
			result.append(permission)
	return result


static func _extract_transaction_id(result: Dictionary) -> String:
	var data: Dictionary = result.get("data", {}) as Dictionary
	var transaction: Dictionary = data.get("transaction", {}) as Dictionary
	if not transaction.is_empty():
		return str(transaction.get("transaction_id", ""))
	var nested: Dictionary = data.get("payment", {}) as Dictionary
	if not nested.is_empty():
		return _extract_transaction_id(nested)
	var asset: Dictionary = data.get("asset", {}) as Dictionary
	return str(asset.get("asset_id", ""))


static func _position_key(organization_id: String, position_id: String) -> String:
	return "%s|%s" % [organization_id, position_id]


static func _support_key(
	organization_id: String, candidate_id: String, supporter_id: String
) -> String:
	return "%s|%s|%s" % [organization_id, candidate_id, supporter_id]


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
