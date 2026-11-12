extends RefCounted
## Development adapter on the existing observer. No world or simulation owner.
var observer: Node
var _resume: Dictionary = {}
var _restore_requested: bool = false
var _restore_error: String = ""

func configure(host: Node) -> void:
	observer = host
	Engine.max_fps=30
	var path := OS.get_environment("WWO_DEV_RESUME")
	if FileAccess.file_exists(path):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary: _resume = value

func _app() -> FormalWorldApplication:
	return observer.get_tree().current_scene as FormalWorldApplication

func _renderer() -> GlobeRenderer:
	var value: Variant=observer.get("renderer")
	return value as GlobeRenderer if is_instance_valid(value) else null

func poll() -> void:
	var background: bool=bool(observer.get_tree().get_meta("dev_preview_background","--dev-background" in OS.get_cmdline_user_args())) or not observer.get_tree().root.has_focus()
	var injected: bool=Time.get_ticks_msec()<int(observer.get_tree().get_meta("dev_preview_input_until_msec",0))
	Engine.max_fps=15 if background and injected else 5 if background else 30
	if _resume.is_empty() or not _restore_error.is_empty(): return
	var scene: Node = observer.get_tree().current_scene
	if scene is FormalWorldMenu and _restore_requested:
		var menu := scene as FormalWorldMenu
		if not menu._entering and menu._worker==null: _restore_error="RESTORE_FAILED: "+menu._status.text
		return
	if scene is FormalWorldMenu and not _restore_requested:
		var menu := scene as FormalWorldMenu
		if menu._preview_worker==null and not menu._preview_waiting and not menu._preview_installing and not menu._entering:
			_restore_requested=true
			menu._enter_world("load",1)
		return
	var app := _app()
	if app==null or app._world==null or app._persistence==null: return
	_restore_view(app.map_controller, _resume.get("view",{}))
	app.time_control.paused=true
	app.main_shell.refresh_clock()
	_resume.clear()

func _view(controller: GlobeController) -> Dictionary:
	var camera := controller.region_camera
	var result: Dictionary={"orientation":controller._orientation,"zoom":controller.zoom,
		"polity":controller.selected_polity_id,"place":controller.selected_place_id,
		"map_mode":controller.map_mode,"labels":controller.labels_enabled,"rails":controller.strategic_rails_enabled,
		"active":camera.active,"local":camera.local_active,
		"basis":camera.tangent_frame,"origin":camera.origin,"scale":camera.km_per_pixel,
		"bearing":camera.bearing,"extent":camera.extent_km,"local_center":camera.local_center_km,
		"local_place":camera.local_place_id,"local_min":camera.local_min_km_per_pixel,
		"local_suppressed":camera.local_suppressed}
	var app := _app()
	if app!=null and app.main_shell.current_page=="economy":
		var page := app.main_shell.economy_page
		result["market_ui"]={"polity":page.polity_id,"scope":page.market_scope,"region":page.region_id,"good":page.chart_good,"site":page.chart_site,"chart":page.chart_kind,"days":page.window_days,"quantity":page.quantity_milli,"commodity":page.selected_commodity_id,"seller":page.selected_seller_site_id,"content":page.content}
	return result

func _restore_view(controller: GlobeController, record: Dictionary) -> void:
	if record.is_empty(): return
	# Exact UI-only Variant payload; formal world restoration uses its original
	# persistence path. No camera field is added to the authoritative snapshot.
	var value: Variant = str_to_var(str(record.get("variant","")))
	if not value is Dictionary: _restore_error="INVALID_VIEW_STATE";return
	var view: Dictionary=value
	var camera := controller.region_camera
	controller.suspend_motion()
	controller.initial_framing_pending=false
	controller._orientation=view.orientation
	controller.zoom=view.zoom
	controller.select(str(view.polity),str(view.place))
	controller.set_map_mode(str(view.map_mode))
	controller.labels_enabled=bool(view.get("labels",controller.labels_enabled))
	controller.strategic_rails_enabled=bool(view.get("rails",controller.strategic_rails_enabled))
	camera.active=view.active;camera.local_active=view.local
	camera.tangent_frame=view.basis;camera.origin=view.origin;camera.km_per_pixel=view.scale
	camera.bearing=view.bearing;camera.extent_km=view.extent
	camera.local_center_km=view.local_center;camera.local_place_id=view.local_place
	camera.local_min_km_per_pixel=view.local_min;camera.local_suppressed=view.local_suppressed
	controller.view_changed.emit()
	controller.appearance_changed.emit()
	var app := _app()
	var market: Dictionary=view.get("market_ui",{})
	if app!=null and not market.is_empty():
		var page := app.main_shell.economy_page
		page.polity_id=str(market.get("polity",""))
		page.market_scope=str(market.get("scope","domestic")) if market.get("scope") in ["international","domestic","regional"] else "domestic"
		page.region_id=str(market.get("region",""));page.chart_good=str(market.get("good","bread"))
		page.chart_site=str(market.get("site",""));page.chart_kind="supply" if market.get("chart")=="supply" else "price"
		page.window_days=clampi(int(market.get("days",30)),7,90);page.quantity_milli=clampi(int(market.get("quantity",1)),1,1000000)
		page.selected_commodity_id=str(market.get("commodity",""));page.selected_seller_site_id=str(market.get("seller",""))
		page.content=str(market.get("content","quotes")) if market.get("content") in ["quotes","good","goods","transport","activity"] else "quotes"
		app.main_shell.set_page("economy",false)

