extends SceneTree
## V2.1.2 map, hierarchy, layout, and interaction smoke coverage.

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
	_expect(packed != null, "独立 V2.1.2 原型场景资源可加载")
	if packed == null:
		_finish()
		return
	_view = packed.instantiate() as PrototypeV2Main
	_expect(_view != null, "独立 V2.1.2 原型场景可实例化")
	if _view == null:
		_finish()
		return
	root.add_child(_view)
	current_scene = _view
	await process_frame
	await process_frame
	_expect(_view.prototype_data != null and _view.prototype_data.errors.is_empty(), "V2.1.2 静态数据加载且不依赖正式服务")
	_expect(_view.map_canvas != null and _view.interface != null, "地理地图与四角界面同时建立")
	_test_geographic_projection_and_land()
	_test_transport_semantics()
	_test_hierarchy()
	_test_zoom_semantics()
	_test_country_identity_and_emblem()
	_test_french_names_and_culture()
	_test_content_reference_consistency()
	_test_v2_1_2_map_geometry_and_camera()
	await _test_v2_1_2_performance_architecture()
	_test_v2_1_2_country_labels()
	_test_v2_1_2_status_and_plan()
	_test_v2_1_2_relationships_and_organizations()
	_test_v2_1_2_economy_permissions_and_tools()
	_test_label_density_and_detail_nodes()
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
			_expect(str((cities[from_id] as Dictionary).get("parent_country_id", "")) == "country_fra" and str((cities[to_id] as Dictionary).get("parent_country_id", "")) == "country_fra", "%s 为法国原型国内铁路" % str(segment.get("id", "")))
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
	var administration: Dictionary = map.get_institution("prefecture_nord")
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


func _test_country_identity_and_emblem() -> void:
	var france: Dictionary = _view.map_canvas.get_country("country_fra")
	_expect(str(france.get("stable_id", "")) == "country_fra", "法国使用独立稳定 ID")
	_expect(str(france.get("data_code", "")) == "FRA", "法国数据简码保留在内部数据字段")
	_expect(str(france.get("display_name_zh", "")) == "法兰西共和国", "法国紧凑入口使用中文显示名")
	_expect(str(france.get("formal_name_zh", "")) == "法兰西第三共和国", "法国详情使用正式名称")
	_expect(str(france.get("native_name", "")) == "République française", "法国数据包含法语原名")
	_expect(str(france.get("emblem_type", "")) == "french_tricolor_rf", "法国徽记使用三色 RF 类型")
	var ui_state: Dictionary = _view.interface.debug_state()
	var visible_country_text: String = str(ui_state.get("country_visible_text", ""))
	for internal_token: String in ["FR", "FRA", "country_fra"]:
		_expect(not visible_country_text.contains(internal_token), "正式国家 UI 文本不暴露 %s" % internal_token)
	_expect(str(ui_state.get("country_detail_name", "")) == "法兰西第三共和国", "国家详情调试状态对应正式显示名")
	_expect(str(ui_state.get("country_emblem_type", "")) == "french_tricolor_rf", "国家角标绑定三色徽记类型")


func _test_french_names_and_culture() -> void:
	var name_pool: Dictionary = _view.prototype_data.get_document("name_pool_fr")
	var given_names: Array = name_pool.get("given_names", []) as Array
	var family_names: Array = name_pool.get("family_names", []) as Array
	var male_count: int = 0
	var female_count: int = 0
	for entry_variant: Variant in given_names:
		var entry: Dictionary = entry_variant as Dictionary
		if str(entry.get("gender", "")) == "male":
			male_count += 1
		elif str(entry.get("gender", "")) == "female":
			female_count += 1
		for field: String in ["culture_id", "gender", "class_tags", "region_tags", "native_given_name", "display_given_name_zh"]:
			_expect(entry.has(field), "法国名字条目包含 %s" % field)
	for entry_variant: Variant in family_names:
		var entry: Dictionary = entry_variant as Dictionary
		for field: String in ["culture_id", "gender", "class_tags", "region_tags", "native_family_name", "display_family_name_zh"]:
			_expect(entry.has(field), "法国姓氏条目包含 %s" % field)
	_expect(male_count >= 12, "法国姓名池包含至少 12 个男性常见名")
	_expect(female_count >= 12, "法国姓名池包含至少 12 个女性常见名")
	_expect(family_names.size() >= 30, "法国姓名池包含至少 30 个常见姓氏")
	var characters: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}) as Dictionary
	for identity_id: String in ["worker", "official"]:
		var person: Dictionary = characters.get(identity_id, {}) as Dictionary
		_expect(str(person.get("culture_id", "")) == "fra", "%s 默认人物使用法国文化" % identity_id)
		_expect(str(person.get("nationality_id", "")) == "country_fra", "%s 默认人物引用法国国籍" % identity_id)
		_expect(not str(person.get("native_name", "")).is_empty(), "%s 默认人物包含法语原名" % identity_id)
		_expect(not str(person.get("display_name_zh", "")).is_empty(), "%s 默认人物包含中文规范音译" % identity_id)
		_expect(str(person.get("name_source", "")) == "prototype_v2_fr_pool", "%s 默认人物引用法国姓名池" % identity_id)
		_expect(str(person.get("migration_background", "")) == "none", "%s 默认人物明确无移民背景" % identity_id)
	_expect(str((characters.get("worker", {}) as Dictionary).get("display_name_zh", "")) == "皮埃尔·勒费弗尔", "普通工人示例为皮埃尔·勒费弗尔")
	_expect(str((characters.get("official", {}) as Dictionary).get("display_name_zh", "")) == "阿尔贝·迪蒙", "地方官员示例为阿尔贝·迪蒙")
	var relationships: Array = _view.prototype_data.get_document("relationships").get("relationships", []) as Array
	for relation_variant: Variant in relationships:
		var relation: Dictionary = relation_variant as Dictionary
		_expect(str(relation.get("culture_id", "")) == "fra" and str(relation.get("name_source", "")) == "prototype_v2_fr_pool", "%s 使用法国姓名池" % str(relation.get("display_name_zh", "")))
		_expect(not str(relation.get("native_name", "")).is_empty(), "%s 同时存储法语原名" % str(relation.get("display_name_zh", "")))
	var person_text: String = JSON.stringify(_view.prototype_data.get_document("characters")) + JSON.stringify(_view.prototype_data.get_document("relationships"))
	for old_name: String in ["林彻", "周明岚", "周明崴", "王明"]:
		_expect(not person_text.contains(old_name), "默认人物数据删除旧姓名 %s" % old_name)


