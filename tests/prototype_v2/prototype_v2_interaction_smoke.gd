extends SceneTree
## V2.1 map, hierarchy, layout, and interaction smoke coverage.

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
	_expect(packed != null, "独立 V2.1 原型场景资源可加载")
	if packed == null:
		_finish()
		return
	_view = packed.instantiate() as PrototypeV2Main
	_expect(_view != null, "独立 V2.1 原型场景可实例化")
	if _view == null:
		_finish()
		return
	root.add_child(_view)
	current_scene = _view
	await process_frame
	await process_frame
	_expect(_view.prototype_data != null and _view.prototype_data.errors.is_empty(), "V2.1 静态数据加载且不依赖正式服务")
	_expect(_view.map_canvas != null and _view.interface != null, "地理地图与四角界面同时建立")
	_test_geographic_projection_and_land()
	_test_transport_semantics()
	_test_hierarchy()
	_test_zoom_semantics()
	_test_layout_constraints()
	await _test_corner_entries_and_identity_review()
	_test_identity_information_architecture()
	_test_organization_and_activity_structure()
	_test_map_modes_and_war_state()
	_test_map_selection()
	await _test_escape_and_exclusivity()
	_test_isolation_source()
	_view.queue_free()
	await process_frame
	_finish()


func _test_static_documents() -> void:
	var prototype_data := PrototypeV2Data.new()
	_expect(prototype_data.load_all(), "全部 V2.1 原型 JSON 可解析")
	_expect(prototype_data.records.size() == PrototypeV2Data.FILES.size(), "原型静态数据文件集合完整")
	for key_variant: Variant in prototype_data.records.keys():
		var document: Dictionary = prototype_data.records[key_variant] as Dictionary
		_expect(document.get("prototype_only", false) == true, "%s 明确标记 prototype_only" % str(key_variant))
	var coastline: Dictionary = prototype_data.get_document("world_coastlines")
	_expect((coastline.get("features", []) as Array).size() >= 170, "世界海岸线包含完整低精度国家轮廓")
	var source: Dictionary = coastline.get("source", {}) as Dictionary
	_expect(str(source.get("dataset", "")).contains("Natural Earth"), "海岸线数据记录 Natural Earth 来源")
	_expect(str(source.get("license", "")) == "Public domain", "海岸线数据记录公共领域许可")
	_expect(str(source.get("prototype_notice", "")).contains("政治边界仅为视觉原型近似"), "海岸线数据记录政治边界原型近似声明")
	var map_modes: Dictionary = prototype_data.get_document("map_modes")
	_expect(not str(map_modes.get("shared_basemap_id", "")).is_empty(), "全部地图模式声明共用底图 ID")


func _test_geographic_projection_and_land() -> void:
	var cities: Array = _view.prototype_data.get_document("cities").get("cities", []) as Array
	var coastline_features: Array = _view.prototype_data.get_document("world_coastlines").get("features", []) as Array
	for city_variant: Variant in cities:
		var city: Dictionary = city_variant as Dictionary
		var lon_lat: Array = city.get("lon_lat", []) as Array
		_expect(lon_lat.size() == 2 and not city.has("position"), "%s 只存经纬度而非屏幕像素" % str(city.get("name", "")))
		if lon_lat.size() != 2:
			continue
		var projected: Vector2 = _view.map_canvas.project_lon_lat(lon_lat)
		_expect(is_finite(projected.x) and is_finite(projected.y), "%s 可经统一 Robinson 近似投影" % str(city.get("name", "")))
		_expect(_point_on_land(Vector2(float(lon_lat[0]), float(lon_lat[1])), coastline_features), "%s 位于世界陆地轮廓内" % str(city.get("name", "")))
		var region_id: String = str(city.get("parent_region_id", ""))
		if not region_id.is_empty():
			_expect(_view.map_canvas.region_contains_lon_lat(region_id, lon_lat), "%s 位于其对应地区原型范围" % str(city.get("name", "")))
	var paris: Dictionary = _view.map_canvas.get_city("paris")
	var paris_projected: Vector2 = _view.map_canvas.project_lon_lat(paris.get("lon_lat", []))
	var paris_screen: Vector2 = _view.map_canvas.lon_lat_to_screen(paris.get("lon_lat", []))
	_expect(paris_screen.is_equal_approx(paris_projected * _view.map_canvas.zoom + _view.map_canvas.pan), "所有城市使用同一投影与视图变换")


