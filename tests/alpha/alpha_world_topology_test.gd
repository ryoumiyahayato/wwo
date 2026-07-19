extends SceneTree
## Alpha A-stage world, functional cells, four-city network and topology.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := AlphaConfig.new()
	test.equal(config.load_all(), OK, "Alpha 配置通过完整结构校验")
	test.equal(config.errors.size(), 0, "Alpha 配置没有校验错误")
	var adapter := AlphaV23Config.new()
	test.equal(adapter.load_all(), OK, "四城数据通过既有 V2.3 空间配置边界")
	test.equal(adapter.errors.size(), 0, "四城 V2.3 适配没有引用错误")
	var spatial := SpatialLocationService.new()
	test.expect(
		spatial.configure(
			adapter.location_records(),
			adapter.social_people(),
			V2DateTime.total_hour_from_iso(
				str(adapter.scenario().get("start_datetime", ""))
			)
		).success,
		"四城地点使用既有正式位置服务建立"
	)
	var graph := TravelGraphService.new()
	test.expect(
		graph.configure(
			adapter.edge_records(), adapter.transport_records(), spatial
		).success,
		"四城交通使用既有正式交通图服务建立"
	)
	test.expect(graph.graph_is_connected(), "四城既有交通图服务确认全图连通")
	var loaded: CoreDataLoadResult = CoreDataLoader.new().load_from_file(
		"res://data/world/demo_world.json"
	)
	test.expect(loaded.is_success(), "既有两国八区稳定 ID 数据继续通过核心校验")
	if not loaded.is_success():
		for error: String in loaded.errors:
			push_error(error)
		test.finish(self, "Alpha world and topology")
		return
	var world := AlphaWorldService.new()
	test.expect(world.configure(loaded.data_set, config), "Alpha 世界服务可从旧稳定 ID 建立")
	if not world.initialization_error.is_empty():
		push_error(world.initialization_error)
	test.equal(world.countries.size(), 2, "正式世界包含两个国家")
	test.equal(world.regions.size(), 8, "正式世界包含八个行政地区")
	test.equal(world.cells.size(), 80, "正式世界包含八十个基础地图单元")
	test.equal(world.cities.size(), 4, "四个主要城市全部进入正式索引")
	test.equal(world.locations.size(), 32, "每个主要城市具有八个可进入地点")
	test.expect(world.routes.size() >= 20, "交通网络至少包含二十条连接")
	test.expect(bool(world.topology_report.get("success", false)), "地图拓扑自动检查通过")
	test.equal(
		int(world.topology_report.get("closed_polygon_count", 0)), 80,
		"八十个单元多边形全部闭合"
	)
	test.equal(
		int(world.topology_report.get("self_intersection_count", -1)), 0,
		"地图不存在自相交单元"
	)
	test.equal(
		int(world.topology_report.get("overlap_count", -1)), 0,
		"地图不存在明显重叠"
	)
	test.equal(
		int(world.topology_report.get("gap_count", -1)), 0,
		"地图不存在明显缝隙"
	)
	test.equal(
		int(world.topology_report.get("reachable_location_count", 0)), 32,
		"全部正式地点均可经交通图到达"
	)
	for raw_city_id: Variant in world.cities.keys():
		var city: Dictionary = world.cities[raw_city_id] as Dictionary
		test.equal(
			(city.get("location_ids", []) as Array).size(), 8,
			"%s 具有八个正式地点" % str(city.get("name", raw_city_id))
		)
		var service_set: Dictionary = {}
		for raw_location_id: Variant in city.get("location_ids", []) as Array:
			var location: Dictionary = world.locations[str(raw_location_id)] as Dictionary
			for raw_service: Variant in location.get("available_services", []) as Array:
				service_set[str(raw_service)] = true
		for required_service: String in [
			"work", "rest", "trade", "credit", "join_organization", "public_office",
		]:
			test.expect(
				service_set.has(required_service),
				"%s 提供 %s 正式功能" % [
					str(city.get("name", raw_city_id)), required_service,
				]
			)
	for raw_cell: Variant in world.cells.values():
		var cell: Dictionary = raw_cell as Dictionary
		for field: String in [
			"country_id", "region_id", "land_use_or_terrain", "population",
			"major_class_or_occupation", "major_industry", "wage_index",
			"living_cost_index", "resource_condition", "transport_connections",
			"infrastructure", "security_or_political_environment",
			"major_organization_influence", "current_economic_state",
			"formal_behavior_effect",
		]:
			if not cell.has(field):
				test.expect(false, "地图单元缺少正式字段：%s/%s" % [
					str(cell.get("cell_id", "")), field,
				])
				break
	test.expect(true, "全部地图单元保存正式功能字段")
	test.finish(self, "Alpha world and topology")