func _test_content_reference_consistency() -> void:
	var countries: Dictionary = _index_records(_view.prototype_data.get_document("countries").get("countries", []) as Array)
	var regions: Dictionary = _index_records(_view.prototype_data.get_document("regions").get("regions", []) as Array)
	var administrative_units: Dictionary = _index_records(_view.prototype_data.get_document("regions").get("administrative_units", []) as Array)
	var cities: Dictionary = _index_records(_view.prototype_data.get_document("cities").get("cities", []) as Array)
	var institutions: Dictionary = _index_records(_view.prototype_data.get_document("institutions").get("institutions", []) as Array)
	var organization_document: Dictionary = _view.prototype_data.get_document("organizations")
	var organizations: Dictionary = _index_records(organization_document.get("catalog", []) as Array)
	for region_variant: Variant in regions.values():
		var region: Dictionary = region_variant as Dictionary
		_expect(str(region.get("region_kind", "")) == "gameplay_macro_region", "%s 明确为游戏宏观地区" % str(region.get("name", "")))
	for unit_variant: Variant in administrative_units.values():
		var unit: Dictionary = unit_variant as Dictionary
		_expect(str(unit.get("region_kind", "")) == "historical_administrative_unit", "%s 与游戏宏观地区使用不同类型" % str(unit.get("name", "")))
	_expect(administrative_units.has("departement_nord") and administrative_units.has("arrondissement_lille") and administrative_units.has("commune_lille"), "北部省、里尔区和里尔市形成独立行政单位链")
	for organization_variant: Variant in organizations.values():
		var organization: Dictionary = organization_variant as Dictionary
		_expect(cities.has(str(organization.get("city_id", ""))), "%s 引用有效城市" % str(organization.get("name", "")))
		if str(organization.get("organization_kind", "")) == "enterprise":
			_expect(not str(organization.get("industry_id", "")).is_empty(), "%s 企业具有行业类型" % str(organization.get("name", "")))
		if str(organization.get("organization_kind", "")) == "labor_union":
			_expect(not str(organization.get("industry_id", "")).is_empty(), "%s 工会具有行业类型" % str(organization.get("name", "")))
	for institution_variant: Variant in institutions.values():
		var institution: Dictionary = institution_variant as Dictionary
		_expect(not str(institution.get("administrative_level", "")).is_empty(), "%s 具有行政层级" % str(institution.get("name", "")))
		_expect(countries.has(str(institution.get("parent_country_id", ""))), "%s 引用有效国家" % str(institution.get("name", "")))
	var identities: Dictionary = organization_document.get("identities", {}) as Dictionary
	for identity_id: String in ["worker", "official"]:
		var identity_data: Dictionary = identities.get(identity_id, {}) as Dictionary
		_expect(identity_data.get("owned", []) != identity_data.get("discover", []), "%s 的我的组织与探索组织保持数据分离" % identity_id)
		for collection_id: String in ["owned", "discover"]:
			for context_variant: Variant in identity_data.get(collection_id, []):
				var context: Dictionary = context_variant as Dictionary
				_expect(organizations.has(str(context.get("organization_id", ""))), "%s 的 %s 组织引用有效" % [identity_id, collection_id])
				if collection_id == "discover":
					_expect(not str(context.get("contact_source", "")).is_empty(), "%s 的探索组织说明真实接触来源" % identity_id)
	var characters: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}) as Dictionary
	var worker: Dictionary = characters.get("worker", {}) as Dictionary
	var official: Dictionary = characters.get("official", {}) as Dictionary
	for organization_field: String in ["employer_id", "union_id", "school_id"]:
		_expect(organizations.has(str(worker.get(organization_field, ""))), "普通工人 %s 引用法国原型组织" % organization_field)
	_expect(institutions.has(str(official.get("institution_id", ""))), "行政职位引用有效政府机构")
	_expect(administrative_units.has(str(official.get("jurisdiction_id", ""))), "地方官员管辖范围引用有效行政单位")
	var activity: Dictionary = _view.prototype_data.get_document("activity")
	for item_variant: Variant in activity.get("items", []):
		var item: Dictionary = item_variant as Dictionary
		_expect(not str(item.get("source_type", "")).is_empty() and not str(item.get("public_channel", "")).is_empty(), "%s 记录来源类型与公开渠道" % str(item.get("title", "")))
		_expect(not str(item.get("occurred_at", "")).is_empty() and not str(item.get("aggregation_key", "")).is_empty(), "%s 记录时间与聚合键" % str(item.get("title", "")))
		_expect(regions.has(str(item.get("region_id", ""))), "%s 引用有效宏观地区" % str(item.get("title", "")))
		for organization_id_variant: Variant in item.get("organization_ids", []):
			_expect(organizations.has(str(organization_id_variant)), "%s 引用有效组织" % str(item.get("title", "")))
		for institution_id_variant: Variant in item.get("institution_ids", []):
			_expect(institutions.has(str(institution_id_variant)), "%s 引用有效机构" % str(item.get("title", "")))
		match str(item.get("location_type", "")):
			"country":
				_expect(countries.has(str(item.get("location_id", ""))), "%s 发生国家有效" % str(item.get("title", "")))
			"region":
				_expect(regions.has(str(item.get("location_id", ""))), "%s 发生地区有效" % str(item.get("title", "")))
			"city":
				_expect(cities.has(str(item.get("location_id", ""))), "%s 发生城市有效" % str(item.get("title", "")))
			"administrative_unit":
				_expect(administrative_units.has(str(item.get("location_id", ""))), "%s 发生行政单位有效" % str(item.get("title", "")))
	var content_text: String = JSON.stringify(_view.prototype_data.records)
	for forbidden_text: String in ["河港", "北部工业区行政署", "地方事务员"]:
		_expect(not content_text.contains(forbidden_text), "法国原型不再出现 %s" % forbidden_text)
	for old_region_id: String in ["north_industrial", "atlantic_west", "southwest", "rhone_alps", "alsace_lorraine"]:
		_expect(not regions.has(old_region_id), "不存在旧架空地区 ID %s" % old_region_id)


