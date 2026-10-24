class_name FormalWorldApplication
extends Control
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
## Scene assembly and UI action dispatch. Domain facts remain in their owners.

const LAUNCH_MODE_META: StringName = &"formal_world_launch_mode"
var historical_content: HistoricalLoader
var _world: WorldState
var _simulation_step: SimulationStep
var _persistence: FormalPersistence
var _save_dirty: bool = true
var _departure_target: String = ""
var _departure_was_paused: bool = true
var _leaving: bool = false
var _save_pending: bool = false
var _map_dirty: bool = false
var _economy_view_dirty: bool = true
var _organization_view_dirty: bool = true
var _economic_map_dirty: bool = false
var _flag_reference: Array = []
var _ui_refresh_pending: bool = false
var _ui_economy_day: int = -1
var _ui_economy_revision: int = -1
var _ui_politics: RuntimePoliticalEntityView
var _ui_economy: FormalWorldEconomyView
var _ui_organizations: FormalWorldOrganizationView
var _ui_responsibilities: FormalWorldOrganizationResponsibilityView
var _last_personal_transaction_id: String = ""
var _last_living_record_id: String = ""
var _economic_brief_key: Array = []
var _economic_detail_key: Array = []
var _economic_topic_pending: bool = false
var _economic_subject: String = ""
var _economic_order_offset: int = 0
var _economic_previous_mode: String = ""
var _economic_return_mode: String = "political"
var _economic_follow_order: String = ""
var _economic_locations_stamp: Array = []
@onready var map_renderer: GlobeRenderer = $GlobeRenderer
@onready var map_controller: GlobeController = $GlobeController
@onready var main_shell: MainShell = $MainShell
@onready var time_control: TimeControl = $TimeControl

func _enter_tree() -> void:
	var tree := get_tree()
	if not tree.has_meta(FormalWorldMenu.PREPARED_MAP_META): return
	var prepared := tree.get_meta(FormalWorldMenu.PREPARED_MAP_META) as GlobeRenderer
	var controller := tree.get_meta(FormalWorldMenu.PREPARED_CONTROLLER_META) as GlobeController
	historical_content = tree.get_meta(FormalWorldMenu.PREPARED_CONTENT_META) as HistoricalLoader
	get_node("GlobeRenderer").free()
	get_node("GlobeController").free()
	controller.reparent(self)
	prepared.reparent(self)
	# z_index changes painting, not Godot's GUI hit order. The reused menu
	# renderer was appended above native archive scrollbars/buttons in the tree.
	move_child(prepared,get_node("MainShell").get_index())
	prepared.preserve_on_reparent = false
	prepared.modulate = Color.WHITE
	prepared.visible = true
	for key: StringName in [FormalWorldMenu.PREPARED_MAP_META,FormalWorldMenu.PREPARED_CONTROLLER_META,FormalWorldMenu.PREPARED_CONTENT_META]:
		tree.remove_meta(key)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready(): _request_departure("quit")

func _ready() -> void:
	get_window().min_size = Vector2i(960,640)
	get_tree().auto_accept_quit = false
	main_shell.configure([],map_controller,time_control)
	main_shell.action_requested.connect(_on_action_requested)
	main_shell.refresh_requested.connect(_request_ui_refresh)
	time_control.advance_requested.connect(_advance_world)
	time_control.controls_changed.connect(main_shell.refresh_clock)
	map_controller.appearance_changed.connect(_refresh_economic_map)
	map_controller.appearance_changed.connect(_economic_mode_changed)
	map_controller.view_changed.connect(_request_economic_topic_refresh)
	map_controller.selection_changed.connect(_request_economic_topic_refresh)
	map_controller.topic_preferences_changed.connect(_request_economic_topic_refresh)
	map_renderer.topic_selected.connect(_open_economic_topic)
	map_renderer.place_content_ready.connect(_request_economic_topic_refresh)
	main_shell.economic_map.query_requested.connect(_query_economic_details)
	main_shell.economic_map.focus_requested.connect(_focus_economic_place)
	main_shell.economic_map.selection_requested.connect(_select_economic_place)
	main_shell.economic_map.links_changed.connect(map_renderer.set_topic_links)
	main_shell.economic_map.back_requested.connect(_close_economic_details)
	main_shell.economic_map.expand_requested.connect(func():map_controller.set_map_mode("economic"))
	main_shell.economic_map.business_requested.connect(_open_economic_business)
	main_shell.economic_map.statistics_requested.connect(func():
		var polity:=map_controller.selected_polity_id if not map_controller.selected_polity_id.is_empty() else map_controller.player_polity_id
		_on_action_requested("economy:polity:"+polity))
	map_controller.selection_changed.connect(main_shell.map_selection_changed)
	map_renderer.map_notice.connect(main_shell.show_map_feedback)
	map_renderer.current_politics_changed.connect(_on_current_map_politics_changed)
	map_renderer.geographic_reference_selected.connect(func(reference: Dictionary) -> void:
		if historical_content!=null: historical_content.remember_geographic_reference(reference))
	map_renderer.place_content_ready.connect(_on_place_content_ready)
	map_renderer.bind_controller(map_controller)
	map_renderer.relief.decode_asset = GeographyLoader.decode_relief
	map_renderer.input_blocked = main_shell.blocks_map
	map_renderer.label_exclusions = main_shell.map_occlusions
	main_shell.set_date(GameClock.new().current_date())
	main_shell.show_feedback("正在准备正式地图。")
	_update_map_visibility()
	_assemble_world.call_deferred()

func _assemble_world() -> void:
	# Let the current scene and its existing globe viewport draw before assembly.
	await get_tree().process_frame
	if _leaving or not is_inside_tree(): return
	var launch_mode := str(get_tree().get_meta(LAUNCH_MODE_META,"new"))
	var built: WorldBuildResult = get_tree().get_meta(FormalWorldMenu.PREPARED_WORLD_META) as WorldBuildResult if get_tree().has_meta(FormalWorldMenu.PREPARED_WORLD_META) else null
	if get_tree().has_meta(FormalWorldMenu.PREPARED_WORLD_META): get_tree().remove_meta(FormalWorldMenu.PREPARED_WORLD_META)
	if built == null:
		var livelihood := str(get_tree().get_meta(FormalWorldMenu.LIVELIHOOD_META,FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT)) if launch_mode=="new" else FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT
		var native_mode: Variant = get_tree().get_meta(FormalWorldMenu.NATIVE_ECONOMY_META,"")
		var native_settings: Dictionary = FormalEconomicOpening.for_source(WorldBootstrap.DEFAULT_FORMAL_PERSON_TERRITORY_ID) if launch_mode=="new" else {}
		if launch_mode=="new":
			if native_mode=="stratified" or OS.get_cmdline_user_args().has("--formal-stratified-economy") or (OS.get_cmdline_user_args().has("--formal-capital-transport") or OS.get_cmdline_user_args().has("--formal-npc-capital-trade") or OS.get_cmdline_user_args().has("--formal-npc-capital-competition") or OS.get_cmdline_user_args().has("--formal-npc-capital-recirculation") or (EconomyDevelopmentConfig.player_capital_requested() or OS.get_cmdline_user_args().has("--formal-economy-feedback"))):
				native_settings = EconomyDevelopmentConfig.formal_stratified_request()
			elif native_mode=="regional" or OS.get_cmdline_user_args().has("--formal-regional-economy"):
				native_settings = EconomyDevelopmentConfig.formal_regional_request()
			elif native_mode==true or native_mode=="limited" or OS.get_cmdline_user_args().has("--formal-native-economy"):
				native_settings = EconomyDevelopmentConfig.formal_limited()
		built = WorldBootstrap.new().build(null,[],[],livelihood,true,native_settings)
	for key: StringName in [LAUNCH_MODE_META,FormalWorldMenu.NATIVE_ECONOMY_META,FormalWorldMenu.LIVELIHOOD_META]:
		if get_tree().has_meta(key): get_tree().remove_meta(key)
	if not built.success:
		FormalWorldPresenter.show_initialization_error(main_shell,built.error)
	else:
		if not _install_world(built,launch_mode in ["new","prepared_new"]):
			_release_prepared_loading()
			return
		if launch_mode=="load": _load_world()
		elif launch_mode=="prepared_load":
			_save_dirty = false
			FormalWorldPresenter.show_load_result(main_shell,built.operation)
		else:
			FormalWorldPresenter.show_new_world(main_shell)
			if not _world.native_economy_error.is_empty():
				push_warning("Native economy was not installed: " + _world.native_economy_error)
				main_shell.show_feedback("经营资料加载失败：" + _world.native_economy_error)
			elif _world.economy_r1 != null: main_shell.show_feedback("经营资料已就绪。", "person:native")
	_update_map_visibility()
	_release_prepared_loading()

