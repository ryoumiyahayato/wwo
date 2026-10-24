extends Node3D
## Physics projection and UI. People, orders, reports and time belong to the supplied WorldState.
signal closed
const Service = preload("res://scripts/vnext/military/military_duty_service.gd")
var world: WorldState
var simulation: SimulationStep
var persistence: FormalPersistence
var service: RefCounted
var npc: CharacterBody3D
var leader: CharacterBody3D
var camera: Camera3D
var hud: CanvasLayer
var facts: Label
var notice: Label
var buttons: Dictionary={}
var busy:=false
var unsaved:=false
var paused:=false
var tour:=""
var output:="user://duty_manual.json"
var capture_dir:=""
var rows: Array=[]
var save_costs: Array=[]
var physics_cpu_usec: Array[int]=[]
var frame_ms: Array[float]=[]
var last_receipt: Dictionary={}
var last_result: Dictionary={}
var start_tick:=Time.get_ticks_msec()
var first_draw_ms:= -1
var stalled_usec:=0
var next_checkpoint_usec:=20000000
var checkpoint_pause:=false

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--duty-tour="):tour=arg.trim_prefix("--duty-tour=")
		if arg.begins_with("--duty-output="):output=arg.trim_prefix("--duty-output=")
		if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
	paused="--duty-pause" in OS.get_cmdline_user_args()
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("718c98");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=0.75;environment.environment=settings;add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-25,0);sun.light_energy=1.2;add_child(sun)
	box(Vector3(180,0.2,180),Vector3(0,-0.1,0),Color("718064"),true)
	box(Vector3(6,4,20),Vector3(0,2,-20),Color("6c6b65"),true)
	var d: Dictionary=world.military_state.duty_operations
	for plan: Dictionary in d.mapping.plans.values():
		for p: Vector3 in plan.route:box(Vector3(1.2,0.03,1.2),p,Color("ddc167"))
		var board:=box(Vector3(2,2,0.2),plan.target_position,Color("82c4ad"),true);board.set_meta("duty_target_id",plan.target_id)
		var label:=Label3D.new();label.text="FICTIONAL ROAD CHECKPOINT";label.font_size=40;label.pixel_size=0.008;label.position=plan.target_position+Vector3(0,2,0);add_child(label)
	leader=body(d.leader,d.leader_position,Color("c5b087"));npc=body(d.executor,d.position,Color("496a91"))
	camera=Camera3D.new();camera.position=npc.position+Vector3(5,3.0,7);add_child(camera);camera.look_at(npc.position+Vector3(0,1, -7));camera.current=true;camera.far=250
	hud=CanvasLayer.new();hud.layer=210;add_child(hud)
	var panel:=ColorRect.new();panel.position=Vector2(12,12);panel.size=Vector2(755,215);panel.color=Color(0.025,0.045,0.065,0.94);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(panel)
	facts=Label.new();facts.position=Vector2(24,22);facts.size=Vector2(725,190);facts.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;facts.add_theme_font_override("font",load("res://cedar/system_font.tres"));facts.add_theme_font_size_override("font_size",17);hud.add_child(facts)
	notice=Label.new();notice.position=Vector2(24,615);notice.size=Vector2(1220,80);notice.add_theme_font_override("font",load("res://cedar/system_font.tres"));notice.add_theme_font_size_override("font_size",16);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hud.add_child(notice)
	button("issue","下达道路核实勤务",24,245,Callable(self,"issue"))
	button("resume","继续实际执行",24,290,Callable(self,"resume_execution"))
	button("save","采用时间并保存",24,335,Callable(self,"checkpoint"))
	button("duplicate","重复上一回执",24,380,Callable(self,"repeat_receipt"))
	button("revoke","撤销执行授权",24,425,Callable(self,"revoke"))
	button("leave","保存并返回全球",24,470,Callable(self,"leave"))
	service=Service.new();var reason: String=service.bind(world,simulation,persistence,self)
	if not reason.is_empty():push_error(reason);get_tree().quit(1);return
	var o: Dictionary=service.current()
	if not o.is_empty():next_checkpoint_usec=(int(o.elapsed_usec/20000000)+1)*20000000
	for old: Dictionary in d.orders.values():
		if not old.receipts.is_empty():last_receipt=old.receipts.back().duplicate(true)
	record("entry");refresh()
	if not tour.is_empty():var replay: Node=load("res://duty/replay.gd").new();replay.host=self;add_child(replay)
	first_draw.call_deferred()

