extends "res://global_link/host.gd"
## A limited real Formal host. The original production application is untouched.
signal formal_closed
const Authority = preload("res://formal_link/authority.gd")
var authority_assessment: Dictionary={}
var authority_panel: Panel
var authority_close: Button
var save_mode := "async"
var saving := false
var unsaved_commit := false
var current_world_saved := false
var formal_save_slot := 1
var _active_save_cost: Dictionary={}
var _tail_save_cost: Dictionary={}
var _last_frame_tick := 0
var world: WorldState
var simulation: SimulationStep
var persistence: FormalPersistence
var formal_application: FormalWorldApplication
var session:=FormalLocalSession.new()
var pending_request: Dictionary={}
var crossing_rows: Array[Dictionary]=[]
var formal_status: Label
var formal_status_text := ""
var last_adoption: Dictionary={}
var last_return: Dictionary={}
var last_duplicate: Dictionary={}
var formal_tour_mode := ""
var formal_boot_ms := 0
var boot_loaded := false
var source_save := ""
var boot_origin := "FORMAL_NEW_WORLD"
var last_cost_sample_count := 0
var formal_costs: Array[Dictionary]=[]

func _ready() -> void:
	var begin:=Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--formal-save-mode="):save_mode=arg.trim_prefix("--formal-save-mode=")
		if arg.begins_with("--formal-tour="):formal_tour_mode=arg.trim_prefix("--formal-tour=")
		if arg.begins_with("--formal-source-save="):source_save=arg.trim_prefix("--formal-source-save=")
	if world!=null:
		boot_loaded=true;boot_origin="LIVE_FORMAL_APPLICATION" if formal_application!=null else "LIVE_CUSTODY_WORLD"
	else:
		var built: WorldBuildResult
		boot_loaded=not FormalPersistence.existing_slot_path(1).is_empty() and "--formal-new" not in OS.get_cmdline_user_args()
		if not source_save.is_empty():
			built=FormalPersistence.new()._restore_snapshot_file(source_save)
			boot_loaded=true;boot_origin="FORMAL_SAVE_COPY"
		else:
			built=FormalPersistence.new().load_from_user(1) if boot_loaded else WorldBootstrap.new().build()
			boot_origin="FORMAL_ISOLATED_RESTART" if boot_loaded else "FORMAL_NEW_WORLD"
		if not built.success:
			push_error("正式运行宿主装配失败："+built.error);get_tree().quit(1);return
		world=built.world;simulation=built.simulation_step;persistence=built.persistence
	formal_boot_ms=Time.get_ticks_msec()-begin
	if not session.bind(world,simulation,persistence):
		push_error("正式运行引用绑定失败");get_tree().quit(1);return
	authority_assessment=Authority.assess(world,world.player_state.player_id())
	var assessment_file:=FileAccess.open("user://formal_resource_assessment.json",FileAccess.WRITE)
	assessment_file.store_string(JSON.stringify(authority_assessment,"\t"))
	runtime_catalog=world.spatial_catalog
	runtime_anchor_place_id=world.person_overlay.current_place(world.player_state.player_id())
	super._ready()
	heading.text="WWO 正式WorldState最小宿主 · 训练地图接续 / 隔离副本"
	_button("正式保存",Vector2(887,49),Vector2(112,31),save_world)
	_button("丢弃未交还",Vector2(1007,49),Vector2(137,31),discard_interrupted)
	_button("推进1分钟",Vector2(1151,49),Vector2(113,31),advance_minute)
	_button("正式作战条件 / TRAINING_ONLY",Vector2(968,598),Vector2(275,30),show_authority)
	state_info.add_theme_font_size_override("font_size",13)
	state_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	selected_info.add_theme_font_size_override("font_size",15)
	selected_info.text=_selected_text()
	progress.position.y=700
	var layer:=CanvasLayer.new();layer.layer=130;add_child(layer)
	formal_status=Label.new();formal_status.position=Vector2(12,668);formal_status.size=Vector2(1256,25);formal_status.mouse_filter=Control.MOUSE_FILTER_IGNORE;formal_status.add_theme_font_override("font",load("res://cedar/system_font.tres"));formal_status.add_theme_font_size_override("font_size",14);formal_status.add_theme_color_override("font_color",Color("f8d383"));layer.add_child(formal_status)
	formal_status_text="从正式精确存档恢复；局部实例尚未创建" if boot_loaded else "原WorldBootstrap新建的正式玩家；不是旧五人样例世界"
	if formal_application!=null:
		heading.text="WWO 军事训练视图 · 共享运行中的正式WorldState / 隔离副本"
		formal_status_text="读取运行中的正式世界；局部实例尚未创建"
	formal_status.position.y=676
	if formal_application!=null:
		_button("返回正式界面",Vector2(968,638),Vector2(275,30),close_to_formal)
	print("FORMAL_RUNTIME_READY "+JSON.stringify({"pid":OS.get_process_id(),"loaded":boot_loaded,"origin":boot_origin,"boot_ms":formal_boot_ms,"person_id":world.player_state.player_id(),"place_id":runtime_anchor_place_id,"world_instance":world.get_instance_id(),"catalog_instance":runtime_catalog.get_instance_id(),"user_dir":OS.get_user_data_dir()}))
	globe.loaded.connect(func() -> void:
		record("formal_boot")
		if not formal_tour_mode.is_empty():
			var tour: Node=load("res://formal_link/tour.gd").new();tour.host=self;add_child(tour))

