extends Control
const Scenario = preload("res://custody/scenario.gd")
const MaterialLedger = preload("res://scripts/vnext/military/military_material_state.gd")
const Service = preload("res://scripts/vnext/military/military_material_service.gd")
const NativeUse = preload("res://custody/native_use.gd")
var built: WorldBuildResult
var service: RefCounted
var buttons: Dictionary={}
var facts: RichTextLabel
var message: Label
var busy:=false
var unsaved:=false
var rows: Array=[]
var last_receipt: Dictionary={}
var tour_mode:=""
var capture_dir:="user://custody_views"
var military_host: Node

func _ready() -> void:
	get_tree().auto_accept_quit=false
	var theme_value:=Theme.new();theme_value.default_font=load("res://cedar/system_font.tres");theme_value.default_font_size=17;theme=theme_value
	var bg:=ColorRect.new();bg.color=Color("0b1921");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var title:=Label.new();title.position=Vector2(24,15);title.text="WWO 正式军事资源登记 / 独立新场景 · 非历史实库 · combat关闭";add_child(title)
	var names: Array=[ ["new","明确新建1900场景"],["reserve","预留步枪 / 6发"],["issue","发放给当前保管员"],["use","原生弹药核销1发"],["duplicate","再次提交同一回执"],["return","归还剩余资源"],["cancel","取消占用"],["recover","冷启明确接管"],["transfer","转交另一库所有权"],["inspect","受控检查 / 状况80"],["loss","受控整件报废"],["save","正式保存"],["training","同世界军事训练"] ]
	for i: int in names.size():
		var b:=Button.new();b.text=names[i][1];b.position=Vector2(24+(i%4)*310,62+(i/4)*45);b.size=Vector2(298,37);b.pressed.connect(action.bind(str(names[i][0])));add_child(b);buttons[names[i][0]]=b
	facts=RichTextLabel.new();facts.position=Vector2(24,250);facts.size=Vector2(1232,380);facts.scroll_active=true;add_child(facts)
	message=Label.new();message.position=Vector2(24,641);message.size=Vector2(1232,70);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(message)
	var source:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--custody-tour="):tour_mode=arg.trim_prefix("--custody-tour=")
		if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--custody-source="):source=arg.trim_prefix("--custody-source=")
	if not source.is_empty():built=FormalPersistence.new()._restore_snapshot_file(source)
	elif tour_mode!="new" and not FormalPersistence.existing_slot_path(2).is_empty():built=FormalPersistence.new().load_from_user(2)
	else:built=WorldBootstrap.new().build()
	if not install(built):return
	message.text="旧保存不会追加资源。明确选择新场景才登记1支步枪和20发弹药。核销只验证弹药owner，不执行弹道、命中或正式战斗。"
	record("initial_loaded");refresh()
	if not tour_mode.is_empty():run_tour.call_deferred()

func install(value: WorldBuildResult) -> bool:
	if not value.success:push_error(value.error);get_tree().quit(1);return false
	built=value;service=Service.new()
	if not service.bind(built.world,built.persistence):push_error("INVALID_MATERIAL_WORLD_REFERENCES");get_tree().quit(1);return false
	return true

func context(op: String) -> Dictionary:
	return Scenario.context(built.world,op)