func _release_prepared_loading() -> void:
	# Installation is complete (or has an explicit error). A draw signal must
	# not keep the carried menu overlay alive when the window is not rendering.
	if get_tree().has_meta(FormalWorldMenu.PREPARED_LOADING_META):
		var loading := get_tree().get_meta(FormalWorldMenu.PREPARED_LOADING_META) as Control
		get_tree().remove_meta(FormalWorldMenu.PREPARED_LOADING_META)
		if is_instance_valid(loading): loading.queue_free()

func _install_world(built: WorldBuildResult, focus_opening: bool = false) -> bool:
	var presentation := historical_content
	if presentation==null: presentation = WorldBootstrap.prepare_presentation_content(built.world.provenance)
	if not presentation.loaded or not presentation.errors.is_empty():
		main_shell.configure(presentation.errors,map_controller,time_control)
		FormalWorldPresenter.show_initialization_error(main_shell,"地图资料准备失败："+"\n".join(presentation.errors))
		return false
	historical_content = presentation
	_world = built.world
	_economic_brief_key.clear()
	_economic_detail_key.clear()
	_economic_subject = ""
	_economic_follow_order = ""
	_economic_locations_stamp.clear()
	map_renderer.set_topic_places([])
	_economic_order_offset = 0
	main_shell.economic_map.clear_observation()
	map_renderer.set_topic_facts([])
	# Former land selections are presentation history, not a reason to reject
	# a world whose underlying land identities remain valid in its snapshot.
	if map_controller.selected_place_id.begins_with("territory_unit:"):
		map_controller.select(map_controller.selected_polity_id)
	map_renderer.spatial_world = _world.spatial_world
	_ui_politics = RuntimePoliticalEntityView.new(_world.political_registry.snapshot())
	_economy_view_dirty = true
	_organization_view_dirty = true
	_flag_reference.clear()
	_ui_economy_day = -1
	_ui_economy_revision = -1
	var personal := _world.personal_economy_state.person_economy(_world.player_state.player_id())
	_last_personal_transaction_id = str((personal.get("recent_wage_transaction",{}) as Dictionary).get("transaction_id",""))
	var living := _world.personal_economy_state.living_records(_world.player_state.player_id(),1)
	_last_living_record_id = str(living[0].record_id) if not living.is_empty() else ""
	_simulation_step = built.simulation_step
	_persistence = built.persistence
	main_shell.configure(historical_content.errors, map_controller, time_control)
	var opening_person := _world.person_overlay.person(_world.player_state.player_id())
	var opening_source := str((opening_person.get("provenance",{}) as Dictionary).get("opening_polity_source_id",WorldBootstrap.DEFAULT_FORMAL_PERSON_TERRITORY_ID if str(opening_person.get("claim_id",""))==WorldBootstrap.DEFAULT_FORMAL_PERSON_CLAIM_ID else str(opening_person.get("population_territory_id",""))))
	var home_id := _world.political_registry_view.runtime_id_for_source(opening_source)
	map_controller.begin_player_view(home_id)
	if map_renderer.content != historical_content.geometry_content:
		map_renderer.configure(historical_content.geometry_content, map_controller)
	map_renderer.local_content = historical_content.local_spatial
	map_renderer.strategic_content = historical_content.strategic_spatial
	map_renderer.relief.decode_asset = GeographyLoader.decode_relief
	_refresh_map()
	if focus_opening:
		map_renderer.focus_place(_world.spatial_catalog.get_place(str(opening_person.get("current_place_id",""))))
	main_shell.refresh()
	_request_economic_topic_refresh()
	return true

func _advance_world(minutes: int) -> void:
	if _simulation_step != null:
		_on_world_changed(_simulation_step.advance_minutes(minutes))

func _on_world_changed(change: Dictionary) -> void:
	if change.has("success") and not bool(change["success"]):
		FormalWorldPresenter.show_advance_error(main_shell, str(change["error"]))
		main_shell.queue_redraw()
		return
	_save_dirty = true
	_request_economic_topic_refresh()
	if _persistence != null and _persistence.queued_save_result != null:
		var result := _persistence.queued_save_result
		_persistence.queued_save_result = null
		_finish_save(result)
		if _world==null or not is_inside_tree(): return
	var economic_state_changed := _ui_economy_day!=int(_world.economy_state.total_hour/FormalWorldEconomyState.HOURS_PER_DAY) or _ui_economy_revision!=_world.economy_state._state_revision
	_economy_view_dirty = _economy_view_dirty or economic_state_changed
	_organization_view_dirty = _organization_view_dirty or bool(change.get("organization_responsibilities",false))
	_economic_map_dirty = _economic_map_dirty or _economy_view_dirty
	var date := _world.game_clock.current_date()
	# Feedback records receive the current world time before their UI delivery.
	main_shell.set_date(date)
	var date_key := HistoricalLoader._date_key(date)
	var previous_date := map_renderer.political.display_date
	var reference_changed := false
	if date_key!=previous_date:
		if historical_content.display_changes_between(previous_date,date_key):
			reference_changed = true
			_flag_reference.clear()
			_refresh_map()
		else:
			map_renderer.political.display_date = date_key
	# The economic overlay is refreshed only while it is the selected theme.
	if bool(change.get("economy",false)): _refresh_economic_map()
	if int(change.get("wages_paid",0)) > 0 or int(change.get("wages_failed",0)) > 0:
		var personal := _world.personal_economy_state.person_economy(_world.player_state.player_id())
		var receipt := personal.get("recent_wage_transaction",{}) as Dictionary
		var transaction_id := str(receipt.get("transaction_id",""))
		if not transaction_id.is_empty() and transaction_id != _last_personal_transaction_id:
			_last_personal_transaction_id = transaction_id
			main_shell.show_feedback("工资到账：+%s 模拟单位。" % receipt.amount,"person:accounts","domain","info",transaction_id)
		elif bool(personal.get("wage_unpaid",false)):
			main_shell.show_feedback("自己的工资已到期，雇主储备不足。","person:accounts","domain","error")
	if bool(change.get("personal_life_changed",false)):
		var living := _world.personal_economy_state.living_records(_world.player_state.player_id(),1)
		if not living.is_empty() and str(living[0].record_id) != _last_living_record_id:
			var record := living[0]
			_last_living_record_id = str(record.record_id)
			var message := "生活记录："+str(record.get("name_zh",""))
			if str(record.kind) in ["arrangement_failed","native_failed"]:
				message = "生活安排未完成："+str(record.get("reason","条件不足。"))
			elif str(record.kind) == "native_delivery":
				message = "商品已实际到货：%s %d %s。" % [record.name_zh,int(record.quantity),record.unit_name_zh]
			elif str(record.kind) in ["consume","native_consume"]:
				message = "消费已完成：%s %.3f %s。" % [record.name_zh,float(record.quantity_milli)/float(record.get("quantity_scale",1000)),record.get("unit_name_zh","")]
			main_shell.show_feedback(message,"living:record:"+str(record.record_id),"domain","info",str(record.record_id))
	var page := main_shell.current_page
	var personal_changed := bool(change.get("personal_life_changed",false)) or bool(change.get("persons_changed",false)) or bool(change.get("native_changed",false)) or int(change.get("wages_paid",0))>0 or int(change.get("wages_failed",0))>0
	if reference_changed or (page=="person" and personal_changed) or (page=="economy" and (economic_state_changed or bool(change.get("native_changed",false)))) or (page=="organization" and _organization_view_dirty):
		main_shell.refresh()
	elif date_key!=previous_date:
		# An observation date is not a change to the selected historical dossier.
		main_shell.world_page.set_observation_date(date_key)
		if page in ["map","world","administration"]: main_shell.queue_redraw()

