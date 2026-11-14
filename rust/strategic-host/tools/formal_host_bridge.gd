extends SceneTree
## Runs the existing formal entry in an isolated compatibility session.
const Pilot = preload("res://scripts/content/technology_pilot.gd")
const EconomicText = preload("res://scripts/presentation/ui/formal_economic_text.gd")
const MarketBridge = preload("formal_market_bridge.gd")
const UILocale = preload("res://scripts/presentation/ui/ui_locale.gd")
const RustCharacter = preload("res://scripts/formal/formal_rust_character.gd")
var folder := ""
var clock_ack := 0
var offset := 0
var published := ""
var finance_page := 0
var checked_slots: Array[Dictionary] = []
var revision: Array = []
var market := MarketBridge.new()
var training_open := false
var training_state := "none"
var menu_instance := 0
var menu_slots: Array[Dictionary] = []
var menu_error := ""
var menu_observed: Array = []
var lobby_enabled := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var isolated := OS.get_environment("WWO_DEV_USER_ROOT").replace("\\","/").trim_suffix("/")
	if isolated.is_empty() or not OS.get_user_data_dir().simplify_path().begins_with(isolated+"/"):
		push_error("The compatibility host requires an isolated Godot user directory")
		quit(2)
		return
	for arg: String in args:
		if arg.begins_with("--formal-bridge="): folder=arg.trim_prefix("--formal-bridge=")
		if arg=="--rust-menu": lobby_enabled=true
	if folder.is_empty():
		push_error("Pass the bridge directory with --formal-bridge")
		quit(2)
		return
	change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
	var timer := Timer.new()
	timer.wait_time = 0.16
	timer.timeout.connect(_poll)
	root.add_child.call_deferred(timer)
	timer.autostart = true
	root.unfocusable = true

func _poll() -> void:
	if lobby_enabled and current_scene is FormalWorldMenu:
		_lobby(current_scene as FormalWorldMenu)
		return
	var app := current_scene as FormalWorldApplication
	if app==null or app._world==null: return
	_consume(app)
	var shell := app.main_shell
	var next_training := _training_phase(app)
	var observed := [app._world.get_instance_id(), app._world.game_clock.total_minutes(), app.time_control.paused,
		app.time_control.speed, app.map_controller.selected_polity_id, shell._message_sequence, shell._slot_mode,
		shell._slot_error, finance_page, offset, shell.current_page, training_open,next_training,app._departure_target,app._save_pending,
		shell._confirmation.get("kind", ""), shell.status_message]
	if observed==revision: return
	training_state=next_training
	var state := _snapshot(app)
	if _publish(state): revision=observed

