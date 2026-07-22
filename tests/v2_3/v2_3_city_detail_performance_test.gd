extends SceneTree
## Generated geography is sparse regional context. City scope must be owned by
## the formal local-location graph and must not render municipality shards.

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
	test.expect(int(initial.get("france_municipalities", 0)) >= 25000, "法国达到全国市镇级数据覆盖下限")
	test.expect(int(initial.get("index_shards", 0)) >= 140, "城市数据按国家和法国区域分片")
	test.expect(bool(initial.get("regional_only", false)), "生成城市只服务区域交通层")
	test.equal(int(initial.get("visible_records", -1)), 0, "初始城市层不绘制生成市镇")
	test.expect(int(initial.get("cache_limit", 99)) <= 4, "城市分片缓存采用低上限")
	test.expect(int(initial.get("node_budget", 9999)) <= 120, "区域城市节点采用稀疏预算")
	test.expect(int(initial.get("label_budget", 9999)) <= 32, "区域城市标签采用稀疏预算")

	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_REGIONAL)
	await process_frame
	var regional: Dictionary = map.debug_city_detail_snapshot()
	test.expect(int(regional.get("visible_records", 0)) > 0, "区域交通层加载少量重要城市")
	test.expect(int(regional.get("visible_records", 9999)) <= int(regional.get("node_budget", 0)), "区域节点不超过稀疏绘制预算")
	test.expect(int(regional.get("loaded_shards", 99)) <= int(regional.get("cache_limit", 0)), "区域层加载后缓存仍受限")
	test.expect(float(regional.get("last_query_ms", 9999.0)) < 1200.0, "区域城市冷查询不阻塞超过1.2秒")

	var cache_hits_before: int = int(regional.get("cache_hits", 0))
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_WORLD)
	await process_frame
	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_REGIONAL)
	await process_frame
	var repeated: Dictionary = map.debug_city_detail_snapshot()
	test.expect(int(repeated.get("cache_hits", 0)) > cache_hits_before, "再次进入同一区域复用已解析分片")

	map.set_map_scope(WorldMapCanvas.MAP_SCOPE_CITY)
	await process_frame
	var city: Dictionary = map.debug_city_detail_snapshot()
	test.equal(int(city.get("visible_records", -1)), 0, "城市层完全停止绘制生成城市和市镇")
	test.expect(map.zoom >= 400.0, "城市层使用足够高的本地地点倍率")
	test.expect(int(city.get("loaded_shards", 99)) <= int(city.get("cache_limit", 0)), "切换城市层后缓存不会失控")
	test.expect(float(city.get("maximum_query_ms", 9999.0)) < 1600.0, "全部地图查询峰值低于1.6秒")
	test.equal(int(city.get("missing_shards", -1)), 0, "索引中的分片均可读取")

	var architecture: Dictionary = map.debug_architecture_state()
	test.equal(str(architecture.get("city_detail_load_mode", "")), "sparse_regional_viewport_shards", "地图只在区域层读取稀疏视窗分片")
	test.expect(bool(architecture.get("city_detail_modern_reference", false)), "现代城市数据不会伪装成历史事实")
	view.queue_free()
	await process_frame
	test.finish(self, "V2.3 city detail performance")
