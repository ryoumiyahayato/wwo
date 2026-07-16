extends SceneTree
## Static V2 prototype smoke coverage. It never creates or advances a formal session.

const VIEWPORT_RECT := Rect2(0.0, 0.0, 1280.0, 720.0)

var _checks: int = 0
var _failures: int = 0
var _view: PrototypeV2Main


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	_test_static_documents()
	var packed: PackedScene = load("res://scenes/prototype_v2/prototype_v2_main.tscn") as PackedScene
	_expect(packed != null, "独立原型主场景资源可加载")
	if packed == null:
		_finish()
		return
	_view = packed.instantiate() as PrototypeV2Main
	_expect(_view != null, "独立原型主场景可实例化")
	if _view == null:
		_finish()
		return
	root.add_child(_view)
	current_scene = _view
	await process_frame
	await process_frame
	_expect(_view.prototype_data != null and _view.prototype_data.errors.is_empty(), "原型静态数据加载且不依赖正式数据服务")
	_expect(_view.map_canvas != null and _view.interface != null, "全屏地图和四角界面同时建立")
	_test_layout_bounds()
	await _test_corner_entries()
	_test_identity_permissions()
	_test_map_interactions()
	_test_relationship_and_organization_views()
	await _test_escape_layers()
	_test_isolation_source()
	_view.queue_free()
	await process_frame
	_finish()


func _test_static_documents() -> void:
	var prototype_data := PrototypeV2Data.new()
	_expect(prototype_data.load_all(), "七份原型 JSON 全部可解析")
	_expect(prototype_data.records.size() == 7, "原型静态数据文件集合完整")
	for key_variant: Variant in prototype_data.records.keys():
		var document: Dictionary = prototype_data.records[key_variant] as Dictionary
		_expect(document.get("prototype_only", false) == true, "%s 明确标记 prototype_only" % str(key_variant))
	var relationships: Array = prototype_data.get_document("relationships").get("relationships", []) as Array
	var direct_count: int = 0
	for relation_variant: Variant in relationships:
		var category: String = str((relation_variant as Dictionary).get("category", ""))
		if category in ["亲近关系", "经常接触", "普通熟人"]:
			direct_count += 1
	_expect(direct_count >= 6 and direct_count <= 10, "普通工人直接关系控制在 6 至 10 人")
	_expect(relationships.size() >= 8 and relationships.size() <= 15, "可见人物总量保持有限")
	var organization_identities: Dictionary = prototype_data.get_document("organizations").get("identities", {}) as Dictionary
	for identity_id: String in ["worker", "official"]:
		var identity_data: Dictionary = organization_identities[identity_id] as Dictionary
		var owned: Array = identity_data.get("owned", []) as Array
		var discover: Array = identity_data.get("discover", []) as Array
		_expect(not owned.is_empty() and not discover.is_empty(), "%s 的我的组织与探索组织数据完全分开" % identity_id)


func _test_layout_bounds() -> void:
	var rects: Array[Rect2] = [
		PrototypeV2Interface.COUNTRY_CORNER,
		PrototypeV2Interface.TIME_CORNER,
		PrototypeV2Interface.CHARACTER_CORNER,
		PrototypeV2Interface.ACTIVITY_CORNER,
		PrototypeV2Interface.IDENTITY_SWITCH,
		PrototypeV2Interface.MODE_SWITCH,
	]
	for rect: Rect2 in rects:
		_expect(_rect_inside(rect, VIEWPORT_RECT), "四角组件与切换器位于 1280×720 内")
	_expect(_view.map_canvas.size == Vector2(1280.0, 720.0), "地图画布覆盖完整 1280×720")


func _test_corner_entries() -> void:
	var interface: PrototypeV2Interface = _view.interface
	interface.handle_pointer_pressed(Vector2(120.0, 52.0))
	await create_timer(0.24).timeout
	_expect(interface.open_panel == "country", "左上国家入口可点击打开")
	interface.handle_pointer_pressed(Vector2(120.0, 52.0))
	await create_timer(0.20).timeout
	_expect(interface.open_panel.is_empty(), "再次点击国家入口可收起")
	interface.handle_pointer_pressed(Vector2(1120.0, 55.0))
	await create_timer(0.24).timeout
	_expect(interface.open_panel == "time", "右上时间入口可点击打开")
	_expect(_rect_inside(interface.get_panel_rect(), VIEWPORT_RECT), "时间面板不伸出屏幕")
	interface.open_panel_named("character", false)
	_expect(interface.open_panel == "character", "左下人物中心可打开")
	_expect(_rect_inside(interface.get_panel_rect(), VIEWPORT_RECT), "人物中心不伸出屏幕")
	interface.open_panel_named("activity", false)
	_expect(interface.open_panel == "activity", "右下世界动态可打开")
	_expect(_rect_inside(interface.get_panel_rect(), VIEWPORT_RECT), "世界动态不伸出屏幕")