func action(name: String) -> void:
	if busy:return
	if unsaved and name!="save":message.text="当前变更尚未保存；先重试正式保存。";return
	if name=="training":open_training();return
	var result: Dictionary
	if name=="new":
		if not install(Scenario.create_new()):return
		last_receipt={};result={"ok":true,"source_kind":MaterialLedger.config().source_kind}
	elif name=="save":result={"ok":true}
	elif name=="use":
		var requested: Dictionary=service.request_use(context("use"),active())
		result=requested
		if requested.ok:
			var native: Dictionary=NativeUse.consume_once(requested.request);result=native
			if native.ok:last_receipt=native.receipt;result=service.adopt_use(context("use"),last_receipt)
	elif name=="duplicate":result=service.adopt_use(context("use"),last_receipt)
	else:
		var payload: Dictionary={"lease_id":active()}
		if name=="reserve":payload={"quantity":6}
		if name in ["return","cancel","loss"]:payload.reason="controlled_scenario_"+name
		if name=="loss":payload.reason="controlled_total_writeoff"
		if name=="transfer":
			var c:=MaterialLedger.config();var v: Dictionary=service.view()
			payload={"owner_id":c.receiver_id if v.get("asset",{}).get("owner_id")==c.owner_id else c.owner_id,"place_id":c.place_id,"reason":"documented_depot_handover"}
		if name=="inspect":payload.merge({"condition":80,"reason":"controlled_inspection_not_combat_damage"})
		result=service.command(name,context(name),payload)
	message.text=JSON.stringify(result if not result.get("ok",false) else {"ok":true,"duplicate":result.get("duplicate",false),"event_id":result.get("event_id","")})
	record(name+"_adopted" if result.get("ok",false) else name+"_rejected")
	if result.get("ok",false) and not result.get("duplicate",false):unsaved=true;await save()
	refresh()

func active() -> String:
	return str(service.view().get("asset",{}).get("lease_id",""))

func save() -> void:
	busy=true;refresh()
	var saved: SaveOperationResult=await built.persistence.save_to_user_async(2)
	busy=false
	unsaved=not saved.success
	message.text="已通过原FormalPersistence核验并原子保存到隔离槽2。" if saved.success else saved.message
	record("durable" if saved.success else "save_failed");write_rows();refresh()
	if not saved.success and not tour_mode.is_empty():get_tree().quit(1)

func refresh() -> void:
	for key: String in buttons:
		(buttons[key] as Button).disabled=busy or (unsaved and key!="save")
	var v: Dictionary=service.view()
	var person_id:=built.world.player_state.player_id()
	var posts: Array=built.world.organization_state.appointments_for_person(person_id)
	var identity: String="人物：%s / 当前任命%d\n"%[person_id,posts.size()]
	if v.is_empty():facts.text=identity+"UNKNOWN / UNMODELED\n当前正式世界没有实体军备登记簿；没有补发装备或任命玩家。";return
	var a: Dictionary=v.asset;var l: Dictionary=v.lot
	facts.text=identity+"来源：%s\n来源类型：%s\n对象：%s / 型别 %s\n所有者：%s    持有人：%s\n地点：%s    状态：%s    状况：%d    租约：%s\n\n弹药批次：%s\n注册 %d = 可用 %d + 预留 %d + 已发在手 %d + 已耗 %d + 已损 %d\n累计发放 %d；累计归还 %d（累计流量不与库存相加）\n\n事件 %d    MilitaryState %s    GameClock %d分\n正式作战：拒绝。只有新场景军需保管权限；未授予局部战斗、地理配准或正式车组。"%[v.source.source_id,v.source.source_kind,a.asset_id,v.source.model_id,a.owner_id,a.holder_id,a.place_id,a.status,a.condition,a.lease_id,l.lot_id,l.registered,l.available,l.reserved,l.issued,l.consumed,l.lost,l.cumulative_issued,l.cumulative_returned,built.world.military_state.material_registry.events.size(),built.world.military_state.snapshot().schema_id,built.world.game_clock.total_minutes()]
	if a.status=="lost":facts.text+="\n地点为报废时最后已知记录；当前持有人已清除。"

func record(stage: String) -> void:
	rows.append({"stage":stage,"pid":OS.get_process_id(),"schema":built.world.military_state.snapshot().schema_id,"world_minute":built.world.game_clock.total_minutes(),"person_id":built.world.player_state.player_id(),"registry":built.world.military_state.material_registry.duplicate(true)})