func _test_v2_1_2_map_geometry_and_camera() -> void:
	var map: PrototypeV2MapCanvas = _view.map_canvas
	var world_document: Dictionary = _view.prototype_data.get_document("world_coastlines")
	var geometry_audit: Dictionary = map.get_land_geometry_audit()
	_expect(int(geometry_audit.get("africa_features", 0)) == int((world_document.get("audit", {}) as Dictionary).get("africa_feature_count", -1)) and int(geometry_audit.get("africa_features", 0)) >= 50, "非洲全部 Natural Earth 陆地要素存在")
	_expect(int(geometry_audit.get("empty_stable_ids", -1)) == 0, "所有有效陆地国家要素具有稳定回退 ID")
	_expect(int(geometry_audit.get("transparent_land_colors", -1)) == 0, "无陆地国家使用透明或海洋颜色")
	_expect(int(geometry_audit.get("failed_outer_rings", -1)) == 0, "全部 Polygon 与 MultiPolygon 外环可绘制：%s" % str(geometry_audit.get("failed_outer_ring_ids", [])))
	_expect(int(geometry_audit.get("outer_rings", 0)) == int((world_document.get("audit", {}) as Dictionary).get("outer_ring_count", -1)), "MultiPolygon 全部外环进入地图审计")
	var repaired: Array = (world_document.get("audit", {}) as Dictionary).get("repaired_features", []) as Array
	_expect(repaired.size() == 1 and str((repaired[0] as Dictionary).get("iso_a3", "")) == "SDN", "苏丹自交尖刺修复原因记录在生成数据中")

	var region_document: Dictionary = _view.prototype_data.get_document("regions")
	var regions: Array = region_document.get("regions", []) as Array
	var units: Array = region_document.get("administrative_units", []) as Array
	var department_count: int = 0
	for unit_variant: Variant in units:
		var unit: Dictionary = unit_variant as Dictionary
		if str(unit.get("administrative_level", "")) != "departement":
			continue
		department_count += 1
		for field: String in ["stable_id", "administrative_level", "parent_country_id", "geometry", "label_anchor", "label_priority", "visible_zoom_min", "display_name_zh", "native_name"]:
			_expect(unit.has(field), "%s 具有行政区字段 %s" % [str(unit.get("display_name_zh", "")), field])
		var geometry: Array = unit.get("geometry", []) as Array
		_expect(not geometry.is_empty() and not _polygon_is_rectangle((geometry[0] as Dictionary).get("outer", []) as Array), "%s 使用自然多边形而非矩形" % str(unit.get("display_name_zh", "")))
	_expect(department_count == 96, "法国加载 96 个本土省级自然边界占位")
	_expect((region_document.get("coverage", {}) as Dictionary).get("unassigned_department_codes", []) == [], "全部法国本土省级单位组合进宏观地区")
	for region_variant: Variant in regions:
		var region: Dictionary = region_variant as Dictionary
		_expect(not region.has("polygon_lon_lat") and not (region.get("administrative_unit_ids", []) as Array).is_empty(), "%s 由行政单位组合而非独立矩形生成" % str(region.get("name", "")))
	_expect(PrototypeV2MapCanvas.REGION_BORDER != PrototypeV2MapCanvas.ADMINISTRATIVE_BORDER, "宏观地区与行政单位使用不同线条样式")
	_expect(map.get_maximum_zoom() >= 24.0 and map.get_maximum_zoom() >= float((_view.prototype_data.get_document("map_modes").get("zoom", {}) as Dictionary).get("v2_1_1_maximum", 12.0)) * 2.0, "最大缩放至少达到 V2.1.1 上限的两倍")
	map.focus_france()
	var france_rect: Rect2 = map.get_country_screen_rect("country_fra", true)
	_expect(france_rect.size.y / 720.0 >= 0.70, "法国聚焦后占据视口高度 70% 以上")
	map.focus_player_location()
	var nord_rect: Rect2 = map.get_administrative_unit_screen_rect("departement_nord")
	_expect(map.camera_focus_id == "lille" and is_equal_approx(map.zoom, 96.0), "当前人物所在地可归位到里尔高倍率近景")
	_expect(nord_rect.size.x / 1280.0 >= 0.45 or nord_rect.size.y / 720.0 >= 0.45, "北部省高倍率近景占据主要地图区域：%s" % str(nord_rect.size))
	_expect(_read_text("res://scripts/prototype_v2/prototype_v2_main.gd").contains("_ui_captured_press = true"), "双击镜头入口消费释放事件，避免穿透打开地图对象卡")
	map.focus_current_country()
	_expect(map.camera_focus_id == "country_fra", "当前国家可归位到法国")
	map.focus_world()
	_expect(map.camera_focus_id == "world" and map.get_zoom_level() == "far", "Home 语义可返回世界视角")
	map.zoom = map.get_maximum_zoom()
	map.pan = Vector2(100000.0, -100000.0)
	map.pan_by(Vector2.ZERO)
	var scaled_world := Rect2(map.pan, PrototypeV2MapCanvas.WORLD_SIZE * map.zoom)
	_expect(scaled_world.intersects(VIEWPORT_RECT), "高倍率平移后地图不能完全离开窗口")
	map.reset_view()