func _test_transport_semantics() -> void:
	var cities: Dictionary = {}
	for city_variant: Variant in _view.prototype_data.get_document("cities").get("cities", []):
		var city: Dictionary = city_variant as Dictionary
		cities[str(city.get("id", ""))] = city
	var rails: Array = _view.prototype_data.get_document("rail_segments").get("segments", []) as Array
	for segment_variant: Variant in rails:
		var segment: Dictionary = segment_variant as Dictionary
		var from_id: String = str(segment.get("from_city_id", ""))
		var to_id: String = str(segment.get("to_city_id", ""))
		_expect(str(segment.get("type", "")) == "rail", "%s 明确使用铁路类型" % str(segment.get("id", "")))
		_expect(cities.has(from_id) and cities.has(to_id), "%s 两端均为已知陆地城市" % str(segment.get("id", "")))
		if cities.has(from_id) and cities.has(to_id):
			_expect(str((cities[from_id] as Dictionary).get("parent_country_id", "")) == "france" and str((cities[to_id] as Dictionary).get("parent_country_id", "")) == "france", "%s 不跨海冒充铁路" % str(segment.get("id", "")))
	var roads: Dictionary = _view.prototype_data.get_document("road_segments")
	var shipping: Dictionary = _view.prototype_data.get_document("shipping_routes")
	_expect(str(roads.get("type", "")) == "road", "一般陆路使用独立 road 类型")
	_expect(str(shipping.get("type", "")) == "shipping", "航运路线使用独立 shipping 类型")
	for route_variant: Variant in shipping.get("routes", []):
		_expect(str((route_variant as Dictionary).get("type", "")) == "shipping", "每条跨海路线保持航运语义")
	var legend: Dictionary = _view.prototype_data.get_document("map_modes").get("transport_legend", {}) as Dictionary
	_expect(str(legend.get("rail", "")) != str(legend.get("shipping", "")), "铁路与航运具有不同线型和图例说明")
	_expect(not str(legend.get("border", "")).is_empty() and not str(legend.get("front", "")).is_empty(), "国境与战线具有独立图例语义")


func _test_hierarchy() -> void:
	var country_ids: Dictionary = {}
	for country_variant: Variant in _view.prototype_data.get_document("countries").get("countries", []):
		var country: Dictionary = country_variant as Dictionary
		country_ids[str(country.get("id", ""))] = true
		_expect(str(country.get("object_level", "")) == "country", "%s 明确为国家层" % str(country.get("name", "")))
	var region_ids: Dictionary = {}
	for region_variant: Variant in _view.prototype_data.get_document("regions").get("regions", []):
		var region: Dictionary = region_variant as Dictionary
		region_ids[str(region.get("id", ""))] = true
		_expect(str(region.get("object_level", "")) == "region" and country_ids.has(str(region.get("parent_country_id", ""))), "%s 具有明确父国家" % str(region.get("name", "")))
	for city_variant: Variant in _view.prototype_data.get_document("cities").get("cities", []):
		var city: Dictionary = city_variant as Dictionary
		var parent_region: String = str(city.get("parent_region_id", ""))
		_expect(str(city.get("object_level", "")) == "city" and country_ids.has(str(city.get("parent_country_id", ""))), "%s 具有明确父国家" % str(city.get("name", "")))
		_expect(parent_region.is_empty() or region_ids.has(parent_region), "%s 的父地区引用有效" % str(city.get("name", "")))
	for port_variant: Variant in _view.prototype_data.get_document("ports").get("ports", []):
		var port: Dictionary = port_variant as Dictionary
		_expect(country_ids.has(str(port.get("parent_country_id", ""))) and not str(port.get("city_id", "")).is_empty(), "%s 具有父国家和城市" % str(port.get("name", "")))


func _test_zoom_semantics() -> void:
	var map: PrototypeV2MapCanvas = _view.map_canvas
	var paris: Dictionary = map.get_city("paris")
	var lille: Dictionary = map.get_city("lille")
	var calais: Dictionary = map.get_city("calais")
	var administration: Dictionary = map.get_institution("northern_administration")
	map.zoom = 1.0
	_expect(map.get_zoom_level() == "far", "远景缩放语义为世界层")
	_expect(map.is_record_visible(paris) and not map.is_record_visible(lille), "远景只显示少量首都或主要城市")
	map.zoom = 3.25
	_expect(map.get_zoom_level() == "middle", "中景缩放语义为国家与地区层")
	_expect(map.is_record_visible(lille) and not map.is_record_visible(calais) and not map.is_record_visible(administration), "中景显示主要城市但隐藏地方节点")
	map.zoom = 9.2
	_expect(map.get_zoom_level() == "near", "近景缩放语义为地方层")
	_expect(map.is_record_visible(calais) and map.is_record_visible(administration), "近景显示小城市与地方机构")
	map.reset_view()