func _publish(state: Dictionary) -> bool:
	var value := JSON.stringify(state)
	if value==published:
		return true
	var target := folder.path_join("world.json")
	var tmp := target+".tmp"
	var file := FileAccess.open(tmp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(value)
	file.close()
	if DirAccess.rename_absolute(tmp,target)==OK:
		published=value
		return true
	return false

func _lobby(menu: FormalWorldMenu) -> void:
	if menu_instance!=menu.get_instance_id():
		menu_instance=menu.get_instance_id()
		menu_slots=FormalPersistence.slot_summaries()
		menu_error=""
		menu_observed=[]
	var stream := FileAccess.open(folder.path_join("requests.ndjson"),FileAccess.READ)
	if stream!=null:
		stream.seek(offset)
		for _i: int in 32:
			if stream.get_position()>=stream.get_length(): break
			var request: Variant=JSON.parse_string(stream.get_line())
			if not request is Dictionary: break
			offset=stream.get_position()
			if request.get("kind")=="interface":
				_apply_interface(request,menu._preferences)
				continue
			if request.get("kind")!="lobby": continue
			_lobby_action(menu,request)
	var ready := not menu._entering and menu._preview_worker==null and not menu._preview_waiting and not menu._preview_installing
	var status := menu_error
	var loading: bool = menu._loading_layer!=null and menu._loading_layer.visible
	if status.is_empty():
		if loading and menu._loading_label!=null: status=menu._loading_label.text
		elif menu._status!=null and menu._status.visible: status=menu._status.text
	var observed := [ready,menu._entering,menu._preview_ready,menu._page,status,offset,loading]
	if menu_observed==observed: return
	var choices: Array[Dictionary]=[]
	for row: Dictionary in menu._countries:
		var id := str(row.id)
		var opening := WorldBootstrap.opening_profile(menu._politics.source_historical_id(id))
		if not opening.is_empty():
			choices.append({"id":id,"label":str(row.get("name_zh",id)),"place":str(opening.place_name)})
	var slots: Array[Dictionary]=[]
	for row: Dictionary in menu_slots:
		slots.append({"slot":row.slot,"name":row.name,"empty":row.empty,"can_read":row.can_read,"description":FormalPersistence.summary_text(row)})
	if _publish({"schema":1,"date":{"year":1900,"month":1,"day":1},"lobby":{"ready":ready,
		"selection_ready":menu._preview_ready and ready,"busy":menu._entering,"loading":loading,"status":status,"choices":choices,"slots":slots}}):
		menu_observed=observed

func _lobby_action(menu: FormalWorldMenu,request: Dictionary) -> void:
	if menu._entering: return
	var verb := str(request.get("verb",""))
	menu_error=""
	match verb:
		"select":
			menu._show_page("selection")
		"home":
			menu._show_page("home")
		"slots":
			menu_slots=FormalPersistence.slot_summaries()
		"load":
			var slot := int(request.get("slot",-1))
			if not menu_slots.any(func(row: Dictionary)->bool: return row.slot==slot and row.can_read):
				menu_error="此存档不可读取。"
				return
			menu._enter_world("load",slot)
		"new":
			var id := str(request.get("polity",""))
			if not menu._preview_ready or menu._politics==null or not menu._politics.has_entity(id) or WorldBootstrap.opening_profile(menu._politics.source_historical_id(id)).is_empty():
				menu_error="该开局尚未就绪。"
				return
			menu._controller.select(id)
			menu._enter_world("new",1)

func _consume(app: FormalWorldApplication) -> void:
	var stream := FileAccess.open(folder.path_join("requests.ndjson"),FileAccess.READ)
	if stream==null: return
	stream.seek(offset)
	for _i: int in 32:
		if stream.get_position()>=stream.get_length(): break
		var request: Variant = JSON.parse_string(stream.get_line())
		if not request is Dictionary: break
		offset = stream.get_position()
		_dispatch(app,request)
		if not is_instance_valid(app) or app._leaving: break

func _dispatch(app: FormalWorldApplication, request: Dictionary) -> void:
	var kind := str(request.get("kind",""))
	match kind:
		"interface":
			_apply_interface(request,app.main_shell._preferences)
			app._refresh_ui()
		"market":
			market.action(app,request)
		"relations":
			var shell := app.main_shell
			var verb := str(request.get("verb",""))
			if verb=="open":
				shell._activate("person:organizations")
				shell.organization_page.drawer="relations"
				app._refresh_ui()
			elif shell.current_page=="organization" and shell.organization_page.own_only:
				var page := shell.organization_page
				var id := str(request.get("id",""))
				if verb=="select" and page._records().any(func(row: Dictionary)->bool: return str(row.organization_id)==id):
					shell._activate("organization:open:"+id)
				elif verb=="drawer" and (id=="relations" or id=="work" and page.has_personal_work):
					if shell._confirmation.get("kind")=="employment": shell.close_confirmation()
					shell._activate("organization:drawer:"+id)
					app._refresh_ui()
				elif verb=="back":
					page.selected_id=""
					app._refresh_ui()
				elif verb=="close":
					if shell._confirmation.get("kind")=="employment": shell.close_confirmation()
					shell.open_workspace("map")
				elif page.work_open() and verb=="work_action" and (id=="native:work" or id=="person:leave_request" or id.begins_with("person:job_request:")):
					for work: Dictionary in shell.person_page.work_drawer_rows():
						if work.get("actions", []).any(func(item: Dictionary) -> bool: return item.action==id and item.enabled):
							shell._activate(id)
							app._refresh_ui()
							break
				elif page.work_open() and verb=="work_confirm" and shell._confirmation.get("kind")=="employment":
					shell._activate("confirm:employment")
					app._refresh_ui()
				elif page.work_open() and verb=="work_cancel" and shell._confirmation.get("kind")=="employment":
					shell.close_confirmation()
		"training":
			var verb := str(request.get("verb",""))
			if verb=="open" and not app._leaving:
				training_open=true
				root.unfocusable=false
				root.keep_title_visible=true
				root.position=Vector2i(65,70)
				root.show()
				root.grab_focus()
				app.debug_select_workspace("training")
			elif verb=="end" and app._debug_terrain_parked:
				app.debug_select_workspace("close_training")
		"inspect":
			var id := str(request.get("id",""))
			if id.begins_with("state:") and app._ui_politics.has_entity(id) and app.map_controller.selected_polity_id!=id:
				app.map_controller.select(id)
		"set_map_mode":
			var mode := str(request.get("mode",""))
			if mode in ["political","economic","geographic","military"]:
				if market.opened: market.action(app,{"verb":"close"})
				app._on_action_requested("map_mode:"+mode)
		"finance_page":
			finance_page = clampi(int(request.get("page",0)),0,100000)
		"open_slots":
			var mode := str(request.get("mode",""))
			if mode in ["save","load"]:
				app.main_shell.open_slots(mode)
				checked_slots = app.main_shell._slots.duplicate()
		"close_slots":
			app.main_shell.close_slots()
		"clock":
			var speed := int(request.get("speed",0))
			if speed in [0,1,2,4]: app._on_action_requested("time:%d" % speed)
			clock_ack = int(request.get("serial",0))
		"host_action":
			var action := str(request.get("action",""))
			if lobby_enabled and action in ["system:main_menu","system:quit","departure:cancel","departure:save","departure:discard"]:
				if is_instance_valid(app._terrain_observation):
					app.main_shell.show_feedback("请先结束隔离训练。")
				else:
					app._on_action_requested(action)
					if action=="departure:cancel": app.main_shell.close_confirmation()
				return
			if action.begins_with("slot:") and is_instance_valid(app._terrain_observation):
				app.main_shell.show_save_error("请结束隔离训练后再操作存档。")
				return
			if action in ["time:pause","time:0","time:1","time:2","time:4","slot:save:1","slot:save:2","slot:save:3","slot:save:4","slot:load:0","slot:load:1","slot:load:2","slot:load:3","slot:load:4"]:
				app._on_action_requested(action)
				if action.begins_with("slot:"):
					checked_slots = FormalPersistence.slot_summaries()

func _apply_interface(request: Dictionary, preferences: Dictionary) -> void:
	var volume := clampf(float(request.get("volume",0.8)),0.0,1.0)
	var locale := "en" if str(request.get("locale"))=="en" else "zh_CN"
	preferences.volume=volume
	preferences.locale=locale
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(0.0001,volume)))
	AudioServer.set_bus_mute(0,volume<=0.0)
	UILocale.apply(locale)

