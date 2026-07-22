extends SceneTree
## Regression for the actual player surface rather than developer projections.

var test := V23TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var simulation := V23ProductSimulationV2.new()
	test.expect(simulation.initialize(), "玩家界面测试环境初始化")
	if not simulation.initialized:
		test.finish(self, "V2.3 player interface")
		return
	var binding := V23PlayerUiBinding.new(simulation, false)
	var person: Dictionary = binding.person_view()
	var maintenance: Dictionary = person.get("maintenance", {}) as Dictionary
	test.expect(not maintenance.is_empty(), "人物摘要具有可读生活物资状态")
	test.expect(maintenance.has("food_days") and maintenance.has("essentials_days"), "生活物资状态使用剩余天数而非AI内部评分")
	var contacts: Array[Dictionary] = binding.contact_options()
	test.expect(not contacts.is_empty(), "玩家关系列表来自当前已知人物")
	var contact: Dictionary = contacts[0]
	test.expect(not str(contact.get("role", "")).is_empty(), "关系对象显示数据驱动身份")
	test.expect(not str(contact.get("relationship_summary", "")).is_empty(), "关系显示可理解叙述")
	test.expect(not str(contact.get("expectation_summary", "")).is_empty(), "关系显示人情与预期")
	var knowledge: Array[Dictionary] = binding.knowledge_view()
	test.expect(not knowledge.is_empty(), "人物具有可读见闻")
	var record: Dictionary = knowledge[0]
	test.expect(record.has("display_title"), "见闻标题不直接显示事实类型和内部ID")
	test.expect(record.has("display_source") and record.has("display_confidence"), "见闻来源与可信程度使用玩家语言")
	var greeting: V2LifeLoopResult = binding.send_greeting(str(contact.get("target_id", "")))
	test.expect(greeting.success, "可向当前动态关系对象发送问候")
	var outbox: Array = binding.messages_view().get("outbox", []) as Array
	test.expect(not outbox.is_empty(), "发出的问候进入玩家消息列表")
	var message: Dictionary = outbox[0] as Dictionary
	test.expect(str(message.get("display_title", "")).contains("问候"), "消息类型显示为中文含义")
	test.expect(not str(message.get("display_title", "")).contains("greeting"), "玩家消息标题不泄露英文枚举")
	var sandbox: Dictionary = binding.sandbox_view()
	test.expect(not (sandbox.get("goals", []) as Array).is_empty(), "行动面板具有当前处境")
	var goal: Dictionary = (sandbox.get("goals", []) as Array)[0] as Dictionary
	test.expect(goal.has("player_summary") and goal.has("urgency_label"), "处境具有玩家可理解的后果和紧迫程度")
	var methods: Array = sandbox.get("methods", []) as Array
	test.expect(not methods.is_empty(), "处境产生数据驱动应对方式")
	var method: Dictionary = methods[0] as Dictionary
	test.expect(method.has("player_explanation") and method.has("preparation_hint"), "应对方式说明现实效果与具体准备重点")
	var overlay: Dictionary = binding.map_overlay_payload()
	var has_city_local_position: bool = false
	for location: Dictionary in overlay.get("locations", []) as Array:
		if str(location.get("parent_region_id", "")) == "lille" and not (location.get("local_position", []) as Array).is_empty():
			has_city_local_position = true
			break
	test.expect(has_city_local_position, "地图载荷同时提供世界位置和城市内部位置")

	root.content_scale_size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/v2_3/v2_3_life_loop_main.tscn") as PackedScene
	var view: V23LifeLoopMain = packed.instantiate() as V23LifeLoopMain
	test.expect(view != null, "正式玩家场景可实例化")
	if view != null:
		root.add_child(view)
		await process_frame
		await process_frame
		test.expect(view.life_binding is V23PlayerUiBinding, "正式场景使用玩家投影绑定")
		test.expect(view.interface is V23PlayerInterface, "正式场景使用玩家界面")
		var map: WorldMapCanvas = view.map_canvas as WorldMapCanvas
		map.set_map_scope(WorldMapCanvas.MAP_SCOPE_WORLD)
		test.equal(map.get_map_scope(), WorldMapCanvas.MAP_SCOPE_WORLD, "世界地图层可切换")
		map.set_map_scope(WorldMapCanvas.MAP_SCOPE_REGIONAL)
		test.equal(map.get_map_scope(), WorldMapCanvas.MAP_SCOPE_REGIONAL, "区域交通层可切换")
		map.set_map_scope(WorldMapCanvas.MAP_SCOPE_CITY)
		test.equal(map.get_map_scope(), WorldMapCanvas.MAP_SCOPE_CITY, "城市内部层可切换")
		view.queue_free()
		await process_frame
	test.finish(self, "V2.3 player interface")
