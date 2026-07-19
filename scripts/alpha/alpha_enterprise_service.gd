class_name AlphaEnterpriseService
extends RefCounted
## Enterprise rules layered on the unified organization, asset, contract and ledger authorities.

const AGGREGATE_MARKET_ID: String = "system:aggregate_market"
const ACTIVE_ENTERPRISE_STATUSES: Array[String] = [
	"operating",
	"distressed",
	"contracting",
]

var enterprises: Dictionary = {}
var _economy: AlphaEconomyService
var _labor: AlphaLaborService
var _organizations: OrganizationService
var _region_country: Dictionary = {}
var _processed_keys: Dictionary = {}
var _next_enterprise_sequence: int = 1


func configure(
	config: AlphaConfig,
	economy: AlphaEconomyService,
	labor: AlphaLaborService,
	organizations: OrganizationService,
	start_hour: int = 0
) -> bool:
	enterprises.clear()
	_region_country.clear()
	_processed_keys.clear()
	_next_enterprise_sequence = 1
	_economy = economy
	_labor = labor
	_organizations = organizations
	for raw_region: Variant in config.region_profiles():
		var region: Dictionary = raw_region as Dictionary
		_region_country[str(region.get("region_id", ""))] = str(
			region.get("country_id", "")
		)
	if not _economy.entity_profiles.has(AGGREGATE_MARKET_ID):
		if not bool(_economy.register_entity(
			AGGREGATE_MARKET_ID, "system", 10_000_000
		).get("success", false)):
			return false
	for raw_enterprise: Variant in config.enterprise_records():
		if not _bootstrap_enterprise(raw_enterprise as Dictionary, start_hour):
			return false
	return enterprises.size() >= 12


func create_enterprise(
	idempotency_key: String,
	owner_id: String,
	name: String,
	structure: String,
	region_id: String,
	city_id: String,
	product_id: String,
	input_id: String,
	initial_capital_centimes: int,
	total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		var existing_id: String = str(_processed_keys[idempotency_key])
		return _ok({
			"enterprise": (enterprises.get(existing_id, {}) as Dictionary).duplicate(true),
			"duplicate": true,
		})
	if (
		owner_id.is_empty()
		or name.is_empty()
		or structure not in ["retail_trade", "small_production", "logistics", "information_service"]
		or not _region_country.has(region_id)
		or not _economy.goods.has(product_id)
		or not _economy.goods.has(input_id)
		or initial_capital_centimes < 0
	):
		return _fail("invalid_enterprise", "企业创建条件无效")
	var organization_id: String = "organization:player_enterprise_%d" % _next_enterprise_sequence
	_next_enterprise_sequence += 1
	if not _register_enterprise_organization(
		organization_id,
		name,
		str(_region_country[region_id]),
		region_id
	):
		return _fail("organization_registration_failed", "企业组织登记失败")
	var registered: Dictionary = _economy.register_entity(
		organization_id,
		"organization",
		0,
		{
			"income_monthly_centimes": 0,
			"reputation": 45,
			"region_id": region_id,
		}
	)
	if not bool(registered.get("success", false)):
		return registered
	if initial_capital_centimes > 0:
		var capitalization: Dictionary = _economy.ledger.transfer(
			"ledger:%s" % idempotency_key,
			total_hour,
			owner_id,
			organization_id,
			initial_capital_centimes,
			"enterprise_capital",
			"fact:enterprise_created:%s" % organization_id,
			"企业初始注资"
		)
		if not bool(capitalization.get("success", false)):
			return capitalization
	var state: Dictionary = _new_enterprise_state({
		"organization_id": organization_id,
		"name": name,
		"structure": structure,
		"region_id": region_id,
		"city_id": city_id,
		"product_id": product_id,
		"input_id": input_id,
		"opening_cash": initial_capital_centimes,
		"opening_debt": 0,
		"employees": 0,
		"purchasable": true,
		"distress": 10,
	})
	var equity: Dictionary = _economy.assets.create_asset(
		"equity:%s" % idempotency_key,
		"enterprise_equity",
		owner_id,
		owner_id,
		initial_capital_centimes,
		{"organization_id": organization_id},
		"asset:equity:%s" % organization_id
	)
	if not bool(equity.get("success", false)):
		return equity
	state["equity_asset_id"] = str(
		((equity.get("data", {}) as Dictionary).get("asset", {}) as Dictionary).get(
			"asset_id", ""
		)
	)
	var equipment_id: String = _create_operating_asset(
		organization_id, "equipment", maxi(1000, initial_capital_centimes / 3),
		{"capacity_units": 12}
	)
	if equipment_id.is_empty():
		return _fail("operating_asset_failed", "企业设备登记失败")
	(state["asset_ids"] as Array).append(equipment_id)
	state["capacity_units_per_day"] = 12
	state["execution_capacity"] = 72
	enterprises[organization_id] = state
	_register_enterprise_job(state)
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true), "duplicate": false})