func _test_v2_1_2_performance_architecture() -> void:
	var map: PrototypeV2MapCanvas = _view.map_canvas
	var interface: PrototypeV2Interface = _view.interface
	var cold_map := PrototypeV2MapCanvas.new()
	cold_map.size = Vector2(1280.0, 720.0)
	root.add_child(cold_map)
	cold_map.setup(_view.prototype_data)
	await process_frame
	var cold_state: Dictionary = cold_map.debug_architecture_state()
	_expect(
		(cold_state.get("loaded_administrative_lods", []) as Array).is_empty()
		and (cold_state.get("loaded_macro_lods", []) as Array).is_empty(),
		"世界远景不实例化法国行政区与宏观地区高精度绘制数组"
	)
	cold_map.queue_free()
	await process_frame
	var cache: Dictionary = _view.prototype_data.get_document("map_geometry_cache")
	var country_lods: Dictionary = cache.get("country_lods", {}) as Dictionary
	var lod_vertex_counts: Array[int] = []
	for lod_id: String in ["lod0", "lod1", "lod2", "lod3", "lod4"]:
		var vertex_count: int = 0
		for feature_variant: Variant in country_lods.get(lod_id, []):
			for polygon_variant: Variant in (
				feature_variant as Dictionary
			).get("polygons", []):
				vertex_count += (
					(polygon_variant as Dictionary).get("outer", []) as Array
				).size()
		lod_vertex_counts.append(vertex_count)
	_expect(
		lod_vertex_counts[0] < lod_vertex_counts[1]
		and lod_vertex_counts[1] < lod_vertex_counts[4],
		"世界远景使用独立强简化 LOD，近景保留更多顶点"
	)
	map.focus_world()
	await process_frame
	var far_state: Dictionary = map.debug_architecture_state()
	var far_counts: Dictionary = far_state.get("visible_counts", {}) as Dictionary
	_expect(
		str(far_state.get("lod", "")) == "lod0"
		and int(far_counts.get("administrative_units", -1)) == 0,
		"世界远景使用 LOD0 且不查询法国行政区"
	)
	map.focus_player_location()
	await process_frame
	var local_state: Dictionary = map.debug_architecture_state()
	var local_counts: Dictionary = local_state.get("visible_counts", {}) as Dictionary
	_expect(
		str(local_state.get("lod", "")) == "lod4"
		and int(local_counts.get("administrative_units", 0)) > 0
		and int(local_counts.get("administrative_units", 999)) < 98,
		"96 倍地方视角只保留视口附近行政区"
	)
	_expect(
		int(local_counts.get("cities", 999)) < (
			_view.prototype_data.get_document("cities").get("cities", []) as Array
		).size()
		and int(local_counts.get("labels", 999)) < 177,
		"屏幕外城市和标签不进入地方视角布局"
	)
	_expect(
		(local_state.get("layers", []) as Array).size() == 9
		and (local_state.get("layers", []) as Array).has("countries")
		and (local_state.get("layers", []) as Array).has("selection"),
		"基础几何与动态选择覆盖层由少量批绘层分离"
	)

	map.debug_reset_performance_metrics()
	map.begin_camera_interaction()
	for _index: int in range(40):
		map.pan_by(Vector2(2.0, -1.0))
	var drag_snapshot: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(drag_snapshot.get("queue_redraw_calls", -1)) == 0
		and int(drag_snapshot.get("visible_queries", -1)) == 0,
		"拖动热循环只更新统一变换，不触发完整重绘或空间查询"
	)
	_expect(
		int(drag_snapshot.get("projection_calls", -1)) == 0
		and int(drag_snapshot.get("runtime_merge_calls", -1)) == 0
		and int(drag_snapshot.get("runtime_triangulation_calls", -1)) == 0,
		"拖动热循环不执行 Robinson 投影、几何合并或三角化"
	)
	_expect(
		int(drag_snapshot.get("label_rebuilds", -1)) == 0
		and int(drag_snapshot.get("label_cache_reuses", 0)) == 40,
		"同一缩放档拖动复用标签布局缓存"
	)
	_expect(
		int(drag_snapshot.get("transport_rebuilds", -1)) == 0
		and int(drag_snapshot.get("json_parses_during_camera", -1)) == 0,
		"拖动不会重建铁路或重新解析 JSON"
	)
	map.end_camera_interaction()
	await process_frame
	var settled_drag: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(settled_drag.get("visible_queries", -1)) == 1
		and int(settled_drag.get("label_rebuilds", -1)) == 1
		and int(settled_drag.get("queue_redraw_calls", 99)) <= 8,
		"拖动结束只进行一次裁剪、标签恢复和分层刷新"
	)

	map.focus_player_location()
	map.debug_reset_performance_metrics()
	var zoom_anchor := Vector2(704.0, 372.0)
	for operation_index: int in range(100):
		map.zoom_at(-1.0 if operation_index % 2 == 0 else 1.0, zoom_anchor)
	var zoom_snapshot: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(zoom_snapshot.get("queue_redraw_calls", -1)) == 0
		and int(zoom_snapshot.get("projection_calls", -1)) == 0
		and int(zoom_snapshot.get("label_rebuilds", -1)) == 0,
		"同一 LOD 内快速缩放只变换缓存层，不逐次重建地图和标签"
	)
	await create_timer(0.1).timeout
	await process_frame
	var settled_zoom: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(settled_zoom.get("visible_queries", -1)) == 1
		and int(settled_zoom.get("queue_redraw_calls", 99)) <= 8,
		"快速缩放停止后仅执行一次精确刷新"
	)

	var lille_screen: Vector2 = map.lon_lat_to_screen([3.064, 50.637])
	map.debug_reset_performance_metrics()
	map.get_object_at(lille_screen)
	var click_snapshot: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(click_snapshot.get("click_candidates", 999)) < 20,
		"点击检测先使用空间候选集而非遍历全部多边形"
	)

	map.debug_reset_performance_metrics()
	interface.open_panel_named("character", false)
	await process_frame
	var panel_snapshot: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(panel_snapshot.get("queue_redraw_calls", -1)) == 0
		and int(panel_snapshot.get("visible_queries", -1)) == 0,
		"打开人物面板不会重排或重建整张地图"
	)
	interface.close_panel(false)
	map.set_mode("population")
	var overlay_snapshot: Dictionary = map.debug_performance_snapshot()
	_expect(
		int(overlay_snapshot.get("visible_queries", -1)) == 0
		and int(overlay_snapshot.get("queue_redraw_calls", 99)) == 4,
		"切换覆盖层只刷新受影响图层"
	)
	map.set_mode("legal")

	map.focus_player_location()
	await process_frame
	var home_center: Vector2 = PrototypeV2Interface.WORLD_VIEW_ENTRY.get_center()
	interface.handle_pointer_motion(home_center)
	var home_hover_state: Dictionary = interface.debug_state()
	var home_consumed: bool = interface.handle_pointer_pressed(home_center)
	_expect(
		home_consumed
		and map.camera_focus_id == "world"
		and map.get_zoom_level() == "far",
		"底部归位图标消费点击并返回世界视角"
	)
	_expect(
		str(home_hover_state.get("hover_tooltip", "")) == "返回世界视角（Home）",
		"归位图标悬停明确显示 Home 提示"
	)
	_expect(
		_rect_inside(PrototypeV2Interface.WORLD_VIEW_ENTRY, VIEWPORT_RECT),
		"归位图标在 1280×720 视口内无裁切"
	)
	var map_source: String = _read_text(
		"res://scripts/prototype_v2/prototype_v2_map_canvas.gd"
	)
	var builder_source: String = _read_text(
		"res://tools/prototype_v2/build_map_performance_geometry.gd"
	)
	_expect(
		not map_source.contains("Geometry2D.merge_polygons")
		and not map_source.contains("Geometry2D.triangulate_polygon")
		and builder_source.contains("Geometry2D.merge_polygons")
		and builder_source.contains("Geometry2D.triangulate_polygon"),
		"几何合并与三角化仅存在于离线构建工具"
	)
	interface.handle_pointer_motion(Vector2.ZERO)
	map.reset_view()


