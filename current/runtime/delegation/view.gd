extends Node3D
signal closed
const Service=preload("res://scripts/vnext/military/military_delegation_service.gd")
const Recovery=preload("res://practice/recovery.gd")
var world: WorldState
var persistence: FormalPersistence
var simulation: SimulationStep
var service: RefCounted
var tour:=""
var busy:=false
var unsaved:=false
var buttons: Dictionary={}
var bodies: Dictionary={}
var leases: Dictionary={}
var facts: Label
var last: Dictionary={}
var original: Dictionary
var output:="user://delegation_gui.json"
var rows: Array=[]
func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--delegation-output="):output=arg.trim_prefix("--delegation-output=")
	original=persistence.snapshot();service=Service.new()
	var error: String=service.bind(world,persistence)
	if not error.is_empty():push_error(error);get_tree().quit(1);return
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263542");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.9;add_child(env)
	var floor_mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(180,0.1,180);floor_mesh.mesh=box;floor_mesh.position.y=-0.15;add_child(floor_mesh)
	var d: Dictionary=world.military_state.duty_operations
	for person: String in [d.leader,d.executor]:
		var body:=CharacterBody3D.new();body.set_meta("formal_person_id",person);body.position=d.leader_position if person==d.leader else d.position;add_child(body);bodies[person]=body
		var mesh:=MeshInstance3D.new();var shape:=CapsuleMesh.new();shape.radius=0.3;shape.height=1.7;mesh.mesh=shape;mesh.position.y=0.85;body.add_child(mesh)
		var label:=Label3D.new();label.text=person.trim_prefix("person:formal_generated_country_fra_")+"\nMEDICAL UNMAPPED";label.position.y=2;label.pixel_size=0.006;body.add_child(label)
	var camera:=Camera3D.new();camera.position=Vector3(8,6,13);add_child(camera);camera.look_at(Vector3(0,1,4));camera.current=true
	var hud:=CanvasLayer.new();add_child(hud)
	var panel:=ColorRect.new();panel.position=Vector2(15,15);panel.size=Vector2(830,360);panel.color=Color(0.02,0.035,0.05,0.95);hud.add_child(panel)
	facts=Label.new();facts.position=Vector2(30,25);facts.size=Vector2(800,340);facts.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;facts.add_theme_font_override("font",load("res://cedar/system_font.tres"));facts.add_theme_font_size_override("font_size",18);hud.add_child(facts)
	var captions: Dictionary={"register":"显式登记受控区域与人物引用","attach":"绑定原人物投影 / 续接原租约","request":"申请一分钟局部防卫委派","duplicate":"重复相同申请","save":"保存当前责任","leave":"释放投影并返回同一全球世界"}
	var index:=0
	for key: String in captions:
		var button:=Button.new();button.text=captions[key];button.position=Vector2(25,390+index*45);button.size=Vector2(340,38);button.add_theme_font_override("font",load("res://cedar/system_font.tres"));hud.add_child(button);button.pressed.connect(action.bind(key));buttons[key]=button;index+=1
	refresh()
	if not tour.is_empty():replay.call_deferred()
func refresh() -> void:
	var d: Dictionary=world.military_state.duty_operations;var state: Dictionary=service.state()
	var detail: String=str(last.get("reason",last.get("message","")))
	if last.has("decision"):detail="缺项：combat授权、作战编制、身体医疗、作战区域、装备指派、执行结算契约。\n申请已记录；未下令、未开火、未结算。"
	elif last.get("ok",false):detail="本项完成。正式combat仍拒绝。"
	facts.text="局部作战委派：FORMAL_COMBAT_NOT_READY\n原人物 %d / claim 2 / 具名单位1 / 聚合兵力0\n两次成功勤务；正式时间 %d 分钟；余量 %d 微秒\n区域：原虚构勤务区，1单位=1米；非历史巴黎战场\n身体：原身份引用；医疗 UNMAPPED；不生成HP或战伤\n登记：%s；投影租约：%d；作战申请：%d\n%s"%[world.person_overlay.person_count(),world.game_clock.total_minutes(),d.pending_usec,"已登记" if not state.is_empty() else "未登记",state.get("leases",[]).size(),state.get("requests",{}).size(),detail]