func _request_ui_refresh() -> void:
	# Selection, page and content signals can describe one action. Build only
	# the final visible page once; domain steps and their order are untouched.
	if _ui_refresh_pending: return
	_ui_refresh_pending = true
	_refresh_ui.call_deferred()

func _refresh_ui() -> void:
	_ui_refresh_pending = false
	if _world == null or _leaving: return
	# Static map dossiers only use the existing identity-to-market links.
	# Fresh economic totals belong to the visible person/economy pages or map theme.
	_prepare_ui_views(_ui_economy==null or main_shell.current_page in ["person","economy"],main_shell.current_page in ["person","organization"])
	var polity := CurrentWorldPoliticalProjection.polity_summary(map_controller.selected_polity_id,_ui_politics,_world.historical_evidence_view)
	if polity.is_empty(): polity = map_renderer.political.records.get(map_controller.selected_polity_id,{}) as Dictionary
	var dossier_visible := main_shell.current_page in ["world","administration"] or (main_shell.current_page=="map" and (not map_controller.selected_polity_id.is_empty() or not map_controller.selected_place_id.is_empty()))
	var content := historical_content.resolve_world_page(_world.game_clock.current_date(),polity,map_controller.selected_place_id) if dossier_visible else WorldPageContent.new(HistoricalLoader._date_key(_world.game_clock.current_date()),{},{},{},null,{})
	if main_shell.current_page=="person" and main_shell.person_page.section=="native" and main_shell.person_page.business_mode and _world.economy_r1!=null:
		map_renderer.note_topic_query("economic_business_refreshes")
	FormalWorldPresenter.refresh_ui(_world,main_shell,map_controller,content,_ui_politics,_ui_economy,_ui_organizations,_ui_responsibilities)
	if dossier_visible:
		main_shell.world_page.set_spatial_context(_world.spatial_world)
		var current_land := map_renderer.selected_current_land()
		if current_land.is_empty() and _world.territory_state.has_territory(map_controller.selected_place_id):
			var raw_controller := _world.territory_state.get_controller(map_controller.selected_place_id)
			current_land = {"controller_polity_id":raw_controller if _ui_politics.has_entity(raw_controller) else _ui_politics.runtime_id_for_source(raw_controller)}
		main_shell.world_page.set_current_territory(current_land,_ui_politics,_world.historical_evidence_view)
	var person := _world.person_overlay.person(_world.player_state.player_id())
	var place := _world.spatial_world.get_place(str(person.get("current_place_id","")))
	var local_polity := CurrentWorldPoliticalProjection.polity_summary(map_controller.player_polity_id,_ui_politics,_world.historical_evidence_view)
	var flag_reference: Array = [map_controller.player_polity_id,str(local_polity.get("flag_id",""))]
	if _flag_reference!=flag_reference:
		main_shell.set_view_polity(local_polity,historical_content.flag_texture(_world.game_clock.current_date(),str(local_polity.get("flag_id",""))))
		_flag_reference = flag_reference
	if main_shell.current_page=="person":
		main_shell.person_page.set_location_context(_world.spatial_world,_world.territory_state,CurrentWorldPoliticalProjection.polity_summary(_ui_politics.runtime_id_for_source(str(place.get("parent_country_id",""))),_ui_politics,_world.historical_evidence_view))
		var market_id := _world.personal_economy_state.accessible_market_id(_world.player_state.player_id())
		var market_aggregate := _ui_economy.economic_aggregate_id_for_market(market_id)
		main_shell.person_page.available_market = not market_id.is_empty() and not _ui_economy.polity_ids_for_economy(market_aggregate).is_empty()
	if main_shell.current_page=="world" and main_shell.world_page.index_open:
		main_shell.world_page.set_index_context(CurrentWorldPoliticalProjection.map_units(_ui_politics,_world.historical_evidence_view))
	var display_record := map_renderer.political.records.get(map_controller.selected_polity_id,{}) as Dictionary
	if dossier_visible and bool(display_record.get("display_only",false)):
		var visual := map_renderer.political.resolved_visuals.get(map_controller.selected_polity_id,{}) as Dictionary
		main_shell.world_page.refresh(display_record,content.place(),WorldPageContent.new(content.date(),content.profile(),content.administration(),content.flag() if not content.flag().is_empty() else visual,map_renderer.political.visual_textures.get(map_controller.selected_polity_id),content.place()))
	# Page data arrives in this deferred refresh, after the initiating draw.
	# Publish the completed page instead of leaving its empty first draw visible.
	main_shell.queue_redraw()

func _on_current_map_politics_changed(state_changed: bool) -> void:
	if _world==null or _leaving: return
	if state_changed: _save_dirty = true
	map_renderer.reconcile_current_selection()
	if main_shell.current_page in ["map","world","administration"]: _request_ui_refresh()

func _on_place_content_ready() -> void:
	if historical_content == null: return
	var errors: Array[String] = []
	for content: LocalSpatialContent in [historical_content.strategic_spatial.content,historical_content.local_spatial.content]:
		if content != null: errors.append_array(content.errors)
	if not errors.is_empty(): main_shell.show_feedback("地图资料读取错误："+"; ".join(errors))
	# A map shard finishing must not rebuild a visible business/person page
	# just because an unrelated geographic selection still exists behind it.
	if main_shell.current_page in ["map","world","administration"] and not map_controller.selected_place_id.is_empty(): main_shell.refresh()

func _refresh_map() -> void:
	_prepare_ui_views(true,false)
	var content := historical_content.resolve_map(_world.game_clock.current_date(),FormalWorldPresenter.map_units(_world,_ui_politics))
	FormalWorldPresenter.refresh_map(_world,map_renderer,content,_ui_politics,_ui_economy)
	_map_dirty = false
	_economic_map_dirty = false

func _prepare_ui_views(need_economy: bool, need_organizations: bool) -> void:
	if need_economy and (_ui_economy==null or _economy_view_dirty):
		_ui_economy = FormalWorldEconomyView.new(_world.economy_state.read_only_presentation_snapshot())
		_ui_economy_day = int(_world.economy_state.total_hour/FormalWorldEconomyState.HOURS_PER_DAY)
		_ui_economy_revision = _world.economy_state._state_revision
		_economy_view_dirty = false
	if need_organizations and (_ui_organizations==null or _organization_view_dirty):
		_ui_organizations = FormalWorldOrganizationView.new(_world.organization_state.snapshot())
		_ui_responsibilities = FormalWorldOrganizationResponsibilityView.new(_world.organization_responsibility.read_only_snapshot())
		_organization_view_dirty = false

