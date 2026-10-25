extends Control
## Attached to the existing menu preview. Never owns a WorldState or an actor.
signal closed
const Catalog = preload("res://scripts/presentation/ui/map_resource_catalog.gd")
const OUTPUT := "user://map_resource_feedback"
const CATEGORIES := ["视觉问题", "碰撞问题", "操作问题", "性能问题", "资源缺失"]
var renderer: GlobeRenderer
var controller: GlobeController
var _rows: Array[Dictionary] = []
var _row: Dictionary = {}
var _inspection: Dictionary = {}
var _active_id: String = ""
var _selection_generation: int = 0
var _active_generation: int = -1
var _worker: Thread
var _worker_kind: String = "resource"
var _panel: PanelContainer
var _choice: OptionButton
var _info: RichTextLabel
var _state: Label
var _open: Button
var _check: Button
var _category: OptionButton
var _note: TextEdit
var _coordinate: Label
var _result: Label
var _capture: Button
var _badge: Label
var _angle: OptionButton
var _scale: OptionButton
var _timer: Timer
var _marking: bool = false
var _marked := Vector3.ZERO
var _capturing: bool = false
var _last_output: String = ""
var _notices: Array[String] = []
var _last_state: String = ""
var _ready_to_capture: bool = false
var _visual_state: String = "NOT_OPENED"
var _saved_controller: Dictionary = {}
var _saved_region: Dictionary = {}
var _saved_max_fps: int = -1
var _restored: bool = false

