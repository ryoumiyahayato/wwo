class_name V23FinanceService
extends RefCounted
## Personal credit on the formal V2.3 world. Household cash remains owned by V2LedgerService.

const HOURS_PER_DAY: int = 24
const DAYS_PER_YEAR: int = 365
const MAX_HISTORY: int = 256

var lenders: Dictionary = {}
var products: Dictionary = {}
var applications: Dictionary = {}
var contracts: Dictionary = {}
var event_history: Array[Dictionary] = []

var _households: V2HouseholdService
var _ledger: V2LedgerService
var _processed_keys: Dictionary = {}
var _processed_key_order: Array[String] = []
var _next_application_sequence: int = 1
var _next_contract_sequence: int = 1


func configure(
	config: V23FinanceConfig,
	households: V2HouseholdService,
	ledger: V2LedgerService
) -> V2LifeLoopResult:
	lenders.clear()
	products.clear()
	applications.clear()
	contracts.clear()
	event_history.clear()
	_processed_keys.clear()
	_processed_key_order.clear()
	_next_application_sequence = 1
	_next_contract_sequence = 1
	_households = households
	_ledger = ledger
	if config == null or households == null or ledger == null:
		return V2LifeLoopResult.fail("finance_dependency_missing", "正式金融服务依赖不可用")
	for raw_lender: Variant in config.lenders():
		var lender: Dictionary = (raw_lender as Dictionary).duplicate(true)
		lender["available_capital_centimes"] = int(
			lender.get("opening_capital_centimes", 0)
		)
		lenders[str(lender.get("lender_id", ""))] = lender
	for raw_product: Variant in config.products():
		var product: Dictionary = (raw_product as Dictionary).duplicate(true)
		products[str(product.get("product_id", ""))] = product
	if lenders.is_empty() or products.is_empty():
		return V2LifeLoopResult.fail("finance_config_empty", "正式金融配置没有可用放贷方或产品")
	return V2LifeLoopResult.ok("正式个人金融服务已连接现有住户账本")


func lender_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id: Variant in lenders.keys():
		ids.append(str(raw_id))
	ids.sort()
	for lender_id: String in ids:
		result.append((lenders[lender_id] as Dictionary).duplicate(true))
	return result


func product_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id: Variant in products.keys():
		ids.append(str(raw_id))
	ids.sort()
	for product_id: String in ids:
		result.append((products[product_id] as Dictionary).duplicate(true))
	return result


func applications_for_person(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_application: Variant in applications.values():
		var application: Dictionary = raw_application as Dictionary
		if str(application.get("borrower_person_id", "")) == person_id:
			result.append(application.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("application_hour", 0)) > int(b.get("application_hour", 0))
	)
	return result


func contracts_for_person(person_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_contract: Variant in contracts.values():
		var contract: Dictionary = raw_contract as Dictionary
		if str(contract.get("borrower_person_id", "")) == person_id:
			result.append(contract.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("start_hour", 0)) > int(b.get("start_hour", 0))
	)
	return result


func total_debt_for_person(person_id: String) -> int:
	var total: int = 0
	for contract: Dictionary in contracts_for_person(person_id):
		if str(contract.get("status", "")) in ["active", "overdue", "defaulted"]:
			total += int(contract.get("principal_outstanding_centimes", 0))
			total += int(contract.get("interest_outstanding_centimes", 0))
	return total


func is_lender_open(lender_id: String, total_hour: int) -> bool:
	var lender: Dictionary = lenders.get(lender_id, {}) as Dictionary
	if lender.is_empty():
		return false
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	if value.is_empty():
		return false
	var weekday: int = int(value.get("weekday", -1))
	var hour: int = int(value.get("hour", -1))
	var opening: Dictionary = lender.get("opening_hours", {}) as Dictionary
	var interval: Array = []
	if weekday >= 0 and weekday <= 4:
		interval = opening.get("weekday", []) as Array
	elif weekday == 5:
		interval = opening.get("saturday", []) as Array
	else:
		interval = opening.get("sunday", []) as Array
	return interval.size() == 2 and hour >= int(interval[0]) and hour < int(interval[1])


