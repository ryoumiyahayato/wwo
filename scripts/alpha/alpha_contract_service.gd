class_name AlphaContractService
extends RefCounted
## Unified lifecycle for employment, trade, service, lease, loan, partnership and orders.

const CONTRACT_TYPES: Array[String] = [
	"employment",
	"sale",
	"service",
	"lease",
	"loan",
	"partnership",
	"order",
]
const ACTIVE_STATUSES: Array[String] = [
	"offered",
	"active",
	"partially_fulfilled",
	"delayed",
	"overdue",
	"renegotiated",
	"disputed",
]
const TERMINAL_STATUSES: Array[String] = [
	"fulfilled",
	"settled",
	"defaulted",
	"terminated",
	"cancelled",
	"enforced",
]

var templates: Dictionary = {}
var contracts: Dictionary = {}
var _ledger: AlphaLedgerService
var _assets: AlphaAssetService
var _processed_keys: Dictionary = {}
var _next_sequence: int = 1


func configure(
	contract_templates: Array,
	ledger: AlphaLedgerService,
	assets: AlphaAssetService
) -> bool:
	templates.clear()
	contracts.clear()
	_processed_keys.clear()
	_next_sequence = 1
	_ledger = ledger
	_assets = assets
	for template: Dictionary in contract_templates:
		var template_id: String = str(template.get("template_id", ""))
		var contract_type: String = str(template.get("contract_type", ""))
		if template_id.is_empty() or contract_type not in CONTRACT_TYPES:
			return false
		templates[template_id] = template.duplicate(true)
	var found_types: Dictionary = {}
	for raw_template: Variant in templates.values():
		found_types[str((raw_template as Dictionary).get("contract_type", ""))] = true
	return found_types.size() == CONTRACT_TYPES.size()


func create_contract(
	idempotency_key: String,
	template_id: String,
	parties: Array,
	subject: Dictionary,
	amount_centimes: int,
	start_hour: int,
	end_hour: int,
	terms: Dictionary = {}
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"contract": (contracts.get(existing_id, {}) as Dictionary).duplicate(true),
			"duplicate": true,
		})
	var template: Dictionary = templates.get(template_id, {}) as Dictionary
	if (
		idempotency_key.is_empty()
		or template.is_empty()
		or parties.size() < 2
		or amount_centimes < 0
		or end_hour <= start_hour
	):
		return _fail("invalid_contract", "合同模板、参与方、金额或期限无效")
	var normalized_parties: Array[Dictionary] = []
	var party_ids: Dictionary = {}
	for raw_party: Variant in parties:
		if not raw_party is Dictionary:
			return _fail("invalid_party", "合同参与方格式无效")
		var party: Dictionary = raw_party as Dictionary
		var party_id: String = str(party.get("party_id", ""))
		var role: String = str(party.get("role", ""))
		if party_id.is_empty() or role.is_empty() or party_ids.has(party_id):
			return _fail("invalid_party", "合同参与方缺失、重复或没有角色")
		party_ids[party_id] = true
		normalized_parties.append({"party_id": party_id, "role": role})
	var collateral_ids: Array[String] = DataRecordUtils.to_string_array(
		terms.get("collateral_asset_ids", [])
	)
	for collateral_id: String in collateral_ids:
		if _assets == null or not _assets.assets.has(collateral_id):
			return _fail("collateral_missing", "合同抵押物不存在")
	var contract_id: String = "contract:alpha:%d" % _next_sequence
	_next_sequence += 1
	var contract: Dictionary = {
		"contract_id": contract_id,
		"template_id": template_id,
		"contract_type": str(template.get("contract_type", "")),
		"parties": normalized_parties,
		"subject": subject.duplicate(true),
		"amount_centimes": amount_centimes,
		"paid_centimes": 0,
		"principal_outstanding_centimes": (
			amount_centimes
			if str(template.get("contract_type", "")) == "loan"
			else 0
		),
		"interest_outstanding_centimes": 0,
		"start_hour": start_hour,
		"end_hour": end_hour,
		"obligations": (template.get("obligations", []) as Array).duplicate(true),
		"payment_conditions": (
			terms.get("payment_conditions", {"due": "on_delivery"}) as Dictionary
		).duplicate(true),
		"delivery_conditions": (
			terms.get("delivery_conditions", {}) as Dictionary
		).duplicate(true),
		"breach_conditions": (
			terms.get("breach_conditions", template.get("breach_rules", []))
			as Array
		).duplicate(true),
		"collateral_asset_ids": collateral_ids,
		"guarantor_ids": DataRecordUtils.to_string_array(terms.get("guarantor_ids", [])),
		"status": "offered",
		"fulfillment_bp": 0,
		"evidence_ids": DataRecordUtils.to_string_array(terms.get("evidence_ids", [])),
		"document_ids": DataRecordUtils.to_string_array(terms.get("document_ids", [])),
		"settlement_transaction_ids": [],
		"breach_reason": "",
		"dispute": {},
		"terms": terms.duplicate(true),
		"history": [{
			"event": "created",
			"total_hour": start_hour,
			"idempotency_key": idempotency_key,
		}],
	}
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true), "duplicate": false})


