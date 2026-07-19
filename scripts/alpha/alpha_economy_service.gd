class_name AlphaEconomyService
extends RefCounted
## Alpha composition for ledger, assets, contracts, credit, markets and life costs.

const HOURS_PER_DAY: int = 24
const DAYS_PER_YEAR: int = 365
const CREDIT_LENDER_IDS: Array[String] = [
	"organization:loran_public_credit",
	"organization:vesta_public_credit",
	"organization:merchant_credit_pool",
]

var ledger := AlphaLedgerService.new()
var assets := AlphaAssetService.new()
var contracts := AlphaContractService.new()
var credit_products: Dictionary = {}
var goods: Dictionary = {}
var markets: Dictionary = {}
var applications: Dictionary = {}
var loan_claim_assets: Dictionary = {}
var entity_profiles: Dictionary = {}
var external_events: Array[Dictionary] = []
var _processed_keys: Dictionary = {}
var _next_application_sequence: int = 1


func configure(config: AlphaConfig) -> bool:
	ledger.configure()
	assets.configure(ledger)
	if not contracts.configure(config.contract_templates(), ledger, assets):
		return false
	credit_products.clear()
	goods.clear()
	markets.clear()
	applications.clear()
	loan_claim_assets.clear()
	entity_profiles.clear()
	external_events.clear()
	_processed_keys.clear()
	_next_application_sequence = 1
	for raw_product: Variant in config.credit_products():
		var product: Dictionary = raw_product as Dictionary
		credit_products[str(product.get("product_id", ""))] = product.duplicate(true)
	for raw_good: Variant in config.goods():
		var good: Dictionary = raw_good as Dictionary
		goods[str(good.get("good_id", ""))] = good.duplicate(true)
	for raw_region: Variant in config.region_profiles():
		var region: Dictionary = raw_region as Dictionary
		_initialize_market(region)
	for lender_id: String in CREDIT_LENDER_IDS:
		var registered: Dictionary = register_entity(lender_id, "organization", 2_000_000)
		if not bool(registered.get("success", false)):
			return false
	return credit_products.size() == 5 and goods.size() >= 8 and markets.size() == 8


func register_entity(
	entity_id: String,
	entity_type: String,
	opening_cash_centimes: int,
	profile: Dictionary = {}
) -> Dictionary:
	var account: Dictionary = ledger.register_cash_account(
		entity_id, entity_type, opening_cash_centimes
	)
	if not bool(account.get("success", false)):
		return account
	var cash_asset: Dictionary = assets.register_cash_asset(entity_id)
	if not bool(cash_asset.get("success", false)):
		return cash_asset
	var normalized: Dictionary = {
		"entity_id": entity_id,
		"entity_type": entity_type,
		"income_monthly_centimes": int(profile.get("income_monthly_centimes", 0)),
		"reputation": int(profile.get("reputation", 50)),
		"relationship_with_lender": int(profile.get("relationship_with_lender", 0)),
		"region_id": str(profile.get("region_id", "")),
		"qualifications": DataRecordUtils.to_string_array(profile.get("qualifications", [])),
		"disclosed_debt_centimes": int(profile.get("disclosed_debt_centimes", 0)),
	}
	entity_profiles[entity_id] = normalized
	return _ok({"account": (account.get("data", {}) as Dictionary).get("account", {})})


func set_entity_profile(entity_id: String, changes: Dictionary) -> bool:
	if not entity_profiles.has(entity_id):
		return false
	var profile: Dictionary = entity_profiles[entity_id] as Dictionary
	for raw_key: Variant in changes:
		profile[str(raw_key)] = changes[raw_key]
	entity_profiles[entity_id] = profile
	return true