func _refresh_economic_map() -> void:
	if _world==null or not _economic_map_dirty or map_controller.map_mode not in ["fulfillment","shortage"]: return
	_prepare_ui_views(true,false)
	map_renderer.refresh_economic_observation(_ui_politics,_world.historical_evidence_view,_ui_economy)
	_economic_map_dirty = false
	_request_economic_topic_refresh()

func _economic_mode_changed() -> void:
	var mode := map_controller.map_mode
	if mode!=_economic_previous_mode:
		if mode=="economic":
			_economic_return_mode = _economic_previous_mode if _economic_previous_mode in ["political","geographic"] else "political"
			main_shell.set("_context_open",false)
		elif _economic_previous_mode=="economic":
			main_shell.economic_map.clear_observation()
			_economic_detail_key.clear()
		_economic_previous_mode = mode
	_request_economic_topic_refresh()

func _request_economic_topic_refresh() -> void:
	if _economic_topic_pending or _world==null or _leaving: return
	_economic_topic_pending = true
	_refresh_economic_topic.call_deferred()

func _refresh_economic_topic() -> void:
	# Coalesce camera/content signals; the renderer keeps the primary layout.
	await get_tree().process_frame
	_economic_topic_pending = false
	if _world==null or _leaving or not is_inside_tree(): return
	var polity := map_controller.selected_polity_id if not map_controller.selected_polity_id.is_empty() else map_controller.player_polity_id
	var state_key := FormalEconomicMapObservation.stamp(_world)
	if _economic_locations_stamp!=state_key:
		_economic_locations_stamp=state_key
		map_renderer.set_topic_places(FormalEconomicMapObservation.known_places(_world))
	if _economic_brief_key.is_empty() or _economic_brief_key[0]!=state_key or _economic_brief_key[2]!=polity:
		var totals := _world.economy_state.country_summary(polity).get("daily_totals",{}) as Dictionary
		var available := not totals.is_empty() and float(totals.get("fulfillment_bp",-1))>=0
		if main_shell.economic_data_available!=available:
			main_shell.economic_data_available = available
			main_shell.queue_redraw()
	if main_shell.current_page!="map":
		main_shell.economic_map.clear_observation()
		_economic_detail_key.clear()
		return
	var places := map_renderer.topic_place_ids()
	var key: Array = [state_key,places,polity,map_controller.economic_supplements_enabled,map_controller.map_mode=="economic"]
	if key!=_economic_brief_key:
		_economic_brief_key = key
		var source := _ui_politics.source_historical_id(polity) if _ui_politics!=null else ""
		var rows: Array[Dictionary] = []
		if map_controller.economic_supplements_enabled or map_controller.map_mode=="economic":
			map_renderer.note_topic_query("economic_brief_queries")
			rows = FormalEconomicMapObservation.brief(_world,places,polity,map_renderer.topic_capital(source))
		map_renderer.set_topic_facts(rows)
		var hint := not rows.is_empty()
		if main_shell.economic_hint_available!=hint:
			main_shell.economic_hint_available = hint
			main_shell.queue_redraw()
	var view := main_shell.economic_map
	if map_controller.map_mode=="economic" or view.visible:
		var detail_key: Array = [state_key,polity,_economic_subject,_economic_order_offset]
		if detail_key!=_economic_detail_key or not view.visible or view.full!=(map_controller.map_mode=="economic"):
			map_renderer.note_topic_query("economic_detail_queries")
			var observation := FormalEconomicMapObservation.details(_world,polity,_economic_subject,_economic_order_offset,_economic_follow_order)
			_economic_follow_order = ""
			_economic_subject = str(observation.get("subject",""))
			_economic_order_offset = int(observation.get("offset",0))
			_economic_detail_key = [state_key,polity,_economic_subject,_economic_order_offset]
			view.present(observation,_world.spatial_catalog,map_controller.map_mode=="economic",_economic_return_mode)

func _query_economic_details(subject: String, offset: int) -> void:
	_economic_subject = subject
	_economic_order_offset = maxi(0,offset)
	_economic_detail_key.clear()
	# A compact political detail is opened explicitly, never by a pan.
	main_shell.economic_map.show()
	main_shell.set("_context_open",false)
	_request_economic_topic_refresh()

func _open_economic_topic(place_id: String, subject: String) -> void:
	main_shell.economic_map.select_place(place_id)
	_query_economic_details(subject,0)

func _select_economic_place(place_id: String) -> void:
	if _world==null: return
	var place := _world.spatial_catalog.get_place(place_id)
	if place.is_empty(): return
	var polity := _ui_politics.runtime_id_for_source(str(place.get("parent_country_id","")))
	map_controller.select(polity,place_id)
	main_shell.set("_context_open",false)

func _focus_economic_place(place_id: String) -> void:
	if _world==null: return
	var place := _world.spatial_catalog.get_place(place_id)
	if not place.get("lon_lat") is Array: return
	_select_economic_place(place_id)
	main_shell.economic_map.select_place(place_id)
	map_renderer.focus_place(place)

func _close_economic_details() -> void:
	main_shell.economic_map.clear_observation()
	_economic_detail_key.clear()
	if map_controller.map_mode=="economic": map_controller.set_map_mode(_economic_return_mode)

func _open_economic_business(subject: String, site_id: String = "") -> void:
	if _world==null: return
	var observer:=_world.player_state.player_id()
	var personal:=LivelihoodAction.query(_world,observer)
	if subject==observer and not personal.is_empty():
		main_shell.remember_page()
		main_shell.person_page.section="native"
		main_shell.person_page.native_scope_expanded=false
		main_shell.person_page.business_mode=false
		main_shell.person_page.lease_mode=false
		main_shell.person_page.resident_services_mode=false
		main_shell.set_page("person",false)
		return
	var managers:=personal.get("managed_firms",[]) as Array
	for index: int in range(managers.size()):
		if str(managers[index].firm_id)!=subject: continue
		var target_site:=site_id if not site_id.is_empty() else main_shell.economic_map.selected_site
		if target_site.is_empty():return
		var business:=LivelihoodAction.query_business(_world,observer,subject,target_site,main_shell.person_page.quantity_milli)
		if business.is_empty():return
		var site_index:=(business.get("sites",[]) as Array).find(target_site)
		if site_index<0:return
		main_shell.remember_page()
		main_shell.person_page.section="native"
		main_shell.person_page.native_scope_expanded=true
		main_shell.person_page.business_mode=true
		main_shell.person_page.business_procurement_mode=true
		main_shell.person_page.business_finance_mode=false
		main_shell.person_page.business_services_mode=false
		main_shell.person_page.business_leases_mode=false
		main_shell.person_page.business_capital_mode=false
		main_shell.person_page.lease_mode=false
		main_shell.person_page.resident_services_mode=false
		main_shell.person_page.selected_record_id=""
		main_shell.person_page.selected_commodity_id=""
		main_shell.person_page.business_firm_index=index
		main_shell.person_page.business_site_index=site_index
		main_shell.person_page.business_firm_id=subject
		main_shell.person_page.business_site_id=target_site
		main_shell.person_page.business_offer_page=0
		main_shell.set_page("person",false)
		return

func _follow_economic_purchase(result: Dictionary, payload: Dictionary) -> void:
	if not bool(result.get("accepted",false)) or str(result.get("order_id","")).is_empty():return
	_economic_subject=str(payload.get("firm",""))
	_economic_follow_order=str(result.order_id)
	_economic_detail_key.clear()
	var business:=main_shell.person_page._business
	main_shell.economic_map.follow_order(_economic_follow_order,str(business.get("site",{}).get("stock_place_id","")),str(payload.get("buyer_site","")))
	_request_economic_topic_refresh()