func _selected_text() -> String:
	var person_id:=world.player_state.player_id()
	var place_id:=world.person_overlay.current_place(person_id)
	return "入口地点：%s\n%.4f°E / %.4f°N\n\n50×50 km训练入口\n地理未配准；不移动世界地点\n训练车与4名辅助乘员\n人物现位：%s"%[runtime_anchor_place_id,globe.anchor_ll.x,globe.anchor_ll.y,place_id]

func enter_local() -> void:
	if saving or unsaved_commit:return
	if not globe.is_loaded or not globe.selected or loading:return
	var enter_begin:=Time.get_ticks_msec()
	var lease_save_ms:=0
	if world.person_overlay.current_place(world.player_state.player_id())!=runtime_anchor_place_id:
		formal_status_text="人物所在地已改变；此入口没有对应的新映射";return
	if local_shell!=null and local_shell.port.closed:
		formal_status_text="租约已关闭，请先处理未交还记录";return
	if local_shell==null:
		var issued:=session.issue(world.player_state.player_id())
		if not issued.ok:formal_status_text=str(issued.reason);return
		pending_request=issued.request
		current_world_saved=false
		var save_begin:=Time.get_ticks_msec()
		var saved: SaveOperationResult=await checkpoint("lease_durability")
		lease_save_ms=Time.get_ticks_msec()-save_begin
		if not saved.success:
			formal_status_text="租约保存失败："+saved.message;return
		record("lease_issued")
	await super.enter_local()
	local_shell.information.add_theme_font_size_override("font_size",13)
	local_shell.information.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	local_shell.information.size=Vector2(365,198)
	formal_costs.append({"action":"enter_local","total_ms":Time.get_ticks_msec()-enter_begin,"lease_save_ms":lease_save_ms,"new_lease":lease_save_ms>0})
	formal_status_text="正式玩家控制训练身体；唯一局部租约运行；Tab只切观察"
	record("formal_local_entered")

func configure_local_shell(shell: Node) -> void:
	var port:=preload("res://formal_link/port.gd").new()
	port.runtime_request=pending_request.duplicate(true)
	shell.port=port
	shell.return_path="user://formal_local_return.json"
	shell.source_note="正式玩家 / 训练车与4名辅助 · 身体与弹药属训练记录 · 地理未配准 · 交还后走正式保存"
	shell.vehicle_caption="训练车 ridgevale_mbt_01 · 1名正式人物 + 4辅助"
	shell.host_returned.connect(accept_return)

func return_global() -> void:
	super.return_global()
	# The retained lease has one battlefield. Returning to the globe selects
	# that existing entrance; a transient pointer selection cannot strand it.
	if local_shell!=null and not local_shell.port.closed:
		globe.select_training()

func accept_return(result: Dictionary) -> void:
	last_return=result.duplicate(true)
	var begin:=Time.get_ticks_msec()
	last_adoption=session.adopt(result)
	var adoption_ms:=Time.get_ticks_msec()-begin
	print("FORMAL_LOCAL_ADOPTION "+JSON.stringify(last_adoption))
	if not last_adoption.ok:
		formal_status_text="交还拒绝："+str(last_adoption.reason)+"；求解器已停止，需明确处理"
		record("return_rejected");dispose_local();get_tree().paused=false
		record("rejected_solver_destroyed");save_observations();return
	get_tree().paused=false;unsaved_commit=true;current_world_saved=false
	record("adopted_once")
	dispose_local()
	formal_status_text="已采用一次；原Persistence正在核验并保存；完成前不可变更世界"
	var save_begin:=Time.get_ticks_msec()
	var saved: SaveOperationResult=await checkpoint("adopted_result_durability")
	formal_costs.append({"action":"adopt_and_save","adoption_ms":adoption_ms,"save_ms":Time.get_ticks_msec()-save_begin,"total_ms":Time.get_ticks_msec()-begin,"saved":saved.success})
	unsaved_commit=not saved.success
	formal_status_text="已唯一采用并正式保存。局部实例已销毁，可重新装配。" if saved.success else "已采用但尚未保存："+saved.message+"；请重试正式保存"
	record("saved_and_local_destroyed" if saved.success else "adopted_save_failed")
	save_observations()

