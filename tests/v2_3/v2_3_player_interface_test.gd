extends SceneTree
## Compatibility-named product-surface regression. The V2.3 flat-map interface
## has been retired; this now guards the formal hemisphere product instead.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	test.equal(
		str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"res://scenes/formal/formal_world_menu.tscn",
		"默认产品入口使用正式世界菜单"
	)
	var menu_scene := load(
		"res://scenes/formal/formal_world_menu.tscn"
	) as PackedScene
	test.expect(menu_scene != null, "正式世界菜单可加载")
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		test.expect(menu is FormalWorldMenu, "菜单不再使用V2.3产品控制器")
		menu.free()

	var main_scene := load(
		"res://scenes/formal/formal_world_main.tscn"
	) as PackedScene
	test.expect(main_scene != null, "正式半球产品场景可加载")
	if main_scene != null:
		var view := main_scene.instantiate() as FormalWorldApplication
		test.expect(view != null, "正式半球产品场景可实例化")
		if view != null:
			root.content_scale_size = Vector2i(1280, 720)
			root.add_child(view)
			await process_frame
			await process_frame
			test.expect(
				view.formal_simulation.initialized,
				"正式半球初始化统一正式世界"
			)
			var summary := view.formal_simulation.world_summary()
			test.equal(
				int(summary.get("world_political_unit_count", 0)),
				146,
				"产品世界包含146个运行时政治实体"
			)
			test.equal(
				int(summary.get("major_economy_count", 0)),
				50,
				"50个主要政权使用高细节经济"
			)
			test.equal(
				int(summary.get("primary_playable_count", 0)),
				30,
				"前30个政权进入核心可玩层"
			)
			test.expect(
				view.get_node_or_null("PrototypeMap") == null,
				"正式产品不包含旧平面PrototypeMap"
			)
			test.expect(
				view.get_node_or_null(
					"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D"
				) != null,
				"正式产品以三维半球作为地图"
			)
			view.economy_panel_open = false
			view._activate_button("formal_economy_toggle")
			test.expect(view.economy_panel_open, "正式政经面板可操作")
			view.queue_free()
			await process_frame

	test.finish(self, "Formal hemisphere player surface")