func _snapshot(app: FormalWorldApplication) -> Dictionary:
	var world := app._world
	var shell := app.main_shell
	var player := world.player_state.player_id()
	var date := world.game_clock.current_date()
	var finance := world.personal_economy_state.person_economy(player)
	var account := str(finance.get("account_id",""))
	var count := 6
	var economy := world.economy_r1
	var receipts: Array[Dictionary] = economy.personal_transaction_rows(player,count+1,finance_page*count) if economy!=null and economy.personal_accounts().has(player) else world.ledger_state.transactions_for_account(account,count+1,finance_page*count)
	var accounts: Dictionary = {account:true}
	for row: Dictionary in finance.get("accounts",[]): accounts[str(row.account_id)] = true
	var rows: Array[Dictionary] = []
	var kinds := {"wage":"工资","opening_cash":"开局现金","purchase":"购买","native_purchase":"购买","person_travel":"旅费"}
	for row: Dictionary in receipts.slice(0,count):
		var kind := str(row.get("kind","交易"))
		rows.append({"description":PersonView.boundary_text(int(row.effective_minute))+" · "+str(kinds.get(kind,kind))+" · "+EconomicText.currency(str(row.get("denomination",FormalLedgerState.DENOMINATION))),
			"amount":("+" if accounts.has(str(row.get("to_account_id",""))) else "−")+str(row.amount)})
	var country := app._ui_politics.source_historical_id(app.map_controller.player_polity_id)
	var public := app._ui_politics.source_historical_id(app.map_controller.selected_polity_id)
	var project := economy.technology_observation(player) if economy!=null else {}
	var milestones: Array[Dictionary] = []
	for entry: Dictionary in project.get("milestones",[]):
		var row := entry.duplicate()
		row["date"] = PersonView.boundary_text(int(row.minute))
		milestones.append(row)
	var messages: Array[Dictionary] = []
	for i: int in range(shell._messages.size()-1,-1,-1):
		var message := shell._messages[i]
		messages.append({"source":shell._message_source_name(str(message.source)), "received_at":str(message.received_at), "text":str(message.message), "action":str(message.action)})
	var slots: Array[Dictionary] = []
	for row: Dictionary in checked_slots:
		slots.append({"slot":row.slot,"name":row.name,"empty":row.empty,"can_read":row.can_read,
			"description":FormalPersistence.summary_text(row)})
	var place := world.spatial_world.get_place(world.person_overlay.current_place(player))
	var property: Array[Dictionary]=[]
	for item: Dictionary in world.personal_economy_state.holding_rows(player,96,0):
		var id := str(item.commodity_id)
		property.append({"id":id,"label":EconomicText.good(id),"quantity":int(item.quantity_milli),
			"scale":int(item.get("quantity_scale",1000)),"unit":str(item.get("unit_name_zh",""))})
	var cash: Variant = finance.get("cash")
	var relations: Variant=null
	if shell.current_page=="organization" and shell.organization_page.own_only:
		var page := shell.organization_page
		var rows_by_id: Array[Dictionary]=[]
		for row: Dictionary in page._records():
			rows_by_id.append({"id":str(row.organization_id),"label":str(row.label),
				"role":str(row.get("player_roles","")),"kind":str(row.kind_label),
				"place":str(row.get("place_name","")),"basis":str(row.basis_label)})
		var work: Array[Dictionary]=[]
		if page.work_open():
			for row: Dictionary in shell.person_page.work_drawer_rows():
				var actions: Array[Dictionary] = []
				for item: Dictionary in row.get("actions", []):
					var id := str(item.action)
					if id in ["native:work", "person:leave_request"] or id.begins_with("person:job_request:"):
						actions.append({"label":str(item.text),"id":id,"enabled":bool(item.enabled)})
				work.append({"label":str(row.name_zh),"details":row.get("details",[]),"actions":actions})
		var confirmation: Variant = null
		if shell._confirmation.get("kind")=="employment":
			confirmation = {"title":str(shell._confirmation.title),"body":str(shell._confirmation.body)}
		relations={"rows":rows_by_id,"selected":page.selected_id,"drawer":page.drawer,
			"has_work":page.has_personal_work,"work":work,"confirmation":confirmation}
	var cash_text := "现金资料不可用" if typeof(cash)!=TYPE_INT else "现金 %s · 可用 %s · 预留 %s %s" % [cash,finance.get("available",cash),finance.get("reserved",0),EconomicText.currency(str(finance.get("denomination",FormalLedgerState.DENOMINATION)))]
	if training_open and training_state in ["none","paused"]:
		training_open=false
		root.unfocusable=true
		root.keep_title_visible=false
		root.position=Vector2i(10000,10000)
	return {"schema":1,"date":{"year":date.year,"month":date.month,"day":date.day},"session":{"player":player,
		"polity":app.map_controller.player_polity_id,"coordinates":place.get("lon_lat",[]),"place":str(place.get("place_id","")),
		"clock_ack":clock_ack,"hour":date.hour,"minute":date.minute,"total_minutes":world.game_clock.total_minutes(),"paused":app.time_control.paused,"speed":app.time_control.speed,
		"finance":{"summary":cash_text,"page":finance_page,"more":receipts.size()>count,"rows":rows},
		"technology":{"country":"法兰西" if country==Pilot.FRANCE else str(Pilot.COUNTRIES.get(country,"本国")),
			"foundation":_foundation(country),"public_country":str(Pilot.COUNTRIES.get(public,"")) if public!=country else "",
			"public_foundation":_foundation(public) if public!=country else [],"project_active":not project.is_empty(),"milestones":milestones},
		"messages":messages,"slots":slots,"slot_open":not shell._slot_mode.is_empty(),"slot_error":shell._slot_error,
		"market":market.view(app),"property":property,"relations":relations,"training":training_state,
		"character":RustCharacter.profile(world),
		"departure":app._departure_target if not app._leaving else "","saving":app._save_pending}}

func _training_phase(app: FormalWorldApplication) -> String:
	if app._terrain_open_pending: return "preparing"
	if not is_instance_valid(app._terrain_observation): return "none"
	if app._debug_terrain_parked: return "paused"
	var observation := app._terrain_observation
	var training: Node=observation.get("_training")
	if not is_instance_valid(training): return "preparing"
	return "active" if str(training.get("_state"))=="running" else "preparing"

func _foundation(country: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var values: Dictionary = Pilot.FOUNDATIONS.get(country,{})
	for id: String in values:
		var pair := str(values[id]).split(" · ",true,1)
		rows.append({"title":pair[0],"description":pair[1] if pair.size()>1 else "",
			"kind":"rail" if id.begins_with("urban_") else "rollers" if id=="roller_milling" else "motor"})
	return rows
