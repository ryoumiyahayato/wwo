extends SceneTree
## Retained world-summary checks. Superseded private UI assertions are retired.

var test := AlphaTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var menu_scene := load(
		"res://scenes/formal/formal_world_menu.tscn"
	) as PackedScene
	test.expect(menu_scene != null, "正式世界菜单场景可载入")
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		test.expect(menu is FormalWorldMenu, "正式菜单使用半球产品控制器")
		menu.free()

	var world_scene := load(
		"res://scenes/formal/formal_world_main.tscn"
	) as PackedScene
	test.expect(world_scene != null, "正式半球政经场景可载入")
	if world_scene == null:
		test.finish(self, "Formal hemisphere economy UI audit")
		return
	var view := world_scene.instantiate() as FormalWorldApplication
	test.expect(view != null, "正式半球政经场景可实例化")
	if view == null:
		test.finish(self, "Formal hemisphere economy UI audit")
		return
	root.add_child(view)
	await process_frame
	await process_frame
	_check_world_summary(view)
	view.queue_free()
	await process_frame
	test.finish(self, "Formal hemisphere economy UI audit")


func _check_world_summary(view: FormalWorldApplication) -> void:
	test.expect(view.get("_world") != null, "正式政经界面完成世界初始化")
	var summary := view.main_shell.economy_page.get("_summary") as Dictionary
	test.equal(int(summary.get("commodity_count", 0)), 67, "界面读取67种正式商品")
	test.equal(
		int(summary.get("world_political_unit_count", 0)),
		146,
		"界面显示146个当前运行政治实体"
	)
	test.equal(
		int(summary.get("major_economy_count", 0)),
		50,
		"界面显示50个高细节经济聚合体"
	)
	test.equal(
		int(summary.get("detailed_polity_unit_count", 0)),
		55,
		"界面区分55个高细节地图单元"
	)
	test.equal(
		int(summary.get("background_polity_count", 0)),
		91,
		"界面区分91个纯背景运行实体"
	)
