extends SceneTree
## Existing world-map layer reuse, local spatial index and dirty redraw scope.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load(
		"res://scenes/v2_3/v2_3_life_loop_main.tscn"
	) as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "地图集成场景可实例化")
	if view == null:
		test.finish(self, "V2.3 map integration")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	var architecture: Dictionary = view.map_canvas.debug_architecture_state()
	var layers: Array = architecture.get("layers", []) as Array
	test.expect("transport" in layers and "cities_ports" in layers, "复用既有交通与节点图层")
	test.expect(
		not "v2_3_second_map" in layers,
		"V2.3 没有创建第二套独立地图"
	)
	var initial: Dictionary = view.map_canvas.debug_performance_snapshot()
	var overlay: Dictionary = initial.get("v2_3_local_overlay", {}) as Dictionary
	test.equal(int(overlay.get("location_count", 0)), 12, "本地覆盖载入 12 个正式节点")
	test.equal(view.map_canvas.zoom, 96.0, "正式场景聚焦里尔最高细节层级")
	view.map_canvas.debug_reset_performance_metrics()
	var binding: V23LifeLoopUiBinding = view.life_binding as V23LifeLoopUiBinding
	binding.set_truth_view(true)
	await process_frame
	var performance: Dictionary = view.map_canvas.debug_performance_snapshot()
	test.equal(
		int(performance.get("v2_3_catalog_rebuilds", -1)), 0,
		"认知或真相切换不重建地点投影目录"
	)
	test.equal(
		int(performance.get("projection_calls", -1)), 0,
		"动态本地覆盖刷新不重复执行经纬度投影"
	)
	test.expect(
		int(performance.get("v2_3_spatial_query_candidates", 99)) <= 12,
		"当前视口通过本地空间索引限制候选节点"
	)
	var redraws: Dictionary = performance.get("layer_redraws", {}) as Dictionary
	test.equal(int(redraws.get("countries", 0)), 0, "本地状态变化不重绘国家几何")
	test.equal(int(redraws.get("administrative", 0)), 0, "本地状态变化不重绘行政区几何")
	test.expect(
		int(redraws.get("transport", 0)) >= 1
		and int(redraws.get("cities_ports", 0)) >= 1,
		"本地状态只请求既有交通与节点覆盖重绘"
	)
	view.queue_free()
	await process_frame
	test.finish(self, "V2.3 map integration")