func action(key: String) -> void:
	if busy:return
	match key:
		"register":last=service.register_controlled_annex();unsaved=last.get("ok",false)
		"attach":
			last={"ok":true,"people":{}}
			for person: String in bodies:
				var resume_id:=""
				for l: Dictionary in service.state().get("leases",[]):
					if l.person==person and l.status=="ACTIVE":resume_id=l.id;bodies[person].position=l.position
				var result: Dictionary=service.attach_projection(person,bodies[person],resume_id)
				last.people[person]=result;last.ok=last.ok and result.ok
				if result.ok:leases[person]=result.lease
			unsaved=true
		"request","duplicate":
			var d: Dictionary=world.military_state.duty_operations
			var q: Dictionary={"id":"delegation_request:annex_gui_001","unit":d.unit,"region":d.area+":controlled","issuer":d.leader,"participants":[d.leader,d.executor],"from_minute":2,"until_minute":3,"settlement_owner":d.organization,"objective":"CONTROLLED_LOCAL_DEFENCE"}
			var context:=OrganizationState.acting_context(d.leader,d.organization,d.organization,"authority."+str(d.unit).replace(":",".")+".issue","duty_leader",true)
			var before:=persistence.snapshot();last=service.request_combat(q,context)
			last.exact_noop=before==persistence.snapshot();unsaved=true
		"save":await save()
		"leave":await leave();return
	rows.append({"action":key,"result":last.duplicate(true)});refresh()
func save() -> void:
	busy=true;var result:=await persistence.save_to_user_async(2);busy=false;unsaved=not result.success;last={"ok":result.success,"message":result.message}
func leave() -> void:
	if busy:return
	for person: String in leases:
		var result: Dictionary=service.release_projection(leases[person],bodies[person])
		if not result.ok:last=result;refresh();return
	leases.clear();await save()
	if unsaved:return
	write_result();closed.emit()
func write_result() -> void:
	var after:=persistence.snapshot();var before:=original.duplicate(true)
	for value: Dictionary in [before,after]:value.military_state.erase("local_delegation");value.military_state.schema_id=VNextMilitaryState.DUTY_SCHEMA_ID
	var export_path:=output.trim_suffix(".json")+"_portable.json"
	var export_error:=Recovery.export_portable(export_path,persistence)
	var result: Dictionary={"pid":OS.get_process_id(),"mode":tour,"same_original_world_except_delegation":before==after,"minute":world.game_clock.total_minutes(),"pending_usec":world.military_state.duty_operations.pending_usec,"rows":rows,"delegation":service.state(),"save":ProjectSettings.globalize_path(FormalPersistence.slot_path(2)),"portable":export_path,"portable_error":export_error,"rendering":DisplayServer.get_name()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("DELEGATION_GUI_FINISHED "+JSON.stringify({"pid":OS.get_process_id(),"unchanged":before==after,"portable_error":export_error}))
func replay() -> void:
	await frames(30)
	if tour=="prepare":await click("register")
	await click("attach")
	if not last.get("ok",false):push_error(str(last));get_tree().quit(1);return
	await click("request")
	if not last.get("ok",false) or last.decision.status!="FORMAL_COMBAT_NOT_READY":push_error("COMBAT_ADMISSION_NOT_REFUSED");get_tree().quit(1);return
	await click("duplicate")
	if not last.get("duplicate",false) or not last.get("exact_noop",false):push_error("REQUEST_NOT_IDEMPOTENT");get_tree().quit(1);return
	await click("save")
	if unsaved:push_error("SAVE_FAILED");get_tree().quit(1);return
	await frames(30)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.trim_suffix(".json")+".png")
	if tour=="prepare":write_result();get_tree().quit();return
	await click("leave")
func frames(count: int) -> void:
	for i: int in count:await get_tree().process_frame
func click(key: String) -> void:
	var at: Vector2=buttons[key].get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;Input.parse_input_event(motion);await frames(2)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=pressed;Input.parse_input_event(event);await frames(2)
	while busy:await get_tree().process_frame
	await frames(4)