func _test_v2_1_2_country_labels() -> void:
	var map: PrototypeV2MapCanvas = _view.map_canvas
	var countries: Array = _view.prototype_data.get_document("countries").get("countries", []) as Array
	_expect(countries.size() == 177, "全部 177 个 Natural Earth 国家要素具有名称记录")
	for country_variant: Variant in countries:
		var country: Dictionary = country_variant as Dictionary
		for field: String in ["display_name_zh", "formal_name_zh", "native_name", "label_priority", "visible_zoom_min", "label_anchor"]:
			_expect(country.has(field) and (not country[field] is String or not str(country[field]).is_empty()), "%s 具有完整国家字段 %s" % [str(country.get("data_code", "")), field])
		_expect(map.country_label_can_be_revealed(country), "%s 可通过悬停或足够缩放显示名称" % str(country.get("display_name_zh", "")))
	_expect(map.get_label_budget("country", "far") <= 12, "世界远景国家标签保持预算上限")
	_expect(map.get_label_budget("country", "middle") <= 12, "欧洲中景继续使用碰撞预算")
	var collision_candidates: Array = [{"id":"france","priority":100,"rect":Rect2(100,100,90,24)}, {"id":"belgium","priority":80,"rect":Rect2(150,100,80,24)}, {"id":"luxembourg","priority":60,"rect":Rect2(165,100,100,24)}]
	_expect(map.debug_resolve_label_candidates(collision_candidates, 12) == ["france"], "欧洲中景重叠标签保留高优先级项")


