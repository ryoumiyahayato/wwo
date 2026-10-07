extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	var data := AlphaHistoricalWorldEconomyData.new()
	_check(data.configure(), "历史世界经济数据可以加载：%s" % data.initialization_error)
	if failures == 0:
		var summary: Dictionary = data.coverage_summary()
		_check(int(summary.get("loaded_country_count", 0)) == 50, "加载50个政治实体")
		_check(int(summary.get("estimated_world_population", 0)) == 1648620000, "世界人口总量闭合")
		_check(int(summary.get("maritime_corridor_count", 0)) >= 30, "海运走廊覆盖")
		_check(int(summary.get("river_corridor_count", 0)) >= 12, "河运走廊覆盖")
		_check(int(summary.get("household_budget_count", 0)) >= 6, "家庭预算覆盖")
		var qing: Dictionary = data.country("qing_empire")
		_check(int((qing.get("population", {}) as Dictionary).get("value", 0)) == 400000000, "清帝国人口校准可读取")
		_check(int((qing.get("gdp_per_capita_2011_intl_dollars", {}) as Dictionary).get("confidence_bp", 0)) == 4500, "GDP估算置信度可读取")
		_check(int((qing.get("infrastructure", {}) as Dictionary).get("rail_route_km", -1)) == 500, "清帝国铁路校准可读取")
		_check(not (qing.get("infrastructure", {}) as Dictionary).get("major_ports", []).is_empty(), "港口清单可读取")
		_check(bool(data.validate_integrity().get("success", false)), "运行时完整性复核")
		var provenance := HistoricalProvenanceFoundation.new()
		_check(provenance.load_current(), "formal evidence provenance loads")
		var evidence := FormalWorldEconomicEvidenceCatalog.new()
		_check(evidence.configure(provenance.gate()), "formal evidence loads directly without Alpha runtime")
		var economic := evidence.economic_snapshot()
		var expected_countries := data.simulation_countries()
		var expected_population: Array[Dictionary] = []
		for record: Dictionary in expected_countries:
			expected_population.append({"economy_entity_id": record["entity_id"], "population": (record["population"] as Dictionary).duplicate(true), "urban_population_share_bp": (record["urban_population_share_bp"] as Dictionary).duplicate(true), "provenance": {"source": AlphaHistoricalWorldEconomyData.WORLD_MANIFEST_PATH, "role": "demographic_bootstrap_fact"}})
			record.erase("population")
			record.erase("urban_population_share_bp")
		_check(economic.get("countries") == expected_countries, "formal country evidence preserves every calibration/confidence/coverage field")
		_check(economic.get("formal_verified_countries") == data.formal_countries(), "formal admission classification is unchanged")
		_check(economic.get("maritime_corridors") == data.maritime_corridors, "formal maritime evidence is unchanged")
		_check(economic.get("river_corridors") == data.river_corridors, "formal river evidence is unchanged")
		_check(evidence.population_snapshot().get("records") == expected_population, "formal population/urbanization bounds and provenance are unchanged")
	print("Alpha historical world economy data: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