func configure(map: GlobeRenderer, camera_controller: GlobeController) -> void:
	renderer = map
	renderer.inspection_preview = true
	controller = camera_controller
	_saved_controller = {"orientation": controller._orientation, "zoom": controller.zoom, "mode": controller.map_mode, "polity": controller.selected_polity_id, "place": controller.selected_place_id}
	for field: String in ["active", "local_active", "local_center_km", "local_place_id", "local_min_km_per_pixel", "tangent_frame", "origin", "km_per_pixel", "bearing", "extent_km"]:
		_saved_region[field] = controller.region_camera.get(field)
	_saved_controller["initial_framing_pending"] = controller.initial_framing_pending
	controller.suspend_motion()
	_saved_max_fps = Engine.max_fps
	Engine.max_fps = mini(30, _saved_max_fps) if _saved_max_fps > 0 else 30

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	theme = UIDrawing.shell_theme()
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.size = Vector2(370, get_viewport_rect().size.y - 24)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 346
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 7)
	scroll.add_child(column)
	_label(column, "地图 / 资源验收 · 开发观察", 19)
	_label(column, "原菜单地图；不创建世界、人物或载具。", 12)
	_choice = OptionButton.new()
	_choice.fit_to_longest_item = false
	column.add_child(_choice)
	_rows = Catalog.discover()
	for row: Dictionary in _rows:
		_choice.add_item(("[缺资源] " if not row.get("missing", []).is_empty() else "") + str(row["name"]) + (" · 模型" if row["kind"] == "model" else ""))
	_choice.item_selected.connect(_select)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_check = _button(actions, "检查 / SHA256", _inspect)
	_open = _button(actions, "打开选中对象", _show_selected)
	_open.disabled = true
	_state = _label(column, "请选择实际安装对象。", 12)
	_state.custom_minimum_size.y = 44
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(346, 390)
	column.add_child(tabs)
	var observation := VBoxContainer.new()
	observation.name = "观察"
	tabs.add_child(observation)
	_label(observation, "仅移动观察镜头。没有驾驶或碰撞判定。", 13)
	_label(observation, "拖动平移 / 滚轮缩放 / WASD 镜头平移\n右键拖动调整方位；不代表人物观察权限。", 12)
	_angle = OptionButton.new()
	for text: String in ["原生默认视角", "俯视 · 85°", "斜视 · 55°", "低角度 · 12°（正交观察）"]: _angle.add_item(text)
	observation.add_child(_angle)
	_angle.item_selected.connect(_change_angle)
	_scale = OptionButton.new()
	for text: String in ["范围 · 10 米/像素", "细节 · 2 米/像素", "概览 · 40 米/像素"]: _scale.add_item(text)
	observation.add_child(_scale)
	_scale.item_selected.connect(func(_index: int) -> void:
		if not _active_id.is_empty(): _focus(Vector2.ZERO))
	var positions := HBoxContainer.new()
	observation.add_child(positions)
	_button(positions, "锚点", _focus.bind(Vector2.ZERO))
	_button(positions, "西侧", _focus.bind(Vector2(-0.5, 0)))
	_button(positions, "东侧", _focus.bind(Vector2(0.5, 0)))
	_label(observation, "西 / 东为原锚点两侧 500 米的镜头观察位置。", 12)
	_label(observation, "军事 5×5 km 战场：未安装。\n车辆 / 步兵控制器、碰撞体、驾驶及战斗：未执行。\n本入口只验当前全球地图的 LOCAL 显示资源。", 13)
	var resources := VBoxContainer.new()
	resources.name = "资源"
	tabs.add_child(resources)
	_info = RichTextLabel.new()
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.custom_minimum_size.y = 260
	_info.selection_enabled = true
	resources.add_child(_info)
	_button(resources, "核对云端候选清单（只读）", _choose_manifest)
	var feedback := VBoxContainer.new()
	feedback.name = "反馈"
	tabs.add_child(feedback)
	_category = OptionButton.new()
	for category: String in CATEGORIES: _category.add_item(category)
	feedback.add_child(_category)
	_note = TextEdit.new()
	_note.placeholder_text = "描述观察结果；未执行的项目请写明。"
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.custom_minimum_size.y = 80
	feedback.add_child(_note)
	_button(feedback, "点选问题坐标", func() -> void:
		_marking = true
		_coordinate.text = "请点击右侧地图；不改变任何人物位置。")
	_coordinate = _label(feedback, "未标点时记录镜头中心。", 12)
	_capture = _button(feedback, "保存实际视口 PNG + 反馈 JSON", _capture_feedback)
	_capture.disabled = true
	_result = _label(feedback, "输出：" + ProjectSettings.globalize_path(OUTPUT), 12)
	_result.custom_minimum_size.y = 70
	_button(feedback, "打开反馈目录", func() -> void:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUTPUT)): OS.shell_open(ProjectSettings.globalize_path(OUTPUT)))
	_button(column, "关闭验收，返回原菜单", _close)
	_badge = Label.new()
	_badge.position = Vector2(400, get_viewport_rect().size.y - 62)
	_badge.add_theme_font_size_override("font_size", 14)
	_badge.add_theme_color_override("font_color", Color.WHITE)
	_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	_badge.add_theme_constant_override("shadow_offset_x", 1)
	_badge.add_theme_constant_override("shadow_offset_y", 1)
	_badge.hide()
	add_child(_badge)
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_refresh_state)
	add_child(_timer)
	_timer.start()
	renderer.map_notice.connect(_remember_notice)
	resized.connect(_layout)
	set_process(false)
	if not _rows.is_empty(): _select(0)

func _layout() -> void:
	if _panel == null: return
	_panel.size = Vector2(minf(370, size.x * 0.40), size.y - 24)
	_badge.position = Vector2(_panel.size.x + 28, size.y - 62)

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 30
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func blocks_map(point: Vector2) -> bool:
	return _capturing or _marking or _panel.get_global_rect().has_point(point)

func occlusions() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if _panel.visible: result.append(_panel.get_global_rect())
	return result

func _select(index: int) -> void:
	_row = _rows[index]
	_marked = Vector3.ZERO
	_coordinate.text = "未标点时记录镜头中心。"
	_inspection = {}
	_open.disabled = true
	_capture.disabled = true
	_inspect()