func _status() -> Dictionary:
	var app := _app()
	var renderer := _renderer()
	var result: Dictionary={"ready":app!=null and app._world!=null,
		"preview_power":{"max_fps":Engine.max_fps,"scope":"DEVELOPMENT_PREVIEW_ONLY"},
		"user_dir":OS.get_user_data_dir(),"restore_pending":not _resume.is_empty(),
		"restore_error":_restore_error,
		"scene":str(observer.get_tree().current_scene.scene_file_path) if observer.get_tree().current_scene!=null else "",
		"military_source":"military_runtime/native (controlled snapshot; no live external sync)"}
	if renderer!=null and renderer.controller!=null:
		var camera := renderer.controller.region_camera
		result["map"]={"mode":"CITY" if camera.local_active else "REGION" if camera.active else "WORLD",
			"mpp":camera.km_per_pixel*1000.0 if camera.active else null,
			"cities":renderer.region_view.city_states(),"water":renderer.region_view.city.water_state(),"pending":observer.call("_pending"),
			"view":var_to_str(_view(renderer.controller))}
		result.map["layers"]={"world_lod":renderer._world_layer.active_lod,"region_lod":renderer._region_layer.active_lod,
			"world_river":renderer._world_layer.has_visible_kind("river"),"region_river":renderer._region_layer.has_visible_kind("river"),
			"rejected":renderer.observation_camera_rejection}
		if renderer.strategic_content!=null:
			result.map.layers["ink"]=renderer.strategic_content._with_ink
			result.map.layers["wanted"]=renderer.strategic_content._wanted
			result.map.layers["failure"]=renderer.strategic_content.failure
		var city := renderer.region_view.city
		if city._parts.has(city._water_active_path):
			var node := city._parts[city._water_active_path] as MeshInstance3D
			var material := node.get_surface_override_material(0) as StandardMaterial3D
			if material!=null: result.map["water_albedo"]=[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b]
	if app!=null and app._world!=null:
		result["world_instance"]=app._world.get_instance_id()
		result["workspace"]= "military" if is_instance_valid(app._terrain_observation) and not app._debug_terrain_parked else app.main_shell.current_page
		result["training_parked"]=app._debug_terrain_parked
		result["minute"]=app._world.game_clock.total_minutes()
		result["paused"]=app.time_control.paused
		result["player"]=app._world.player_state.player_id()
		result["economy_available"]=app._world.economy_r1!=null
		result["accounts"]=app._world.ledger_state.own_accounts(app._world.player_state.player_id())
		result["military_open"]=is_instance_valid(app._terrain_observation)
		if is_instance_valid(app._terrain_observation):
			var training: Node=app._terrain_observation.get("_training") as Node
			result["military"]=training.call("get_player_status") if training!=null else {"state":"not_started"}
	return result