func dispose_local() -> void:
	if local_shell==null:return
	if mode=="local":return_global()
	var old: Node=local_shell
	old.process_mode=Node.PROCESS_MODE_DISABLED
	local_viewport.remove_child(old);old.queue_free();local_shell=null
	local_container.hide();local_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	global_ui.show();mode="global";globe.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;globe.whole_earth()

func check_native_duplicate() -> void:
	var before:=world.military_state.snapshot()
	var minute_before:=world.game_clock.total_minutes()
	last_duplicate=session.adopt(last_return)
	last_duplicate["state_unchanged"]=world.military_state.snapshot()==before
	last_duplicate["clock_unchanged"]=world.game_clock.total_minutes()==minute_before
	print("FORMAL_NATIVE_DUPLICATE "+JSON.stringify(last_duplicate))
	record("native_return_duplicate_ignored")

func save_world() -> void:
	if saving:return
	var saved: SaveOperationResult=await checkpoint("manual_save")
	formal_status_text=saved.message
	if saved.success:unsaved_commit=false
	if saved.success and not session.time_advance_allowed():formal_status_text+="；租约未交还，未采用的局部行动不入存档"

func close_to_formal() -> void:
	if saving or unsaved_commit:
		formal_status_text="请等待保存完成；保存失败时先重试";return
	if not (session.state().active as Dictionary).is_empty():
		formal_status_text="局部区间尚未交还，请先交还或明确处理中断";return
	simulation.local_operation_guard=Callable(persistence,"world_time_available")
	formal_closed.emit()

func advance_minute() -> void:
	if saving or unsaved_commit:return
	var result:=simulation.advance_minutes(1)
	if bool(result.get("success",true)):current_world_saved=false
	formal_status_text="正式GameClock已推进1分钟" if bool(result.get("success",true)) else str(result.get("error","推进拒绝"))

func discard_interrupted() -> void:
	if saving or unsaved_commit:return
	if local_shell!=null and not local_shell.port.closed:
		formal_status_text="局部求解器仍在运行，请先交还；不能丢弃活跃求解器";return
	var active: Dictionary=session.state().active
	if active.is_empty():formal_status_text="没有未交还租约";return
	var result:=session.interrupt(str(active.lease_id))
	if result.ok:
		current_world_saved=false
		dispose_local()
		var saved: SaveOperationResult=await checkpoint("explicit_interruption")
		formal_status_text="已明确丢弃中断区间；旧结果不能再采用。" if saved.success else saved.message
	else:formal_status_text=str(result.reason)

func _process(delta: float) -> void:
	var now:=Time.get_ticks_usec()
	if _last_frame_tick>0:
		var gap: float=(now-_last_frame_tick)/1000.0
		for cost: Dictionary in [_active_save_cost,_tail_save_cost]:
			if not cost.is_empty():cost.max_frame_gap_ms=maxf(float(cost.max_frame_gap_ms),gap)
		_tail_save_cost={}
	_last_frame_tick=now
	super._process(delta)
	if world==null or formal_status==null:return
	if saving:formal_status_text="原Persistence核验和原子写入中；世界不可变更，界面仍可绘制"
	formal_status.visible=mode=="global"
	if samples.size()>last_cost_sample_count:
		last_cost_sample_count=samples.size()
		var cost: Dictionary=samples.back()
		cost["main_process_ms"]=Performance.get_monitor(Performance.TIME_PROCESS)*1000
		cost["physics_process_ms"]=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
	var data:=session.state()
	var person_id:=world.player_state.player_id()
	var record: Dictionary=(data.participants as Dictionary).get(person_id,{})
	var active: Dictionary=data.active
	formal_status.text="正式GameClock %d分 · rev%d · %s · %s"%[world.game_clock.total_minutes(),int(data.revision),"局部区间待交还" if not active.is_empty() else "宿主持有",formal_status_text]
	if mode=="global":
		var text: String="正式玩家\n%s\n地点 %s\n"%[person_id,world.person_overlay.current_place(person_id)]
		if local_shell!=null and local_shell.ready_battle:
			var ammo: Dictionary=local_shell.battle.vehicle_ammo.status("player_vehicle","primary")
			text+="训练主炮 %d；事件%d\n局部区间 %.2fs（待采用）\n"%[ammo.total,local_shell.battle.shot_sequence,local_shell.battle.elapsed]
		elif not record.is_empty():
			var pool: Dictionary=record.local.native_ammo.vehicles.player_vehicle.primary
			text+="已采用训练主炮 %d；事件%d\n累计采用%d次；无常驻局部实例\n"%[int(pool.capacity)-int(pool.spent),int(record.local.shot_sequence),int(record.adoption_count)]
		text+="GameClock %d分 / rev%d\n"%[world.game_clock.total_minutes(),int(data.revision)]
		text+="真实人物引用；训练车/身体\n行政边界仍为静态参考"
		state_info.text=text