func submit_application(
	idempotency_key: String,
	person_id: String,
	product_id: String,
	amount_centimes: int,
	total_hour: int,
	current_location_id: String,
	monthly_income_centimes: int,
	employment_active: bool
) -> V2LifeLoopResult:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return V2LifeLoopResult.ok(
			"该借款申请已经提交",
			{"application": (applications.get(existing_id, {}) as Dictionary).duplicate(true), "duplicate": true}
		)
	var product: Dictionary = products.get(product_id, {}) as Dictionary
	if idempotency_key.is_empty() or person_id.is_empty() or product.is_empty():
		return V2LifeLoopResult.fail("invalid_loan_application", "借款申请对象或产品无效")
	var lender_id: String = str(product.get("lender_id", ""))
	var lender: Dictionary = lenders.get(lender_id, {}) as Dictionary
	if lender.is_empty():
		return V2LifeLoopResult.fail("lender_missing", "借款产品的放贷方不存在")
	if current_location_id != str(lender.get("location_id", "")):
		return V2LifeLoopResult.fail(
			"not_at_lender", "申请人当前不在该放贷方的办理地点",
			str(lender.get("location_id", "")), [person_id, lender_id]
		)
	if not is_lender_open(lender_id, total_hour):
		return V2LifeLoopResult.fail("lender_closed", "该放贷方当前没有营业", lender_id)
	var allowed_amounts: Array = product.get("amount_options_centimes", []) as Array
	if amount_centimes not in allowed_amounts:
		return V2LifeLoopResult.fail("unsupported_loan_amount", "该产品不受理这一借款金额")
	for application: Dictionary in applications_for_person(person_id):
		if (
			str(application.get("product_id", "")) == product_id
			and str(application.get("status", "")) in ["submitted", "offered"]
		):
			return V2LifeLoopResult.fail("application_already_open", "同一产品已有待处理申请")
	var household_id: String = _households.household_id_for_person(person_id)
	var household: Dictionary = _households.households.get(household_id, {}) as Dictionary
	if household.is_empty():
		return V2LifeLoopResult.fail("household_missing", "申请人没有正式住户账本", person_id)
	var application_id: String = "loan_application:v2_3:%d" % _next_application_sequence
	_next_application_sequence += 1
	var application: Dictionary = {
		"application_id": application_id,
		"borrower_person_id": person_id,
		"borrower_household_id": household_id,
		"lender_id": lender_id,
		"product_id": product_id,
		"amount_centimes": amount_centimes,
		"application_hour": total_hour,
		"review_due_hour": total_hour + int(product.get("review_delay_hours", 1)),
		"monthly_income_centimes": maxi(0, monthly_income_centimes),
		"employment_active": employment_active,
		"cash_at_application_centimes": int(household.get("cash_centimes", 0)),
		"debt_at_application_centimes": total_debt_for_person(person_id),
		"status": "submitted",
		"decision_reasons": [],
		"offered_terms": {},
		"offer_expires_hour": -1,
		"contract_id": "",
	}
	applications[application_id] = application
	_remember_key(idempotency_key, application_id)
	_append_event(total_hour, "application_submitted", "借款申请已经提交", [person_id, lender_id, application_id])
	return V2LifeLoopResult.ok(
		"借款申请已经提交，将在审查完成后形成结果",
		{"application": application.duplicate(true)}, [person_id, lender_id, application_id]
	)