func create_opening_debt(
	idempotency_key: String,
	borrower_id: String,
	lender_id: String,
	principal_centimes: int,
	product_id: String,
	start_hour: int,
	collateral_asset_ids: Array = []
) -> Dictionary:
	if principal_centimes <= 0:
		return _fail("invalid_opening_debt", "期初债务金额无效")
	var product: Dictionary = credit_products.get(product_id, {}) as Dictionary
	if product.is_empty():
		return _fail("credit_product_missing", "信贷产品不存在")
	var contract_result: Dictionary = contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:loan",
		[
			{"party_id": lender_id, "role": "creditor"},
			{"party_id": borrower_id, "role": "borrower"},
		],
		{"product_id": product_id, "opening_obligation": true},
		principal_centimes,
		start_hour,
		start_hour + int(product.get("term_days", 90)) * HOURS_PER_DAY,
		{
			"annual_rate_bp": int(product.get("annual_rate_bp", 0)),
			"collateral_asset_ids": collateral_asset_ids,
			"document_ids": ["document:opening_debt:%s" % borrower_id],
		}
	)
	if not bool(contract_result.get("success", false)):
		return contract_result
	var contract: Dictionary = (contract_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	var activated: Dictionary = contracts.activate(
		"activate:%s" % idempotency_key, contract_id, start_hour
	)
	if not bool(activated.get("success", false)):
		return activated
	var claim_result: Dictionary = assets.create_asset(
		"claim:%s" % idempotency_key,
		"claim",
		lender_id,
		lender_id,
		principal_centimes,
		{"contract_id": contract_id, "borrower_id": borrower_id}
	)
	if not bool(claim_result.get("success", false)):
		return claim_result
	var claim: Dictionary = (claim_result.get("data", {}) as Dictionary).get("asset", {}) as Dictionary
	loan_claim_assets[contract_id] = str(claim.get("asset_id", ""))
	for collateral_id: String in DataRecordUtils.to_string_array(collateral_asset_ids):
		var mortgaged: Dictionary = assets.mortgage(
			"mortgage:%s:%s" % [idempotency_key, collateral_id],
			collateral_id,
			contract_id,
			lender_id
		)
		if not bool(mortgaged.get("success", false)):
			return mortgaged
	return _ok({
		"contract": contracts.contracts[contract_id],
		"claim_asset_id": loan_claim_assets[contract_id],
	})


func apply_for_loan(
	idempotency_key: String,
	borrower_id: String,
	lender_id: String,
	product_id: String,
	amount_centimes: int,
	total_hour: int,
	collateral_asset_ids: Array = [],
	guarantor_ids: Array = [],
	provided_information: Dictionary = {}
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({
			"application": (
				applications.get(str(_processed_keys[idempotency_key]), {}) as Dictionary
			).duplicate(true),
			"duplicate": true,
		})
	var product: Dictionary = credit_products.get(product_id, {}) as Dictionary
	var profile: Dictionary = entity_profiles.get(borrower_id, {}) as Dictionary
	if (
		idempotency_key.is_empty()
		or product.is_empty()
		or profile.is_empty()
		or not entity_profiles.has(lender_id)
		or amount_centimes <= 0
	):
		return _fail("invalid_application", "借款申请对象、产品或金额无效")
	if bool(product.get("collateral_required", false)) and collateral_asset_ids.is_empty():
		return _fail("collateral_required", "该信贷产品要求具体抵押物")
	for collateral_id: String in DataRecordUtils.to_string_array(collateral_asset_ids):
		if not assets.assets.has(collateral_id):
			return _fail("collateral_missing", "借款申请引用未知抵押物")
	var application_id: String = "loan_application:alpha:%d" % _next_application_sequence
	_next_application_sequence += 1
	var application: Dictionary = {
		"application_id": application_id,
		"borrower_id": borrower_id,
		"lender_id": lender_id,
		"product_id": product_id,
		"amount_centimes": amount_centimes,
		"application_hour": total_hour,
		"collateral_asset_ids": DataRecordUtils.to_string_array(collateral_asset_ids),
		"guarantor_ids": DataRecordUtils.to_string_array(guarantor_ids),
		"provided_information": provided_information.duplicate(true),
		"status": "submitted",
		"credit_score": 0,
		"decision_reasons": [],
		"offered_terms": {},
	}
	applications[application_id] = application
	_processed_keys[idempotency_key] = application_id
	return _ok({"application": application.duplicate(true), "duplicate": false})


func review_application(
	idempotency_key: String, application_id: String, total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _application_duplicate(idempotency_key)
	var application: Dictionary = applications.get(application_id, {}) as Dictionary
	if application.is_empty() or str(application.get("status", "")) != "submitted":
		return _fail("invalid_review", "借款申请不处于待审查状态")
	var borrower_id: String = str(application.get("borrower_id", ""))
	var product: Dictionary = credit_products[
		str(application.get("product_id", ""))
	] as Dictionary
	var profile: Dictionary = entity_profiles[borrower_id] as Dictionary
	var monthly_income: int = int(profile.get("income_monthly_centimes", 0))
	var amount: int = int(application.get("amount_centimes", 0))
	var actual_debt: int = total_debt(borrower_id)
	var disclosed_debt: int = int(
		(application.get("provided_information", {}) as Dictionary).get(
			"existing_debt_centimes",
			profile.get("disclosed_debt_centimes", actual_debt)
		)
	)
	var asset_value: int = total_asset_value(borrower_id)
	var collateral_value: int = 0
	for collateral_id: String in DataRecordUtils.to_string_array(
		application.get("collateral_asset_ids", [])
	):
		collateral_value += assets.value(collateral_id)
	var region_credit: int = _region_credit_environment(
		str(profile.get("region_id", ""))
	)
	var score: int = 15
	score += mini(25, monthly_income * 100 / maxi(1, amount))
	score += mini(18, asset_value * 20 / maxi(1, amount))
	score += mini(15, collateral_value * 20 / maxi(1, amount))
	score += clampi(int(profile.get("reputation", 50)) / 5, 0, 20)
	score += clampi(int(profile.get("relationship_with_lender", 0)) / 5, -10, 10)
	score += clampi(region_credit / 10, 0, 10)
	score += mini(8, (application.get("guarantor_ids", []) as Array).size() * 4)
	score -= mini(30, actual_debt * 30 / maxi(1, monthly_income * 6))
	var reasons: Array[String] = []
	if disclosed_debt < actual_debt:
		score -= 12
		reasons.append("申报债务低于可核实债务")
	if collateral_value > 0:
		reasons.append("具体抵押物降低了损失风险")
	if monthly_income <= 0:
		reasons.append("缺少可核实持续收入")
	var threshold: int = 100 - int(product.get("risk_tolerance", 50))
	var approved: bool = score >= threshold
	application["credit_score"] = score
	application["status"] = "offered" if approved else "rejected"
	application["review_hour"] = total_hour
	application["decision_reasons"] = reasons
	if approved:
		var risk_markup: int = maxi(0, threshold + 20 - score) * 12
		application["offered_terms"] = {
			"annual_rate_bp": int(product.get("annual_rate_bp", 0)) + risk_markup,
			"term_days": int(product.get("term_days", 90)),
			"amount_centimes": amount,
		}
	applications[application_id] = application
	_processed_keys[idempotency_key] = application_id
	return _ok({"application": application.duplicate(true)})


func accept_loan_offer(
	idempotency_key: String, application_id: String, total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"contract": (contracts.contracts.get(existing_id, {}) as Dictionary).duplicate(true),
			"duplicate": true,
		})
	var application: Dictionary = applications.get(application_id, {}) as Dictionary
	if application.is_empty() or str(application.get("status", "")) != "offered":
		return _fail("offer_unavailable", "借款条件尚未提出或已失效")
	var borrower_id: String = str(application.get("borrower_id", ""))
	var lender_id: String = str(application.get("lender_id", ""))
	var amount: int = int(application.get("amount_centimes", 0))
	var terms: Dictionary = application.get("offered_terms", {}) as Dictionary
	var contract_result: Dictionary = contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:loan",
		[
			{"party_id": lender_id, "role": "creditor"},
			{"party_id": borrower_id, "role": "borrower"},
		],
		{"product_id": application.get("product_id", "")},
		amount,
		total_hour,
		total_hour + int(terms.get("term_days", 90)) * HOURS_PER_DAY,
		{
			"annual_rate_bp": int(terms.get("annual_rate_bp", 0)),
			"collateral_asset_ids": application.get("collateral_asset_ids", []),
			"guarantor_ids": application.get("guarantor_ids", []),
			"document_ids": ["document:loan_offer:%s" % application_id],
		}
	)
	if not bool(contract_result.get("success", false)):
		return contract_result
	var contract: Dictionary = (contract_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	var activated: Dictionary = contracts.activate(
		"activate:%s" % idempotency_key, contract_id, total_hour
	)
	if not bool(activated.get("success", false)):
		return activated
	var disbursement: Dictionary = ledger.transfer(
		"disburse:%s" % idempotency_key,
		total_hour,
		lender_id,
		borrower_id,
		amount,
		"loan_disbursement",
		"fact:loan_disbursed:%s" % contract_id,
		"借款放款"
	)
	if not bool(disbursement.get("success", false)):
		return disbursement
	var claim_result: Dictionary = assets.create_asset(
		"claim:%s" % idempotency_key,
		"claim",
		lender_id,
		lender_id,
		amount,
		{"contract_id": contract_id, "borrower_id": borrower_id}
	)
	if not bool(claim_result.get("success", false)):
		return claim_result
	var claim: Dictionary = (claim_result.get("data", {}) as Dictionary).get("asset", {}) as Dictionary
	loan_claim_assets[contract_id] = str(claim.get("asset_id", ""))
	for collateral_id: String in DataRecordUtils.to_string_array(
		application.get("collateral_asset_ids", [])
	):
		var mortgaged: Dictionary = assets.mortgage(
			"mortgage:%s:%s" % [idempotency_key, collateral_id],
			collateral_id,
			contract_id,
			lender_id
		)
		if not bool(mortgaged.get("success", false)):
			return mortgaged
	application["status"] = "accepted"
	application["contract_id"] = contract_id
	applications[application_id] = application
	_processed_keys[idempotency_key] = contract_id
	return _ok({
		"contract": contracts.contracts[contract_id],
		"claim_asset_id": loan_claim_assets[contract_id],
		"disbursement": (disbursement.get("data", {}) as Dictionary).get("transaction", {}),
	})


func accrue_loan_interest(
	idempotency_key: String, contract_id: String, total_hour: int, days: int
) -> Dictionary:
	var contract: Dictionary = contracts.contracts.get(contract_id, {}) as Dictionary
	if days <= 0 or str(contract.get("contract_type", "")) != "loan":
		return _fail("invalid_interest_period", "借款计息周期无效")
	var terms: Dictionary = contract.get("terms", {}) as Dictionary
	var principal: int = int(contract.get("principal_outstanding_centimes", 0))
	var rate_bp: int = int(terms.get("annual_rate_bp", 0))
	var interest: int = maxi(1, principal * rate_bp * days / DAYS_PER_YEAR / 10000)
	var result: Dictionary = contracts.accrue_interest(
		idempotency_key, contract_id, total_hour, interest
	)
	if bool(result.get("success", false)):
		_update_claim(idempotency_key, contract_id)
	return result


func repay_loan(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	requested_centimes: int
) -> Dictionary:
	var contract: Dictionary = contracts.contracts.get(contract_id, {}) as Dictionary
	if requested_centimes <= 0 or str(contract.get("contract_type", "")) != "loan":
		return _fail("invalid_repayment", "还款合同或金额无效")
	var borrower_id: String = _party_with_role(contract, "borrower")
	var lender_id: String = _party_with_role(contract, "creditor")
	var interest: int = mini(
		requested_centimes, int(contract.get("interest_outstanding_centimes", 0))
	)
	var principal: int = mini(
		requested_centimes - interest,
		int(contract.get("principal_outstanding_centimes", 0))
	)
	var amount: int = principal + interest
	if amount <= 0:
		return _fail("loan_already_paid", "借款已经结清")
	var payment: Dictionary = ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		borrower_id,
		lender_id,
		amount,
		"loan_repayment",
		"fact:loan_payment:%s" % contract_id,
		"借款还款"
	)
	if not bool(payment.get("success", false)):
		return payment
	var transaction: Dictionary = (payment.get("data", {}) as Dictionary).get(
		"transaction", {}
	) as Dictionary
	var recorded: Dictionary = contracts.record_payment(
		idempotency_key,
		contract_id,
		total_hour,
		str(transaction.get("transaction_id", "")),
		principal,
		interest
	)
	if bool(recorded.get("success", false)):
		_update_claim(idempotency_key, contract_id)
	return recorded


func mark_loan_overdue(
	idempotency_key: String, contract_id: String, total_hour: int
) -> Dictionary:
	return contracts.mark_overdue(idempotency_key, contract_id, total_hour)


func default_loan(
	idempotency_key: String, contract_id: String, total_hour: int, reason: String
) -> Dictionary:
	var contract: Dictionary = contracts.contracts.get(contract_id, {}) as Dictionary
	if str(contract.get("status", "")) != "overdue":
		return _fail("loan_not_overdue", "借款必须先进入逾期状态")
	return contracts.default_contract(idempotency_key, contract_id, total_hour, reason)


func seize_collateral(
	idempotency_key: String, contract_id: String, total_hour: int
) -> Dictionary:
	var contract: Dictionary = contracts.contracts.get(contract_id, {}) as Dictionary
	if str(contract.get("status", "")) != "defaulted":
		return _fail("loan_not_defaulted", "抵押处置要求借款已经违约")
	var lender_id: String = _party_with_role(contract, "creditor")
	var disposed_ids: Array[String] = []
	for collateral_id: String in DataRecordUtils.to_string_array(
		contract.get("collateral_asset_ids", [])
	):
		var disposed: Dictionary = assets.dispose_in_bankruptcy(
			"%s:%s" % [idempotency_key, collateral_id], collateral_id, lender_id
		)
		if not bool(disposed.get("success", false)):
			return disposed
		disposed_ids.append(collateral_id)
	var enforced: Dictionary = contracts.enforce(
		"enforce:%s" % idempotency_key,
		contract_id,
		total_hour,
		lender_id,
		"collateral_seized"
	)
	if not bool(enforced.get("success", false)):
		return enforced
	return _ok({"disposed_asset_ids": disposed_ids, "contract": enforced.get("data", {}).get("contract", {})})


func restructure_loan(
	idempotency_key: String,
	contract_id: String,
	total_hour: int,
	extra_days: int,
	new_annual_rate_bp: int
) -> Dictionary:
	var contract: Dictionary = contracts.contracts.get(contract_id, {}) as Dictionary
	if extra_days <= 0 or new_annual_rate_bp <= 0:
		return _fail("invalid_restructure", "债务重组期限或利率无效")
	return contracts.renegotiate(
		idempotency_key,
		contract_id,
		total_hour,
		int(contract.get("end_hour", total_hour)) + extra_days * HOURS_PER_DAY,
		{
			"annual_rate_bp": new_annual_rate_bp,
			"restructured_at_hour": total_hour,
		}
	)


func assign_claim(
	idempotency_key: String,
	contract_id: String,
	from_creditor_id: String,
	to_creditor_id: String,
	total_hour: int,
	price_centimes: int
) -> Dictionary:
	var claim_asset_id: String = str(loan_claim_assets.get(contract_id, ""))
	if claim_asset_id.is_empty():
		return _fail("claim_missing", "借款合同没有对应债权资产")
	return assets.sell(
		idempotency_key,
		total_hour,
		claim_asset_id,
		from_creditor_id,
		to_creditor_id,
		price_centimes
	)


func create_trade(
	idempotency_key: String,
	buyer_id: String,
	seller_id: String,
	good_id: String,
	quantity: int,
	origin_region_id: String,
	destination_region_id: String,
	total_hour: int,
	transport_days: int = 0
) -> Dictionary:
	if quantity <= 0 or not goods.has(good_id):
		return _fail("invalid_trade", "商品或交易数量无效")
	var unit_price: int = market_price(origin_region_id, good_id)
	var transport_cost: int = (
		0
		if origin_region_id == destination_region_id
		else quantity * maxi(20, unit_price / 12)
	)
	var total_price: int = unit_price * quantity + transport_cost
	var contract_result: Dictionary = contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:order",
		[
			{"party_id": buyer_id, "role": "buyer"},
			{"party_id": seller_id, "role": "seller"},
		],
		{
			"good_id": good_id,
			"quantity": quantity,
			"origin_region_id": origin_region_id,
			"destination_region_id": destination_region_id,
		},
		total_price,
		total_hour,
		total_hour + maxi(1, transport_days + 3) * HOURS_PER_DAY,
		{
			"delivery_conditions": {
				"transport_days": transport_days,
				"transport_cost_centimes": transport_cost,
			},
			"document_ids": ["document:order:%s" % idempotency_key],
		}
	)
	if not bool(contract_result.get("success", false)):
		return contract_result
	var contract: Dictionary = (contract_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	var activated: Dictionary = contracts.activate(
		"activate:%s" % idempotency_key, contract_id, total_hour
	)
	if not bool(activated.get("success", false)):
		return activated
	return _ok({
		"contract": contracts.contracts[contract_id],
		"total_price_centimes": total_price,
		"transport_cost_centimes": transport_cost,
	})


func settle_trade(
	idempotency_key: String, contract_id: String, total_hour: int
) -> Dictionary:
	var contract: Dictionary = contracts.contracts.get(contract_id, {}) as Dictionary
	if str(contract.get("contract_type", "")) not in ["sale", "order"]:
		return _fail("invalid_trade_contract", "结算对象不是买卖或订单合同")
	var buyer_id: String = _party_with_role(contract, "buyer")
	var seller_id: String = _party_with_role(contract, "seller")
	var amount: int = contracts.outstanding(contract_id)
	var payment: Dictionary = ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		buyer_id,
		seller_id,
		amount,
		"trade_payment",
		"fact:trade_settlement:%s" % contract_id,
		"商品或服务交易结算"
	)
	if not bool(payment.get("success", false)):
		return payment
	var delivered: Dictionary = contracts.record_delivery(
		"delivery:%s" % idempotency_key,
		contract_id,
		total_hour,
		10000,
		"evidence:delivery:%s" % contract_id
	)
	if not bool(delivered.get("success", false)):
		return delivered
	var transaction: Dictionary = (payment.get("data", {}) as Dictionary).get(
		"transaction", {}
	) as Dictionary
	return contracts.record_payment(
		idempotency_key,
		contract_id,
		total_hour,
		str(transaction.get("transaction_id", "")),
		amount
	)