func _test_v2_1_2_status_and_plan() -> void:
	var identities: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}) as Dictionary
	for identity_id: String in ["worker", "official"]:
		var person: Dictionary = identities.get(identity_id, {}) as Dictionary
		var indicators: Array = person.get("status_indicators", []) as Array
		_expect(indicators.size() >= 3, "%s 人物概览具有统一状态符号" % identity_id)
		for indicator_variant: Variant in indicators:
			var indicator: Dictionary = indicator_variant as Dictionary
			_expect(str(indicator.get("symbol", "")) in ["✓", "!", "×", "🔒"], "%s 状态第一层使用规范符号" % identity_id)
			for field: String in ["state", "reason", "trend", "impact", "suggestion"]:
				_expect(not str(indicator.get(field, "")).is_empty(), "%s 状态悬停说明包含 %s" % [identity_id, field])
		var plan: Dictionary = person.get("plan_detail", {}) as Dictionary
		_expect(not str(plan.get("title", "")).contains("%") and not str(person.get("plan", "")).contains("%"), "%s 当前计划标题不包含成功率百分比" % identity_id)
		for field: String in ["goal", "responsible", "stage", "duration", "effects", "time_cost", "resources", "authority", "stop_conditions", "next_step"]:
			_expect(plan.has(field), "%s 当前计划主要说明包含 %s" % [identity_id, field])
		_expect(str(plan.get("success_symbol", "")) in ["★", "✓", "!", "×"] and not str(plan.get("success_detail", "")).is_empty(), "%s 成功信息仅作为附属符号与悬停说明" % identity_id)
	var ui_state: Dictionary = _view.interface.debug_state()
	_expect(ui_state.get("plan_formula_visible") == false, "普通计划界面不显示完整内部公式")


func _test_v2_1_2_relationships_and_organizations() -> void:
	var ui_state: Dictionary = _view.interface.debug_state()
	_expect(ui_state.get("visible_ellipsis_has_menu") == true, "所有保留的可见省略号均具有二级菜单")
	var jeanne: Dictionary = _index_records(_view.prototype_data.get_document("relationships").get("relationships", []) as Array).get("jeanne", {}) as Dictionary
	for field: String in ["relation_type", "familiarity", "trust", "affinity", "common_work", "common_organizations", "common_contacts", "last_interaction", "obligations", "available_relationship_actions"]:
		_expect(jeanne.has(field), "关系详情预留 %s" % field)
	var organization_document: Dictionary = _view.prototype_data.get_document("organizations")
	var organization_identities: Dictionary = organization_document.get("identities", {}) as Dictionary
	var worker_discover: Array = (organization_identities.get("worker", {}) as Dictionary).get("discover", []) as Array
	var official_discover: Array = (organization_identities.get("official", {}) as Dictionary).get("discover", []) as Array
	_expect(JSON.stringify(worker_discover) != JSON.stringify(official_discover), "普通工人与公务员探索组织集合不同")
	for collection: Array in [worker_discover, official_discover]:
		for context_variant: Variant in collection:
			var context: Dictionary = context_variant as Dictionary
			for field: String in ["organization_id", "type", "access", "available_position", "primary_action"]:
				_expect(not str(context.get(field, "")).is_empty(), "探索组织默认卡片包含 %s" % field)
			for field: String in ["known_reason", "contact_source", "function", "entry_method", "eligible", "missing_conditions"]:
				_expect(context.has(field), "组织名称悬停包含 %s" % field)
			for field: String in ["position_salary", "pay_cycle", "allowance", "position_authority", "position_work", "position_requirements", "supervisor", "department"]:
				_expect(context.has(field), "职位悬停包含 %s" % field)
	for identity_id: String in ["worker", "official"]:
		var identity_data: Dictionary = organization_identities.get(identity_id, {}) as Dictionary
		_expect(identity_data.get("owned", []) != identity_data.get("discover", []), "%s 的我的组织与探索组织继续分离" % identity_id)