func first_draw() -> void:
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	first_draw_ms=Time.get_ticks_msec()-start_tick
func box(size_value: Vector3, at: Vector3, color: Color, solid: bool=false) -> Node3D:
	var root: Node3D=StaticBody3D.new() if solid else Node3D.new();add_child(root);root.position=at
	var mesh:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=size_value;mesh.mesh=shape;var mat:=StandardMaterial3D.new();mat.albedo_color=color;mesh.material_override=mat;root.add_child(mesh)
	if solid:
		(root as StaticBody3D).collision_layer=1
		var collider:=CollisionShape3D.new();var bounds:=BoxShape3D.new();bounds.size=size_value;collider.shape=bounds;root.add_child(collider)
	return root
func body(id: String, at: Vector3, color: Color) -> CharacterBody3D:
	var b:=CharacterBody3D.new();b.set_meta("formal_person_id",id);b.collision_layer=32;b.collision_mask=1;add_child(b);b.position=at
	var c:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.28;capsule.height=1.7;c.shape=capsule;c.position.y=0.86;b.add_child(c)
	var mesh:=MeshInstance3D.new();var cap:=CapsuleMesh.new();cap.radius=0.28;cap.height=1.7;mesh.mesh=cap;mesh.position.y=0.86;var mat:=StandardMaterial3D.new();mat.albedo_color=color;mesh.material_override=mat;b.add_child(mesh)
	var label:=Label3D.new();label.text=id.trim_prefix("person:formal_generated_country_fra_")+"\nUNARMED";label.position.y=2.3;label.font_size=40;label.pixel_size=0.008;b.add_child(label)
	return b
func button(id: String, text_value: String, x: float, y: float, action: Callable) -> void:
	var b:=Button.new();b.position=Vector2(x,y);b.size=Vector2(235,37);b.text=text_value;b.add_theme_font_override("font",load("res://cedar/system_font.tres"));hud.add_child(b);b.pressed.connect(action);buttons[id]=b
func face_clear() -> bool:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(npc.position+Vector3(0,1.5,0),leader.position+Vector3(0,1.5,0),9)).is_empty()
func issue() -> void:
	if busy or unsaved:return
	var d: Dictionary=world.military_state.duty_operations
	last_result=service.issue(self,str(d.mapping.plans.keys()[0]))
	record("issue" if last_result.ok else "issue_refused")
	if last_result.ok:unsaved=true;await checkpoint()
	refresh()
func resume_execution() -> void:
	if busy or unsaved:return
	paused=false;record("resume");refresh()
func revoke() -> void:
	if busy or unsaved:return
	var d: Dictionary=world.military_state.duty_operations
	var ok:=world.organization_state.revoke_authority("authority."+str(d.unit).replace(":",".")+".execute",world.game_clock.current_hour())
	last_result={"ok":ok,"reason":"EXECUTION_AUTHORITY_REVOKED"};record("revoke");unsaved=true;await checkpoint();refresh()
func repeat_receipt() -> void:
	if busy or unsaved:return
	var before:=persistence.snapshot()
	last_result=service.checkpoint(self,last_receipt)
	last_result.state_exact=before==persistence.snapshot()
	record("duplicate");refresh()
func checkpoint() -> void:
	if busy:return
	busy=true
	last_result=service.checkpoint(self)
	if not last_result.ok:unsaved=true;busy=false;notice.text=str(last_result);record("checkpoint_refused");return
	if last_result.has("receipt"):last_receipt=last_result.receipt.duplicate(true)
	var saved: SaveOperationResult=await persistence.save_to_user_async(2)
	save_costs.append({"save":persistence.last_save_costs.duplicate(true),"adoption":last_result.duplicate(true),"success":saved.success})
	unsaved=not saved.success;busy=false
	record("checkpoint_saved" if saved.success else "save_failed")
	if not saved.success:notice.text=saved.message
	refresh()
func leave() -> void:
	if busy:return
	paused=true;await checkpoint()
	if unsaved:return
	record("leave");write_rows();closed.emit()
func _process(delta: float) -> void:
	if npc!=null:
		camera.position=npc.position+Vector3(5,3.0,7);camera.look_at(npc.position+Vector3(0,1,-7))
	if frame_ms.size()<12000:frame_ms.append(delta*1000)