func activate(idempotency_key: String, contract_id: String, total_hour: int) -> Dictionary:
	return _transition(
		idempotency_key, contract_id, ["offered"], "active", "activated", total_hour
	)


func record_delivery(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	fulfillment_delta_bp: int,
	evidence_id: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _duplicate_contract(idempotency_key)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if (
		contract.is_empty()
		or str(contract.get("status", "")) not in ACTIVE_STATUSES
		or fulfillment_delta_bp <= 0
		or evidence_id.is_empty()
	):
		return _fail("invalid_delivery", "交付状态、比例或证据无效")
	contract["fulfillment_bp"] = mini(
		10000, int(contract.get("fulfillment_bp", 0)) + fulfillment_delta_bp
	)
	var evidence_ids: Array = contract.get("evidence_ids", []) as Array
	if evidence_id not in evidence_ids:
		evidence_ids.append(evidence_id)
	contract["evidence_ids"] = evidence_ids
	contract["status"] = (
		"fulfilled"
		if int(contract["fulfillment_bp"]) == 10000
		and int(contract.get("paid_centimes", 0)) >= int(contract.get("amount_centimes", 0))
		else "partially_fulfilled"
	)
	_append_history(contract, "delivery_recorded", total_hour, idempotency_key, {
		"fulfillment_delta_bp": fulfillment_delta_bp,
		"evidence_id": evidence_id,
	})
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true)})


func record_payment(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	transaction_id: String,
	principal_centimes: int,
	interest_centimes: int = 0
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _duplicate_contract(idempotency_key)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if (
		contract.is_empty()
		or str(contract.get("status", "")) not in ACTIVE_STATUSES
		or transaction_id.is_empty()
		or principal_centimes < 0
		or interest_centimes < 0
		or principal_centimes + interest_centimes <= 0
		or not _ledger_has_transaction(transaction_id)
	):
		return _fail("invalid_payment", "合同付款必须引用有效账本交易")
	var settlement_ids: Array = contract.get("settlement_transaction_ids", []) as Array
	if transaction_id in settlement_ids:
		return _fail("duplicate_payment", "该账本交易已用于合同付款")
	if str(contract.get("contract_type", "")) == "loan":
		var principal_outstanding: int = int(
			contract.get("principal_outstanding_centimes", 0)
		)
		var interest_outstanding: int = int(
			contract.get("interest_outstanding_centimes", 0)
		)
		if principal_centimes > principal_outstanding or interest_centimes > interest_outstanding:
			return _fail("overpayment", "还款超过合同应付余额")
		contract["principal_outstanding_centimes"] = (
			principal_outstanding - principal_centimes
		)
		contract["interest_outstanding_centimes"] = (
			interest_outstanding - interest_centimes
		)
	contract["paid_centimes"] = (
		int(contract.get("paid_centimes", 0)) + principal_centimes + interest_centimes
	)
	settlement_ids.append(transaction_id)
	contract["settlement_transaction_ids"] = settlement_ids
	if str(contract.get("contract_type", "")) == "loan":
		if (
			int(contract["principal_outstanding_centimes"]) == 0
			and int(contract["interest_outstanding_centimes"]) == 0
		):
			contract["status"] = "fulfilled"
	else:
		if (
			int(contract.get("paid_centimes", 0)) >= int(contract.get("amount_centimes", 0))
			and int(contract.get("fulfillment_bp", 0)) == 10000
		):
			contract["status"] = "fulfilled"
	_append_history(contract, "payment_recorded", total_hour, idempotency_key, {
		"transaction_id": transaction_id,
		"principal_centimes": principal_centimes,
		"interest_centimes": interest_centimes,
	})
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true)})


