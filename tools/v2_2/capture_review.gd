extends Control
## Visible-window deterministic capture journey for all V2.2 review states.

const MAIN_SCENE := preload(
	"res://scenes/v2_2/v2_2_life_loop_main.tscn"
)
const ARTIFACT_DIRECTORY := "res://artifacts/v2_2_life_loop_review"

var _view: V2LifeLoopMain
var _captured_files: Array[String] = []


func _ready() -> void:
	get_viewport().content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(ARTIFACT_DIRECTORY)
	)
	_view = MAIN_SCENE.instantiate() as V2LifeLoopMain
	add_child(_view)
	_run_capture.call_deferred()


func _run_capture() -> void:
	await _wait_frames(14)
	if _view.life_simulation == null or not _view.life_simulation.initialized:
		push_error("V2.2 review scene did not initialize")
		get_tree().quit(1)
		return
	await _reset()
	_view.map_canvas.focus_player_location()
	await _capture("01_v2_2_start")

	_view.life_binding.set_speed(1)
	await get_tree().create_timer(1.1).timeout
	_view.life_binding.set_paused(true)
	await _capture("02_authoritative_time_running")

	_open_character("summary")
	await _capture("03_current_activity")

	_open_panel("schedule")
	await _capture("04_today_schedule")

	_open_character("life_work")
	await _capture("05_financial_summary")

	_view.life_simulation.set_condition(
		V2LifeLoopSimulation.PIERRE_ID, "health", 650
	)
	_view.life_simulation.set_condition(
		V2LifeLoopSimulation.PIERRE_ID, "fatigue", 650
	)
	_view.life_simulation.set_condition(
		V2LifeLoopSimulation.PIERRE_ID, "stress", 700
	)
	_open_character("summary")
	await _capture("06_condition_symbols")

	var indicator: Dictionary = _view.life_simulation.conditions.indicator(
		V2LifeLoopSimulation.PIERRE_ID,
		"fatigue",
		_view.life_simulation.clock.total_hours
	)
	_view.interface._hover_position = Vector2(566.0, 204.0)
	_view.interface._hover_tooltip = (
		"当前状态：%s\n主要原因：%s\n近期趋势：%s\n当前影响：%s\n建议：%s"
		% [
			indicator.get("state", ""),
			indicator.get("reason", ""),
			indicator.get("trend", ""),
			indicator.get("impact", ""),
			indicator.get("suggestion", ""),
		]
	)
	_view.interface.queue_redraw()
	await _capture("07_condition_causal_tooltip")
	_view.interface._hover_tooltip = ""

	await _reset()
	_open_panel("schedule")
	_view.interface._activate("schedule_activity", "rest")
	await _capture("08_activity_schedule_form")

	await _reset()
	var food_hour: int = V2DateTime.total_hour_from_iso(
		"1900-03-12T18:00:00"
	)
	_view.life_simulation.request_activity(
		V2LifeLoopSimulation.PIERRE_ID, "purchase_food", food_hour, 1
	)
	_view.life_simulation.advance_hours(
		food_hour - _view.life_simulation.clock.total_hours + 1
	)
	_open_character("life_work")
	await _capture("09_food_purchase")

	await _reset()
	_view.life_simulation.set_household_cash(
		V2LifeLoopSimulation.PIERRE_ID, 0
	)
	_open_panel("schedule")
	_view.interface._activate("schedule_activity", "purchase_food")
	_view.interface._activate("schedule_confirm", null)
	await _capture("10_insufficient_cash")

	await _reset()
	var pay_hour: int = int(
		_view.life_simulation.employment.contract_for_person(
			V2LifeLoopSimulation.PIERRE_ID
		).get("next_pay_hour", -1)
	)
	_view.life_simulation.advance_hours(
		pay_hour - _view.life_simulation.clock.total_hours + 1
	)
	_open_character("life_work")
	await _capture("11_wage_arrival")
	await _capture("12_wage_details")

	await _reset()
	_open_panel("schedule")
	_view.interface._activate("schedule_activity", "overtime")
	await _capture("13_overtime_schedule")

	_view.life_simulation.set_condition(
		V2LifeLoopSimulation.PIERRE_ID, "fatigue", 950
	)
	_view.interface._activate("schedule_confirm", null)
	await _capture("14_fatigue_limit")

	await _reset()
	_view.life_simulation.request_activity(
		V2LifeLoopSimulation.PIERRE_ID,
		"authorized_leave",
		V2DateTime.total_hour_from_iso("1900-03-12T07:00:00"),
		5
	)
	_open_panel("schedule")
	await _capture("15_authorized_leave")

	await _reset()
	var absence_start: int = V2DateTime.total_hour_from_iso(
		"1900-03-12T07:00:00"
	)
	_view.life_simulation.request_activity(
		V2LifeLoopSimulation.PIERRE_ID, "absence", absence_start, 5
	)
	_view.life_simulation.advance_hours(
		absence_start - _view.life_simulation.clock.total_hours + 5
	)
	_open_panel("developer")
	await _capture("16_unauthorized_absence")

	await _reset()
	var contact_hour: int = V2DateTime.total_hour_from_iso(
		"1900-03-12T18:00:00"
	)
	_view.life_simulation.request_activity(
		V2LifeLoopSimulation.PIERRE_ID,
		"social_contact",
		contact_hour,
		1
	)
	_view.life_simulation.advance_hours(
		contact_hour - _view.life_simulation.clock.total_hours + 1
	)
	_open_character("relationships")
	await _capture("17_contact_jeanne")

	await _reset()
	var union_hour: int = V2DateTime.total_hour_from_iso(
		"1900-03-14T19:00:00"
	)
	_view.life_simulation.request_activity(
		V2LifeLoopSimulation.PIERRE_ID, "union_activity", union_hour, 2
	)
	_view.life_simulation.advance_hours(
		union_hour - _view.life_simulation.clock.total_hours + 2
	)
	_open_character("life_work")
	await _capture("18_union_activity")

	await _reset()
	var rent_hour: int = int(
		_view.life_simulation.households.household_for_person(
			V2LifeLoopSimulation.PIERRE_ID
		).get("next_rent_due_hour", -1)
	)
	_view.life_simulation.advance_hours(
		rent_hour - _view.life_simulation.clock.total_hours + 1
	)
	_open_character("life_work")
	await _capture("19_rent_paid")

	await _reset()
	_view.life_simulation.set_household_cash(
		V2LifeLoopSimulation.PIERRE_ID, 0
	)
	_view.life_binding.developer_command("force_rent")
	_open_character("life_work")
	await _capture("20_rent_arrears")

	await _reset()
	_view.interface.set_review_mode(true)
	_view.interface.set_identity("official")
	_open_character("life_work")
	await _capture("21_albert_personal_economy")

	_view.life_simulation.advance_to_datetime("1900-04-01T19:00:00")
	_open_character("life_work")
	await _capture("22_albert_april_salary")

	_close_layers()
	_view.interface.system_menu_open = true
	_view.interface.queue_redraw()
	await _capture("23_save_menu")

	_view.life_binding.save_review()
	_view.life_simulation.advance_hours(24)
	_view.life_binding.load_review()
	_open_panel("activity")
	await _capture("24_load_result")

	await _reset()
	_view.life_simulation.run_days(30)
	_open_character("life_work")
	await _capture("25_30_day_state")

	_view.interface.set_review_mode(true)
	_open_panel("developer")
	await _capture("26_developer_ledger_validation")

	_write_manifest()
	print(
		"V2_2_REVIEW_CAPTURE_COMPLETE screenshots=%d directory=%s"
		% [_captured_files.size(), ARTIFACT_DIRECTORY]
	)
	await _wait_frames(4)
	get_tree().quit(0)