func pay_life_costs(
	idempotency_key: String,
	person_id: String,
	service_provider_id: String,
	total_hour: int,
	living_centimes: int,
	housing_centimes: int,
	transport_centimes: int,
	development_centimes: int = 0,
	tax_centimes: int = 0
) -> Dictionary:
	var total: int = (
		living_centimes + housing_centimes + transport_centimes
		+ development_centimes + tax_centimes
	)
	if total < 0:
		return _fail("invalid_life_cost", "生活预算不能为负")
	return ledger.transfer(
		idempotency_key,
		total_hour,
		person_id,
		service_provider_id,
		total,
		"life_budget",
		"fact:life_budget:%s:%d" % [person_id, total_hour],
		"自动生活预算结算"
	)


func apply_market_shock(
	idempotency_key: String,
	region_id: String,
	good_id: String,
	price_delta_bp: int,
	duration_days: int,
	cause: String,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"duplicate": true})
	if not markets.has(region_id) or not goods.has(good_id) or duration_days <= 0:
		return _fail("invalid_market_shock", "市场冲击引用无效")
	var market: Dictionary = markets[region_id] as Dictionary
	var prices: Dictionary = market.get("prices", {}) as Dictionary
	var before: int = int(prices.get(good_id, 0))
	prices[good_id] = maxi(1, before * (10000 + price_delta_bp) / 10000)
	market["prices"] = prices
	market["state"] = "shortage" if price_delta_bp > 0 else "surplus"
	markets[region_id] = market
	external_events.append({
		"event_id": "market_event:%d" % external_events.size(),
		"region_id": region_id,
		"good_id": good_id,
		"before_price": before,
		"after_price": prices[good_id],
		"end_hour": total_hour + duration_days * HOURS_PER_DAY,
		"cause": cause,
	})
	while external_events.size() > 128:
		external_events.pop_front()
	_processed_keys[idempotency_key] = "market"
	return _ok({"before_price": before, "after_price": prices[good_id]})