func inject_capital(
	idempotency_key: String,
	organization_id: String,
	investor_id: String,
	amount_centimes: int,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or amount_centimes <= 0:
		return _fail("invalid_capital", "企业注资对象或金额无效")
	var transfer: Dictionary = _economy.ledger.transfer(
		idempotency_key,
		total_hour,
		investor_id,
		organization_id,
		amount_centimes,
		"enterprise_capital",
		"fact:capital:%s:%d" % [organization_id, total_hour],
		"企业注资"
	)
	if bool(transfer.get("success", false)):
		state["capital_contributed_centimes"] = (
			int(state.get("capital_contributed_centimes", 0)) + amount_centimes
		)
		enterprises[organization_id] = state
	return transfer


func purchase_enterprise_share(
	idempotency_key: String,
	organization_id: String,
	seller_id: String,
	buyer_id: String,
	share_bp: int,
	price_centimes: int,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or not bool(state.get("purchasable", false)):
		return _fail("enterprise_not_purchasable", "该企业当前不可购买")
	var equity_id: String = str(state.get("equity_asset_id", ""))
	var sold: Dictionary = _economy.assets.sell(
		idempotency_key,
		total_hour,
		equity_id,
		seller_id,
		buyer_id,
		price_centimes,
		share_bp
	)
	if bool(sold.get("success", false)) and share_bp >= 5001:
		state["controller_id"] = buyer_id
		enterprises[organization_id] = state
	return sold


func establish_partnership(
	idempotency_key: String,
	organization_id: String,
	current_owner_id: String,
	partner_id: String,
	contribution_centimes: int,
	share_bp: int,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if (
		state.is_empty()
		or contribution_centimes <= 0
		or share_bp <= 0
		or share_bp >= 5000
	):
		return _fail("invalid_partnership", "合伙投入或份额无效")
	var contract_result: Dictionary = _economy.contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:partnership",
		[
			{"party_id": current_owner_id, "role": "managing_partner"},
			{"party_id": partner_id, "role": "partner"},
			{"party_id": organization_id, "role": "enterprise"},
		],
		{"organization_id": organization_id, "share_bp": share_bp},
		contribution_centimes,
		total_hour,
		total_hour + 365 * 24,
		{
			"contribution_centimes": contribution_centimes,
			"profit_share_bp": share_bp,
			"liability_share_bp": share_bp,
			"document_ids": ["document:partnership:%s" % organization_id],
		}
	)
	if not bool(contract_result.get("success", false)):
		return contract_result
	var contract: Dictionary = (contract_result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	var activated: Dictionary = _economy.contracts.activate(
		"activate:%s" % idempotency_key, contract_id, total_hour
	)
	if not bool(activated.get("success", false)):
		return activated
	var contribution: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		partner_id,
		organization_id,
		contribution_centimes,
		"partnership_contribution",
		"fact:partnership:%s" % contract_id,
		"合伙人投入"
	)
	if not bool(contribution.get("success", false)):
		return contribution
	var share_transfer: Dictionary = _economy.assets.transfer_share(
		idempotency_key,
		str(state.get("equity_asset_id", "")),
		current_owner_id,
		partner_id,
		share_bp
	)
	if not bool(share_transfer.get("success", false)):
		return share_transfer
	(state["contract_ids"] as Array).append(contract_id)
	enterprises[organization_id] = state
	return _ok({"contract": _economy.contracts.contracts[contract_id], "enterprise": state.duplicate(true)})


func borrow_for_operations(
	idempotency_key: String,
	organization_id: String,
	lender_id: String,
	amount_centimes: int,
	total_hour: int,
	collateral_asset_ids: Array = []
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty():
		return _fail("enterprise_missing", "借款企业不存在")
	var product_id: String = (
		"credit:asset_mortgage"
		if not collateral_asset_ids.is_empty()
		else "credit:enterprise_operating"
	)
	var applied: Dictionary = _economy.apply_for_loan(
		"apply:%s" % idempotency_key,
		organization_id,
		lender_id,
		product_id,
		amount_centimes,
		total_hour,
		collateral_asset_ids,
		[],
		{"existing_debt_centimes": _economy.total_debt(organization_id)}
	)
	if not bool(applied.get("success", false)):
		return applied
	var application: Dictionary = (applied.get("data", {}) as Dictionary).get(
		"application", {}
	) as Dictionary
	var application_id: String = str(application.get("application_id", ""))
	var reviewed: Dictionary = _economy.review_application(
		"review:%s" % idempotency_key, application_id, total_hour
	)
	if not bool(reviewed.get("success", false)):
		return reviewed
	var reviewed_application: Dictionary = (
		reviewed.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	if str(reviewed_application.get("status", "")) != "offered":
		return _fail("enterprise_credit_rejected", "企业信用审查拒绝了借款")
	var accepted: Dictionary = _economy.accept_loan_offer(
		idempotency_key, application_id, total_hour
	)
	if bool(accepted.get("success", false)):
		var contract: Dictionary = (accepted.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary
		(state["contract_ids"] as Array).append(str(contract.get("contract_id", "")))
		enterprises[organization_id] = state
	return accepted


func accept_order(
	idempotency_key: String,
	organization_id: String,
	client_id: String,
	quantity: int,
	destination_region_id: String,
	total_hour: int,
	transport_days: int = 0
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if (
		state.is_empty()
		or str(state.get("status", "")) not in ACTIVE_ENTERPRISE_STATUSES
	):
		return _fail("enterprise_not_operating", "企业当前不能接受订单")
	var order: Dictionary = _economy.create_trade(
		idempotency_key,
		client_id,
		organization_id,
		str(state.get("product_id", "")),
		quantity,
		str(state.get("region_id", "")),
		destination_region_id,
		total_hour,
		transport_days
	)
	if bool(order.get("success", false)):
		var contract: Dictionary = (order.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary
		var contract_id: String = str(contract.get("contract_id", ""))
		(state["order_contract_ids"] as Array).append(contract_id)
		(state["contract_ids"] as Array).append(contract_id)
		state["status"] = "contracting"
		enterprises[organization_id] = state
	return order


func procure_inputs(
	idempotency_key: String,
	organization_id: String,
	supplier_id: String,
	quantity: int,
	supplier_region_id: String,
	total_hour: int,
	transport_days: int = 0
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or quantity <= 0:
		return _fail("invalid_procurement", "采购企业或数量无效")
	var trade: Dictionary = _economy.create_trade(
		"trade:%s" % idempotency_key,
		organization_id,
		supplier_id,
		str(state.get("input_id", "")),
		quantity,
		supplier_region_id,
		str(state.get("region_id", "")),
		total_hour,
		transport_days
	)
	if not bool(trade.get("success", false)):
		return trade
	var contract: Dictionary = (trade.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	var settled: Dictionary = _economy.settle_trade(
		idempotency_key, contract_id, total_hour + transport_days * 24
	)
	if not bool(settled.get("success", false)):
		return settled
	state["input_inventory_units"] = int(state.get("input_inventory_units", 0)) + quantity
	(state["contract_ids"] as Array).append(contract_id)
	enterprises[organization_id] = state
	return _ok({"contract": _economy.contracts.contracts[contract_id], "enterprise": state.duplicate(true)})


func produce(
	idempotency_key: String,
	organization_id: String,
	quantity: int,
	total_hour: int,
	executor_id: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"enterprise": (enterprises.get(organization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if (
		state.is_empty()
		or quantity <= 0
		or int(state.get("input_inventory_units", 0)) < quantity
		or quantity > int(state.get("capacity_units_per_day", 0))
	):
		return _fail("production_unavailable", "投入品或执行能力不足")
	state["input_inventory_units"] = int(state["input_inventory_units"]) - quantity
	state["finished_inventory_units"] = (
		int(state.get("finished_inventory_units", 0)) + quantity
	)
	state["last_production_fact"] = {
		"fact_id": "fact:production:%s" % idempotency_key,
		"executor_id": executor_id,
		"quantity": quantity,
		"total_hour": total_hour,
	}
	enterprises[organization_id] = state
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true), "duplicate": false})


func deliver_order(
	idempotency_key: String,
	organization_id: String,
	contract_id: String,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	var contract: Dictionary = _economy.contracts.contracts.get(contract_id, {}) as Dictionary
	var subject: Dictionary = contract.get("subject", {}) as Dictionary
	var quantity: int = int(subject.get("quantity", 0))
	if (
		state.is_empty()
		or contract_id not in state.get("order_contract_ids", [])
		or int(state.get("finished_inventory_units", 0)) < quantity
	):
		return _fail("order_delivery_unavailable", "产成品不足或订单不属于该企业")
	var settled: Dictionary = _economy.settle_trade(
		idempotency_key, contract_id, total_hour
	)
	if not bool(settled.get("success", false)):
		return settled
	state["finished_inventory_units"] = int(state["finished_inventory_units"]) - quantity
	state["completed_orders"] = int(state.get("completed_orders", 0)) + 1
	state["status"] = "operating"
	enterprises[organization_id] = state
	return _ok({"contract": _economy.contracts.contracts[contract_id], "enterprise": state.duplicate(true)})


func outsource_service(
	idempotency_key: String,
	organization_id: String,
	provider_id: String,
	service_name: String,
	price_centimes: int,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or price_centimes <= 0:
		return _fail("invalid_outsource", "外包服务对象或价格无效")
	var result: Dictionary = _economy.contracts.create_contract(
		"contract:%s" % idempotency_key,
		"contract_template:service",
		[
			{"party_id": organization_id, "role": "client"},
			{"party_id": provider_id, "role": "provider"},
		],
		{"service_name": service_name},
		price_centimes,
		total_hour,
		total_hour + 30 * 24,
		{"document_ids": ["document:outsource:%s" % idempotency_key]}
	)
	if not bool(result.get("success", false)):
		return result
	var contract: Dictionary = (result.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var contract_id: String = str(contract.get("contract_id", ""))
	_economy.contracts.activate("activate:%s" % idempotency_key, contract_id, total_hour)
	var payment: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		organization_id,
		provider_id,
		price_centimes,
		"professional_service",
		"fact:service:%s" % contract_id,
		"购买专业服务"
	)
	if not bool(payment.get("success", false)):
		return payment
	_economy.contracts.record_delivery(
		"delivery:%s" % idempotency_key,
		contract_id,
		total_hour,
		10000,
		"evidence:service:%s" % contract_id
	)
	var transaction: Dictionary = (payment.get("data", {}) as Dictionary).get(
		"transaction", {}
	) as Dictionary
	var recorded: Dictionary = _economy.contracts.record_payment(
		idempotency_key,
		contract_id,
		total_hour,
		str(transaction.get("transaction_id", "")),
		price_centimes
	)
	if bool(recorded.get("success", false)):
		(state["contract_ids"] as Array).append(contract_id)
		enterprises[organization_id] = state
	return recorded


func hire(
	idempotency_key: String,
	organization_id: String,
	person_id: String,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty():
		return _fail("enterprise_missing", "雇主企业不存在")
	var job_id: String = "job:enterprise:%s" % organization_id
	if not _labor.jobs.has(job_id):
		_register_enterprise_job(state)
	var hired: Dictionary = _labor.direct_hire(
		idempotency_key, person_id, job_id, total_hour
	)
	if bool(hired.get("success", false)):
		var contract: Dictionary = (hired.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary
		var contract_id: String = str(contract.get("contract_id", ""))
		if person_id not in state.get("employee_ids", []):
			(state["employee_ids"] as Array).append(person_id)
		(state["employment_contract_ids"] as Array).append(contract_id)
		(state["contract_ids"] as Array).append(contract_id)
		enterprises[organization_id] = state
	return hired


func set_price_policy(
	idempotency_key: String, organization_id: String, markup_bp: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"enterprise": (enterprises.get(organization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or markup_bp < -5000 or markup_bp > 20000:
		return _fail("invalid_price_policy", "企业定价幅度无效")
	var policies: Dictionary = state.get("operating_policies", {}) as Dictionary
	policies["markup_bp"] = markup_bp
	state["operating_policies"] = policies
	enterprises[organization_id] = state
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true)})


func expand(
	idempotency_key: String,
	organization_id: String,
	investment_centimes: int,
	additional_capacity: int,
	vendor_id: String,
	total_hour: int
) -> Dictionary:
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or investment_centimes <= 0 or additional_capacity <= 0:
		return _fail("invalid_expansion", "扩张投入或执行能力无效")
	var payment: Dictionary = _economy.ledger.transfer(
		"ledger:%s" % idempotency_key,
		total_hour,
		organization_id,
		vendor_id,
		investment_centimes,
		"enterprise_expansion",
		"fact:expansion:%s:%d" % [organization_id, total_hour],
		"企业扩张设备投资"
	)
	if not bool(payment.get("success", false)):
		return payment
	var asset_id: String = _create_operating_asset(
		organization_id,
		"equipment",
		investment_centimes,
		{"capacity_units": additional_capacity}
	)
	if asset_id.is_empty():
		return _fail("expansion_asset_failed", "扩张设备登记失败")
	(state["asset_ids"] as Array).append(asset_id)
	state["capacity_units_per_day"] = (
		int(state.get("capacity_units_per_day", 0)) + additional_capacity
	)
	enterprises[organization_id] = state
	return _ok({"enterprise": state.duplicate(true), "asset_id": asset_id})


func shrink(
	idempotency_key: String, organization_id: String, capacity_reduction: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"enterprise": (enterprises.get(organization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or capacity_reduction <= 0:
		return _fail("invalid_contraction", "收缩幅度无效")
	state["capacity_units_per_day"] = maxi(
		1, int(state.get("capacity_units_per_day", 1)) - capacity_reduction
	)
	state["status"] = "distressed"
	enterprises[organization_id] = state
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true)})


func aggregate_day(
	idempotency_key: String, organization_id: String, total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"enterprise": (enterprises.get(organization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if (
		state.is_empty()
		or str(state.get("status", "")) not in ACTIVE_ENTERPRISE_STATUSES
	):
		return _fail("enterprise_not_operating", "企业不处于可结算状态")
	var distress: int = int(state.get("distress", 0))
	var capacity: int = int(state.get("capacity_units_per_day", 1))
	var base_price: int = _economy.market_price(
		str(state.get("region_id", "")), str(state.get("product_id", ""))
	)
	var revenue: int = maxi(0, base_price * capacity * (100 - distress) / 250)
	var cost: int = (
		maxi(1, int(state.get("background_employee_count", 0))) * 35
		+ base_price * capacity / 5
	)
	var net: int = revenue - cost
	var ledger_result: Dictionary
	if net >= 0:
		ledger_result = _economy.ledger.transfer(
			"ledger:%s" % idempotency_key,
			total_hour,
			AGGREGATE_MARKET_ID,
			organization_id,
			net,
			"aggregate_enterprise_profit",
			"fact:aggregate_day:%s:%d" % [organization_id, total_hour],
			"背景企业日结利润"
		)
	else:
		ledger_result = _economy.ledger.transfer(
			"ledger:%s" % idempotency_key,
			total_hour,
			organization_id,
			AGGREGATE_MARKET_ID,
			-net,
			"aggregate_enterprise_loss",
			"fact:aggregate_day:%s:%d" % [organization_id, total_hour],
			"背景企业日结亏损"
		)
	if not bool(ledger_result.get("success", false)):
		state["distress"] = mini(100, distress + 4)
		state["status"] = "distressed"
	else:
		state["distress"] = clampi(distress - 1 if net >= 0 else distress + 1, 0, 100)
	state["last_day_net_centimes"] = net
	state["last_settlement_hour"] = total_hour
	state["operating_days"] = int(state.get("operating_days", 0)) + 1
	enterprises[organization_id] = state
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true), "net_centimes": net})


func bankrupt(
	idempotency_key: String,
	organization_id: String,
	total_hour: int,
	reason: String
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"enterprise": (enterprises.get(organization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if (
		state.is_empty()
		or str(state.get("status", "")) in ["bankrupt", "dissolved"]
	):
		return _fail("invalid_bankruptcy", "企业不存在或已经退出")
	var creditor_id: String = AGGREGATE_MARKET_ID
	var defaulted_contract_ids: Array[String] = []
	for contract: Dictionary in _economy.contracts.contracts_for_party(organization_id, false):
		var contract_id: String = str(contract.get("contract_id", ""))
		var contract_type: String = str(contract.get("contract_type", ""))
		if contract_type == "loan" and _party_with_role(contract, "borrower") == organization_id:
			creditor_id = _party_with_role(contract, "creditor")
			var defaulted: Dictionary = _economy.contracts.default_contract(
				"default:%s:%s" % [idempotency_key, contract_id],
				contract_id,
				total_hour,
				reason
			)
			if bool(defaulted.get("success", false)):
				defaulted_contract_ids.append(contract_id)
			elif str(contract.get("status", "")) == "defaulted":
				defaulted_contract_ids.append(contract_id)
			elif str(contract.get("status", "")) not in ["fulfilled", "settled", "enforced"]:
				return defaulted
		elif contract_type in ["order", "sale", "service"]:
			_economy.contracts.default_contract(
				"default:%s:%s" % [idempotency_key, contract_id],
				contract_id,
				total_hour,
				"企业破产导致未履约"
			)
	for employment_id: String in DataRecordUtils.to_string_array(
		state.get("employment_contract_ids", [])
	):
		if _labor.employment_states.has(employment_id):
			_labor.dismiss(
				"dismiss:%s:%s" % [idempotency_key, employment_id],
				employment_id,
				total_hour,
				"企业破产"
			)
	var disposed_asset_ids: Array[String] = []
	for asset_id: String in DataRecordUtils.to_string_array(state.get("asset_ids", [])):
		var asset: Dictionary = _economy.assets.assets.get(asset_id, {}) as Dictionary
		if asset.is_empty() or str(asset.get("status", "")) in ["closed", "bankruptcy_disposed"]:
			continue
		var disposed: Dictionary = _economy.assets.dispose_in_bankruptcy(
			"dispose:%s:%s" % [idempotency_key, asset_id], asset_id, creditor_id
		)
		if bool(disposed.get("success", false)):
			disposed_asset_ids.append(asset_id)
	state["status"] = "bankrupt"
	state["bankruptcy_hour"] = total_hour
	state["bankruptcy_reason"] = reason
	state["controller_id"] = creditor_id
	state["distress"] = 100
	state["defaulted_contract_ids"] = defaulted_contract_ids
	state["disposed_asset_ids"] = disposed_asset_ids
	enterprises[organization_id] = state
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true)})


func dissolve(
	idempotency_key: String, organization_id: String, total_hour: int
) -> Dictionary:
	if _processed_keys.has(idempotency_key):
		return _ok({"enterprise": (enterprises.get(organization_id, {}) as Dictionary).duplicate(true), "duplicate": true})
	var state: Dictionary = enterprises.get(organization_id, {}) as Dictionary
	if state.is_empty() or str(state.get("status", "")) != "bankrupt":
		return _fail("dissolution_unavailable", "企业必须先完成破产或清算")
	state["status"] = "dissolved"
	state["dissolved_hour"] = total_hour
	state["capacity_units_per_day"] = 0
	state["employee_ids"] = []
	state["background_employee_count"] = 0
	enterprises[organization_id] = state
	_processed_keys[idempotency_key] = organization_id
	return _ok({"enterprise": state.duplicate(true)})


func validate_integrity() -> Dictionary:
	for raw_enterprise: Variant in enterprises.values():
		var state: Dictionary = raw_enterprise as Dictionary
		var organization_id: String = str(state.get("organization_id", ""))
		if (
			organization_id.is_empty()
			or _organizations.get_organization(organization_id) == null
			or _economy.ledger.cash_account_id(organization_id).is_empty()
			or not _economy.assets.assets.has(str(state.get("equity_asset_id", "")))
		):
			return _fail("enterprise_reference_missing", "企业组织、账本或权益引用不闭合")
		for contract_id: String in DataRecordUtils.to_string_array(
			state.get("contract_ids", [])
		):
			if not _economy.contracts.contracts.has(contract_id):
				return _fail("enterprise_contract_missing", "企业合同引用不闭合")
		for asset_id: String in DataRecordUtils.to_string_array(state.get("asset_ids", [])):
			if not _economy.assets.assets.has(asset_id):
				return _fail("enterprise_asset_missing", "企业资产引用不闭合")
	return _ok({"enterprise_count": enterprises.size()})


func get_persistent_state() -> Dictionary:
	return {
		"enterprises": enterprises.duplicate(true),
		"processed_keys": _processed_keys.duplicate(true),
		"next_enterprise_sequence": _next_enterprise_sequence,
	}


func restore_persistent_state(state: Dictionary) -> bool:
	if not state.get("enterprises", {}) is Dictionary:
		return false
	enterprises = (state["enterprises"] as Dictionary).duplicate(true)
	_processed_keys = (state.get("processed_keys", {}) as Dictionary).duplicate(true)
	_next_enterprise_sequence = int(state.get("next_enterprise_sequence", 0))
	return (
		_next_enterprise_sequence >= 1
		and bool(validate_integrity().get("success", false))
	)


func _bootstrap_enterprise(record: Dictionary, start_hour: int) -> bool:
	var organization_id: String = str(record.get("organization_id", ""))
	var region_id: String = str(record.get("region_id", ""))
	if (
		organization_id.is_empty()
		or not _region_country.has(region_id)
		or enterprises.has(organization_id)
	):
		return false
	if _organizations.get_organization(organization_id) == null:
		if not _register_enterprise_organization(
			organization_id,
			str(record.get("name", organization_id)),
			str(_region_country[region_id]),
			region_id
		):
			return false
	var state: Dictionary = _new_enterprise_state(record)
	var registered: Dictionary = _economy.register_entity(
		organization_id,
		"organization",
		int(record.get("opening_cash", 0)),
		{
			"income_monthly_centimes": int(record.get("opening_cash", 0)) / 2,
			"reputation": 100 - int(record.get("distress", 0)) / 2,
			"region_id": region_id,
		}
	)
	if not bool(registered.get("success", false)):
		return false
	var owner_id: String = "owner:%s" % organization_id
	if not _economy.entity_profiles.has(owner_id):
		if not bool(_economy.register_entity(
			owner_id, "person", 5000, {"region_id": region_id, "reputation": 55}
		).get("success", false)):
			return false
	var equity: Dictionary = _economy.assets.create_asset(
		"equity:opening:%s" % organization_id,
		"enterprise_equity",
		owner_id,
		owner_id,
		maxi(0, int(record.get("opening_cash", 0)) - int(record.get("opening_debt", 0))),
		{"organization_id": organization_id},
		"asset:equity:%s" % organization_id
	)
	if not bool(equity.get("success", false)):
		return false
	state["equity_asset_id"] = "asset:equity:%s" % organization_id
	state["controller_id"] = owner_id
	var equipment_id: String = _create_operating_asset(
		organization_id,
		"equipment",
		maxi(3000, int(record.get("employees", 0)) * 500),
		{"capacity_units": int(state.get("capacity_units_per_day", 0))}
	)
	if equipment_id.is_empty():
		return false
	(state["asset_ids"] as Array).append(equipment_id)
	var inventory_id: String = _create_operating_asset(
		organization_id,
		"inventory",
		2000,
		{
			"input_id": record.get("input_id", ""),
			"product_id": record.get("product_id", ""),
			"input_units": int(state.get("input_inventory_units", 0)),
			"finished_units": int(state.get("finished_inventory_units", 0)),
		}
	)
	if inventory_id.is_empty():
		return false
	(state["asset_ids"] as Array).append(inventory_id)
	if str(record.get("structure", "")) == "logistics":
		var vehicle_id: String = _create_operating_asset(
			organization_id,
			"vehicle",
			6000,
			{"freight_capacity": 20}
		)
		if vehicle_id.is_empty():
			return false
		(state["asset_ids"] as Array).append(vehicle_id)
	enterprises[organization_id] = state
	var opening_debt: int = int(record.get("opening_debt", 0))
	if opening_debt > 0:
		var lender_id: String = (
			"organization:loran_public_credit"
			if str(_region_country[region_id]).contains("loran")
			else "organization:vesta_public_credit"
		)
		var debt: Dictionary = _economy.create_opening_debt(
			"opening_debt:%s" % organization_id,
			organization_id,
			lender_id,
			opening_debt,
			"credit:enterprise_operating",
			start_hour
		)
		if not bool(debt.get("success", false)):
			return false
		var contract: Dictionary = (debt.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary
		(state["contract_ids"] as Array).append(str(contract.get("contract_id", "")))
		enterprises[organization_id] = state
	_register_enterprise_job(state)
	return true


func _new_enterprise_state(record: Dictionary) -> Dictionary:
	var employees: int = int(record.get("employees", 0))
	var distress: int = int(record.get("distress", 0))
	return {
		"organization_id": str(record.get("organization_id", "")),
		"name": str(record.get("name", "")),
		"structure": str(record.get("structure", "")),
		"region_id": str(record.get("region_id", "")),
		"city_id": str(record.get("city_id", "")),
		"product_id": str(record.get("product_id", "")),
		"input_id": str(record.get("input_id", "")),
		"controller_id": "",
		"equity_asset_id": "",
		"asset_ids": [],
		"contract_ids": [],
		"order_contract_ids": [],
		"employment_contract_ids": [],
		"employee_ids": [],
		"background_employee_count": employees,
		"supplier_ids": [],
		"customer_ids": [],
		"input_inventory_units": maxi(4, employees / 2),
		"finished_inventory_units": maxi(2, employees / 4),
		"capacity_units_per_day": maxi(4, employees / 2),
		"execution_capacity": maxi(20, 100 - distress / 2),
		"operating_policies": {"markup_bp": 1800, "reserve_days": 20},
		"current_risks": ["cash_shortage"] if distress >= 70 else [],
		"distress": distress,
		"status": "distressed" if distress >= 75 else "operating",
		"purchasable": bool(record.get("purchasable", false)),
		"completed_orders": 0,
		"operating_days": 0,
		"capital_contributed_centimes": int(record.get("opening_cash", 0)),
	}


func _register_enterprise_organization(
	organization_id: String,
	name: String,
	country_id: String,
	region_id: String
) -> bool:
	var organization := OrganizationData.from_dict({
		"id": organization_id,
		"name": name,
		"type": "enterprise",
		"country_id": country_id,
		"region_id": region_id,
		"size": 1.0,
		"resources": 0.0,
		"influence": 0.05,
		"public_stance": "commercial",
		"leader_character_id": "",
		"member_ids": [],
		"position_structure": {
			"entry_position": "employee",
			"leader_position": "director",
			"positions": {
				"employee": {
					"name": "雇员",
					"level": 1,
					"slots": 64,
					"permissions": [],
					"holder_ids": [],
				},
				"manager": {
					"name": "经理",
					"level": 2,
					"slots": 8,
					"permissions": ["manage_staff", "use_operating_budget"],
					"holder_ids": [],
				},
				"director": {
					"name": "负责人",
					"level": 3,
					"slots": 1,
					"permissions": [
						"manage_staff",
						"use_operating_budget",
						"sign_contract",
						"appoint_manager",
					],
					"holder_ids": [],
				},
			},
		},
		"organization_relations": {},
	})
	return _organizations.register_runtime_organization(organization)


func _register_enterprise_job(state: Dictionary) -> void:
	var organization_id: String = str(state.get("organization_id", ""))
	var job_id: String = "job:enterprise:%s" % organization_id
	if _labor.jobs.has(job_id):
		return
	_labor.register_runtime_job({
		"job_id": job_id,
		"name": "企业执行人员",
		"category": "commercial",
		"employer_id": organization_id,
		"city_id": str(state.get("city_id", "")),
		"wage": 1800,
		"hours_per_week": 42,
		"skill": "administration",
		"qualification": "",
		"risk": 18,
		"promotion": "manager",
		"dismissal": "absence_or_low_quality",
		"part_time": false,
	})


func _create_operating_asset(
	organization_id: String,
	asset_type: String,
	value_centimes: int,
	attributes: Dictionary
) -> String:
	var result: Dictionary = _economy.assets.create_asset(
		"asset:%s:%s:%d" % [
			organization_id, asset_type, _economy.assets.assets.size(),
		],
		asset_type,
		organization_id,
		organization_id,
		value_centimes,
		attributes
	)
	if not bool(result.get("success", false)):
		return ""
	var asset: Dictionary = (result.get("data", {}) as Dictionary).get("asset", {}) as Dictionary
	return str(asset.get("asset_id", ""))


static func _party_with_role(contract: Dictionary, role: String) -> String:
	for party: Dictionary in contract.get("parties", []) as Array[Dictionary]:
		if str(party.get("role", "")) == role:
			return str(party.get("party_id", ""))
	return ""


static func _ok(data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": "", "data": data}


static func _fail(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}