func _inspect() -> void:
	if _worker != null or _row.is_empty(): return
	_selection_generation += 1
	_open.disabled = true
	_check.disabled = true
	_choice.disabled = true
	_capture.disabled = true
	_info.text = "正在读取选中对象的文件、来源和 SHA256。"
	_state.text = "正在检查资源。"
	_worker = Thread.new()
	_worker_kind = "resource"
	var error := _worker.start(Catalog.inspect.bind(_row.duplicate(true)))
	if error != OK:
		_worker = null
		_state.text = "无法启动资源检查：" + error_string(error)
		_check.disabled = false
		_choice.disabled = false
		return
	set_process(true)

func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive(): return
	var completed: Dictionary = _worker.wait_to_finish()
	_worker = null
	set_process(false)
	_check.disabled = false
	_choice.disabled = false
	if _worker_kind == "manifest":
		_info.text = JSON.stringify(completed, "\t")
		_state.text = "候选清单核对完成；未执行安装。" if (completed["errors"] as Array).is_empty() else "候选清单存在错误；未执行安装。"
		_open.disabled = _inspection.is_empty() or not (_inspection.get("errors", []) as Array).is_empty()
		return
	_inspection = completed
	_open.disabled = not (_inspection["errors"] as Array).is_empty()
	var lines: Array[String] = ["候选：" + str(_row["id"]), "地图 ID：" + str(_row["map_id"]), "版本：" + str(_row["version"]), "内容：" + str(_row["path"])]
	for source: Dictionary in _inspection.get("sources", []):
		lines.append("来源：%s · %s\n%s" % [source.get("title", source.get("source_id", "")), source.get("version", ""), source.get("locator", "")])
	for file: Dictionary in _inspection.get("files", []): lines.append("%s\n%d B\nSHA256 %s" % [file["path"], file["bytes"], file["sha256"]])
	for error: String in _inspection["errors"]: lines.append(error)
	_info.text = "\n\n".join(lines)
	_state.text = "资源可读；可打开观察。驾驶未执行。" if not _open.disabled else "资源检查未完成：" + "; ".join(_inspection["errors"])

func _show_selected() -> void:
	if _open.disabled or _worker != null: return
	var content := renderer.local_content.content
	var same_source := content!=null and content.errors.is_empty() and str(content.metadata.get("content_path", ""))==str(_row["path"])
	if not same_source:
		renderer.local_content.clear_inspection_source()
		renderer.local_content.release()
		if _row.get("kind") == "candidate" and not renderer.local_content.set_inspection_source(str(_row["path"]), str(_row["map_id"])):
			_state.text = "候选未安装到原 LOCAL 加载器。"
			return
	_active_id = str(_row["id"])
	_active_generation = _selection_generation
	_scale.select(1 if Catalog.detail_scale_needed(_row) else 0)
	_last_state = ""
	_marked = Vector3.ZERO
	_focus(Vector2.ZERO)

func _focus(offset_km: Vector2) -> void:
	if not _is_active_selection(): return
	controller.suspend_motion()
	controller.region_camera.leave_local()
	var anchor: Vector2 = _row["anchor"]
	var unit := GlobeProjection.lon_lat_to_unit(anchor)
	var pixel := get_viewport_rect().size * Vector2(0.65, 0.5)
	var scale: float = [0.010, 0.002, 0.040][_scale.selected]
	controller.focus_region(unit, pixel, scale, 0.0, get_viewport_rect().size)
	controller.enter_local(unit, pixel, get_viewport_rect().size, str(_row["map_id"]), 2.0)
	if not offset_km.is_zero_approx():
		controller.region_camera.pan(-(RegionProjection.screen_axes(0.0) * offset_km) / scale, get_viewport_rect().size)
	controller.set_map_mode("geographic")
	controller.view_changed.emit()
	_refresh_state()

func _change_angle(index: int) -> void:
	renderer.region_view.set_inspection_elevation([-1.0, 85.0, 55.0, 12.0][index])
	controller.view_changed.emit()