func market_price(region_id: String, good_id: String) -> int:
	var market: Dictionary = markets.get(region_id, {}) as Dictionary
	var prices: Dictionary = market.get("prices", {}) as Dictionary
	return int(prices.get(good_id, 0))


func total_debt(entity_id: String) -> int:
	var total: int = 0
	for contract: Dictionary in contracts.contracts_for_party(entity_id, false):
		if (
			str(contract.get("contract_type", "")) == "loan"
			and _party_with_role(contract, "borrower") == entity_id
		):
			total += contracts.outstanding(str(contract.get("contract_id", "")))
	return total


func total_asset_value(entity_id: String) -> int:
	var total: int = 0
	for raw_asset: Variant in assets.assets.values():
		var asset: Dictionary = raw_asset as Dictionary
		var share_bp: int = assets.owner_share(str(asset.get("asset_id", "")), entity_id)
		if share_bp > 0:
			total += assets.value(str(asset.get("asset_id", ""))) * share_bp / 10000
	return total


func validate_integrity() -> Dictionary:
	for result: Dictionary in [
		ledger.validate_balances(),
		assets.validate_references(),
		contracts.validate_references(),
	]:
		if not bool(result.get("success", false)):
			return result
	for raw_contract_id: Variant in loan_claim_assets:
		var contract_id: String = str(raw_contract_id)
		var asset_id: String = str(loan_claim_assets[contract_id])
		if not contracts.contracts.has(contract_id) or not assets.assets.has(asset_id):
			return _fail("loan_reference_missing", "借款合同与债权资产引用不闭合")
	return _ok({
		"accounts": ledger.accounts.size(),
		"assets": assets.assets.size(),
		"contracts": contracts.contracts.size(),
		"debts": loan_claim_assets.size(),
	})