func _test_v2_1_2_economy_permissions_and_tools() -> void:
	var official: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}).get("official", {}) as Dictionary
	for field: String in ["cash", "income", "expenses", "monthly_salary", "pay_cycle", "allowance", "debt_burden"]:
		_expect(not str(official.get(field, "")).is_empty(), "公务员个人经济包含 %s" % field)
	_expect(official.has("institution_budget_source") and not official.has("budget_source"), "公务员个人资金与机构预算字段严格分开")
	var worker: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}).get("worker", {}) as Dictionary
	_expect(not str(worker.get("weekly_wage", "")).is_empty() and not str(worker.get("pay_cycle", "")).is_empty(), "普通工人显示工资支付周期")
	var permission_text: String = JSON.stringify(_view.prototype_data.get_document("institutions")) + _read_text("res://scripts/prototype_v2/prototype_v2_interface.gd")
	_expect(not permission_text.contains("已知但无权处理"), "权限界面不再出现笼统限制措辞")
	_expect(permission_text.contains("需要中央部门批准") and permission_text.contains("需要省长授权") and permission_text.contains("需要跨部门会签"), "权限限制使用具体原因")
	var state: Dictionary = _view.interface.debug_state()
	_expect((state.get("time_menu_items", []) as Array) == ["暂停", "1×", "2×", "4×", "8×"] and state.get("time_menu_contains_system_tools") == false, "时间展开菜单为独立紧凑速度菜单")
	_expect((state.get("system_menu_items", []) as Array).size() == 3, "右上齿轮菜单包含保存、设置和退出占位")
	_expect(state.get("time_is_static_prototype") == true and not _read_text("res://scripts/prototype_v2/prototype_v2_interface.gd").contains("▶ 运行"), "静态原型不会虚假表示正式时间结算已运行")
	_expect(_rect_inside(PrototypeV2Interface.SYSTEM_CORNER, VIEWPORT_RECT), "独立齿轮系统入口位于右上角且无裁切")
	_view.interface.open_panel_named("time", false)
	_expect(_view.interface.get_panel_rect().size.x <= 180.0 and _view.interface.get_panel_rect().size.y <= 200.0, "时间菜单保持紧凑尺寸")
	_view.interface.close_panel(false)


func _test_label_density_and_detail_nodes() -> void:
	var map: PrototypeV2MapCanvas = _view.map_canvas
	_expect(map.get_label_budget("country", "far") >= 10 and map.get_label_budget("country", "far") <= 14, "世界远景国家标签预算为 10–14")
	_expect(map.get_label_budget("city", "far") >= 3 and map.get_label_budget("city", "far") <= 6, "世界远景城市标签预算为 3–6")
	_expect(map.get_label_budget("country", "middle") >= 8 and map.get_label_budget("country", "middle") <= 12, "欧洲中景国家标签预算为 8–12")
	_expect(map.get_label_budget("city", "middle") >= 8 and map.get_label_budget("city", "middle") <= 12, "欧洲中景城市标签预算为 8–12")
	_expect(map.get_label_budget("transport", "middle") >= 4 and map.get_label_budget("transport", "middle") <= 6, "欧洲中景交通预算为 4–6")
	_expect(map.get_label_budget("region", "near") >= 6 and map.get_label_budget("region", "near") <= 9, "法国近景宏观地区标签预算为 6–9")
	_expect(map.get_label_budget("city", "near") >= 8 and map.get_label_budget("city", "near") <= 12, "法国近景城市标签预算为 8–12")
	_expect(map.get_label_budget("transport", "near") >= 5 and map.get_label_budget("transport", "near") <= 8, "法国近景铁路预算为 5–8")
	_expect(map.get_visible_rail_ids("far").is_empty(), "世界远景不显示法国国内铁路")
	var middle_rails: Array[String] = map.get_visible_rail_ids("middle")
	_expect(middle_rails.size() > 0 and middle_rails.size() <= 4, "欧洲中景仅显示至多四条主要铁路")
	var rail_by_id: Dictionary = _index_records(_view.prototype_data.get_document("rail_segments").get("segments", []) as Array)
	for rail_id: String in middle_rails:
		_expect(bool((rail_by_id.get(rail_id, {}) as Dictionary).get("main", false)), "%s 为中景主要铁路" % rail_id)
	var middle_city_nodes: Array[String] = map.get_visible_city_node_ids("middle")
	for hidden_city_id: String in ["calais", "le_havre", "nantes", "bordeaux", "toulouse"]:
		_expect(hidden_city_id not in middle_city_nodes, "欧洲中景隐藏法国次要城市节点 %s" % hidden_city_id)
	for required_city_id: String in ["paris", "lille", "london", "berlin"]:
		_expect(required_city_id in middle_city_nodes, "欧洲中景保留主要城市节点 %s" % required_city_id)
	var near_rails: Array[String] = map.get_visible_rail_ids("near")
	_expect(near_rails.size() >= 5 and near_rails.size() <= 8, "法国近景铁路数量遵守 5–8 条预算")
	var collision_result: Array[String] = map.debug_resolve_label_candidates([
		{"id":"selected","priority":100,"rect":Rect2(10.0, 10.0, 80.0, 20.0)},
		{"id":"minor","priority":10,"rect":Rect2(20.0, 12.0, 80.0, 20.0)}
	], 2)
	_expect(collision_result == ["selected"], "标签碰撞时保留高优先级并隐藏低优先级")
	map.zoom = 9.2
	map.clear_selection()
	_expect(not map.should_draw_detail_nodes(), "法国近景未选择对象时隐藏机构与组织节点")
	map.set_selection("city", "lille")
	_expect(map.should_draw_detail_nodes(), "选择里尔后允许显示对应机构与组织节点")
	map.clear_selection()
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
	var review_key := InputEventKey.new()
	review_key.keycode = KEY_F9
	review_key.pressed = true
	_view._input(review_key)
	_expect(interface.review_mode, "F9 可显隐本地评审身份切换器")
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
	for field: String in ["department", "supervisor", "subordinates", "jurisdiction", "institution_budget_source", "agenda", "procedures", "upstream_locked"]:
		_expect(official.has(field), "地方官员结构包含 %s" % field)
	var worker: Dictionary = _view.prototype_data.get_document("characters").get("identities", {}).get("worker", {}) as Dictionary
	for field: String in ["work_contract", "employer", "union", "household"]:
		_expect(worker.has(field), "普通工人生活与工作结构包含 %s" % field)
	var actions: Dictionary = interface.debug_state()
	_expect(int(actions.get("object_card_primary_actions", 0)) == 1 and int(actions.get("object_card_secondary_actions", 0)) <= 2, "单张对象卡第一层限制为一个主动作和不超过两个次入口")
	interface.close_panel(false)