func _test_identity_permissions() -> void:
	var interface: PrototypeV2Interface = _view.interface
	interface.set_identity("worker")
	interface.open_panel_named("country", false)
	var worker_state: Dictionary = interface.debug_state()
	interface.set_identity("official")
	var official_state: Dictionary = interface.debug_state()
	_expect(worker_state["identity"] == "worker" and official_state["identity"] == "official", "普通工人与地方官员可在原型内部切换")
	var institutions: Array = _view.prototype_data.get_document("institutions").get("institutions", []) as Array
	var finance: Dictionary = institutions[2] as Dictionary
	var army: Dictionary = institutions[3] as Dictionary
	_expect(finance["worker_visibility"] == "hidden" and finance["official_visibility"] == "known_locked", "中央财政对工人隐藏、对地方官员仅已知锁定")
	_expect(army["worker_visibility"] == "hidden" and army["official_visibility"] == "hidden", "全国军队对两套示例身份均完全无关并隐藏")
	var permissions: Array = _view.prototype_data.get_document("institutions").get("official_permissions", []) as Array
	_expect(permissions.has("提交地方事务") and permissions.has("查阅科室预算"), "地方官员额外具有辖区事务与科室预算信息")


func _test_map_interactions() -> void:
	var before_zoom: float = _view.map_canvas.zoom
	_view.map_canvas.zoom_at(1.0, Vector2(640.0, 360.0))
	_expect(_view.map_canvas.zoom > before_zoom, "鼠标滚轮对应的地图缩放改变缩放值")
	var before_pan: Vector2 = _view.map_canvas.pan
	_view.map_canvas.pan_by(Vector2(36.0, -18.0))
	_expect(_view.map_canvas.pan != before_pan, "地图拖动改变平移位置")
	_view.interface.mode_requested.emit("market")
	_expect(_view.map_canvas.current_mode == "market", "区域市场地图模式可切换")
	_view.interface.mode_requested.emit("population")
	_expect(_view.map_canvas.current_mode == "population", "人口地图模式可切换")
	_view.interface.mode_requested.emit("war")
	_expect(_view.map_canvas.current_mode == "war", "战争静态视觉模式可切换")
	_view.interface.mode_requested.emit("legal")
	_expect(_view.map_canvas.current_mode == "legal", "法理地图模式可切换")
	_expect(_view.select_review_object("region", "western_europe"), "地图地区可选择并打开地区卡")
	_expect(_view.map_canvas.selected_type == "region", "当前地区选择获得高亮状态")
	_expect(_view.select_review_object("city", "paris"), "地图城市可选择并打开城市卡")
	_view.interface.close_top_layer()
	_expect(_view.map_canvas.selected_id.is_empty(), "点击空白或关闭对象卡可取消地图选择")
	_view.map_canvas.reset_view()


func _test_relationship_and_organization_views() -> void:
	var interface: PrototypeV2Interface = _view.interface
	interface.apply_review_state("relationships")
	_expect(interface.open_panel == "character" and interface.character_section == "relationships", "关系人物卡网格可打开")
	interface.apply_review_state("person_detail")
	_expect(interface.detail_person_id == "anna", "人物卡可进入单个人物详情")
	interface.apply_review_state("owned_organizations")
	_expect(interface.character_section == "owned_orgs", "我的组织独立视图可打开")
	interface.apply_review_state("discover_organizations")
	_expect(interface.character_section == "discover_orgs", "探索组织独立视图可打开")


func _test_escape_layers() -> void:
	var interface: PrototypeV2Interface = _view.interface
	interface.apply_review_state("person_detail")
	_expect(interface.close_top_layer() and interface.detail_person_id.is_empty(), "Esc 第一层关闭人物详情")
	var closed_workspace: bool = interface.close_top_layer()
	await create_timer(0.20).timeout
	_expect(closed_workspace and interface.open_panel.is_empty(), "Esc 下一层关闭人物工作区")
	_expect(not interface.close_top_layer(), "无上层界面时 Esc 不退出原型")


func _test_isolation_source() -> void:
	var forbidden: Array[String] = ["ActionService", "RelationshipService", "OrganizationService", "WorldState", "SaveService"]
	var paths: Array[String] = [
		"res://scripts/prototype_v2/prototype_v2_data.gd",
		"res://scripts/prototype_v2/prototype_v2_map_canvas.gd",
		"res://scripts/prototype_v2/prototype_v2_interface.gd",
		"res://scripts/prototype_v2/prototype_v2_main.gd",
	]
	for path: String in paths:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		var source: String = file.get_as_text() if file != null else ""
		for token: String in forbidden:
			_expect(not source.contains(token), "%s 不引用正式服务或正式存档边界 %s" % [path.get_file(), token])


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.has_point(inner.position) and inner.end.x <= outer.end.x and inner.end.y <= outer.end.y


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V2 prototype smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