func _test_layout_constraints() -> void:
	var rects: Array[Rect2] = [
		PrototypeV2Interface.COUNTRY_CORNER,
		PrototypeV2Interface.TIME_CORNER,
		PrototypeV2Interface.CHARACTER_CORNER,
		PrototypeV2Interface.ACTIVITY_CORNER,
		PrototypeV2Interface.MODE_ENTRY,
	]
	for rect: Rect2 in rects:
		_expect(_rect_inside(rect, VIEWPORT_RECT), "四角入口与紧凑地图模式位于 1280×720 内")
	_expect(_view.map_canvas.size == Vector2(1280.0, 720.0), "地理地图画布覆盖完整 1280×720")
	for panel_id: String in ["country", "character", "activity", "time"]:
		_view.interface.open_panel_named(panel_id, false)
		var panel_rect: Rect2 = _view.interface.get_panel_rect()
		_expect(_rect_inside(panel_rect, VIEWPORT_RECT), "%s 面板在 1280×720 无裁切" % panel_id)
		_expect(panel_rect.size.x <= 420.0, "%s 面板宽度不超过 420 px" % panel_id)
		_expect((1280.0 - panel_rect.size.x) / 1280.0 >= 0.65, "%s 打开后地图横向可见比例不少于 65%%" % panel_id)
	_view.interface.close_panel(false)


func _test_corner_entries_and_identity_review() -> void:
	var interface: PrototypeV2Interface = _view.interface
	await process_frame
	interface.handle_pointer_pressed(Vector2(120.0, 52.0))
	await create_timer(0.22).timeout
	_expect(interface.open_panel == "country", "左上国家入口可点击打开")
	interface.close_panel(false)
	await process_frame
	interface.handle_pointer_pressed(Vector2(1120.0, 55.0))
	await create_timer(0.22).timeout
	_expect(interface.open_panel == "time", "右上日期入口可点击展开")
	interface.close_panel(false)
	interface.open_panel_named("character", false)
	await process_frame
	var character_state: Dictionary = interface.debug_state()
	_expect(character_state.get("character_corner_visible", true) == false, "打开人物中心后左下人物摘要不重复显示")
	interface.close_panel(false)
	_expect(interface.debug_state().get("identity_switch_visible", true) == false, "普通原型模式隐藏身份切换器")
	interface.set_review_mode(true)
	await process_frame
	interface.handle_pointer_pressed(Vector2(710.0, 30.0))
	_expect(interface.identity == "official", "--prototype-review 评审工具可切换地方官员")
	interface.set_review_mode(false)
	await process_frame
	interface.handle_pointer_pressed(PrototypeV2Interface.MODE_ENTRY.get_center())
	_expect(interface.mode_menu_open, "单个地图模式入口可展开紧凑菜单")
	interface.close_top_layer()


func _test_identity_information_architecture() -> void:
	var interface: PrototypeV2Interface = _view.interface
	interface.set_identity("worker")
	interface.open_panel_named("country", false)
	var worker_state: Dictionary = interface.debug_state()
	interface.set_identity("official")
	var official_state: Dictionary = interface.debug_state()
	_expect(worker_state.get("institution_structure") == "public_portal", "普通工人国家入口使用公开政策与新闻结构")
	_expect(official_state.get("institution_structure") == "department_hierarchy", "地方官员机构页使用部门层级结构")
	var official: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}).get("official", {}) as Dictionary
	for field: String in ["department", "supervisor", "subordinates", "jurisdiction", "budget_source", "agenda", "procedures", "upstream_locked"]:
		_expect(official.has(field), "地方官员结构包含 %s" % field)
	var worker: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}).get("worker", {}) as Dictionary
	for field: String in ["work_contract", "employer", "union", "household"]:
		_expect(worker.has(field), "普通工人生活与工作结构包含 %s" % field)
	var actions: Dictionary = interface.debug_state()
	_expect(int(actions.get("object_card_primary_actions", 0)) == 1 and int(actions.get("object_card_secondary_actions", 0)) <= 2, "单张对象卡第一层限制为一个主动作和不超过两个次入口")
	interface.close_panel(false)