func _on_action_requested(action: String) -> void:
	if _leaving: return
	if action in ["system:main_menu","system:quit"]:
		_request_departure("menu" if action=="system:main_menu" else "quit")
		return
	elif action=="departure:cancel":
		if not _departure_target.is_empty():
			_departure_target = ""
			time_control.paused = _departure_was_paused
		return
	elif action=="departure:discard":
		_leave_world()
		return
	elif action=="departure:save":
		if not _departure_target.is_empty(): _save_world(0)
		return
	elif action.begins_with("slot:save:"):
		_save_world(int(action.trim_prefix("slot:save:")))
		return
	elif action.begins_with("slot:load:"):
		_load_world(int(action.trim_prefix("slot:load:")))
		return
	elif action=="map:internal_load":
		if _world!=null and OS.has_feature("internal_landmark_preview"):
			main_shell.world_page.internal_load_active = not main_shell.world_page.internal_load_active
			map_renderer.set_internal_load_test(main_shell.world_page.internal_load_active)
			main_shell.queue_redraw()
		return
	elif action.begins_with("map:pilot_landmark:"):
		if _world!=null and map_renderer.focus_internal_landmark(action.trim_prefix("map:pilot_landmark:")):
			main_shell.world_page.index_open = false
			main_shell.set_page("map")
		return
	elif action.begins_with("encyclopedia:country:"):
		main_shell.remember_page()
		map_controller.select(action.trim_prefix("encyclopedia:country:"))
		main_shell.world_page.index_open = false
		main_shell.set_page("world")
		return
	elif action=="encyclopedia:organizations":
		main_shell.remember_page()
		main_shell.organization_page.own_only = false
		main_shell.organization_page.country_id = ""
		main_shell.organization_page.selected_id = ""
		main_shell.set_page("organization",false)
		return
	elif action.begins_with("map_mode:"):
		map_controller.set_map_mode(action.trim_prefix("map_mode:"))
		if main_shell.current_page!="map": main_shell.set_page("map",false)
	elif action.begins_with("time:"):
		var command := action.trim_prefix("time:")
		if command == "pause": time_control.toggle_pause()
		else: time_control.set_speed(int(command))
	elif action.begins_with("lease_ui:"):
		if action=="lease_ui:personal_toggle": main_shell.person_page.lease_mode=not main_shell.person_page.lease_mode
		elif action=="lease_ui:business_toggle": main_shell.person_page.business_leases_mode=not main_shell.person_page.business_leases_mode
		else: main_shell.person_page.lease_page=maxi(0,main_shell.person_page.lease_page+(-1 if action.ends_with("previous") else 1))
		main_shell.refresh()
	elif action.begins_with("resident_service_ui:"):
		if action=="resident_service_ui:toggle": main_shell.person_page.resident_services_mode=not main_shell.person_page.resident_services_mode
		else: main_shell.person_page.resident_service_page=maxi(0,main_shell.person_page.resident_service_page+(-1 if action.ends_with("previous") else 1))
		main_shell.refresh()
	elif action.begins_with("capital_ui:"):
		if action=="capital_ui:toggle": main_shell.person_page.business_capital_mode=not main_shell.person_page.business_capital_mode
		elif action.contains("action_"): main_shell.person_page.business_capital_action_page=maxi(0,main_shell.person_page.business_capital_action_page+(-1 if action.ends_with("previous") else 1))
		else:
			main_shell.person_page.business_capital_page=maxi(0,main_shell.person_page.business_capital_page+(-1 if action.ends_with("previous") else 1));main_shell.person_page.business_capital_action_page=0
		main_shell.refresh()
	elif action.begins_with("service_ui:"):
		if action=="service_ui:toggle": main_shell.person_page.business_services_mode=not main_shell.person_page.business_services_mode
		else: main_shell.person_page.business_service_page=maxi(0,main_shell.person_page.business_service_page+(-1 if action.ends_with("previous") else 1))
		main_shell.refresh()
	elif _world != null and action.begins_with("native:"):
		var result: Dictionary
		if action.begins_with("native:capital_action:"):
			var row:=main_shell.person_page.capital_request(action.trim_prefix("native:capital_action:"))
			result=LivelihoodAction.execute_current(_world,row["kind"],row["payload"]) if not row.is_empty() else {"accepted":false,"reason":"KNOWN_CAPITAL_ACTION_NO_LONGER_AVAILABLE"}
		elif action.begins_with("native:lease_action:"):
			var parts:=action.trim_prefix("native:lease_action:").split(":")
			var row:=main_shell.person_page.lease_request(int(parts[1]),parts[0]=="business") if parts.size()==2 else {}
			result=LivelihoodAction.execute_current(_world,row["kind"],row["payload"]) if not row.is_empty() else {"accepted":false,"reason":"LEASE_CANDIDATE_UNAVAILABLE"}
		elif action.begins_with("native:labor_action:"):
			var row:=main_shell.person_page.labor_request(int(action.trim_prefix("native:labor_action:")))
			result=LivelihoodAction.execute_current(_world,row["kind"],row["payload"]) if not row.is_empty() else {"accepted":false,"reason":"EMPLOYMENT_PROPOSAL_UNAVAILABLE"}
		elif action.begins_with("native:resident_service_action:"):
			var row:=main_shell.person_page.resident_service_request(int(action.trim_prefix("native:resident_service_action:")))
			result=LivelihoodAction.execute_current(_world,row["kind"],row["payload"]) if not row.is_empty() else {"accepted":false,"reason":"RESIDENT_SERVICE_CANDIDATE_UNAVAILABLE"}
		elif action.begins_with("native:service_action:"):
			var row:=main_shell.person_page.business_service_request(int(action.trim_prefix("native:service_action:")))
			result=LivelihoodAction.execute_current(_world,row["kind"],row["payload"]) if not row.is_empty() else {"accepted":false,"reason":"SERVICE_CANDIDATE_UNAVAILABLE"}
		elif action=="native:business_finance":
			var payload := main_shell.person_page.business_finance_request()
			if not payload.is_empty(): result=LivelihoodAction.execute_current(_world,"finance_firm",payload)
		elif action.begins_with("native:business_buy:"):
			var payload := main_shell.person_page.business_request(int(action.trim_prefix("native:business_buy:")))
			result=LivelihoodAction.execute_current(_world,"buy",payload) if not payload.is_empty() else {"accepted":false,"reason":"KNOWN_ENTERPRISE_QUOTE_UNAVAILABLE"}
			_follow_economic_purchase(result,payload)
		elif action.begins_with("native:business_activity:"):
			var parts := action.trim_prefix("native:business_activity:").split("|")
			result=LivelihoodAction.execute_current(_world,"set_activity_enabled",{"firm":parts[0],"site_id":parts[1],"activity_id":parts[2],"enabled":parts[3]=="1"}) if parts.size()==4 else {"accepted":false,"reason":"INVALID_ACTIVITY_INPUT"}
		elif action == "native:residence":
			var person := _world.player_state.player_id()
			var place := _world.person_overlay.current_place(person)
			result = LivelihoodAction.execute_current(_world, "request_residence", {"destination_unit_id": _world.population_state.unit_for_place(place), "place_id": place})
		elif action.begins_with("native:travel:"):
			result = LivelihoodAction.execute_current(_world, "travel", {"destination_place_id": action.trim_prefix("native:travel:")})
		elif action.begins_with("native:collect:") or action.begins_with("native:collect_store:"):
			var payload := {"shipment_id": action.trim_prefix("native:collect:").trim_prefix("native:collect_store:"), "quantity": main_shell.person_page.quantity_milli}
			if action.begins_with("native:collect_store:"): payload["custody_mode"] = "STORED"
			result = LivelihoodAction.execute_current(_world, "collect", payload)
		elif action in ["native:store", "native:withdraw"]:
			var person := _world.player_state.player_id()
			result = LivelihoodAction.execute_current(_world, "store_goods" if action == "native:store" else "withdraw_goods", {"good": main_shell.person_page.selected_commodity_id.trim_prefix("native:"), "quantity": main_shell.person_page.quantity_milli, "place_id": _world.person_overlay.current_place(person)})
		elif action.begins_with("native:freight:"):
			var person := _world.player_state.player_id()
			var good := main_shell.person_page.selected_commodity_id.trim_prefix("native:")
			var options := _world.economy_r1.personal_freight_options(person, good)
			var index := int(action.trim_prefix("native:freight:"))
			result = {"accepted": false, "reason": "EXPIRED_FREIGHT_OPTION"}
			if index >= 0 and index < options.size():
				var offer := options[index] as Dictionary
				result = LivelihoodAction.execute_current(_world, "send_personal_goods", {"good": good, "quantity": main_shell.person_page.quantity_milli, "from_place_id": offer["from_place_id"], "to_place_id": offer["to_place_id"], "path_id": offer["path_id"], "denomination": offer["denomination"], "max_freight": offer["freight_per_unit"]})
		elif action.begins_with("native:investment_credit:"):
			var parts := action.trim_prefix("native:investment_credit:").split("|", true, 2)
			result = LivelihoodAction.execute_current(_world, "finance_investment", {"project_id": parts[0], "offer_id": parts[1], "amount": int(parts[2])}) if parts.size() == 3 and str(parts[2]).is_valid_int() else {"accepted": false, "reason": "INVALID_FINANCE_INPUT"}
		elif action.begins_with("native:invest:") or action.begins_with("native:maintain:"):
			var maintenance := action.begins_with("native:maintain:")
			var id := action.trim_prefix("native:invest:").trim_prefix("native:maintain:")
			var terms := _world.economy_r1._capital.maintenance_template(id,_world.game_clock.total_minutes()) if maintenance else _world.economy_r1._capital.template(id)
			result = LivelihoodAction.execute_current(_world, "maintain_capital" if maintenance else "invest", {("asset_id" if maintenance else "template_id"): id, "budget": terms.get("budget", 0)})
		elif action.begins_with("native:project:") or action.begins_with("native:equipment:"):
			var equipment := action.begins_with("native:equipment:")
			var parts := action.trim_prefix("native:project:").trim_prefix("native:equipment:").split("|", true, 1)
			result = LivelihoodAction.execute_current(_world, "capital_status" if equipment else "investment_status", {("asset_id" if equipment else "project_id"): parts[0], "status": parts[1]}) if parts.size() == 2 else {"accepted": false, "reason": "INVALID_CAPITAL_INPUT"}
		elif action.begins_with("native:expand:"):
			result = LivelihoodAction.execute_current(_world, "expand_configured_scope", {"extension_id": action.trim_prefix("native:expand:")})
		elif action.begins_with("native:pause:") or action.begins_with("native:resume:"):
			var operating := action.begins_with("native:resume:")
			result = LivelihoodAction.execute_current(_world, "set_firm_operating", {"firm": action.trim_prefix("native:pause:").trim_prefix("native:resume:"), "operating": operating})
		elif action == "native:leave_job":
			result = LivelihoodAction.execute_current(_world, "leave_job", {})
		elif action == "native:reenter":
			result = LivelihoodAction.execute_current(_world, "reenter_scope", {"subject_id": _world.player_state.player_id()})
		elif action.begins_with("native:retry_exit:"):
			result = LivelihoodAction.execute_current(_world, "retry_scope_exit", {"request_id": action.trim_prefix("native:retry_exit:")})
		elif action.begins_with("native:management_accept:"):
			result = LivelihoodAction.execute_current(_world, "accept_firm_management", {"request_id": action.trim_prefix("native:management_accept:")})
		elif action.begins_with("native:management:"):
			var parts := action.trim_prefix("native:management:").split("|", true, 1)
			result = LivelihoodAction.execute_current(_world, "request_firm_management", {"firm": parts[0], "successor": parts[1]}) if parts.size() == 2 else {"accepted": false, "reason": "INVALID_MANAGEMENT_INPUT"}
		elif action.begins_with("native:site_pause:") or action.begins_with("native:site_resume:") or action.begins_with("native:site_close:"):
			var parts := action.trim_prefix("native:site_pause:").trim_prefix("native:site_resume:").trim_prefix("native:site_close:").split("|", true, 1)
			result = {"accepted": false, "reason": "INVALID_SITE_INPUT"}
			if parts.size() == 2:
				if action.begins_with("native:site_close:"): result = LivelihoodAction.execute_current(_world, "close_site", {"firm": parts[0], "site_id": parts[1]})
				else:
					var enabled := action.begins_with("native:site_resume:")
					result = LivelihoodAction.execute_current(_world, "set_site_status", {"firm": parts[0], "site_id": parts[1], "enabled": enabled, "production_enabled": enabled, "accepting_business": enabled})
		elif action.begins_with("native:wind_down:"):
			result = LivelihoodAction.execute_current(_world, "wind_down_firm", {"firm": action.trim_prefix("native:wind_down:")})
		elif action.begins_with("native:finish:"):
			result = LivelihoodAction.execute_current(_world, "finish_firm", {"firm": action.trim_prefix("native:finish:")})
		elif action.begins_with("native:exit:"):
			result = LivelihoodAction.execute_current(_world, "request_scope_exit", {"subject_id": action.trim_prefix("native:exit:")})
		elif action.begins_with("native:apply:"):
			var parts:=action.trim_prefix("native:apply:").split("|")
			var payload:={"job_id":parts[0]}
			if parts.size()==2 and not parts[1].is_empty(): payload["job_quote_id"]=parts[1]
			result = LivelihoodAction.execute_current(_world, "apply", payload)
		elif action == "native:work":
			var employment := _world.personal_economy_state.person_economy(_world.player_state.player_id()).get("employment", {}) as Dictionary
			result = LivelihoodAction.execute_current(_world, "work", {"hours": int(employment.get("work_hours_available", employment.get("work_hours_limit", 0)))})
		elif action.begins_with("native:loss_confirm:"):
			result = LivelihoodAction.execute_current(_world, "confirm_cargo_loss", {"loss_id": action.trim_prefix("native:loss_confirm:")})
		elif action.begins_with("native:loss_release:"):
			result = LivelihoodAction.execute_current(_world, "propose_cargo_disposition", {"loss_id": action.trim_prefix("native:loss_release:"), "mode": "RELEASE", "quantity": main_shell.person_page.quantity_milli, "basis": "EXPLICIT_PLAYER_CONTRACT_RELEASE_PROPOSAL", "authorizations": _world.economy_r1._cargo_fulfilment.action_authorizations(_world.player_state.player_id(),action.trim_prefix("native:loss_release:"),"RELEASE",main_shell.person_page.quantity_milli)})
		elif action.begins_with("native:loss_replace:"):
			result = LivelihoodAction.execute_current(_world, "propose_cargo_disposition", {"loss_id": action.trim_prefix("native:loss_replace:"), "mode": "REPLACE", "quantity": main_shell.person_page.quantity_milli, "fees": [], "basis": "EXPLICIT_PLAYER_NO_ADDITIONAL_FREIGHT_PROPOSAL", "authorizations": _world.economy_r1._cargo_fulfilment.action_authorizations(_world.player_state.player_id(),action.trim_prefix("native:loss_replace:"),"REPLACE",main_shell.person_page.quantity_milli)})
		elif action.begins_with("native:disposition_confirm:"):
			result = LivelihoodAction.execute_current(_world, "confirm_cargo_disposition", {"disposition_id": action.trim_prefix("native:disposition_confirm:"), "authorizations":_world.economy_r1._cargo_fulfilment.action_authorizations(_world.player_state.player_id(),"","",0,action.trim_prefix("native:disposition_confirm:"))})
		elif action.begins_with("native:disposition_execute:"):
			result = LivelihoodAction.execute_current(_world, "execute_cargo_disposition", {"disposition_id": action.trim_prefix("native:disposition_execute:"), "authorizations":_world.economy_r1._cargo_fulfilment.action_authorizations(_world.player_state.player_id(),"","",0,action.trim_prefix("native:disposition_execute:"),true)})
		elif action.begins_with("native:cancel:"):
			result = LivelihoodAction.execute_current(_world, "cancel", {"order_id": action.trim_prefix("native:cancel:")})
		else:
			result = {"accepted": false, "reason": "UNKNOWN_ACTION"}
		if result.get("responsibility_changed", false): _save_dirty = true
		var feedback := "行动未接受："+(EconomicText.reason(str(result.get("reason", "条件不足。"))) if action.begins_with("native:apply:") or action in ["native:work","native:leave_job"] else PersonView.capital_reason(str(result.get("reason","条件不足。"))))
		if result.get("accepted", false):
			_save_dirty = true
			feedback = "行动已接受，按正式时间履行。"
			if action.begins_with("native:apply:"):
				main_shell.person_page.native_tab="wages"
				feedback="劳动合同已成立；须另行登记实际工作，完成后才形成工资。"
			elif action=="native:work": feedback="本期工作已登记，尚未完成。下次日界结算劳动，再按合同到期规则处理工资。"
			elif action=="native:leave_job": feedback="离职待生效："+PersonView.boundary_text(int(result.get("boundary_minute",0)))+"；此前仍占岗，旧工资责任保留。"
			if action.begins_with("native:business_buy:"):feedback="采购已受理：%s · %s单位。返回经济地图可跟进本单。"%[str(result.get("order_id","")),str(result.get("quantity",""))]
			if result.get("reason") == "COLLECTED": feedback = "已领取 %d 单位；原订单付款与持有已记录。" % int(result["quantity"])
			elif result.get("reason") in ["STORED", "WITHDRAWN", "PERSONAL_FREIGHT_ACCEPTED"]: feedback = "物品行动已接受："+str(result["reason"])+" · 数量 "+str(result["quantity"])
			elif result.get("reason") == "TRAVEL_STARTED": feedback = "旅行已出发；到达前不能登记劳动。"
			elif result.get("reason") == "QUEUED_FOR_ECONOMIC_BOUNDARY": feedback = "接管已排队："+PersonView.boundary_text(int(result["boundary_minute"]))
			elif result.get("reason") == "RESIDENCE_QUEUED": feedback = "常住迁居已申请："+PersonView.boundary_text(int(result["boundary_minute"]))+"；生效前保留原统计归属。"
			elif result.get("reason") == "EXIT_QUEUED": feedback = "退出已排队；边界确认无未结责任后，由旧宏观承担未来常住消费。"
			elif result.get("reason") == "EXIT_DEFERRED": feedback = "退出延后，保留原归属："+str(result["responsibility_reason"])
		main_shell.show_feedback(feedback, "person:goods" if action in ["native:store", "native:withdraw"] or action.begins_with("native:freight:") else "person:native")
		main_shell.refresh()
	elif _world != null and action in ["livelihood:terminate_wage", "livelihood:cancel_plan", "livelihood:convert_plan"]:
		var payload: Dictionary = {}
		var kind := "terminate_legacy_wage"
		if action != "livelihood:terminate_wage":
			payload["commodity_id"] = main_shell.person_page.selected_commodity_id
			kind = "cancel_legacy_arrangement" if action == "livelihood:cancel_plan" else "convert_legacy_arrangement"
			if kind == "convert_legacy_arrangement": payload["auto_buy_missing"] = bool(_world.personal_economy_state.arrangement(_world.player_state.player_id(), payload["commodity_id"]).get("auto_buy_missing", false))
		var result := LivelihoodAction.execute_current(_world, kind, payload)
		if result.get("accepted", false): _save_dirty = true
		main_shell.show_feedback("生计变更已排队，原责任在生效前继续履行。" if result.get("accepted", false) else "未接受："+str(result.get("reason", "")), "person:goods" if action != "livelihood:terminate_wage" else "person:situation")
		main_shell.refresh()
	elif _world != null and action in ["purchase","consume","consumption:daily","consumption:autobuy"]:
		var person_id := _world.player_state.player_id()
		var personal := _world.personal_economy_state
		var result: Dictionary
		if action == "purchase":
			var page := main_shell.economy_page
			var market_id := _ui_economy.market_id_for_economic_aggregate(_ui_economy.economy_entity_for_polity(page.polity_id))
			if personal.manages_native(person_id): market_id = page.selected_seller_site_id
			result = personal.purchase(person_id,market_id,page.selected_commodity_id,page.quantity_milli,int(page.quote.get("unit_price",-1)),page.quote)
			if bool(result.get("success",false)):
				main_shell.person_page.selected_commodity_id = page.selected_commodity_id
				# One displayed quote is one purchase choice. The next purchase
				# requires selecting an offer again, including a double click.
				page.selected_commodity_id = ""
				page.selected_seller_site_id = ""
				page.quote = {}
		elif action == "consume":
			result = personal.consume(person_id,main_shell.person_page.selected_commodity_id,main_shell.person_page.quantity_milli)
		elif action == "consumption:autobuy":
			var page := main_shell.person_page
			var plan := personal.arrangement(person_id,page.selected_commodity_id)
			result = {"success":false,"error":"请先设置每日安排。"} if plan.is_empty() else personal.set_daily_consumption(person_id,page.selected_commodity_id,int(plan.quantity_milli),true,not bool(plan.auto_buy_missing))
		else:
			var page := main_shell.person_page
			result = personal.set_daily_consumption(person_id,page.selected_commodity_id,page.quantity_milli,personal.arrangement(person_id,page.selected_commodity_id).is_empty())
		if bool(result.get("success",false)):
			_save_dirty = true
			var recent := personal.living_records(person_id,1)
			if not recent.is_empty(): _last_living_record_id = str(recent[0].record_id)
			var destination := "holding:select:"+main_shell.person_page.selected_commodity_id if action != "consume" else "living:record:"+_last_living_record_id
			main_shell.show_feedback("购买已受理；在个人订单查看交付，物品页查看实际持有。" if action=="purchase" and personal.manages_native(person_id) else "已按原消费规则使用"+EconomicText.good(main_shell.person_page.selected_commodity_id)+"；需要状态已更新。" if action=="consume" and personal.manages_native(person_id) else str(result.message),destination)
		else: main_shell.show_feedback("操作未完成："+str(result.get("error","条件不可用。")))
		main_shell.refresh()
	elif _world != null and action == "person:market":
		var market_id := _world.personal_economy_state.accessible_market_id(_world.player_state.player_id())
		var aggregate := _ui_economy.economic_aggregate_id_for_market(market_id)
		var polity_ids := _ui_economy.polity_ids_for_economy(aggregate)
		if polity_ids.is_empty(): main_shell.show_feedback("人物所在地没有可访问的正式交易市场。")
		else:
			main_shell.remember_page()
			main_shell.economy_page.polity_id = polity_ids[0]
			main_shell.economy_page.personal_market = true
			main_shell.economy_page.show_native_statistics = false
			main_shell.economy_page.commodity_page = 0
			main_shell.economy_page.selected_commodity_id = ""
			main_shell.economy_page.scope_label = "人物所在地已关联的经营地点" if _world.personal_economy_state.manages_native(_world.player_state.player_id()) else "国家市场统计范围 · 由人物所在地明确关联"
			main_shell.economy_page.selected_seller_site_id = ""
			main_shell.set_page("economy",false)
	elif _world != null and action.begins_with("organization:open:"):
		var id := action.trim_prefix("organization:open:")
		if _world.organization_state.has_organization(id):
			if main_shell.current_page!="organization" or main_shell.organization_page.selected_id!=id: main_shell.remember_page()
			if main_shell.current_page=="person":
				main_shell.organization_page.own_only = true
				main_shell.organization_page.country_id = ""
			main_shell.organization_page.selected_id = id
			main_shell.set_page("organization",false)
	elif _world != null and action.begins_with("economy:polity:"):
		var id := action.trim_prefix("economy:polity:")
		if _ui_economy != null and not _ui_economy.economy_entity_for_polity(id).is_empty():
			main_shell.remember_page()
			main_shell.economy_page.polity_id = id
			main_shell.economy_page.personal_market = false
			main_shell.economy_page.show_native_statistics = false
			main_shell.economy_page.selected_commodity_id = ""
			main_shell.economy_page.commodity_page = 0
			main_shell.economy_page.scope_label = main_shell.world_page.selection_name() if main_shell.current_page in ["map","world"] else ""
			main_shell.set_page("economy",false)
	elif _world != null and action.begins_with("admin:select:"):
		var id := action.trim_prefix("admin:select:")
		var row := _world.spatial_world.administrative_identity(id)
		if row.is_empty(): row = main_shell.world_page.administration_entry(id)
		if not row.is_empty():
			var detail_open := main_shell.current_page=="world"
			map_controller.select(str(row.get("polity_id",map_controller.selected_polity_id)),id)
			main_shell.set_page("world" if detail_open else "map")
	elif _world != null and action.begins_with("place:open:"):
		var place := _world.spatial_world.get_place(action.trim_prefix("place:open:"))
		if not place.is_empty():
			map_controller.select(_ui_politics.runtime_id_for_source(str(place.get("parent_country_id",""))),str(place.place_id))
			main_shell.set_page("world")
	else:
		match action:
			"admin:focus":
				if map_renderer.focus_administration(map_controller.selected_place_id): main_shell.set_page("map")
			"admin:list":
				map_controller.select(map_controller.selected_polity_id)
				main_shell.set_page("administration")
			"map:home_administration":
				if _world == null: return
				var home := _ui_politics.source_historical_id(map_controller.player_polity_id)
				var document := historical_content.administration.administration_for(home,HistoricalLoader._date_key(_world.game_clock.current_date()))
				var units := document.get("runtime_units",[]) as Array
				if units.is_empty(): main_shell.show_feedback("本国尚无已接入的历史行政资料。")
				else:
					map_controller.select(map_controller.player_polity_id)
					main_shell.world_page.selected_admin_id = ""
					main_shell.set_page("administration")
			"page_changed": _update_map_visibility()
			"map:focus":
				if map_controller.selected_place_id.begins_with("administrative_region:"):
					if map_renderer.focus_administration(map_controller.selected_place_id): main_shell.set_page("map")
					return
				var place: Dictionary = {}
				if _world != null and not map_controller.selected_place_id.is_empty():
					place = _world.spatial_world.get_place(map_controller.selected_place_id)
					if place.is_empty():
						var polity := CurrentWorldPoliticalProjection.polity_summary(map_controller.selected_polity_id,_ui_politics,_world.historical_evidence_view)
						place = historical_content.resolve_world_page(_world.game_clock.current_date(),polity,map_controller.selected_place_id).place()
				if place.has("geometry") and str((place.geometry as Dictionary).get("type",""))=="Point":
					place = {"lon_lat":(place.geometry as Dictionary).coordinates}
				if not map_renderer.focus_place(place): map_renderer.focus_selection()
				main_shell.set_page("map")
			"person:focus":
				if _world == null: return
				var person := _world.person_overlay.person(_world.player_state.player_id())
				var place := _world.spatial_world.get_place(str(person.get("current_place_id","")))
				if map_renderer.focus_place(place):
					map_controller.select(_ui_politics.runtime_id_for_source(str(place.get("parent_country_id",""))),str(place.get("place_id","")))
					main_shell.set_page("map")
				else: main_shell.show_feedback("人物所在地没有可用地图坐标，保留当前视角。","page:person")
			"save": main_shell.open_slots("save")
			"load": main_shell.open_slots("load")
	main_shell.queue_redraw()