func write_rows() -> void:
	FileAccess.open("user://custody_%s.json"%(tour_mode if not tour_mode.is_empty() else "manual"),FileAccess.WRITE).store_string(JSON.stringify({"source":"ACTUAL_GODOT_SCENARIO_DOMAIN_COMMANDS_AND_NATIVE_AMMO_NO_BALLISTICS","rows":rows},"\t"))

func capture(stage: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var p:=ProjectSettings.globalize_path(capture_dir);DirAccess.make_dir_recursive_absolute(p)
	get_viewport().get_texture().get_image().save_png(p+"/"+stage+".png")

func click(name: String) -> void:
	var at: Vector2=(buttons[name] as Button).get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;get_viewport().push_input(motion,true)
	await get_tree().process_frame
	for down: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;get_viewport().push_input(event,true)
		await get_tree().process_frame
	while busy:await get_tree().process_frame
	for i: int in 8:await get_tree().process_frame

func run_tour() -> void:
	get_viewport().notify_mouse_entered();Input.use_accumulated_input=false
	for i: int in 35:await get_tree().process_frame
	if tour_mode=="coexist":
		await capture("formal_stock_before_training")
		await click("training")
		if military_host==null:push_error("SAME_WORLD_TRAINING_NOT_OPENED");get_tree().quit(1)
		return
	if tour_mode=="new":
		await click("new");await capture("registered_source")
		await click("reserve");await capture("reserved_once")
		await click("reserve");await capture("competing_request_rejected")
		await click("issue");await click("use");await capture("native_consumed_once")
		await click("duplicate");await capture("duplicate_unchanged")
	else:
		await capture("cold_issued_state")
		await click("use");await capture("cold_requires_recovery")
		await click("recover")
		var receipts: Dictionary=service.view().receipts
		if not receipts.is_empty():last_receipt=receipts.values()[0].duplicate(true)
		await click("duplicate");await click("cancel");await capture("cancel_kept_consumption")
		await click("reserve");await click("issue");await click("return");await capture("returned_to_owner")
		await click("transfer");await capture("transferred_owner")
		await click("reserve");await click("issue");await click("inspect");await capture("controlled_inspection_80")
		await click("loss");await capture("lost_asset_conserved_rounds")
	var final: Dictionary=service.view()
	var valid: bool=not final.is_empty() and ((final.asset.status=="issued" and final.lot.consumed==1 and final.lot.issued==5) if tour_mode=="new" else (final.asset.status=="lost" and final.lot.consumed==1 and final.lot.lost==6 and final.lot.available==13))
	if not valid:push_error("CUSTODY_TOUR_EXPECTED_STATE_NOT_REACHED");write_rows();get_tree().quit(1);return
	record("tour_finished");write_rows();print("CUSTODY_TOUR_FINISHED "+tour_mode+" pid="+str(OS.get_process_id()))
	for i: int in 20:await get_tree().process_frame
	get_tree().quit()

func open_training() -> void:
	if military_host!=null:return
	if not active().is_empty():message.text="先归还或处理本件装备占用，再进入训练。";return
	hide()
	military_host=load("res://formal_link/main.tscn").instantiate();military_host.world=built.world;military_host.simulation=built.simulation_step;military_host.persistence=built.persistence;military_host.formal_save_slot=2
	print("CUSTODY_TRAINING_SAME_OWNERS "+JSON.stringify({"pid":OS.get_process_id(),"world_instance":str(built.world.get_instance_id()),"world":military_host.world==built.world,"step":military_host.simulation==built.simulation_step,"persistence":military_host.persistence==built.persistence,"save_slot":2}))
	record("same_world_training_open");write_rows()
	military_host.formal_closed.connect(func() -> void:
		var old: Node=military_host;military_host=null;get_tree().root.remove_child(old);old.queue_free();show();refresh())
	get_tree().root.add_child(military_host)
	military_host._button("返回军备登记",Vector2(968,638),Vector2(275,30),military_host.close_to_formal)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if busy or unsaved:message.text="请等待或重试正式保存，再退出。"
		else:get_tree().quit()