func accept_offer(
	idempotency_key: String,
	application_id: String,
	total_hour: int
) -> V2LifeLoopResult:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return V2LifeLoopResult.ok(
			"该借款条件已经处理",
			{"contract": (contracts.get(existing_id, {}) as Dictionary).duplicate(true), "duplicate": true}
		)
	var application: Dictionary = applications.get(application_id, {}) as Dictionary
	if application.is_empty() or str(application.get("status", "")) != "offered":
		return V2LifeLoopResult.fail("loan_offer_unavailable", "借款条件尚未形成或已经失效")
	if total_hour > int(application.get("offer_expires_hour", -1)):
		application["status"] = "expired"
		applications[application_id] = application
		return V2LifeLoopResult.fail("loan_offer_expired", "借款条件已经过期")
	var lender_id: String = str(application.get("lender_id", ""))
	var lender: Dictionary = lenders.get(lender_id, {}) as Dictionary
	var amount: int = int(application.get("amount_centimes", 0))
	if int(lender.get("available_capital_centimes", 0)) < amount:
		return V2LifeLoopResult.fail("lender_capital_unavailable", "放贷方当前可用资金不足")
	var person_id: String = str(application.get("borrower_person_id", ""))
	var household_id: String = str(application.get("borrower_household_id", ""))
	var ledger_result: V2LifeLoopResult = _ledger.post(
		_households.households,
		household_id,
		person_id,
		amount,
		"income",
		"loan_disbursement",
		total_hour,
		lender_id,
		application_id,
		"finance:%s:disbursement" % idempotency_key,
		"个人借款放款"
	)
	if not ledger_result.success:
		return ledger_result
	var product: Dictionary = products[str(application.get("product_id", ""))] as Dictionary
	var terms: Dictionary = application.get("offered_terms", {}) as Dictionary
	var contract_id: String = "contract:v2_3_loan:%d" % _next_contract_sequence
	_next_contract_sequence += 1
	var contract: Dictionary = {
		"contract_id": contract_id,
		"contract_type": "loan",
		"borrower_person_id": person_id,
		"borrower_household_id": household_id,
		"lender_id": lender_id,
		"product_id": str(application.get("product_id", "")),
		"principal_original_centimes": amount,
		"principal_outstanding_centimes": amount,
		"interest_outstanding_centimes": 0,
		"annual_rate_bp": int(terms.get("annual_rate_bp", product.get("annual_rate_bp", 0))),
		"start_hour": total_hour,
		"end_hour": total_hour + int(terms.get("term_days", product.get("term_days", 30))) * HOURS_PER_DAY,
		"grace_days": int(product.get("grace_days", 0)),
		"status": "active",
		"payment_transaction_ids": [],
		"disbursement_transaction_id": str(ledger_result.data.get("transaction", {}).get("transaction_id", "")),
		"history": [{"event": "accepted", "total_hour": total_hour}],
	}
	contracts[contract_id] = contract
	application["status"] = "accepted"
	application["contract_id"] = contract_id
	applications[application_id] = application
	lender["available_capital_centimes"] = int(lender.get("available_capital_centimes", 0)) - amount
	lenders[lender_id] = lender
	_remember_key(idempotency_key, contract_id)
	_sync_household_debt(person_id)
	_append_event(total_hour, "loan_disbursed", "借款已经放款并形成正式合同", [person_id, lender_id, contract_id])
	return V2LifeLoopResult.ok(
		"借款已经放款，合同与住户账本已经更新",
		{"contract": contract.duplicate(true), "transaction": ledger_result.data.get("transaction", {})},
		[person_id, lender_id, contract_id]
	)