func _physics_process(delta: float) -> void:
	if npc==null or busy or unsaved or paused:return
	var o: Dictionary=service.current()
	if o.is_empty() or o.phase not in ["OUTBOUND","RETURNING"]:return
	var tick:=Time.get_ticks_usec()
	var permission: Dictionary=service.authorize("execute")
	if not permission.ok:
		sample_cpu(tick)
		service.block(str(permission.reason));record("execution_blocked");unsaved=true;await checkpoint();return
	var d: Dictionary=world.military_state.duty_operations
	var plan: Dictionary=d.mapping.plans[o.plan]
	var target: Vector3
	if o.phase=="OUTBOUND":target=plan.route[o.waypoint]
	else:target=plan.route[o.waypoint] if o.waypoint>=0 else leader.position
	var offset:=target-npc.position;offset.y=0
	var threshold:=0.22 if o.phase=="OUTBOUND" or o.waypoint>=0 else 1.8
	if offset.length()>threshold:
		var prior:=npc.position;var direction:=offset.normalized();var speed:=minf(2.0,offset.length()/delta)
		npc.velocity=Vector3(direction.x*speed,-0.1 if npc.is_on_floor() else npc.velocity.y-18*delta,direction.z*speed);npc.move_and_slide()
		d.position=npc.position;o.travelled+=prior.distance_to(npc.position);o.physics_steps+=1;o.elapsed_usec+=int(round(delta*1000000.0))
		stalled_usec=stalled_usec+int(round(delta*1000000)) if prior.distance_to(npc.position)<0.001 else 0
		if stalled_usec>3000000:sample_cpu(tick);service.block("PHYSICAL_ROUTE_OBSTRUCTED");unsaved=true;record("route_blocked");await checkpoint();return
	else:
		if o.phase=="OUTBOUND" and o.waypoint<plan.route.size()-1:o.waypoint+=1
		elif o.phase=="RETURNING" and o.waypoint>=0:o.waypoint-=1
		else:
			if o.phase=="OUTBOUND":
				var origin:=npc.position+Vector3(0,1.5,0)
				var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin,plan.target_position,9))
				last_result=service.observe(self,hit,origin)
			else:last_result=service.report(self)
			if not last_result.ok:
				service.block(str(last_result.reason));record("information_action_blocked")
			else:record("private_observation" if o.phase=="RETURNING" else "report_delivered")
			sample_cpu(tick);unsaved=true;await checkpoint();refresh();return
	sample_cpu(tick)
	if o.elapsed_usec>=next_checkpoint_usec:
		next_checkpoint_usec+=20000000
		if tour=="outbound":paused=true;checkpoint_pause=true
		unsaved=true;await checkpoint()
	if o.physics_steps%15==0:refresh()
func refresh() -> void:
	if facts==null:return
	var d: Dictionary=world.military_state.duty_operations
	var last: Dictionary=d.orders.values().back() if not d.orders.is_empty() else {}
	var report: Dictionary=last.get("report",{})
	var status: String="未下达" if last.is_empty() else "报告已送达" if not report.is_empty() else "已派出；等待合法回报"
	if last.get("phase")=="BLOCKED":status="任务中断，未完成："+str(last.failure.reason)
	facts.text="1900 年虚构勤务区 · 观察员现场画面；非巴黎历史地形\n正式具名分队：2 人，聚合计兵 0；place:paris 身份锚点。\n任务：道路拐角核实并面对面回报；无武器，无战斗授权。\n正式 GameClock：%d 分钟 · 状态：%s\n%s"%[world.game_clock.total_minutes(),status,"已收到观察员实地视线核实的道路标记报告。" if not report.is_empty() else "指挥者尚未收到现场观察内容。"]
	(buttons.issue as Button).disabled=busy or unsaved or not d.active.is_empty()
	(buttons.resume as Button).visible=paused
	notice.text="按界面按钮操作 · 任务真实物理执行；每20秒及观察/回报边界保存。\n保存失败会暂停。离开局部视图不会解除未完成任务的时间责任。"
func record(event: String) -> void:
	var d: Dictionary=world.military_state.duty_operations
	rows.append({"event":event,"world_id":world.get_instance_id(),"step_id":simulation.get_instance_id(),"persistence_id":persistence.get_instance_id(),"minute":world.game_clock.total_minutes(),"duty":d.duplicate(true),"people":world.person_overlay.snapshot(),"population":world.population_state.snapshot(),"organization":world.organization_state.snapshot(),"materials":world.military_state.material_registry.duplicate(true),"last_result":last_result.duplicate(true)})
	print("FORMAL_DUTY_EVENT "+JSON.stringify({"event":event,"minute":world.game_clock.total_minutes(),"active":d.active,"pose":d.position}))
func capture(label: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir+"/"+label+".png")
func write_rows() -> void:
	var result: Dictionary={"pid":OS.get_process_id(),"project":ProjectSettings.globalize_path("res://"),"automated_native_input":not tour.is_empty(),"human_gui":false,"movie_fixed_30":"--duty-movie" in OS.get_cmdline_user_args(),"first_draw_ms":first_draw_ms,"rows":rows,"save_costs":save_costs,"physics_cpu_usec":physics_cpu_usec,"frame_ms":frame_ms,"combat":load("res://formal_link/authority.gd").assess(world,world.player_state.player_id()),"unit":world.military_state.get_formation(world.military_state.duty_operations.unit).to_dict(),"final_minute":world.game_clock.total_minutes()}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))

func sample_cpu(start: int) -> void:
	if physics_cpu_usec.size()<12000:physics_cpu_usec.append(Time.get_ticks_usec()-start)