func execute(command: Dictionary) -> Dictionary:
	var operation := str(command.get("op","status"))
	if operation=="window":
		var background := bool(command.get("background",false))
		var tree := observer.get_tree()
		tree.set_meta("dev_preview_background",background)
		var window := tree.root
		window.unfocusable=background
		window.keep_title_visible=not background
		if not background:
			if window.mode==Window.MODE_MINIMIZED: window.mode=Window.MODE_WINDOWED
			window.position=Vector2i(60,70)
			window.show()
		return {"ok":true,"background":background}
	if operation=="status": return {"ok":true,"state":_status()}
	if operation=="controls": return {"ok":true,"controls":observer.call("_observation_state").get("visible_controls",[])}
	if operation=="select":
		var option := observer.get_tree().root.get_node_or_null(NodePath(str(command.get("path","")))) as OptionButton
		var index := int(command.get("index",-1))
		if option==null or not option.is_visible_in_tree() or option.disabled or index<0 or index>=option.item_count or option.is_item_disabled(index):
			return {"ok":false,"error":"CONTROL_NO_LONGER_AVAILABLE"}
		option.select(index);option.item_selected.emit(index)
		return {"ok":true}
	var app := _app()
	if operation=="checkpoint":
		if app==null: return {"ok":true,"resume":false}
		if app._world==null or app._persistence==null: return {"ok":false,"error":"WORLD_NOT_READY"}
		if is_instance_valid(app._terrain_observation): return {"ok":false,"error":"CLOSE_MILITARY_BEFORE_RESTART"}
		if app._simulation_step.processing: return {"ok":false,"error":"WORLD_BUSY"}
		app.time_control.paused=true;app.main_shell.refresh_clock()
		var saved := app._persistence.save_to_user(1)
		if not saved.success: return {"ok":false,"error":saved.error_code,"message":saved.message}
		return {"ok":true,"resume":true,"view":{"variant":var_to_str(_view(app.map_controller))}}
	if app==null or app._world==null: return {"ok":false,"error":"ENTER_WORLD_IN_NATIVE_WINDOW"}
	if operation=="focus_region":
		var renderer := _renderer()
		var lon := float(command.get("lon",NAN))
		var lat := float(command.get("lat",NAN))
		var mpp := float(command.get("mpp",NAN))
		if renderer==null or not is_finite(lon) or not is_finite(lat) or not is_finite(mpp):
			return {"ok":false,"error":"INVALID_REGION_VIEW"}
		if absf(lon)>180.0 or absf(lat)>=90.0 or mpp<=0.0:
			return {"ok":false,"error":"INVALID_REGION_VIEW"}
		app.main_shell.set_page("map",false)
		var controller := app.map_controller
		var unit := GlobeProjection.lon_lat_to_unit(Vector2(lon,lat))
		controller.set_map_mode("geographic")
		controller.focus_region(unit,renderer.size*.5,mpp/1000.0,0.0,renderer.size)
		return {"ok":true}
	if operation=="economy":
		var economy := app._world.economy_r1
		var result := {"ok":true,"personal":LivelihoodAction.query(app._world,app._world.player_state.player_id()),
			"cohorts":economy.cohort_observation(app._world.player_state.player_id(),16,0) if economy!=null else {}}
		if OS.is_debug_build() and economy!=null and economy._spec["actors"].has("cohort:opening:rouen_farm"):
			var regions: Dictionary = {}
			for id: String in ["cohort:opening:paris_households", "cohort:opening:lyon_households", "cohort:opening:rouen_farm"]:
				var actor: Dictionary = economy._spec["actors"][id]
				var needs: Dictionary = economy._totals[id]["categories"]["food"]
				var awaiting: int = 0
				var moving: int = 0
				for order_id: String in economy._active_by_buyer.get(id, []):
					var order: Dictionary = economy._orders[order_id]
					if order["good"]!="grain": continue
					awaiting += int(order["pending"])
					moving += int(order["transit"])
				regions[actor["place_id"]] = {"people":actor["members"],"opening_grain_kg":actor["stock"]["grain"],
					"grain_kg":economy._household_items(id)["grain"],"grain_used_kg":economy._physical_totals[id]["used"]["grain"],
					"food_required_kg":float(needs["required"])*0.5,"food_satisfied_kg":float(needs["satisfied"])*0.5,"food_unmet_kg":float(needs["unmet"])*0.5,
					"awaiting_kg":awaiting,"transit_kg":moving}
			result["resident_market"] = {"day":economy.day,"regions":regions,
				"farm":economy.agricultural_observation("cohort:opening:rouen_farm"),
				"freight_income":app._world.ledger_state.available_balance("account:opening_french_rail"),
				"passenger_quotes":[app._world.person_travel.quote(app._world.player_state.player_id(),"place:rouen"),
					app._world.person_travel.quote(app._world.player_state.player_id(),"place:lyon")]}
			if economy._local_quotes.market_enabled():
				var market: Dictionary = economy._local_quotes.observation(7, true)
				var regional_quotes: Dictionary = market.get("regions",{})
				result["resident_market"]["freight_flows"] = market.get("freight_flows",[])
				result["resident_market"]["freight_window_days"] = market.get("window_days",7)
				for place: String in regions:
					regions[place]["grain_market"] = regional_quotes.get(place+"|grain",{})
		return result
	if operation=="pause":
		app.time_control.paused=true;app.main_shell.refresh_clock()
		return {"ok":true}
	if operation=="step":
		if is_instance_valid(app._terrain_observation): return {"ok":false,"error":"MILITARY_OBSERVATION_ACTIVE"}
		if not app.time_control.paused or app._simulation_step.processing: return {"ok":false,"error":"PAUSE_BEFORE_STEP"}
		var minutes := int(command.get("minutes",15))
		if minutes not in [15,60,1440]: return {"ok":false,"error":"INVALID_STEP"}
		app._advance_world(minutes)
		return {"ok":true,"state":_status()}
	if operation=="military_open":
		app._on_action_requested("terrain:open")
		return {"ok":is_instance_valid(app._terrain_observation)}
	if operation=="military_close":
		app._close_terrain_observation()
		return {"ok":true}
	if operation in ["military_pause","military_resume","military_status"]:
		if not is_instance_valid(app._terrain_observation): return {"ok":false,"error":"OPEN_MILITARY_FIRST"}
		if operation=="military_pause": app._terrain_observation.call("_pause_training")
		elif operation=="military_resume":
			if not is_instance_valid(app._terrain_observation.get("_training")): return {"ok":false,"error":"START_TRAINING_IN_NATIVE_WINDOW"}
			if not bool(app._terrain_observation.get("_training_active")): app._terrain_observation.call("_toggle_training")
		return {"ok":true,"military":TerrainPixelSource.serial(app._terrain_observation.call("get_training_status"))}
	return {"ok":false,"error":"UNSUPPORTED_OPERATION"}