func repay(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	requested_centimes: int
) -> V2LifeLoopResult:
	if _processed_keys.has(idempotency_key):
		return V2LifeLoopResult.ok(
			"该笔还款已经处理",
			{"contract": (contracts.get(str(_processed_keys[idempotency_key]), {}) as Dictionary).duplicate(true), "duplicate": true}
		)
	var contract: Dictionary = contracts.get(contract_id, {}) as Dictionary
	if contract.is_empty() or str(contract.get("status", "")) not in ["active", "overdue", "defaulted"]:
		return V2LifeLoopResult.fail("loan_not_payable", "该借款当前不能还款")
	if requested_centimes <= 0:
		return V2LifeLoopResult.fail("invalid_repayment", "还款金额必须大于零")
	var outstanding: int = int(contract.get("principal_outstanding_centimes", 0)) + int(
		contract.get("interest_outstanding_centimes", 0)
	)
	var amount: int = mini(requested_centimes, outstanding)
	if amount <= 0:
		return V2LifeLoopResult.fail("loan_already_settled", "该借款已经结清")
	var person_id: String = str(contract.get("borrower_person_id", ""))
	var household_id: String = str(contract.get("borrower_household_id", ""))
	var lender_id: String = str(contract.get("lender_id", ""))
	var ledger_result: V2LifeLoopResult = _ledger.post(
		_households.households,
		household_id,
		person_id,
		amount,
		"expense",
		"loan_repayment",
		total_hour,
		lender_id,
		contract_id,
		"finance:%s:repayment" % idempotency_key,
		"个人借款还款"
	)
	if not ledger_result.success:
		return ledger_result
	var interest_paid: int = mini(amount, int(contract.get("interest_outstanding_centimes", 0)))
	var principal_paid: int = amount - interest_paid
	contract["interest_outstanding_centimes"] = int(contract.get("interest_outstanding_centimes", 0)) - interest_paid
	contract["principal_outstanding_centimes"] = int(contract.get("principal_outstanding_centimes", 0)) - principal_paid
	var transaction_ids: Array = contract.get("payment_transaction_ids", []) as Array
	transaction_ids.append(str(ledger_result.data.get("transaction", {}).get("transaction_id", "")))
	contract["payment_transaction_ids"] = transaction_ids
	(contract.get("history", []) as Array).append({
		"event": "repayment",
		"total_hour": total_hour,
		"principal_centimes": principal_paid,
		"interest_centimes": interest_paid,
	})
	if int(contract.get("principal_outstanding_centimes", 0)) == 0 and int(
		contract.get("interest_outstanding_centimes", 0)
	) == 0:
		contract["status"] = "settled"
	contracts[contract_id] = contract
	var lender: Dictionary = lenders.get(lender_id, {}) as Dictionary
	lender["available_capital_centimes"] = int(lender.get("available_capital_centimes", 0)) + amount
	lenders[lender_id] = lender
	_remember_key(idempotency_key, contract_id)
	_sync_household_debt(person_id)
	_append_event(total_hour, "loan_repayment", "借款发生还款", [person_id, lender_id, contract_id])
	return V2LifeLoopResult.ok(
		"还款已经写入住户账本和借款合同",
		{"contract": contract.duplicate(true), "transaction": ledger_result.data.get("transaction", {})},
		[person_id, lender_id, contract_id]
	)