func get_persistent_state() -> Dictionary:
	return {
		"ledger": ledger.get_persistent_state(),
		"assets": assets.get_persistent_state(),
		"contracts": contracts.get_persistent_state(),
		"applications": applications.duplicate(true),
		"loan_claim_assets": loan_claim_assets.duplicate(true),
		"entity_profiles": entity_profiles.duplicate(true),
		"markets": markets.duplicate(true),
		"external_events": external_events.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_application_sequence": _next_application_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if (
		not state.get("applications", {}) is Dictionary
		or not state.get("loan_claim_assets", {}) is Dictionary
		or not state.get("entity_profiles", {}) is Dictionary
		or not state.get("markets", {}) is Dictionary
	):
		return false
	if not ledger.restore_persistent_state(state.get("ledger", {}) as Dictionary):
		return false
	if not assets.restore_persistent_state(state.get("assets", {}) as Dictionary):
		return false
	if not contracts.restore_persistent_state(state.get("contracts", {}) as Dictionary):
		return false
	applications = (state["applications"] as Dictionary).duplicate(true)
	loan_claim_assets = (state["loan_claim_assets"] as Dictionary).duplicate(true)
	entity_profiles = (state["entity_profiles"] as Dictionary).duplicate(true)
	markets = (state["markets"] as Dictionary).duplicate(true)
	external_events = (
		(state.get("external_events", []) as Array).duplicate(true)
		as Array[Dictionary]
	)
	_processed_keys = (
		(state.get("processed_keys", {}) as Dictionary).duplicate(true)
	)
	_next_application_sequence = int(state.get("next_application_sequence", 0))
	return (
		_next_application_sequence >= 1
		and bool(validate_integrity().get("success", false))
	)