func accrue_interest(
	idempotency_key: String, contract_id: String, total_hour: int, amount_centimes: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _duplicate_contract(idempotency_key)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if (
		str(contract.get("contract_type", "")) != "loan"
		or str(contract.get("status", "")) not in ACTIVE_STATUSES
		or amount_centimes < 0
	):
		return _fail("invalid_interest", "计息只适用于有效借款合同")
	contract["interest_outstanding_centimes"] = (
		int(contract.get("interest_outstanding_centimes", 0)) + amount_centimes
	)
	_append_history(contract, "interest_accrued", total_hour, idempotency_key, {
		"amount_centimes": amount_centimes,
	})
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true)})


func delay(
	idempotency_key: String, contract_id: String, total_hour: int, reason: String
) -> Dictionary:
	return _transition(
		idempotency_key, contract_id, ACTIVE_STATUSES, "delayed", "delayed",
		total_hour, {"reason": reason}
	)


func mark_overdue(
	idempotency_key: String, contract_id: String, total_hour: int
) -> Dictionary:
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if total_hour <= int(contract.get("end_hour", total_hour)):
		return _fail("not_due", "合同尚未到期")
	return _transition(
		idempotency_key, contract_id, ACTIVE_STATUSES, "overdue", "overdue",
		total_hour
	)


func renegotiate(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	new_end_hour: int,
	term_changes: Dictionary
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _duplicate_contract(idempotency_key)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if (
		contract.is_empty()
		or str(contract.get("status", "")) not in ACTIVE_STATUSES
		or new_end_hour <= total_hour
	):
		return _fail("invalid_renegotiation", "重新谈判的状态或期限无效")
	contract["end_hour"] = new_end_hour
	var terms: Dictionary = contract.get("terms", {}) as Dictionary
	for raw_key: Variant in term_changes:
		terms[str(raw_key)] = term_changes[raw_key]
	contract["terms"] = terms
	contract["status"] = "renegotiated"
	_append_history(contract, "renegotiated", total_hour, idempotency_key, term_changes)
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true)})


func report_fraud(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	perpetrator_id: String,
	evidence_id: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _duplicate_contract(idempotency_key)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if contract.is_empty() or perpetrator_id.is_empty() or evidence_id.is_empty():
		return _fail("invalid_fraud_report", "欺诈报告必须指明行为人和证据")
	var evidence_ids: Array = contract.get("evidence_ids", []) as Array
	if evidence_id not in evidence_ids:
		evidence_ids.append(evidence_id)
	contract["evidence_ids"] = evidence_ids
	contract["status"] = "disputed"
	contract["dispute"] = {
		"type": "fraud",
		"perpetrator_id": perpetrator_id,
		"evidence_id": evidence_id,
		"reported_hour": total_hour,
	}
	_append_history(contract, "fraud_reported", total_hour, idempotency_key, {
		"perpetrator_id": perpetrator_id,
		"evidence_id": evidence_id,
	})
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true)})


func default_contract(
	idempotency_key: String, contract_id: String, total_hour: int, reason: String
) -> Dictionary:
	var result: Dictionary = _transition(
		idempotency_key, contract_id, ACTIVE_STATUSES, "defaulted", "defaulted",
		total_hour, {"reason": reason}
	)
	if bool(result.get("success", false)):
		var contract: Dictionary = contracts[contract_id] as Dictionary
		contract["breach_reason"] = reason
		contracts[contract_id] = contract
		result["data"] = {"contract": contract.duplicate(true)}
	return result


func enforce(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	enforcer_id: String,
	resolution: String
) -> Dictionary:
	return _transition(
		idempotency_key, contract_id, ["defaulted", "disputed", "overdue"],
		"enforced", "enforced", total_hour,
		{"enforcer_id": enforcer_id, "resolution": resolution}
	)


func settle_privately(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	resolution: String
) -> Dictionary:
	return _transition(
		idempotency_key, contract_id, ["defaulted", "disputed", "overdue"],
		"settled", "settled_privately", total_hour, {"resolution": resolution}
	)


