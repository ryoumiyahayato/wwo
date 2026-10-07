class_name FormalWorldApplication
extends Control
## Scene assembly and UI action dispatch. Domain facts remain in their owners.

const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
var historical_content: HistoricalLoader
var _world: WorldState
var _simulation_step: SimulationStep
var _persistence: FormalPersistence
var _map_dirty: bool = false
@onready var map_renderer: GlobeRenderer = $GlobeRenderer
@onready var map_controller: GlobeController = $GlobeController
@onready var main_shell: MainShell = $MainShell
@onready var time_control: TimeControl = $TimeControl

func _ready() -> void:
	main_shell.action_requested.connect(_on_action_requested)
	main_shell.refresh_requested.connect(_refresh_ui)
	time_control.advance_requested.connect(_advance_world)
	time_control.controls_changed.connect(main_shell.queue_redraw)
	map_controller.selection_changed.connect(main_shell.refresh)
	var launch_mode := str(get_tree().get_meta(LAUNCH_MODE_META, "new"))
	var livelihood := str(get_tree().get_meta(FormalWorldMenu.LIVELIHOOD_META, FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT)) if launch_mode == "new" else FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT
	var built := WorldBootstrap.new().build(null, [], [], livelihood)
	if get_tree().has_meta(FormalWorldMenu.LIVELIHOOD_META):
		get_tree().remove_meta(FormalWorldMenu.LIVELIHOOD_META)
	if get_tree().has_meta(LAUNCH_MODE_META):
		get_tree().remove_meta(LAUNCH_MODE_META)
	if not built.success:
		FormalWorldPresenter.show_initialization_error(main_shell, built.error)
	else:
		_install_world(built)
		if launch_mode == "load":
			_load_world()
		else:
			FormalWorldPresenter.show_new_world(main_shell)
	map_renderer.input_blocked = main_shell.blocks_map
	_update_map_visibility()

func _install_world(built: WorldBuildResult) -> void:
	_world = built.world
	_simulation_step = built.simulation_step
	_persistence = built.persistence
	historical_content = WorldBootstrap.prepare_presentation_content(_world.provenance)
	main_shell.configure(historical_content.errors, map_controller, time_control)
	map_renderer.configure(historical_content.geometry_content, map_controller)
	map_renderer.local_content = historical_content.local_spatial
	map_renderer.relief.decode_asset = GeographyLoader.decode_relief
	_refresh_map()
	main_shell.refresh()

func _advance_world(minutes: int) -> void:
	if _simulation_step != null:
		_on_world_changed(_simulation_step.advance_minutes(minutes))

func _on_world_changed(change: Dictionary) -> void:
	if change.has("success") and not bool(change["success"]):
		FormalWorldPresenter.show_advance_error(main_shell, str(change["error"]))
		main_shell.queue_redraw()
		return
	if bool(change.get("economy", false)):
		_map_dirty = true
		if map_renderer.visible:
			_refresh_map()
	if int(change.get("wages_failed", 0)) > 0:
		main_shell.status_message = "工资到期未支付：雇主储备不足。"
	elif int(change.get("wages_paid", 0)) > 0:
		main_shell.status_message = "已收到 %d 笔工资交易。" % int(change["wages_paid"])
	if bool(change.get("economy", false)) or bool(change.get("organization_responsibilities", false)) or int(change.get("wages_paid", 0)) > 0 or int(change.get("wages_failed", 0)) > 0:
		main_shell.refresh()
	else:
		# Only the clock changed: the existing page facts are still current.
		main_shell.set_date(_world.game_clock.current_date())
		main_shell.queue_redraw()

func _refresh_ui() -> void:
	if _world != null:
		var content := historical_content.resolve_world_page(_world.game_clock.current_date(), FormalWorldPresenter.selected_world_polity(_world, map_controller), map_controller.selected_place_id)
		FormalWorldPresenter.refresh_ui(_world, main_shell, map_controller, content)

func _refresh_map() -> void:
	var content := historical_content.resolve_map(_world.game_clock.current_date(), FormalWorldPresenter.map_units(_world))
	FormalWorldPresenter.refresh_map(_world, map_renderer, content)
	_map_dirty = false

func _on_action_requested(action: String) -> void:
	if action.begins_with("map_mode:"):
		map_controller.set_map_mode(action.trim_prefix("map_mode:"))
	elif action.begins_with("time:"):
		var command := action.trim_prefix("time:")
		if command == "pause":
			time_control.toggle_pause()
		else:
			time_control.set_speed(int(command))
	else:
		match action:
			"page_changed": _update_map_visibility()
			"map:labels": map_controller.toggle_labels()
			"map:focus": map_renderer.focus_selection()
			"save":
				var result := _persistence.save_to_user() if _persistence != null else SaveOperationResult.fail("not_initialized", "正式世界尚未初始化，无法保存。", FormalPersistence.SAVE_PATH)
				FormalWorldPresenter.show_save_result(main_shell, result)
			"load": _load_world()
	main_shell.queue_redraw()

func _load_world() -> void:
	if _persistence == null:
		return
	var candidate := _persistence.load_from_user()
	var result := candidate.operation
	FormalWorldPresenter.show_load_result(main_shell, result)
	if candidate.success:
		if not candidate.world.political_registry.has_entity(map_controller.selected_polity_id):
			map_controller.select("")
		elif not map_controller.selected_place_id.is_empty() and candidate.world.spatial_world.get_place(map_controller.selected_place_id).is_empty():
			map_controller.select(map_controller.selected_polity_id)
		_install_world(candidate)

func _update_map_visibility() -> void:
	map_renderer.visible = main_shell.current_page == "map"
	# Other pages paint an opaque full-screen shell over the space shader.
	($Background as ColorRect).visible = map_renderer.visible or _world == null
	if map_renderer.visible and _map_dirty and _world != null:
		_refresh_map()
	elif not map_renderer.visible:
		map_controller.suspend_motion()