func process_hour(total_hour: int) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	for application_id_variant: Variant in applications.keys():
		var application_id: String = str(application_id_variant)
		var application: Dictionary = applications[application_id] as Dictionary
		var status: String = str(application.get("status", ""))
		if status == "submitted" and int(application.get("review_due_hour", 0)) <= total_hour:
			var reviewed: Dictionary = _review_application(application, total_hour)
			applications[application_id] = reviewed
			var approved: bool = str(reviewed.get("status", "")) == "offered"
			var event: Dictionary = _event(
				total_hour,
				"loan_offer" if approved else "loan_rejected",
				"借款方提出了具体条件" if approved else "借款申请被拒绝",
				[str(reviewed.get("borrower_person_id", "")), str(reviewed.get("lender_id", "")), application_id]
			)
			emitted.append(event)
			_remember_event(event)
		elif status == "offered" and total_hour > int(application.get("offer_expires_hour", -1)):
			application["status"] = "expired"
			applications[application_id] = application
			var event: Dictionary = _event(
				total_hour, "loan_offer_expired", "借款条件已经过期",
				[str(application.get("borrower_person_id", "")), str(application.get("lender_id", "")), application_id]
			)
			emitted.append(event)
			_remember_event(event)
	var value: Dictionary = V2DateTime.from_total_hour(total_hour)
	var daily_boundary: bool = int(value.get("hour", -1)) == 0
	var affected_people: Dictionary = {}
	for contract_id_variant: Variant in contracts.keys():
		var contract_id: String = str(contract_id_variant)
		var contract: Dictionary = contracts[contract_id] as Dictionary
		var contract_status: String = str(contract.get("status", ""))
		if contract_status not in ["active", "overdue", "defaulted"]:
			continue
		if daily_boundary and int(contract.get("principal_outstanding_centimes", 0)) > 0:
			var daily_interest: int = maxi(
				1,
				int(contract.get("principal_outstanding_centimes", 0))
				* int(contract.get("annual_rate_bp", 0))
				/ DAYS_PER_YEAR / 10000
			)
			contract["interest_outstanding_centimes"] = int(
				contract.get("interest_outstanding_centimes", 0)
			) + daily_interest
			(contract.get("history", []) as Array).append({
				"event": "interest_accrued", "total_hour": total_hour,
				"interest_centimes": daily_interest,
			})
		if contract_status == "active" and total_hour >= int(contract.get("end_hour", 0)):
			contract["status"] = "overdue"
			var overdue_event: Dictionary = _event(
				total_hour, "loan_overdue", "借款已经逾期",
				[str(contract.get("borrower_person_id", "")), str(contract.get("lender_id", "")), contract_id]
			)
			emitted.append(overdue_event)
			_remember_event(overdue_event)
		var default_hour: int = int(contract.get("end_hour", 0)) + int(contract.get("grace_days", 0)) * HOURS_PER_DAY
		if str(contract.get("status", "")) == "overdue" and total_hour >= default_hour:
			contract["status"] = "defaulted"
			var default_event: Dictionary = _event(
				total_hour, "loan_defaulted", "借款已经违约",
				[str(contract.get("borrower_person_id", "")), str(contract.get("lender_id", "")), contract_id]
			)
			emitted.append(default_event)
			_remember_event(default_event)
		contracts[contract_id] = contract
		affected_people[str(contract.get("borrower_person_id", ""))] = true
	for person_id_variant: Variant in affected_people.keys():
		_sync_household_debt(str(person_id_variant))
	return emitted


func get_persistent_state() -> Dictionary:
	return {
		"lenders": lenders.duplicate(true),
		"applications": applications.duplicate(true),
		"contracts": contracts.duplicate(true),
		"event_history": event_history.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"processed_key_order": _processed_key_order.duplicate(),
		"next_application_sequence": _next_application_sequence,
		"next_contract_sequence": _next_contract_sequence,
	}


func validate_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("lenders", {}) is Dictionary
		or not state.get("applications", {}) is Dictionary
		or not state.get("contracts", {}) is Dictionary
		or not state.get("event_history", []) is Array
		or not state.get("processed_keys", {}) is Dictionary
		or not state.get("processed_key_order", []) is Array
		or int(state.get("next_application_sequence", 0)) < 1
		or int(state.get("next_contract_sequence", 0)) < 1
	):
		return false
	for raw_contract: Variant in (state.get("contracts", {}) as Dictionary).values():
		if not raw_contract is Dictionary:
			return false
		var contract: Dictionary = raw_contract as Dictionary
		if (
			str(contract.get("contract_id", "")).is_empty()
			or str(contract.get("borrower_person_id", "")).is_empty()
			or int(contract.get("principal_outstanding_centimes", -1)) < 0
			or int(contract.get("interest_outstanding_centimes", -1)) < 0
			or str(contract.get("status", "")) not in ["active", "overdue", "defaulted", "settled"]
		):
			return false
	return true