func terminate(
	idempotency_key: String, contract_id: String, total_hour: int, reason: String
) -> Dictionary:
	return _transition(
		idempotency_key, contract_id, ACTIVE_STATUSES, "terminated", "terminated",
		total_hour, {"reason": reason}
	)


func outstanding(contract_id: String) -> int:
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if str(contract.get("contract_type", "")) == "loan":
		return (
			int(contract.get("principal_outstanding_centimes", 0))
			+ int(contract.get("interest_outstanding_centimes", 0))
		)
	return maxi(
		0,
		int(contract.get("amount_centimes", 0))
		- int(contract.get("paid_centimes", 0))
	)


func contracts_for_party(party_id: String, include_terminal: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_contract: Variant in contracts.values():
		var contract: Dictionary = raw_contract as Dictionary
		if not include_terminal and str(contract.get("status", "")) in TERMINAL_STATUSES:
			continue
		for party: Dictionary in contract.get("parties", []) as Array[Dictionary]:
			if str(party.get("party_id", "")) == party_id:
				result.append(contract.duplicate(true))
				break
	return result


func validate_references() -> Dictionary:
	for raw_contract: Variant in contracts.values():
		var contract: Dictionary = raw_contract as Dictionary
		if (
			str(contract.get("contract_type", "")) not in CONTRACT_TYPES
			or not templates.has(str(contract.get("template_id", "")))
			or (contract.get("parties", []) as Array).size() < 2
			or int(contract.get("paid_centimes", 0)) < 0
			or int(contract.get("principal_outstanding_centimes", 0)) < 0
			or int(contract.get("interest_outstanding_centimes", 0)) < 0
		):
			return _fail("contract_integrity_error", "合同结构或余额无效")
		for collateral_id: String in DataRecordUtils.to_string_array(
			contract.get("collateral_asset_ids", [])
		):
			if _assets == null or not _assets.assets.has(collateral_id):
				return _fail("contract_asset_missing", "合同抵押引用不闭合")
		for transaction_id: String in DataRecordUtils.to_string_array(
			contract.get("settlement_transaction_ids", [])
		):
			if not _ledger_has_transaction(transaction_id):
				return _fail("contract_ledger_missing", "合同结算引用不闭合")
	return _ok({"contract_count": contracts.size()})


func get_persistent_state() -> Dictionary:
	return {
		"contracts": contracts.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_sequence": _next_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("contracts", {}) is Dictionary
		or not state.get("processed_keys", {}) is Dictionary
	):
		return false
	contracts = (state["contracts"] as Dictionary).duplicate(true)
	_processed_keys = (state["processed_keys"] as Dictionary).duplicate(true)
	_next_sequence = int(state.get("next_sequence", 0))
	return _next_sequence >= 1 and bool(validate_references().get("success", false))


func _transition(
	idempotency_key: String,
	contract_id: String,
	allowed_statuses: Array,
	new_status: String,
	event_name: String,
	total_hour: int,
	details: Dictionary = {}
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _duplicate_contract(idempotency_key)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if (
		contract.is_empty()
		or str(contract.get("status", "")) not in allowed_statuses
		or idempotency_key.is_empty()
	):
		return _fail("invalid_contract_transition", "合同状态迁移无效")
	contract["status"] = new_status
	_append_history(contract, event_name, total_hour, idempotency_key, details)
	contracts[contract_id] = contract
	_processed_keys[idempotency_key] = contract_id
	return _ok({"contract": contract.duplicate(true), "duplicate": false})


func _duplicate_contract(idempotency_key: String) -> Dictionary:
	var contract_id: String = str(_processed_keys[idempotency_key])
	return _ok({
		"contract": (contracts.get(contract_id, {}) as Dictionary).duplicate(true),
		"duplicate": true,
	})


func _ledger_has_transaction(transaction_id: String) -> bool:
	if _ledger == null:
		return false
	for transaction: Dictionary in _ledger.transactions:
		if str(transaction.get("transaction_id", "")) == transaction_id:
			return true
	return false


static func _append_history(
	contract: Dictionary,
	event_name: String,
	total_hour: int,
	idempotency_key: String,
	details: Dictionary
) -> void:
	var history: Array = contract.get("history", []) as Array
	history.append({
		"event": event_name,
		"total_hour": total_hour,
		"idempotency_key": idempotency_key,
		"details": details.duplicate(true),
	})
	while history.size() > 32:
		history.pop_front()
	contract["history"] = history


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