func _test_organization_and_activity_structure() -> void:
	var organization_document: Dictionary = _view.prototype_data.get_document("organizations")
	var organization_catalog: Dictionary = _index_records(organization_document.get("catalog", []) as Array)
	var organization_identities: Dictionary = organization_document.get("identities", {}) as Dictionary
	for identity_id: String in ["worker", "official"]:
		var identity_data: Dictionary = organization_identities[identity_id] as Dictionary
		var owned: Array = identity_data.get("owned", []) as Array
		var discover: Array = identity_data.get("discover", []) as Array
		_expect(not owned.is_empty() and not discover.is_empty(), "%s 的我的组织与探索组织数据保持分离" % identity_id)
		for organization_variant: Variant in owned:
			var organization_context: Dictionary = organization_variant as Dictionary
			_expect(organization_catalog.has(str(organization_context.get("organization_id", ""))), "%s 我的组织引用目录对象" % identity_id)
			for field: String in ["position", "department", "project", "supervisor", "authority"]:
				_expect(organization_context.has(field), "%s 我的组织卡包含 %s" % [identity_id, field])
			var catalog_record: Dictionary = organization_catalog.get(str(organization_context.get("organization_id", "")), {}) as Dictionary
			_expect(catalog_record.has("emblem"), "%s 我的组织目录包含徽记" % identity_id)
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
	_expect(_view.select_review_object("country", "country_fra"), "国家对象可从地图进入对象卡")
	_expect(_view.map_canvas.selected_type == "country", "国家选择获得独立层级高亮")
	_expect(_view.select_review_object("region", "northern_industrial_belt"), "地区对象可从地图进入对象卡")
	_expect(_view.select_review_object("city", "lille"), "城市对象可从地图进入对象卡")
	_expect(_view.select_review_object("institution", "prefecture_nord"), "地方机构对象可从地图进入对象卡")
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
	_expect(interface.close_top_layer() and interface.detail_person_id.is_empty(), "Esc 第一层关闭人物完整关系详情")
	interface.apply_review_state("person_more_menu")
	_expect(interface.close_top_layer() and not interface.person_more_menu_open and not interface.detail_person_id.is_empty(), "Esc 先关闭人物更多二级菜单")
	interface.close_top_layer()
	interface.apply_review_state("system_menu")
	_expect(interface.close_top_layer() and not interface.system_menu_open, "Esc 可关闭右上系统工具菜单")
	interface.apply_review_state("mode_menu")
	_expect(interface.close_top_layer() and not interface.mode_menu_open, "Esc 可关闭地图覆盖层菜单")
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


func _polygon_is_rectangle(points: Array) -> bool:
	if points.size() != 5:
		return false
	var unique_x: Dictionary = {}
	var unique_y: Dictionary = {}
	for point_variant: Variant in points:
		var point: Array = point_variant as Array
		unique_x[float(point[0])] = true
		unique_y[float(point[1])] = true
	return unique_x.size() == 2 and unique_y.size() == 2


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _index_records(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for record_variant: Variant in records:
		var record: Dictionary = record_variant as Dictionary
		result[str(record.get("id", ""))] = record
	return result


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _finish() -> void:
	print("V2.1.2 prototype smoke: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