func restore_persistent_state(state: Dictionary) -> bool:
	if not validate_persistent_state(state):
		return false
	lenders = (state.get("lenders", {}) as Dictionary).duplicate(true)
	applications = (state.get("applications", {}) as Dictionary).duplicate(true)
	contracts = (state.get("contracts", {}) as Dictionary).duplicate(true)
	event_history = (state.get("event_history", []) as Array).duplicate(true)
	_processed_keys = (state.get("processed_keys", {}) as Dictionary).duplicate(true)
	_processed_key_order.clear()
	for raw_key: Variant in state.get("processed_key_order", []) as Array:
		_processed_key_order.append(str(raw_key))
	_next_application_sequence = int(state.get("next_application_sequence", 1))
	_next_contract_sequence = int(state.get("next_contract_sequence", 1))
	for person_id_variant: Variant in _households.person_to_household.keys():
		_sync_household_debt(str(person_id_variant))
	return true


func _review_application(application: Dictionary, total_hour: int) -> Dictionary:
	var reviewed: Dictionary = application.duplicate(true)
	var product: Dictionary = products.get(str(application.get("product_id", "")), {}) as Dictionary
	var income: int = int(application.get("monthly_income_centimes", 0))
	var amount: int = int(application.get("amount_centimes", 0))
	var debt: int = int(application.get("debt_at_application_centimes", 0))
	var cash: int = int(application.get("cash_at_application_centimes", 0))
	var minimum_income: int = int(product.get("minimum_monthly_income_centimes", 0))
	var score: int = 18
	var reasons: Array[String] = []
	if bool(application.get("employment_active", false)):
		score += 24
		reasons.append("存在可核实的正式劳动收入")
	else:
		reasons.append("没有可核实的正式劳动收入")
	if minimum_income <= 0 or income >= minimum_income:
		score += 18
	else:
		score += clampi(income * 18 / maxi(1, minimum_income), 0, 17)
		reasons.append("收入低于该产品通常审查水平")
	score += clampi(income * 20 / maxi(1, amount), 0, 18)
	score += clampi(cash * 8 / maxi(1, amount), 0, 8)
	if debt > 0:
		var debt_penalty: int = clampi(debt * 18 / maxi(1, income * 3), 0, 24)
		score -= debt_penalty
		reasons.append("已有债务提高了偿付压力")
	var approved: bool = score >= int(product.get("approval_threshold", 50))
	reviewed["review_hour"] = total_hour
	reviewed["credit_score"] = score
	reviewed["decision_reasons"] = reasons
	if approved:
		reviewed["status"] = "offered"
		reviewed["offered_terms"] = {
			"amount_centimes": amount,
			"annual_rate_bp": int(product.get("annual_rate_bp", 0)),
			"term_days": int(product.get("term_days", 0)),
		}
		reviewed["offer_expires_hour"] = total_hour + int(product.get("offer_valid_hours", 48))
	else:
		reviewed["status"] = "rejected"
	return reviewed


func _sync_household_debt(person_id: String) -> void:
	var household_id: String = _households.household_id_for_person(person_id)
	if household_id.is_empty() or not _households.households.has(household_id):
		return
	var household: Dictionary = _households.households[household_id] as Dictionary
	household["other_debt_centimes"] = total_debt_for_person(person_id)
	_households.households[household_id] = household


func _remember_key(key: String, value: String) -> void:
	_processed_keys[key] = value
	_processed_key_order.append(key)
	while _processed_key_order.size() > 2048:
		_processed_keys.erase(_processed_key_order.pop_front())


func _append_event(total_hour: int, event_type: String, summary: String, entity_ids: Array[String]) -> void:
	_remember_event(_event(total_hour, event_type, summary, entity_ids))


func _remember_event(event: Dictionary) -> void:
	event_history.append(event)
	while event_history.size() > MAX_HISTORY:
		event_history.pop_front()


static func _event(
	total_hour: int,
	event_type: String,
	summary: String,
	entity_ids: Array[String]
) -> Dictionary:
	return {
		"event_id": "finance_event:%s:%d" % [event_type, total_hour],
		"event_type": event_type,
		"summary": summary,
		"total_hour": total_hour,
		"entity_ids": entity_ids.duplicate(),
	}