func _test_organization_and_activity_structure() -> void:
	var organization_identities: Dictionary = _view.prototype_data.get_document("organizations").get("identities", {}) as Dictionary
	for identity_id: String in ["worker", "official"]:
		var identity_data: Dictionary = organization_identities[identity_id] as Dictionary
		var owned: Array = identity_data.get("owned", []) as Array
		var discover: Array = identity_data.get("discover", []) as Array
		_expect(not owned.is_empty() and not discover.is_empty(), "%s 的我的组织与探索组织数据保持分离" % identity_id)
		for organization_variant: Variant in owned:
			var organization: Dictionary = organization_variant as Dictionary
			for field: String in ["emblem", "position", "department", "project", "supervisor", "authority"]:
				_expect(organization.has(field), "%s 我的组织卡包含 %s" % [identity_id, field])
		for organization_variant: Variant in discover:
			var organization: Dictionary = organization_variant as Dictionary
			_expect(not str(organization.get("contact_source", "")).is_empty(), "%s 探索组织说明接触来源" % str(organization.get("name", "")))
	var summary: Dictionary = _view.prototype_data.get_document("activity").get("default_summary", {}) as Dictionary
	_expect(int(summary.get("max_visible_items", 0)) == 1, "世界动态默认只显示一条摘要")
	var kinds: Dictionary = {}
	for item_variant: Variant in _view.prototype_data.get_document("activity").get("items", []):
		var item: Dictionary = item_variant as Dictionary
		kinds[str(item.get("kind", ""))] = true
	_expect(kinds.has("notification") and kinds.has("event") and kinds.has("news"), "世界动态区分通知、事件与新闻")
	var grouped: bool = false
	for item_variant: Variant in _view.prototype_data.get_document("activity").get("items", []):
		if int((item_variant as Dictionary).get("group_count", 1)) > 1:
			grouped = true
	_expect(grouped, "同类普通动态存在聚合消息")


func _test_map_modes_and_war_state() -> void:
	var map: PrototypeV2MapCanvas = _view.map_canvas
	var baseline_id: String = map.get_shared_basemap_id()
	for mode_id: String in ["legal", "market", "population", "war"]:
		map.set_mode(mode_id)
		_expect(map.get_shared_basemap_id() == baseline_id, "%s 模式复用同一地理底图" % mode_id)
	map.set_mode("war")
	map.set_war_example_active(false)
	_expect(not map.has_visible_front(), "和平状态不显示战线")
	map.set_war_example_active(true)
	_expect(map.has_visible_front(), "战争示例只增加静态控制覆盖与战线")
	map.set_war_example_active(false)
	map.set_mode("legal")


func _test_map_selection() -> void:
	_expect(_view.select_review_object("country", "france"), "国家对象可从地图进入对象卡")
	_expect(_view.map_canvas.selected_type == "country", "国家选择获得独立层级高亮")
	_expect(_view.select_review_object("region", "north_industrial"), "地区对象可从地图进入对象卡")
	_expect(_view.select_review_object("city", "lille"), "城市对象可从地图进入对象卡")
	_expect(_view.select_review_object("institution", "northern_administration"), "地方机构对象可从地图进入对象卡")
	var state: Dictionary = _view.interface.debug_state()
	_expect(int(state.get("object_card_primary_actions", 0)) == 1, "地图对象卡不平铺大量等权动作")
	_view.interface.close_top_layer()
	_expect(_view.map_canvas.selected_id.is_empty(), "关闭对象卡会取消地图选择")


func _test_escape_and_exclusivity() -> void:
	var interface: PrototypeV2Interface = _view.interface
	interface.open_panel_named("character", false)
	interface.open_panel_named("country", false)
	_expect(interface.open_panel == "country", "主要面板互斥，后打开面板替换前一面板")
	interface.apply_review_state("person_detail")
	_expect(interface.close_top_layer() and interface.detail_person_id.is_empty(), "Esc 第一层关闭人物第三层详情")
	interface.open_panel_named("character", false)
	var closed_workspace: bool = interface.close_top_layer()
	await create_timer(0.18).timeout
	_expect(closed_workspace and interface.open_panel.is_empty(), "Esc 下一层关闭人物中心")
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
			_expect(not source.contains(token), "%s 不引用正式服务边界 %s" % [path.get_file(), token])


func _point_on_land(point: Vector2, features: Array) -> bool:
	for feature_variant: Variant in features:
		var feature: Dictionary = feature_variant as Dictionary
		for ring_variant: Variant in feature.get("rings", []):
			var polygon := PackedVector2Array()
			for raw_point_variant: Variant in ring_variant as Array:
				var raw_point: Array = raw_point_variant as Array
				polygon.append(Vector2(float(raw_point[0]), float(raw_point[1])))
			if Geometry2D.is_point_in_polygon(point, polygon):
				return true
	return false


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
	print("V2.1 prototype smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