func record(name: String) -> void:
	super.record(name)
	if world==null:return
	var data:=session.state()
	var person_id:=world.player_state.player_id()
	var row: Dictionary={"stage":name,"process_id":OS.get_process_id(),"world_instance":str(world.get_instance_id()),"live_application_same_world":formal_application!=null and formal_application._world==world,"live_application_same_persistence":formal_application!=null and formal_application._persistence==persistence,"world_person_id":person_id,"world_place_id":world.person_overlay.current_place(person_id),"world_person":world.person_overlay.person(person_id),"world_minutes":world.game_clock.total_minutes(),"military_schema":world.military_state.snapshot().schema_id,"revision":int(data.revision),"active_lease":data.active.duplicate(true),"adoptions":data.adoptions.duplicate(true),"participant":data.participants.get(person_id,{}).duplicate(true),"globe_catalog_same_instance":globe.catalog==world.spatial_catalog,"local_instance":local_shell.get_instance_id() if local_shell!=null else 0,"last_adoption":last_adoption.duplicate(true),"last_duplicate":last_duplicate.duplicate(true)}
	if local_shell!=null and local_shell.ready_battle:row["native"]=local_shell.port.snapshot(local_shell.battle)
	crossing_rows.append(row)

func save_observations() -> void:
	super.save_observations()
	var file:=FileAccess.open("user://formal_crossing_%s.json"%(formal_tour_mode if not formal_tour_mode.is_empty() else "manual"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":"formal_local_crossing_v2","save_mode":save_mode,"authority":authority_assessment,"boot_loaded":boot_loaded,"boot_origin":boot_origin,"formal_boot_ms":formal_boot_ms,"formal_costs":formal_costs,"source_kind":"REAL_FORMAL_WORLD_ISOLATED_COPY","formal_individual_vehicle":false,"georegistered":false,"clock_resolution":"whole formal minutes; delegated fractional local progress saved on adoption","rows":crossing_rows},"\t"))


func checkpoint(action: String) -> SaveOperationResult:
	if saving:return SaveOperationResult.fail("busy","保存进行中",FormalPersistence.slot_path(formal_save_slot))
	saving=true;enter_button.disabled=true
	var begin:=Time.get_ticks_msec()
	var cost: Dictionary={"action":action,"mode":save_mode,"max_frame_gap_ms":0.0}
	_active_save_cost=cost
	var result: SaveOperationResult
	if save_mode=="sync":result=persistence.save_to_user(formal_save_slot)
	else:result=await persistence.save_to_user_async(formal_save_slot)
	cost.total_ms=Time.get_ticks_msec()-begin;cost.saved=result.success
	current_world_saved=result.success
	if save_mode!="sync":cost.merge(persistence.last_save_costs,true)
	formal_costs.append(cost)
	_active_save_cost={};_tail_save_cost=cost
	saving=false;enter_button.disabled=false
	return result

func show_authority() -> void:
	authority_assessment=Authority.assess(world,world.player_state.player_id())
	var rejected:=session.issue(world.player_state.player_id(),"combat")
	authority_assessment["actual_combat_request"]={"ok":rejected.ok,"reason":rejected.get("reason","")}
	if authority_panel==null:
		authority_panel=Panel.new();authority_panel.position=Vector2(220,108);authority_panel.size=Vector2(840,508);authority_panel.z_index=100;global_ui.add_child(authority_panel)
		var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.055,.06,.98);style.border_color=Color("adac77");style.set_border_width_all(1);style.set_corner_radius_all(8);authority_panel.add_theme_stylebox_override("panel",style)
		var label:=Label.new();label.name="Facts";label.position=Vector2(20,18);label.size=Vector2(800,424);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_override("font",load("res://cedar/system_font.tres"));label.add_theme_font_size_override("font_size",17);authority_panel.add_child(label)
		authority_close=Button.new();authority_close.position=Vector2(678,452);authority_close.size=Vector2(140,36);authority_close.text="关闭条件检查";authority_close.add_theme_font_override("font",load("res://cedar/system_font.tres"));authority_panel.add_child(authority_close);authority_close.pressed.connect(authority_panel.hide)
	(authority_panel.get_node("Facts") as Label).text=Authority.explanation(authority_assessment)
	authority_panel.show()
	record("formal_authority_assessed");save_observations()
