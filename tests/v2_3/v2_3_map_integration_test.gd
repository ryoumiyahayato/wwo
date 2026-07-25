extends SceneTree
## Existing world-map layer reuse, local spatial index and city-scope consistency.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/v2_3/v2_3_life_loop_main.tscn") as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "地图集成场景可实例化")
	if view == null:
		test.finish(self, "V2.3 map integration")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	var map: WorldMapCanvasPlayer = view.map_canvas as WorldMapCanvasPlayer
	var architecture: Dictionary = map.debug_architecture_state()
	var layers: Array = architecture.get("layers", []) as Array
	test.expect("transport" in layers and "cities_ports" in layers, "复用既有交通与节点图层")
	test.expect(not "v2_3_second_map" in layers, "V2.3 没有创建第二套独立地图")
	var initial: Dictionary = map.debug_performance_snapshot()
	var overlay: Dictionary = initial.get("v2_3_local_overlay", {}) as Dictionary
	var formal_config := V23Config.new()
	formal_config.load_all()
	var formal_location_count: int = formal_config.location_records().size()
	test.equal(int(overlay.get("location_count", 0)), formal_location_count, "本地覆盖载入全部扩展正式节点")
	test.equal(map.zoom, 420.0, "正式场景使用当前城市内部聚焦倍率")

	map.debug_reset_performance_metrics()
	var binding: V23LifeLoopUiBinding = view.life_binding as V23LifeLoopUiBinding
	binding.set_truth_view(true)
	await process_frame
	var performance: Dictionary = map.debug_performance_snapshot()
	test.equal(int(performance.get("v2_3_catalog_rebuilds", -1)), 0, "认知或真相切换不重建地点投影目录")
	test.equal(int(performance.get("projection_calls", -1)), 0, "动态本地覆盖刷新不重复执行经纬度投影")
	test.expect(int(performance.get("v2_3_spatial_query_candidates", 999)) <= formal_location_count, "当前视口通过本地空间索引限制候选节点")
	var redraws: Dictionary = performance.get("layer_redraws", {}) as Dictionary
	test.equal(int(redraws.get("countries", 0)), 0, "本地状态变化不重绘国家几何")
	test.equal(int(redraws.get("administrative", 0)), 0, "本地状态变化不重绘行政区几何")
	test.expect(int(redraws.get("transport", 0)) >= 1 and int(redraws.get("cities_ports", 0)) >= 1, "本地状态只请求既有交通与节点覆盖重绘")

	_test_city_local_pick_only(map)
	_test_city_scope_recenter(map)
	_test_overlay_parent_refresh(map)
	_test_cross_scope_transit_hidden(map)

	view.queue_free()
	await process_frame
	test.finish(self, "V2.3 map integration")


func _test_city_local_pick_only(map: WorldMapCanvasPlayer) -> void:
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_CITY)
	var locations: Array = map.get("_v2_3_local_locations") as Array
	var points: Dictionary = map.get("_v2_3_local_location_points") as Dictionary
	var picked: bool = false
	for raw_location: Variant in locations:
		if not raw_location is Dictionary:
			continue
		var location: Dictionary = raw_location as Dictionary
		if not bool(location.get("visible", false)) or not bool(map.call("_location_visible_in_scope", location, WorldMapCanvas.MAP_SCOPE_CITY)):
			continue
		var location_id: String = str(location.get("location_id", ""))
		var point: Vector2 = points.get(location_id, Vector2.INF) as Vector2
		if point == Vector2.INF:
			continue
		var result: Dictionary = map.get_object_at(point * map.zoom + map.pan)
		test.equal(str(result.get("type", "")), "location", "城市层只命中可见本地地点")
		test.equal(str(result.get("id", "")), location_id, "城市层命中正确本地地点")
		picked = true
		break
	test.expect(picked, "城市层存在可测试的本地地点")
	var blank: Dictionary = map.get_object_at(Vector2(-5000.0, -5000.0))
	test.expect(blank.is_empty(), "城市层空白位置不回退选择隐藏底图对象")


