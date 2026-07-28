extends SceneTree

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "Alpha配置可加载")
	var economy := AlphaEconomyService.new()
	test.expect(economy.configure(config), "统一经济服务可初始化")
	var market := AlphaCommodityMarketService.new()
	test.expect(market.configure(config), "商品市场可初始化")
	var labor := AlphaLaborService.new()
	test.expect(labor.configure(config, economy), "劳动服务可初始化")
	var organizations := OrganizationService.new([])
	var enterprise := AlphaEnterpriseService.new()
	test.expect(
		enterprise.configure(config, economy, labor, organizations, 0),
		"企业服务可初始化"
	)
	var closure := AlphaEconomicClosureService.new()
	test.expect(
		closure.configure(economy, market, enterprise, labor),
		"经济闭环服务可初始化"
	)
	var integrity := closure.validate_integrity()
	test.expect(bool(integrity.get("success", false)), "地区、企业和运输索引完整")
	test.equal(
		closure.site_finance.size(), market.production_sites.size(),
		"每个生产设施绑定企业财务账户"
	)
	test.equal(
		closure.route_neighbors.size(), market.region_states.size(),
		"每个地区进入稀疏运输网络"
	)
	var initial_transactions := economy.ledger.transactions.size()
	for day: int in range(1, 31):
		var hour := day * 24 - 1
		var market_result := market.settle_day(hour)
		test.expect(bool(market_result.get("success", false)), "商品市场日结成功：%d" % day)
		var closure_result := closure.settle_day(hour)
		test.expect(bool(closure_result.get("success", false)), "经济闭环日结成功：%d" % day)
	var ledger_validation := economy.ledger.validate_balances()
	test.expect(bool(ledger_validation.get("success", false)), "现金账本保持双重记账平衡")
	test.expect(economy.ledger.transactions.size() > initial_transactions, "居民消费、工资和维护形成现金交易")
	test.expect(not closure.daily_history.is_empty(), "经济闭环保留日结历史")
	test.expect(closure.in_transit.size() > 0, "邻接网络形成在途运输")
	test.expect(closure.bilateral_trade.size() > 0, "国际流量形成双边贸易记录")
	var persistent := closure.get_persistent_state()
	var restored := AlphaEconomicClosureService.new()
	test.expect(restored.configure(economy, market, enterprise, labor), "恢复目标服务可初始化")
	test.expect(restored.restore_persistent_state(persistent), "经济闭环状态可恢复")
	test.equal(restored.in_transit.size(), closure.in_transit.size(), "在途运输存档一致")
	test.equal(restored.site_finance.size(), closure.site_finance.size(), "企业财务存档一致")
	test.finish(self, "Alpha economic closure")