func _load_world(slot: int = 1) -> void:
	if _persistence == null:
		return
	var candidate := _persistence.load_from_user(slot)
	var result := candidate.operation
	FormalWorldPresenter.show_load_result(main_shell, result)
	if candidate.success:
		_save_dirty = false
		main_shell.close_slots()
		if not candidate.world.political_registry.has_entity(map_controller.selected_polity_id):
			map_controller.select("")
		elif not map_controller.selected_place_id.is_empty() and candidate.world.spatial_world.get_place(map_controller.selected_place_id).is_empty() and candidate.world.spatial_world.administrative_land_summary(map_controller.selected_place_id).is_empty():
			map_controller.select(map_controller.selected_polity_id)
		_install_world(candidate)

func _update_map_visibility() -> void:
	# Pages are bounded workspaces; the uncovered map remains interactive.
	map_renderer.visible = true
	($Background as CanvasItem).visible = true
	map_controller.suspend_motion()
	if _world != null and _map_dirty: _refresh_map()
	_request_economic_topic_refresh()

func _request_departure(target: String) -> void:
	if _save_pending: return
	if _world==null or not _save_dirty:
		_departure_target = target
		_leave_world()
		return
	_departure_target = target
	_departure_was_paused = time_control.paused
	time_control.paused = true
	map_controller.suspend_motion()
	main_shell.show_departure(target)

