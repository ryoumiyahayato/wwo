extends SceneTree
## Compatibility-named hierarchy performance guard. The retired flat map and
## municipality-shard renderer are gone; this validates the formal hemisphere,
## verified historical administration and bounded local-detail presentation.

const MAX_ADMIN_PAGE_SIZE: int = 24
const MAX_READY_USEC: int = 3_000_000

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(
		"res://scenes/formal/formal_world_main.tscn"
	) as PackedScene
	test.expect(packed != null, "正式半球层级场景可加载")
	if packed == null:
		test.finish(self, "Formal hemisphere hierarchy performance")
		return
	var started_usec := Time.get_ticks_usec()
	var view := packed.instantiate() as FormalWorldApplication
	test.expect(view != null, "正式半球层级场景可实例化")
	if view == null:
		test.finish(self, "Formal hemisphere hierarchy performance")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	var ready_usec := Time.get_ticks_usec() - started_usec
	_check_formal_map(view, ready_usec)
	_check_historical_admin(view)
	_check_local_detail_budget(view)
	view.queue_free()
	await process_frame
	test.finish(self, "Formal hemisphere hierarchy performance")


func _check_formal_map(
	view: FormalWorldApplication, ready_usec: int
) -> void:
	test.expect(view.formal_simulation.initialized, "正式半球世界完成初始化")
	var summary := view.formal_simulation.world_summary()
	test.equal(
		int(summary.get("world_political_unit_count", 0)),
		146,
		"全球层持有1900年1月1日有效的146个政治单元"
	)
	test.equal(
		int(summary.get("major_economy_count", 0)),
		50,
		"高细节经济目录为50个聚合体"
	)
	test.equal(
		int(summary.get("detailed_polity_unit_count", 0)),
		55,
		"高细节经济明确绑定55个地图单元"
	)
	test.expect(
		view.get_node_or_null("PrototypeMap") == null,
		"正式产品不再实例化平面PrototypeMap"
	)
	test.expect(
		view.get_node_or_null(
			"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D"
		) != null,
		"全球层由真实三维半球承载"
	)
	test.expect(
		ready_usec < MAX_READY_USEC,
		"正式半球冷启动低于三秒CI预算"
	)


func _check_historical_admin(view: FormalWorldApplication) -> void:
	var coverage := view.historical_admin_coverage_report()
	var detailed_count := int(coverage.get("detailed_country_count", 0))
	test.expect(
		int(coverage.get("profile_count", 0)) >= 50,
		"主要政权配置覆盖当前高细节目录"
	)
	test.equal(
		detailed_count,
		view._historical_admin_by_entity.size(),
		"覆盖报告与已加载历史一级行政目录一致"
	)
	test.expect(detailed_count >= 15, "已验证的历史一级行政目录全部可用")
	test.expect(
		bool(coverage.get("modern_admin_names_forbidden", false)),
		"缺失历史边界时禁止回退成现代行政区"
	)
	var germany := view._historical_admin_by_entity.get(
		"german_empire", {}
	) as Dictionary
	var units := germany.get("runtime_units", []) as Array
	test.expect(not units.is_empty(), "德意志帝国区域层读取历史一级行政目录")
	var page_count := maxi(
		1,
		int(ceil(float(units.size()) / float(MAX_ADMIN_PAGE_SIZE)))
	)
	test.expect(page_count >= 2, "大型区域目录采用有界分页")
	test.expect(
		mini(units.size(), MAX_ADMIN_PAGE_SIZE) <= MAX_ADMIN_PAGE_SIZE,
		"单页一级行政按钮不超过24个"
	)


func _check_local_detail_budget(view: FormalWorldApplication) -> void:
	var australia_ids := view.formal_simulation.economy.polity_ids_for_economy(
		"australia_colonies_1900"
	)
	test.equal(australia_ids.size(), 6, "澳大利亚聚合经济保持六个地图单元")
	var background := view.formal_simulation.polity_summary("cshapes_gw_31")
	test.expect(not background.is_empty(), "背景政治单元仍可查询")
	test.expect(
		not bool(background.get("has_detailed_economy", true)),
		"背景单元不展开高成本国家级经济"
	)
	test.expect(
		view._historical_admin_by_entity.size() <= 64,
		"历史区域目录只覆盖有证据政权而非全世界盲目展开"
	)
	test.expect(
		view._history_entity_by_id.size() == 151,
		"区域细化不会删减全球政治单元"
	)