func _initialize_market(region: Dictionary) -> void:
	var region_id: String = str(region.get("region_id", ""))
	var supply: Dictionary = region.get("supply", {}) as Dictionary
	var demand: Dictionary = region.get("demand", {}) as Dictionary
	var prices: Dictionary = {}
	for raw_good_id: Variant in goods:
		var good_id: String = str(raw_good_id)
		var good: Dictionary = goods[good_id] as Dictionary
		var base_price: int = int(good.get("base_price", 1))
		var supply_index: int = int(supply.get(good_id, 50))
		var demand_index: int = int(demand.get(good_id, 50))
		var price_index: int = clampi(100 + demand_index - supply_index, 60, 180)
		prices[good_id] = base_price * price_index / 100
	markets[region_id] = {
		"region_id": region_id,
		"supply": supply.duplicate(true),
		"demand": demand.duplicate(true),
		"prices": prices,
		"credit_environment": int(region.get("credit_environment", 50)),
		"state": "balanced",
	}


func _region_credit_environment(region_id: String) -> int:
	var market: Dictionary = markets.get(region_id, {}) as Dictionary
	return int(market.get("credit_environment", 50))


func _update_claim(idempotency_key: String, contract_id: String) -> void:
	var claim_asset_id: String = str(loan_claim_assets.get(contract_id, ""))
	if claim_asset_id.is_empty():
		return
	assets.update_contract_value(
		"claim_update:%s" % idempotency_key,
		claim_asset_id,
		contract_id,
		contracts.outstanding(contract_id)
	)


func _application_duplicate(idempotency_key: String) -> Dictionary:
	var application_id: String = str(_processed_keys[idempotency_key])
	return _ok({
		"application": (
			applications.get(application_id, {}) as Dictionary
		).duplicate(true),
		"duplicate": true,
	})


static func _party_with_role(contract: Dictionary, role: String) -> String:
	for party: Dictionary in contract.get("parties", []) as Array[Dictionary]:
		if str(party.get("role", "")) == role:
			return str(party.get("party_id", ""))
	return ""


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