func _refresh_state() -> void:
	if _active_id.is_empty() or _worker != null: return
	_ready_to_capture = false
	_visual_state = "NOT_OPENED"
	var message := "已选其他候选；请先打开。"
	if _is_active_selection():
		var loader := renderer.local_content
		_visual_state = "PREPARING"
		if loader.content != null and str(loader.content.metadata.get("content_path", "")) == str(_row["path"]) and not controller.region_camera.local_active and loader.content.errors.is_empty():
			var unit := GlobeProjection.lon_lat_to_unit(_row["anchor"])
			controller.enter_local(unit, controller.region_camera.project(unit), get_viewport_rect().size, str(_row["map_id"]), 2.0)
		if loader.preparing() or loader.content == null or str(loader.content.metadata.get("content_path", "")) != str(_row["path"]): message = "正在由原 LOCAL 加载器准备地图。"
		elif not loader.content.errors.is_empty():
			_visual_state = "LOAD_FAILED"
			message = "地图加载失败：" + "; ".join(loader.content.errors)
		elif not str(_row.get("surface_path", "")).is_empty() and loader.content.surface_reference.is_empty():
			_visual_state = "SURFACE_UNAVAILABLE"
			message = "高程未加载，原显示退回平面。可记录资源缺失反馈。"
		elif renderer.region_view.landmark_preparing() or renderer.region_view._landmark_render_pending: message = "正在准备原生地形 / 模型。"
		elif not str(_row.get("surface_path", "")).is_empty() and renderer.region_view.coverage_description(controller.region_camera).is_empty():
			_visual_state = "REGION_REFERENCE_ONLY"
			message = "已读取高程，当前仅有区域底图；请选择细节比例。"
		elif _row.get("kind") == "model" and not renderer.region_view.landmark_visible(str(_row.get("visual_id", ""))):
			_visual_state = "MODEL_NOT_VISIBLE"
			message = "模型尚未实际显示；请核对位置 / 原地图身份合同。"
		else:
			_visual_state = "OBSERVED_IN_NATIVE_VIEWPORT"
			message = "当前 LOCAL 显示已准备。驾驶 / 碰撞未执行。"
		_ready_to_capture = controller.region_camera.local_active and not _inspection.is_empty()
	_capture.disabled = not _ready_to_capture or _capturing
	if message != _last_state:
		_last_state = message
		_state.text = message

func _input(event: InputEvent) -> void:
	if _capturing:
		get_viewport().set_input_as_handled()
		return
	if _marking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _panel.get_global_rect().has_point(event.position):
		var unit := renderer.unit_at(event.position)
		if not unit.is_zero_approx():
			_marked = unit
			var ll := RegionProjection.lon_lat(unit)
			_coordinate.text = "问题点：经度 %.7f，纬度 %.7f" % [ll.x, ll.y]
		_marking = false
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
		return
	if not _is_active_selection() or not controller.region_camera.active: return
	var directions := {KEY_W: Vector2(0, 48), KEY_S: Vector2(0, -48), KEY_A: Vector2(48, 0), KEY_D: Vector2(-48, 0)}
	if directions.has(event.keycode):
		controller.region_camera.pan(directions[event.keycode], get_viewport_rect().size)
		controller.view_changed.emit()
		get_viewport().set_input_as_handled()

func _remember_notice(message: String) -> void:
	_notices.append(message)
	if _notices.size() > 24: _notices.pop_front()

func _is_active_selection() -> bool:
	return _active_id == str(_row.get("id", "")) and _active_generation == _selection_generation

