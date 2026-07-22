extends SceneTree
## Validates generated coverage and the runtime budget without iterating the full
## 88k-record dataset during ordinary camera movement.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_main.tscn"
	) as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "城市细化正式场景可实例化")
	if view == null:
		test.finish(self, "V2.3 city detail performance")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	var map: WorldMapCanvasPlayer = view.map_canvas as WorldMapCanvasPlayer
	test.expect(map != null, "正式场景使用城市细化玩家地图")
	if map == null:
		view.queue_free()
		test.finish(self, "V2.3 city detail performance")
		return

	var initial: Dictionary = map.debug_city_detail_snapshot()
	test.expect(bool(initial.get("configured", false)), "城市分片索引已接入正式地图")
	test.equal(int(initial.get("index_records", 0)), 88927, "欧洲亚洲北美细化记录数量固定")
	test.expect(int(initial.get("france_municipalities", 0)) >= 25000, "法国达到全国市镇级覆盖下限")
	test.expect(int(initial.get("index_shards", 0)) >= 140, "城市数据按国家和法国区域分片")
	test.expect(int(initial.get("loaded_shards", 99)) <= int(initial.get("cache_limit", 0)), "初始城市缓存不超过LRU预算")
	test.expect(int(initial.get("visible_records", 9999)) <= int(initial.get("node_budget", 0)), "初始可见节点不超过绘制预算")

	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_REGIONAL)
	await process_frame
	var regional: Dictionary = map.debug_city_detail_snapshot()
	test.expect(int(regional.get("visible_records", 0)) > 0, "区域交通层实际加载当前视窗城市")
	test.expect(int(regional.get("loaded_shards", 99)) <= int(regional.get("cache_limit", 0)), "区域层加载后缓存仍受限")
	test.expect(float(regional.get("last_query_ms", 9999.0)) < 1500.0, "区域城市冷查询不阻塞超过1.5秒")

	var cache_hits_before: int = int(regional.get("cache_hits", 0))
	map.pan_by(Vector2(-180.0, 0.0))
	map.pan_by(Vector2(180.0, 0.0))
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_CITY)
	await process_frame
	var city: Dictionary = map.debug_city_detail_snapshot()
	test.expect(int(city.get("visible_records", 0)) > 0, "城市层显示当前视窗市镇和城市")
	test.expect(int(city.get("visible_records", 9999)) <= int(city.get("node_budget", 0)), "法国密集市镇仍受节点预算限制")
	test.expect(int(city.get("loaded_shards", 99)) <= int(city.get("cache_limit", 0)), "城市层不会无限保留国家分片")
	test.expect(int(city.get("cache_hits", 0)) > cache_hits_before, "重复视窗查询复用已解析分片")
	test.expect(float(city.get("maximum_query_ms", 9999.0)) < 2000.0, "全部测试查询峰值低于2秒")
	test.equal(int(city.get("missing_shards", -1)), 0, "索引中的分片均可读取")

	var architecture: Dictionary = map.debug_architecture_state()
	test.equal(str(architecture.get("city_detail_load_mode", "")), "viewport_intersecting_shards", "地图使用视窗相交分片而非全量启动加载")
	test.expect(bool(architecture.get("city_detail_modern_reference", false)), "现代城市数据不会伪装成历史事实")
	view.queue_free()
	await process_frame
	test.finish(self, "V2.3 city detail performance")
