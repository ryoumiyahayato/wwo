extends SceneTree
## Population, production, storage, regional balancing and international trade regression.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "1900商品市场配置可载入")
	var market := AlphaCommodityMarketService.new()
	test.expect(market.configure(config), "1900商品市场完成配置")
	test.equal(market.commodities.size(), 67, "商品目录包含67个历史校准品类")
	test.equal(_category_count(market, "luxury"), 7, "奢侈品单独形成七个合并品类")
	test.equal(market.region_states.size(), 8, "八个Alpha地区均建立本地市场和仓储")
	test.equal(market.production_sites.size(), 49, "农业、食品、重工、军需和公用事业设施已配置")

	var bread_one_million: float = market.daily_household_demand(
		"region:loran_dawnbay", "bread", 1_000_000, 100
	)
	var bread_two_million: float = market.daily_household_demand(
		"region:loran_dawnbay", "bread", 2_000_000, 100
	)
	test.expect(
		absf(bread_two_million - bread_one_million * 2.0) < 0.001,
		"人口翻倍使基础口粮需求线性翻倍"
	)
	var bread_low_income: float = market.daily_household_demand(
		"region:loran_dawnbay", "bread", 1_000_000, 80
	)
	var bread_high_income: float = market.daily_household_demand(
		"region:loran_dawnbay", "bread", 1_000_000, 150
	)
	var luxury_low_income: float = market.daily_household_demand(
		"region:loran_dawnbay", "fine_clothing", 1_000_000, 80
	)
	var luxury_high_income: float = market.daily_household_demand(
		"region:loran_dawnbay", "fine_clothing", 1_000_000, 150
	)
	test.expect(
		luxury_high_income / maxf(0.0001, luxury_low_income)
		> bread_high_income / maxf(0.0001, bread_low_income),
		"奢侈品需求的收入弹性高于基础面包"
	)

	for region_id: String in [
		"region:vesta_northstar", "region:vesta_silverfield",
		"region:vesta_eastlake", "region:vesta_redhill",
	]:
		test.expect(market.set_inventory(region_id, "bread", 0.0), "可调整地区面包库存")
	var bread_price_before: int = market.market_price("region:vesta_redhill", "bread")
	var first_day: Dictionary = market.settle_day(23)
	test.expect(bool(first_day.get("success", false)), "商品市场完成首日结算")
	var redhill: Dictionary = market.region_report("region:vesta_redhill")
	var redhill_metrics: Dictionary = redhill.get("daily_metrics", {}) as Dictionary
	var redhill_unmet: Dictionary = redhill_metrics.get("unmet", {}) as Dictionary
	test.expect(float(redhill_unmet.get("bread", 0.0)) > 0.0, "本国无面包库存时形成真实短缺")
	test.expect(
		market.market_price("region:vesta_redhill", "bread") > bread_price_before,
		"本地短缺平滑推高面包价格"
	)

	var balancing := AlphaCommodityMarketService.new()
	test.expect(balancing.configure(config), "区域平衡测试市场完成配置")
	balancing.set_inventory("region:loran_dawnbay", "clothing", 0.0)
	balancing.set_inventory("region:loran_riverback", "clothing", 5000.0)
	var balanced_day: Dictionary = balancing.settle_day(23)
	test.expect(bool(balanced_day.get("success", false)), "区域调拨测试完成日结")
	var dawnbay_metrics: Dictionary = (
		balancing.region_report("region:loran_dawnbay").get("daily_metrics", {})
		as Dictionary
	)
	var regional_received: Dictionary = dawnbay_metrics.get("regional_received", {}) as Dictionary
	test.expect(
		float(regional_received.get("clothing", 0.0)) > 0.0,
		"同一国家的区域余货先于国际市场调入"
	)

	var production := AlphaCommodityMarketService.new()
	test.expect(production.configure(config), "生产测试市场完成配置")
	var steel_before: float = production.inventory_units("region:vesta_redhill", "steel")
	var pig_iron_before: float = production.inventory_units("region:vesta_redhill", "pig_iron")
	var production_day: Dictionary = production.settle_day(23)
	test.expect(bool(production_day.get("success", false)), "企业投入产出完成日结")
	var production_metrics: Dictionary = (
		production.region_report("region:vesta_redhill").get("daily_metrics", {})
		as Dictionary
	)
	var produced: Dictionary = production_metrics.get("produced", {}) as Dictionary
	test.expect(float(produced.get("steel", 0.0)) > 0.0, "钢铁厂产生钢材")
	test.expect(
		production.inventory_units("region:vesta_redhill", "pig_iron") < pig_iron_before
		or float((production_metrics.get("industrial_inputs", {}) as Dictionary).get("pig_iron", 0.0)) > 0.0,
		"炼钢实际消耗生铁投入"
	)
	test.expect(
		production.inventory_units("region:vesta_redhill", "steel") != steel_before,
		"钢材库存随生产、消费和出口发生变化"
	)

	var shock := AlphaCommodityMarketService.new()
	test.expect(shock.configure(config), "市场冲击测试服务完成配置")
	test.expect(
		bool(shock.apply_market_shock(
			"shock:test:coal", "region:vesta_redhill", "coal",
			3000, -5000, 1, "矿井事故", 0
		).get("success", false)),
		"临时供应冲击可登记"
	)
	shock.settle_day(23)
	test.equal(shock.active_shocks.size(), 1, "冲击在有效期内保留")
	shock.settle_day(47)
	test.equal(shock.active_shocks.size(), 0, "到期冲击自动移除而非永久改价")

	var long_run := AlphaCommodityMarketService.new()
	test.expect(long_run.configure(config), "长期市场测试服务完成配置")
	for day: int in range(365):
		var result: Dictionary = long_run.settle_day(day * 24 + 23)
		if not bool(result.get("success", false)):
			test.expect(false, "一年日结不中断")
			break
	test.expect(
		bool(long_run.validate_integrity().get("success", false)),
		"一年模拟后无负库存、无失效价格和断裂引用"
	)
	var summary: Dictionary = long_run.world_summary()
	test.expect(int(summary.get("labor_force", 0)) > 0, "地区劳动力规模被统计")
	test.expect(int(summary.get("unemployed", -1)) >= 0, "失业人数保持非负")
	test.expect(
		int(summary.get("unemployment_bp", -1)) in range(0, 10001),
		"失业率保持在有效区间"
	)

	var saved: Dictionary = long_run.get_persistent_state()
	var restored := AlphaCommodityMarketService.new()
	test.expect(restored.configure(config), "恢复目标商品市场可配置")
	test.expect(restored.restore_persistent_state(saved), "商品、库存、价格、就业和冲击状态可恢复")
	test.equal(
		restored.market_price("region:loran_dawnbay", "bread"),
		long_run.market_price("region:loran_dawnbay", "bread"),
		"恢复后地区价格一致"
	)
	test.expect(
		absf(
			restored.inventory_units("region:vesta_redhill", "steel")
			- long_run.inventory_units("region:vesta_redhill", "steel")
		) < 0.001,
		"恢复后仓储库存一致"
	)
	test.finish(self, "Alpha 1900 commodity market")


func _category_count(market: AlphaCommodityMarketService, category: String) -> int:
	var count: int = 0
	for raw_commodity: Variant in market.commodities.values():
		if str((raw_commodity as Dictionary).get("category", "")) == category:
			count += 1
	return count
