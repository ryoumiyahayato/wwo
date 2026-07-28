extends Node

const TARGET_SCENE: String = "res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn"

var workspace: Control


func _ready() -> void:
	_run_probe.call_deferred()


func _run_probe() -> void:
	var packed_scene: PackedScene = load(TARGET_SCENE) as PackedScene
	if not _require(packed_scene != null, "样机场景无法加载"):
		return
	workspace = packed_scene.instantiate() as Control
	if not _require(workspace != null, "样机场景无法实例化为Control"):
		return
	add_child(workspace)
	await _settle_frames(8)

	var moon: MeshInstance3D = workspace.get_node_or_null(
		"HemisphereViewportContainer/HemisphereViewport/Hemisphere3D/Moon"
	) as MeshInstance3D
	if not _require(moon != null and moon.mesh != null, "三维视口中的月球网格缺失"):
		return
	if not _require(moon.material_override is ShaderMaterial, "月球没有程序化材质"):
		return
	if not _require(moon.visible, "全球最小视图没有显示月球"):
		return

	var frame_before: Image = workspace.get_viewport().get_texture().get_image()
	await get_tree().create_timer(1.6).timeout
	await _settle_frames(2)
	var frame_after: Image = workspace.get_viewport().get_texture().get_image()
	if not _require(_count_changed_background_samples(frame_before, frame_after) >= 6, "动态星空没有形成缓慢明暗变化"):
		return

	workspace.call("_unhandled_key_input", _key_event(KEY_F2))
	if not _require(int(workspace.get("layout_mode_id")) == 1, "F2未切换操作桌面布局"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_F1))
	if not _require(int(workspace.get("layout_mode_id")) == 0, "F1未切换半球聚焦布局"):
		return

	workspace.call("_set_world_zoom", 0.74)
	workspace.call("_ensure_projection_cache")
	var history_entities: Dictionary = workspace.get("_history_entity_by_id") as Dictionary
	var global_entities: Dictionary = workspace.get("_country_by_id") as Dictionary
	var history_conflicts: Array = workspace.get("_history_conflicts") as Array
	var provisional_entities: Array = workspace.get("_history_provisional_entity_ids") as Array
	var flag_polygons: Dictionary = workspace.get("_flag_screen_polygons") as Dictionary
	var admin1_by_iso: Dictionary = workspace.get("_world_admin1_by_iso") as Dictionary
	var admin1_by_id: Dictionary = workspace.get("_world_admin1_by_id") as Dictionary
	if not _require(history_entities.size() >= 45, "明确配置的1900政治实体数量不足"):
		return
	if not _require(
		history_entities.has("german_empire")
		and history_entities.has("austria_hungary")
		and history_entities.has("russian_empire")
		and history_entities.has("qing_empire")
		and history_entities.has("kingdom_of_nepal")
		and history_entities.has("kingdom_of_bhutan"),
		"主要1900政治实体或小国实体不完整"
	):
		return
	if not _require(global_entities.has("german_empire") and not global_entities.has("country_deu"), "现代德国没有被德意志帝国替代"):
		return
	if not _require(history_conflicts.size() >= 4, "战争与争议边界层数量不足"):
		return
	if not _require(provisional_entities.size() < global_entities.size(), "政治实体仍全部退化为现代待校订国家"):
		return
	if not _require(flag_polygons.size() >= 12, "最小视图可见的1900政治实体蒙皮数量异常"):
		return
	if not _require(float(workspace.call("_country_label_alpha")) <= 0.01, "最小视图仍显示常驻政治实体名称"):
		return
	if not _require(admin1_by_id.size() >= 4000 and admin1_by_iso.size() >= 180, "全球一级行政区数据未完整加载"):
		return
	if not _require(
		not (admin1_by_iso.get("DEU", []) as Array).is_empty()
		and not (admin1_by_iso.get("NPL", []) as Array).is_empty()
		and not (admin1_by_iso.get("BTN", []) as Array).is_empty(),
		"德国、尼泊尔或不丹缺少一级行政区数据"
	):
		return

	var texture_ids: Array[String] = [
		"country_fra", "german_empire", "british_isles_1900", "austria_hungary",
		"ottoman_empire", "qing_empire", "empire_of_japan", "kingdom_of_nepal", "kingdom_of_bhutan"
	]
	var signatures: Dictionary = {}
	for entity_id: String in texture_ids:
		var signature: String = str(workspace.call("_flag_texture_signature", entity_id))
		if not _require(not signature.is_empty(), "旗帜纹理签名缺失：" + entity_id):
			return
		signatures[signature] = true
	if not _require(signatures.size() >= 8, "主要政治实体旗帜仍然缺少可区分的结构特征"):
		return

	var border_signature_before: String = str(workspace.call("_historical_border_geometry_signature"))
	var border_pulse_before: float = float(workspace.call("_history_border_pulse_value", "german_empire"))
	for _index: int in range(9):
		workspace.call("_on_flag_timer_timeout")
	var border_pulse_after: float = float(workspace.call("_history_border_pulse_value", "german_empire"))
	var border_signature_after: String = str(workspace.call("_historical_border_geometry_signature"))
	if not _require(absf(border_pulse_after - border_pulse_before) > 0.005, "政治边境没有缓慢波动"):
		return
	if not _require(border_signature_before == border_signature_after, "边境波动错误地改变了边界几何"):
		return

	var centre: Vector2 = workspace.get("_hemisphere_center") as Vector2
	var camera: Camera3D = workspace.get_node("HemisphereViewportContainer/HemisphereViewport/Camera3D") as Camera3D
	var zoom_before: float = float(workspace.get("world_zoom"))
	var camera_size_before: float = camera.size
	_send_wheel(centre, MOUSE_BUTTON_WHEEL_UP)
	if not _require(float(workspace.get("world_zoom")) > zoom_before and camera.size < camera_size_before, "滚轮没有同步放大全球投影与正交相机"):
		return
	workspace.call("_set_world_zoom", 3.6)
	if not _require(float(workspace.call("_country_label_alpha")) >= 0.98, "高倍率没有淡入政治实体名称"):
		return
	if not _require(not moon.visible, "高倍率后月球仍挤占国家阅读空间"):
		return

	workspace.set("selected_country_id", "kingdom_of_nepal")
	workspace.call("_zoom_to_selected_historical_entity")
	workspace.call("_ensure_projection_cache")
	var nepal_bounds: Rect2 = (workspace.get("_flag_screen_bounds") as Dictionary).get("kingdom_of_nepal", Rect2()) as Rect2
	if not _require(float(workspace.get("world_zoom")) >= 2.5 and float(workspace.get("world_zoom")) <= 6.0, "尼泊尔聚焦倍率未落在有限高倍率范围"):
		return
	if not _require(nepal_bounds.size.x >= 24.0 and nepal_bounds.size.y >= 7.0, "最大倍率仍无法阅读完整尼泊尔轮廓"):
		return

	workspace.set("selected_country_id", "kingdom_of_bhutan")
	workspace.call("_zoom_to_selected_historical_entity")
	workspace.call("_ensure_projection_cache")
	var bhutan_bounds: Rect2 = (workspace.get("_flag_screen_bounds") as Dictionary).get("kingdom_of_bhutan", Rect2()) as Rect2
	if not _require(bhutan_bounds.size.x >= 16.0 and bhutan_bounds.size.y >= 6.0, "最大倍率仍无法阅读完整不丹轮廓"):
		return

	workspace.call("_return_to_global_world")
	workspace.call("_set_world_zoom", 0.86)
	if not _require(moon.visible, "恢复全球总览后月球没有重新显示"):
		return
	centre = workspace.get("_hemisphere_center") as Vector2
	var yaw_before: float = float(workspace.get("yaw"))
	_send_mouse_button(centre, true)
	_send_mouse_motion(centre + Vector2(42.0, 0.0), Vector2(42.0, 0.0))
	_send_mouse_button(centre + Vector2(42.0, 0.0), false)
	if not _require(absf(float(workspace.get("yaw")) - yaw_before) > 0.05, "半球拖动未改变经度角"):
		return
	workspace.set("angular_velocity", 0.0)
	workspace.set_process(false)

	workspace.set("selected_country_id", "german_empire")
	workspace.call("_focus_selected_country")
	if not _require(str(workspace.get("world_mode")) == "historical_entity_focus", "德意志帝国没有进入通用政治实体层"):
		return
	if not _require(not moon.visible, "通用政治实体平面层仍显示月球"):
		return
	workspace.call("_enter_region")
	if not _require(str(workspace.get("space_level")) == "region", "德意志帝国没有进入一级行政区层"):
		return
	workspace.queue_redraw()
	await _settle_frames(3)
	var german_admin1: Array = admin1_by_iso.get("DEU", []) as Array
	if not _require(german_admin1.size() >= 10, "德国一级行政区数量异常"):
		return
	workspace.set("selected_world_admin1_id", str((german_admin1[0] as Dictionary).get("id", "")))
	workspace.call("_enter_selected_world_admin1")
	if not _require(str(workspace.get("space_level")) == "city", "一级行政区没有进入下属层级"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("space_level")) == "region", "下属层级Esc没有返回一级行政区"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("space_level")) == "world" and str(workspace.get("world_mode")) == "historical_entity_focus", "一级行政区Esc没有返回政治实体层"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("world_mode")) == "countries", "政治实体层Esc没有返回全球层"):
		return

	workspace.set("selected_country_id", "russian_empire")
	workspace.call("_focus_selected_country")
	var russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
	if not _require(
		russian_territories.size() == 1
		and str((russian_territories[0] as Dictionary).get("iso_a3", "")) == "RUS",
		"俄罗斯帝国本土没有保持为CShapes历史政治核心"
	):
		return
	var dated_units: Array = (workspace.get("_dated_units_document") as Dictionary).get("units", []) as Array
	var russian_protected_units := 0
	for unit_value: Variant in dated_units:
		var unit := unit_value as Dictionary
		if str(unit.get("controller_id", "")) == "russian_empire":
			russian_protected_units += 1
	if not _require(russian_protected_units >= 2, "俄罗斯保护国没有作为独立历史政治单元保留"):
		return
	workspace.call("_return_to_global_world")

	workspace.set("yaw", -0.08)
	workspace.set("tilt", -0.18)
	workspace.call("_set_world_zoom", 0.86)
	workspace.call("_mark_projection_dirty")
	workspace.call("_ensure_projection_cache")
	var country_anchors: Dictionary = workspace.get("_country_screen_anchors") as Dictionary
	if not _require(country_anchors.has("country_fra"), "默认视角下法兰西第三共和国锚点不可见"):
		return
	var france_point: Vector2 = country_anchors.get("country_fra", Vector2.INF) as Vector2
	_send_mouse_button(france_point, true)
	_send_mouse_button(france_point, false)
	if not _require(str(workspace.get("selected_country_id")) == "country_fra", "点击未选择法兰西第三共和国"):
		return
	workspace.call("_focus_selected_country")
	if not _require(str(workspace.get("world_mode")) == "country_focus", "法兰西没有进入既有九大区聚焦模式"):
		return

	var regions: Array = workspace.get("_regions") as Array
	var region_polygons: Dictionary = workspace.get("_region_polygons") as Dictionary
	var region_units: Dictionary = workspace.get("_administrative_units_by_region") as Dictionary
	var region_cities: Dictionary = workspace.get("_cities_by_region") as Dictionary
	if not _require(regions.size() == 9, "法兰西宏观大区数量不是9"):
		return
	for region_value: Variant in regions:
		var region: Dictionary = region_value as Dictionary
		var region_id: String = str(region.get("id", ""))
		if not _require(not (region_polygons.get(region_id, []) as Array).is_empty(), "大区缺少几何：" + region_id):
			return
		if not _require(not (region_units.get(region_id, []) as Array).is_empty(), "大区缺少行政分区：" + region_id):
			return
		if not _require(not (region_cities.get(region_id, []) as Array).is_empty(), "大区缺少城市入口：" + region_id):
			return

	workspace.call("_ensure_projection_cache")
	var region_anchors: Dictionary = workspace.get("_focus_region_screen_anchors") as Dictionary
	var region_point: Vector2 = region_anchors.get("northern_industrial_belt", Vector2.INF) as Vector2
	_send_mouse_button(region_point, true)
	if not _require(str(workspace.get("selected_region_id")) == "northern_industrial_belt", "未选择北部工业带"):
		return
	workspace.call("_enter_region")
	if not _require(str(workspace.get("space_level")) == "region", "法兰西大区没有进入大区层"):
		return
	workspace.queue_redraw()
	await _settle_frames(3)
	if not _require((workspace.get("_administrative_screen_polygons") as Dictionary).size() == 5, "北部工业带未绘制5个行政分区"):
		return
	workspace.call("_activate_button", "next_region")
	if not _require(str(workspace.get("selected_region_id")) == "paris_basin", "下一个大区未切换到巴黎盆地"):
		return
	workspace.call("_activate_button", "previous_region")
	workspace.call("_enter_city", "lille")
	if not _require(str(workspace.get("space_level")) == "city" and str(workspace.get("selected_city_id")) == "lille", "里尔没有进入城市层"):
		return
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	workspace.call("_unhandled_key_input", _key_event(KEY_ESCAPE))
	if not _require(str(workspace.get("world_mode")) == "countries" and moon.visible, "法兰西返回链没有回到全球三维半球"):
		return

	workspace.queue_redraw()
	await _settle_frames(3)
	_send_mouse_button(Vector2(50.0, 50.0), true)
	if not _require(str(workspace.get("active_hud_panel")) == "country", "左上国家角未打开国家面板"):
		return
	workspace.call("_activate_button", "close_hud_panel")
	workspace.call("_activate_button", "speed:4")
	if not _require(int(workspace.get("sim_speed")) == 4 and not bool(workspace.get("sim_paused")), "速度按钮未设置4倍并解除暂停"):
		return

	workspace.queue_free()
	get_tree().quit(0)


func _count_changed_background_samples(before: Image, after: Image) -> int:
	if before == null or after == null or before.is_empty() or after.is_empty():
		return 0
	var width: int = mini(before.get_width(), after.get_width())
	var height: int = mini(before.get_height(), after.get_height())
	var changed: int = 0
	for y: int in range(mini(84, height - 1), maxi(mini(84, height - 1), height - 84)):
		for x: int in range(12, maxi(12, width - 12)):
			var first: Color = before.get_pixel(x, y)
			var second: Color = after.get_pixel(x, y)
			var difference: float = maxf(absf(first.r - second.r), maxf(absf(first.g - second.g), absf(first.b - second.b)))
			if difference > 0.0015:
				changed += 1
				if changed >= 6:
					return changed
	return changed


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	event.global_position = position
	workspace.call("_gui_input", event)


func _send_wheel(position: Vector2, button_index: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = position
	event.global_position = position
	workspace.call("_gui_input", event)


func _send_mouse_motion(position: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	workspace.call("_gui_input", event)


func _key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _settle_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("Holographic workspace interaction probe: " + message)
	get_tree().quit(1)
	return false