func _capture_feedback() -> void:
	_refresh_state()
	if not _ready_to_capture or _capturing: return
	_capturing = true
	controller.suspend_motion()
	var version := Catalog.project_version()
	var unit := _marked if not _marked.is_zero_approx() else renderer.unit_at(get_viewport_rect().size * 0.5)
	if unit.is_zero_approx():
		_capturing = false
		_result.text = "当前画面无法解析地图坐标，请重新定位。"
		return
	var ll := RegionProjection.lon_lat(unit)
	_badge.text = "开发观察 · %s\n经纬度 %.7f, %.7f · 源码 %s" % [_active_id, ll.x, ll.y, str(version["git_revision"]).left(8)]
	_badge.show()
	_panel.hide()
	await RenderingServer.frame_post_draw
	# The completed LOCAL child is published into the cached REGION parent.
	# Read the root only after that parent and the badge have also drawn.
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	_refresh_state()
	var report := _snapshot(unit, version)
	_panel.show()
	_badge.hide()
	var folder := OUTPUT.path_join(Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(Time.get_ticks_msec()))
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if error == OK: error = image.save_png(folder.path_join("viewport.png")) if image != null and not image.is_empty() else ERR_CANT_CREATE
	if error == OK:
		var file := FileAccess.open(folder.path_join("feedback.json"), FileAccess.WRITE)
		if file == null: error = FileAccess.get_open_error()
		else:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	_capturing = false
	_last_output = ProjectSettings.globalize_path(folder)
	_result.text = ("已保存 PNG + JSON：\n" if error == OK else "保存失败；可能保留部分输出：" + error_string(error) + "\n") + _last_output
	_refresh_state()

func _snapshot(unit: Vector3, version: Dictionary) -> Dictionary:
	var camera := controller.region_camera
	var center := renderer.unit_at(get_viewport_rect().size * 0.5)
	var view := renderer.region_view
	var local_camera := view._landmark_camera
	return {
		"schema_id": "wwo_map_resource_feedback_v1",
		"candidate_id": _active_id, "map_id": _row["map_id"],
		"candidate_version": _row["version"], "content_path": _row["path"],
		"category": CATEGORIES[_category.selected], "note": _note.text.left(4000),
		"captured_at": Time.get_datetime_string_from_system(),
		"timezone": Time.get_time_zone_from_system(), "project": version,
		"resources": _inspection,
		"problem_point": {
			"lon_lat": _v2(RegionProjection.lon_lat(unit)),
			"local_chart_metres": _v2(camera.local_metric(unit) * 1000.0),
			"basis": "user_map_click" if not _marked.is_zero_approx() else "viewport_center"
		},
		"camera": {
			"mode": "LOCAL" if camera.local_active else "REGION" if camera.active else "WORLD",
			"center_lon_lat": _v2(RegionProjection.lon_lat(center)) if not center.is_zero_approx() else [],
			"chart_anchor_lon_lat": _v2(RegionProjection.lon_lat(camera.tangent_frame.z)),
			"origin_pixels": _v2(camera.origin), "metres_per_pixel": camera.km_per_pixel * 1000.0,
			"bearing_radians": camera.bearing, "elevation_radians": view.elevation_at(camera),
			"native_position": _v3(local_camera.position) if local_camera != null else [],
			"native_rotation": _v3(local_camera.rotation) if local_camera != null else [],
			"native_units": "existing orthographic map viewport units; not a physical actor pose",
			"view_only": true
		},
		"viewport_pixels": _v2(get_viewport_rect().size),
		"device": {
			"os": OS.get_name(), "os_version": OS.get_version(), "cpu": OS.get_processor_name(),
			"gpu": RenderingServer.get_video_adapter_name(), "gpu_vendor": RenderingServer.get_video_adapter_vendor(),
			"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
		},
		"display": {
			"local_errors": _local_errors(), "terrain_note": _local_note(),
			"relief_errors": renderer.relief.errors.duplicate(),
			"active_relief_textures": renderer.relief.textures.keys(),
			"native_surface": {
				"ready": view.ready, "content_path": view._local_surface_key,
				"presented_path": view._surface_presented_key,
				"mesh_present": view._local_surface != null,
				"preparing": view.landmark_preparing(),
				"visible_models": view._landmark_presented.keys()
			},
			"terrain_reference": {
				"survey_bounds_lon_lat": _v4(view._surface_material.get_shader_parameter("survey_bounds")) if view._surface_material!=null else [],
				"display_spacing_m": view._surface_reference.get("display_spacing_m_approx",[]),
				"context_height_asset": (view._surface_reference.get("presentation",{}) as Dictionary).get("context_height_asset",{}),
				"context_transition_metres": 400 if (view._surface_reference.get("presentation",{}) as Dictionary).has("context_height_asset") else 0,
				"context_role": "quantized regional DSM and display interpolation; not native DTM measurement or physics",
				"local_render_pixels": _v2(view._local_render_rect.size)
			},
			"map_notices": _notices.duplicate(), "engine_error_log": _error_log()
		},
		"checks": {
			"visual": _visual_state, "driving": "NOT_EXECUTED", "infantry_movement": "NOT_EXECUTED",
			"collision": "NOT_EXECUTED", "combat": "NOT_EXECUTED",
			"missing_dependency": "No installed military local battlefield, vehicle/infantry controller or physical collision scene in this checkout",
			"world_created": false, "actor_state_modified": false
		}
	}