func _test_city_scope_recenter(map: WorldMapCanvasPlayer) -> void:
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_REGIONAL)
	map.zoom = WorldMapCanvas.CITY_SCOPE_THRESHOLD - 1.0
	map.pan += Vector2(900.0, -700.0)
	map.zoom_at(1.0, Vector2(80.0, 80.0))
	test.equal(map.get_map_scope(), WorldMapCanvas.MAP_SCOPE_CITY, "滚轮跨阈值进入城市层")
	var city_anchor: Vector2 = map.call("_player_city_anchor") as Vector2
	var map_anchor: Vector2 = map.call("_map_anchor") as Vector2
	var screen_point: Vector2 = city_anchor * map.zoom + map.pan
	test.expect(screen_point.distance_to(map_anchor) < 1.0, "进入城市层时自动重新居中当前城市")


func _test_overlay_parent_refresh(map: WorldMapCanvasPlayer) -> void:
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_CITY)
	var previous_parent: String = str(map.get("_current_city_parent_id"))
	var payload: Dictionary = (map.get("_v2_3_local_overlay") as Dictionary).duplicate(true)
	var candidate: Dictionary = {}
	var expected_parent: String = ""
	for raw_location: Variant in (payload.get("locations", []) as Array):
		if not raw_location is Dictionary:
			continue
		var location: Dictionary = raw_location as Dictionary
		var location_id: String = str(location.get("location_id", ""))
		var parent_id: String = str(location.get("parent_region_id", ""))
		if str(location.get("location_type", "")) == "regional_centre":
			parent_id = location_id
		if not parent_id.is_empty() and parent_id != previous_parent:
			candidate = location
			expected_parent = parent_id
			break
	test.expect(not candidate.is_empty(), "存在另一个城市父级用于覆盖刷新")
	if candidate.is_empty():
		return
	var observer_id: String = str(payload.get("observer_id", ""))
	var positions: Array = payload.get("person_positions", []) as Array
	for raw_position: Variant in positions:
		if raw_position is Dictionary and str((raw_position as Dictionary).get("person_id", "")) == observer_id:
			(raw_position as Dictionary)["current_location_id"] = str(candidate.get("location_id", ""))
			(raw_position as Dictionary)["location_state"] = "at_location"
			break
	payload["person_positions"] = positions
	payload["overlay_revision"] = int(payload.get("overlay_revision", 0)) + 1
	var before: int = int(map.debug_performance_snapshot().get("v2_3_catalog_rebuilds", 0))
	map.set_v2_3_local_overlay(payload)
	var after: int = int(map.debug_performance_snapshot().get("v2_3_catalog_rebuilds", 0))
	test.equal(str(map.get("_current_city_parent_id")), expected_parent, "覆盖位置变化会更新当前城市父级")
	test.expect(after > before, "城市父级变化会重建城市投影目录")


func _test_cross_scope_transit_hidden(map: WorldMapCanvasPlayer) -> void:
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_CITY)
	var edges: Array = (map.get("_v2_3_local_overlay") as Dictionary).get("edges", []) as Array
	var lookup: Dictionary = map.get("_v2_3_local_location_lookup") as Dictionary
	var found: bool = false
	for raw_edge: Variant in edges:
		if not raw_edge is Dictionary:
			continue
		var edge: Dictionary = raw_edge as Dictionary
		var from_id: String = str(edge.get("from_location_id", ""))
		var to_id: String = str(edge.get("to_location_id", ""))
		var from_location: Dictionary = lookup.get(from_id, {}) as Dictionary
		var to_location: Dictionary = lookup.get(to_id, {}) as Dictionary
		var from_visible: bool = bool(map.call("_location_visible_in_scope", from_location, WorldMapCanvas.MAP_SCOPE_CITY))
		var to_visible: bool = bool(map.call("_location_visible_in_scope", to_location, WorldMapCanvas.MAP_SCOPE_CITY))
		if from_visible == to_visible:
			continue
		var visible_id: String = from_id if from_visible else to_id
		var position := {"current_location_id":visible_id, "location_state":"in_transit", "current_edge_id":str(edge.get("edge_id", "")), "segment_progress":0.5}
		test.equal(map.call("_v2_3_person_world_point", position) as Vector2, Vector2.INF, "跨城市行程人物标记不会混合本地与世界坐标")
		found = true
		break
	test.expect(found, "存在跨城市边用于人物标记一致性测试")
