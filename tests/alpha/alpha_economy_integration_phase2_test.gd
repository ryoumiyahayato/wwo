extends SceneTree
## Unified physical goods, cash ledger, enterprise, labor and sparse logistics regression.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := AlphaSimulationService.new()
	test.expect(simulation.initialize(), "统一经济模拟可初始化")
	if not simulation.initialized:
		test.finish(self, "Alpha economy integration phase two")
		return

	var integration := simulation.economy_integration
	test.equal(integration.region_accounts.size(), 8, "八个地区均建立现金与家庭结算账户")
	test.equal(integration.site_enterprise.size(), 49, "四十九个生产设施全部绑定具体企业")
	test.equal(integration.transport_edge_count(), 9, "稀疏运输图包含九条基础线路")
	test.expect(
		simulation.commodity_market.external_logistics_managed(),
		"模拟实例关闭全地区互扫和共享国际库存池"
	)

	for raw_site_id: Variant in simulation.commodity_market.production_sites:
		var site_id := str(raw_site_id)
		var site := simulation.commodity_market.production_sites[site_id] as Dictionary
		var enterprise_id := str(site.get("enterprise_id", ""))
		test.expect(
			not enterprise_id.is_empty()
			and simulation.enterprise.enterprises.has(enterprise_id),
			"生产设施引用正式企业：%s" % site_id
		)

	var loran_regions: Array[String] = [
		"region:loran_dawnbay",
		"region:loran_riverback",
		"region:loran_forgeplain",
		"region:loran_southridge",
	]
	for region_id: String in loran_regions:
		simulation.commodity_market.set_inventory(region_id, "coal", 0.0)
	var coal_site := simulation.commodity_market.production_sites["forgeplain_coal"] as Dictionary
	coal_site["operating_target_bp"] = 0
	simulation.commodity_market.production_sites["forgeplain_coal"] = coal_site
	simulation.commodity_market.set_inventory("region:vesta_redhill", "coal", 120000.0)

	var loran_gold_before := float(
		(simulation.economy_integration.country_finance[
			"country:loran_federation"
		] as Dictionary).get("gold_reserve_grams", 0.0)
	)
	var vesta_gold_before := float(
		(simulation.economy_integration.country_finance[
			"country:vesta_union"
		] as Dictionary).get("gold_reserve_grams", 0.0)
	)

	simulation.advance_hours(24)
	var active_shipments := integration.shipments
	test.expect(not active_shipments.is_empty(), "短缺通过运输图形成在途订单")
	var cross_border_found := false
	var positive_duration_found := false
	for shipment: Dictionary in active_shipments:
		cross_border_found = cross_border_found or bool(shipment.get("cross_border", false))
		positive_duration_found = positive_duration_found or (
			int(shipment.get("arrival_hour", 0)) > int(shipment.get("dispatch_hour", 0))
		)
	test.expect(cross_border_found, "国内无煤时形成真实双边跨境运输")
	test.expect(positive_duration_found, "货物具有运输时间而非瞬时传送")
	test.expect(
		simulation.economy.ledger.owner_cash(AlphaEconomyIntegrationService.ESCROW_ID) > 0,
		"在途货物的货款进入托管账户"
	)

	simulation.advance_hours(72)
	var delivered_cross_border := false
	for shipment: Dictionary in integration.shipment_history:
		if (
			bool(shipment.get("cross_border", false))
			and str(shipment.get("status", "")) == "delivered"
		):
			delivered_cross_border = true
			break
	test.expect(delivered_cross_border, "跨境货物到期后交付并释放托管货款")
	test.expect(
		float((integration.country_finance[
			"country:loran_federation"
		] as Dictionary).get("gold_reserve_grams", 0.0)) < loran_gold_before,
		"进口国黄金储备因国际结算下降"
	)
	test.expect(
		float((integration.country_finance[
			"country:vesta_union"
		] as Dictionary).get("gold_reserve_grams", 0.0)) > vesta_gold_before,
		"出口国黄金储备因国际结算上升"
	)
	test.expect(
		int((integration.country_finance[
			"country:loran_federation"
		] as Dictionary).get("cumulative_tariff_centimes", 0)) > 0,
		"进口关税进入政府财政账户"
	)

	var enterprise_finance_found := false
	var production_binding_found := false
	for state: Dictionary in simulation.enterprise.enterprises.values():
		enterprise_finance_found = enterprise_finance_found or state.has(
			"last_commodity_margin_centimes"
		)
		production_binding_found = production_binding_found or not (
			state.get("production_site_ids", []) as Array
		).is_empty()
	test.expect(production_binding_found, "企业持有具体生产设施资产引用")
	test.expect(enterprise_finance_found, "企业记录商品收入、投入、工资、维护与税费")

	var labor_market_link_found := false
	for job: Dictionary in simulation.labor.jobs.values():
		if job.has("labor_demand_index") and job.has("openings"):
			labor_market_link_found = true
			break
	test.expect(labor_market_link_found, "商品开工率同步到具体岗位需求")
	test.expect(not integration.decision_history.is_empty(), "企业根据利润与短缺调整开工目标")
	test.expect(
		bool(simulation.economy.ledger.validate_balances().get("success", false)),
		"商品、工资、运费、税费和贸易结算保持复式账本平衡"
	)
	test.expect(
		bool(integration.validate_integrity().get("success", false)),
		"统一经济服务无断裂企业、运输、货币或库存引用"
	)

	var saved := simulation.get_alpha_persistent_state()
	var restored := AlphaSimulationService.new()
	test.expect(restored.initialize(), "统一经济存档恢复目标可初始化")
	var restore_result := restored.restore_alpha_state(saved)
	test.expect(restore_result.success, "在途货物、黄金、财政、企业和决策状态可恢复")
	if restore_result.success:
		test.equal(
			restored.economy_integration.shipments.size(),
			integration.shipments.size(),
			"恢复后在途运输数量一致"
		)
		test.expect(
			bool(restored.economy_integration.validate_integrity().get("success", false)),
			"恢复后统一经济完整性保持有效"
		)

	for _day: int in range(90):
		simulation.advance_hours(24)
	var final_integrity := simulation.validate_alpha_integrity()
	print("PHASE2_FINAL_INTEGRITY=", final_integrity)
	print("PHASE2_MAXIMUM_HOUR_USEC=", simulation.alpha_maximum_hour_usec)
	print("PHASE2_ACTIVE_SHIPMENTS=", integration.shipments.size())
	print("PHASE2_SHIPMENT_HISTORY=", integration.shipment_history.size())
	test.expect(
		bool(final_integrity.get("success", false)),
		"九十日统一结算后无负库存、失衡账本或无效运输"
	)
	test.expect(
		simulation.alpha_maximum_hour_usec < 1_000_000,
		"稀疏运输图下最慢单小时低于一秒"
	)

	test.finish(self, "Alpha economy integration phase two")