func _local_errors() -> Array[String]:
	var errors: Array[String] = []
	if renderer.local_content.content != null: errors.append_array(renderer.local_content.content.errors)
	else: errors.append("LOCAL content pending")
	return errors

func _local_note() -> String:
	return str(renderer.local_content.content.metadata.get("terrain_note_zh", "")) if renderer.local_content.content != null else "LOCAL content pending"

func _error_log() -> Dictionary:
	var path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	var args := OS.get_cmdline_args()
	for index: int in range(args.size()):
		if args[index] == "--log-file" and index + 1 < args.size(): path = args[index + 1]
	# Godot consumes recognized engine arguments. Mirror a custom log override
	# in user arguments so this feedback reads the same bounded engine log.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map-resource-log="): path = arg.trim_prefix("--map-resource-log=")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"path": path, "state": "UNAVAILABLE"}
	file.seek(maxi(0, file.get_length() - 32768))
	var tail := file.get_buffer(32768).get_string_from_utf8()
	var errors: Array[String] = []
	for line: String in tail.split("\n"):
		if "SCRIPT ERROR" in line or "ERROR:" in line or "WARNING:" in line:
			errors.append(line)
	return {"path": path, "state": "READ_LAST_32_KIB", "messages": errors.slice(maxi(0, errors.size() - 24))}

func _choose_manifest() -> void:
	if _worker != null: return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; 云端候选清单"])
	dialog.title = "只读核对候选清单；不安装、不覆盖"
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		_open.disabled = true
		_check.disabled = true
		_choice.disabled = true
		_capture.disabled = true
		_worker_kind = "manifest"
		_worker = Thread.new()
		var error := _worker.start(Catalog.verify_manifest.bind(path))
		if error == OK:
			_state.text = "正在后台核对候选路径、长度与 SHA256。"
			set_process(true)
		else:
			_worker = null
			_check.disabled = false
			_choice.disabled = false
			_state.text = "无法核对清单：" + error_string(error)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func _close() -> void:
	if _capturing: return
	_restore_preview()
	closed.emit()
	queue_free()

func _restore_preview() -> void:
	if _restored: return
	_restored = true
	if _saved_max_fps >= 0: Engine.max_fps = _saved_max_fps
	if not is_instance_valid(renderer) or not is_instance_valid(controller): return
	controller.suspend_motion()
	renderer.inspection_preview = false
	renderer.region_view.set_inspection_elevation(-1.0)
	renderer.local_content.clear_inspection_source()
	for field: String in _saved_region: controller.region_camera.set(field, _saved_region[field])
	controller.initial_framing_pending = bool(_saved_controller["initial_framing_pending"])
	controller._orientation = _saved_controller["orientation"]
	controller.zoom = float(_saved_controller["zoom"])
	controller.set_map_mode(str(_saved_controller["mode"]))
	controller.select(str(_saved_controller["polity"]), str(_saved_controller["place"]))
	controller.view_changed.emit()

func _exit_tree() -> void:
	_restore_preview()
	if _worker != null and _worker.is_started(): _worker.wait_to_finish()

static func _v2(value: Vector2) -> Array:
	return [value.x, value.y]

static func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _v4(value: Vector4) -> Array:
	return [value.x, value.y, value.z, value.w]