func _save_world(slot: int) -> void:
	if _save_pending: return
	if _persistence==null:
		main_shell.show_feedback("世界尚未准备完成，无法保存。")
		return
	var result := _persistence.save_to_user(slot)
	if result.error_code=="queued":
		_save_pending = true
		main_shell.set_save_pending(true)
		main_shell.show_feedback("正在等待当前游戏状态完成保存。")
		return
	_finish_save(result)

func _finish_save(result: SaveOperationResult) -> void:
	_save_pending = false
	main_shell.set_save_pending(false)
	if not result.success:
		main_shell.show_save_error("保存失败："+result.message)
		return
	_save_dirty = false
	main_shell.show_feedback("已保存。")
	main_shell.close_slots()
	if not _departure_target.is_empty(): _leave_world()

func _leave_world() -> void:
	if _departure_target.is_empty() or _leaving: return
	_leaving = true
	time_control.paused = true
	map_controller.suspend_motion()
	# Scene removal must not run inside MainShell's input/signal dispatch.
	_finish_departure.call_deferred()

func _finish_departure() -> void:
	var target := _departure_target
	var tree := get_tree()
	if target=="quit":
		tree.quit()
	else:
		for key: StringName in [FormalWorldMenu.PREPARED_WORLD_META,LAUNCH_MODE_META,FormalWorldMenu.PREPARED_MAP_META,FormalWorldMenu.PREPARED_CONTROLLER_META,FormalWorldMenu.PREPARED_CONTENT_META,FormalWorldMenu.PREPARED_LOADING_META,FormalWorldMenu.LIVELIHOOD_META,FormalWorldMenu.NATIVE_ECONOMY_META]:
			if tree.has_meta(key):
				var carried: Variant = tree.get_meta(key)
				if carried is Node and is_instance_valid(carried) and (carried as Node).get_parent()==tree.root: (carried as Node).queue_free()
				tree.remove_meta(key)
		var error := tree.change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
		if error!=OK:
			_leaving = false
			time_control.paused = _departure_was_paused
			main_shell.show_save_error("无法返回主菜单："+error_string(error))
