extends SceneTree
## Alpha B-stage ledger, asset, contract, debt and market lifecycle regression.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "Alpha 经济配置可载入")
	var economy := AlphaEconomyService.new()
	test.expect(economy.configure(config), "统一经济服务完成配置")
	for registration: Dictionary in [
		economy.register_entity(
			"person:borrower",
			"person",
			12000,
			{
				"income_monthly_centimes": 6000,
				"reputation": 76,
				"relationship_with_lender": 40,
				"region_id": "region:loran_dawnbay",
			}
		),
		economy.register_entity("person:buyer", "person", 50000),
		economy.register_entity("organization:seller", "organization", 10000),
		economy.register_entity("organization:life_provider", "organization", 10000),
	]:
		test.expect(bool(registration.get("success", false)), "正式对象取得现金账户和现金资产")
	var equipment_result: Dictionary = economy.assets.create_asset(
		"asset:test:equipment",
		"equipment",
		"person:borrower",
		"person:borrower",
		24000,
		{"location_id": "location:dawnharbor:workplace"}
	)
	test.expect(bool(equipment_result.get("success", false)), "设备资产区分所有权与控制权")
	var equipment: Dictionary = (equipment_result.get("data", {}) as Dictionary).get(
		"asset", {}
	) as Dictionary
	var equipment_id: String = str(equipment.get("asset_id", ""))
	var application_result: Dictionary = economy.apply_for_loan(
		"application:test:secured",
		"person:borrower",
		"organization:loran_public_credit",
		"credit:personal_secured",
		10000,
		0,
		[equipment_id],
		[],
		{"existing_debt_centimes": 0}
	)
	test.expect(bool(application_result.get("success", false)), "人物可申请有抵押借款")
	var application: Dictionary = (
		application_result.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	var application_id: String = str(application.get("application_id", ""))
	var review: Dictionary = economy.review_application(
		"review:test:secured", application_id, 1
	)
	test.expect(bool(review.get("success", false)), "信用审查读取收入资产关系地区和抵押")
	test.equal(
		str(((review.get("data", {}) as Dictionary).get(
			"application", {}
		) as Dictionary).get("status", "")),
		"offered",
		"充分信用条件形成可接受借款条件"
	)
	var cash_before_loan: int = economy.ledger.owner_cash("person:borrower")
	var accepted: Dictionary = economy.accept_loan_offer(
		"accept:test:secured", application_id, 2
	)
	test.expect(bool(accepted.get("success", false)), "接受条件同时建立合同、债权资产并放款")
	var loan: Dictionary = (accepted.get("data", {}) as Dictionary).get(
		"contract", {}
	) as Dictionary
	var loan_id: String = str(loan.get("contract_id", ""))
	test.equal(
		economy.ledger.owner_cash("person:borrower"),
		cash_before_loan + 10000,
		"放款只经正式账本增加借款人现金"
	)
	test.equal(economy.total_debt("person:borrower"), 10000, "债务余额来自借款合同")
	var duplicate_accept: Dictionary = economy.accept_loan_offer(
		"accept:test:secured", application_id, 2
	)
	test.expect(
		bool(duplicate_accept.get("success", false))
		and bool((duplicate_accept.get("data", {}) as Dictionary).get("duplicate", false)),
		"重复放款幂等返回且不重复产生现金"
	)
	test.equal(
		economy.ledger.owner_cash("person:borrower"),
		cash_before_loan + 10000,
		"重复接受借款不重复放款"
	)
	var interest: Dictionary = economy.accrue_loan_interest(
		"interest:test:secured:30", loan_id, 30 * 24, 30
	)
	test.expect(bool(interest.get("success", false)), "借款按正式合同计息")
	var debt_after_interest: int = economy.total_debt("person:borrower")
	test.expect(debt_after_interest > 10000, "利息形成可追踪应付余额")
	var repayment: Dictionary = economy.repay_loan(
		"repay:test:secured:partial", loan_id, 31 * 24, 3200
	)
	test.expect(bool(repayment.get("success", false)), "借款支持分期和提前部分偿还")
	test.expect(
		economy.total_debt("person:borrower") < debt_after_interest,
		"还款同步降低合同余额和债权资产"
	)
	var contract_after_payment: Dictionary = economy.contracts.contracts[loan_id] as Dictionary
	var original_end: int = int(contract_after_payment.get("end_hour", 0))
	test.expect(
		bool(economy.mark_loan_overdue(
			"overdue:test:secured:first", loan_id, original_end + 1
		).get("success", false)),
		"到期未清借款进入逾期"
	)
	test.expect(
		bool(economy.restructure_loan(
			"restructure:test:secured", loan_id, original_end + 2, 45, 1200
		).get("success", false)),
		"逾期借款可重组且不清除余额"
	)
	var debt_after_restructure: int = economy.total_debt("person:borrower")
	test.expect(debt_after_restructure > 0, "债务重组保留未偿余额")
	var new_end: int = int(
		(economy.contracts.contracts[loan_id] as Dictionary).get("end_hour", 0)
	)
	test.expect(
		bool(economy.mark_loan_overdue(
			"overdue:test:secured:second", loan_id, new_end + 1
		).get("success", false)),
		"重组后再次到期仍可逾期"
	)
	test.expect(
		bool(economy.default_loan(
			"default:test:secured", loan_id, new_end + 2, "未能履行重组条件"
		).get("success", false)),
		"逾期借款可正式违约"
	)
	test.expect(
		bool(economy.seize_collateral(
			"seize:test:secured", loan_id, new_end + 3
		).get("success", false)),
		"违约借款可处置具体抵押物"
	)
	test.equal(
		str((economy.assets.assets[equipment_id] as Dictionary).get("status", "")),
		"bankruptcy_disposed",
		"抵押处置改变资产所有权和状态"
	)
	var trade_result: Dictionary = economy.create_trade(
		"trade:test:interregional",
		"person:buyer",
		"organization:seller",
		"machinery",
		3,
		"region:loran_riverback",
		"region:vesta_silverfield",
		100,
		4
	)
	test.expect(bool(trade_result.get("success", false)), "跨地区订单形成价格、运输费和交付期限")
	var trade_contract: Dictionary = (
		trade_result.get("data", {}) as Dictionary
	).get("contract", {}) as Dictionary
	var trade_id: String = str(trade_contract.get("contract_id", ""))
	test.expect(
		bool(economy.settle_trade(
			"settle:test:interregional", trade_id, 100 + 4 * 24
		).get("success", false)),
		"订单交付和付款经合同与账本完成"
	)
	test.equal(
		str((economy.contracts.contracts[trade_id] as Dictionary).get("status", "")),
		"fulfilled",
		"买卖合同形成完整履行终态"
	)
	var buyer_cash_before_life: int = economy.ledger.owner_cash("person:buyer")
	test.expect(
		bool(economy.pay_life_costs(
			"life:test:budget",
			"person:buyer",
			"organization:life_provider",
			200,
			500,
			700,
			180,
			120,
			100
		).get("success", false)),
		"生活、住房、交通、发展和税费可聚合自动结算"
	)
	test.equal(
		economy.ledger.owner_cash("person:buyer"),
		buyer_cash_before_life - 1600,
		"生活预算只在正式账本形成一次支出"
	)
	var before_shock: int = economy.market_price("region:vesta_redhill", "grain")
	test.expect(
		bool(economy.apply_market_shock(
			"shock:test:grain",
			"region:vesta_redhill",
			"grain",
			2500,
			30,
			"铁路中断",
			300
		).get("success", false)),
		"外部事件可改变地区商品价格"
	)
	test.expect(
		economy.market_price("region:vesta_redhill", "grain") > before_shock,
		"地区短缺实际提高正式价格"
	)
	var integrity: Dictionary = economy.validate_integrity()
	test.expect(bool(integrity.get("success", false)), "账本、资产、合同和债务引用闭合")
	var saved: Dictionary = economy.get_persistent_state()
	var restored := AlphaEconomyService.new()
	test.expect(restored.configure(config), "恢复目标经济服务可配置")
	test.expect(restored.restore_persistent_state(saved), "经济状态可完整保存恢复")
	test.equal(
		restored.ledger.owner_cash("person:borrower"),
		economy.ledger.owner_cash("person:borrower"),
		"恢复后现金与账本一致"
	)
	test.equal(
		restored.contracts.outstanding(loan_id),
		economy.contracts.outstanding(loan_id),
		"恢复后债务合同余额一致"
	)
	test.expect(
		bool(restored.validate_integrity().get("success", false)),
		"恢复后跨对象引用仍然闭合"
	)
	test.finish(self, "Alpha economy lifecycle")