func _reset() -> void:
	_close_layers()
	_view.life_simulation.reset_scenario()
	_view.interface.set_review_mode(false)
	_view.interface.set_identity("worker")
	_view.life_binding.set_paused(true)
	_view.interface.schedule_form.clear()
	_view.interface._hover_tooltip = ""
	await _wait_frames(3)


func _close_layers() -> void:
	if not _view.interface.open_panel.is_empty():
		_view.interface.close_panel(false)
	_view.interface.system_menu_open = false
	_view.interface.mode_menu_open = false
	_view.interface.detail_person_id = ""
	_view.interface.person_more_menu_open = false
	_view.interface.selected_object.clear()


func _open_panel(panel_id: String) -> void:
	_close_layers()
	_view.interface.open_panel_named(panel_id, false)


func _open_character(section: String) -> void:
	_open_panel("character")
	_view.interface.character_section = section
	_view.interface.queue_redraw()


func _capture(stem: String) -> void:
	await _wait_frames(4)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var filename: String = "%s.png" % stem
	var path: String = "%s/%s" % [ARTIFACT_DIRECTORY, filename]
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Unable to save review screenshot: %s" % path)
	else:
		_captured_files.append(filename)
		print("V2_2_CAPTURE_SAVED %s" % path)


func _write_manifest() -> void:
	var manifest: Dictionary = {
		"record_type": "v2_2_visible_window_review_manifest",
		"engine_version": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [1280, 720],
		"scene": "res://scenes/v2_2/v2_2_life_loop_main.tscn",
		"screenshot_count": _captured_files.size(),
		"screenshots": _captured_files,
	}
	var file := FileAccess.open(
		"%s/visible_review_manifest.json" % ARTIFACT_DIRECTORY,
		FileAccess.WRITE
	)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t", false))
		file.close()


func _wait_frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().process_frame
