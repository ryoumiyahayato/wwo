extends Node3D
## One real unarmed body projects the existing formal NPC. No person or resource creation.
const State = preload("res://scripts/vnext/military/military_training_state.gd")
const Service = preload("res://scripts/vnext/military/military_training_service.gd")
var host: Node3D
var service: RefCounted
var npc: CharacterBody3D
var facts: Label
var last_transition: Dictionary={}
var paused_for_resume:=false
var pose_dirty:=false

func _ready() -> void:
	service=Service.new()
	var reason: String=service.bind(host.world,self)
	if not reason.is_empty():push_error(reason);get_tree().quit(1);return
	var d: Dictionary=host.world.military_state.training_group
	npc=CharacterBody3D.new();npc.name="FormalObserverBody";npc.set_meta("formal_person_id",d.observer);npc.collision_layer=32;npc.collision_mask=9;add_child(npc);npc.position=d.position
	var shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=0.28;capsule.height=1.7;shape.shape=capsule;shape.position.y=0.86;npc.add_child(shape)
	var body:=MeshInstance3D.new();var mesh:=CapsuleMesh.new();mesh.radius=0.28;mesh.height=1.7;body.mesh=mesh;body.position.y=0.86;body.material_override=host._material(Color("526678"));npc.add_child(body)
	var nameplate:=Label3D.new();nameplate.text="FORMAL NPC 0002\nUNARMED OBSERVER";nameplate.font_size=32;nameplate.pixel_size=0.005;nameplate.position.y=2.15;npc.add_child(nameplate)
	host._box(host,Vector3(1.2,0.02,1.2),State.TARGET,Color("d8ac46"))
	var marker:=Label3D.new();marker.text="OBSERVATION POINT";marker.font_size=30;marker.pixel_size=0.005;marker.position=State.TARGET+Vector3(0,0.15,0);marker.rotation.x=-PI/2;host.add_child(marker)
	var panel:=ColorRect.new();panel.position=Vector2(15,108);panel.size=Vector2(560,187);panel.color=Color(0.035,0.065,0.075,0.94);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;host.hud.add_child(panel)
	var b:=Button.new();b.position=Vector2(25,118);b.size=Vector2(530,35);b.text="带队岗位：指示观察员前往黄标、观察并近距回报";b.add_theme_font_override("font",load("res://cedar/system_font.tres"));host.hud.add_child(b);b.pressed.connect(issue);host.buttons.order=b
	facts=Label.new();facts.position=Vector2(25,164);facts.size=Vector2(535,120);facts.add_theme_font_override("font",load("res://cedar/system_font.tres"));facts.add_theme_font_size_override("font_size",16);facts.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;host.hud.add_child(facts)
	paused_for_resume=OS.get_cmdline_user_args().has("--group-pause")
	var resume_button:=Button.new();resume_button.position=Vector2(585,118);resume_button.size=Vector2(270,35);resume_button.text="继续观察员执行";resume_button.add_theme_font_override("font",load("res://cedar/system_font.tres"));host.hud.add_child(resume_button);resume_button.pressed.connect(resume_execution);host.buttons.group_resume=resume_button
	refresh()

func resume_execution() -> void:
	if host.busy or host.unsaved or host.pending_native_blocked:return
	paused_for_resume=false;host.record("group_local_execution_resumed");refresh()

func face_clear() -> bool:
	var from:=npc.position+Vector3(0,1.5,0)
	var to: Vector3=host.actor.position+Vector3(0,1.5,0)
	var query:=PhysicsRayQueryParameters3D.create(from,to,9)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func issue() -> void:
	if host.busy or host.unsaved or host.pending_native_blocked:return
	last_transition=service.issue(self)
	host.last_result=last_transition
	host.record("group_order_issued" if last_transition.get("ok",false) else "group_order_refused")
	if last_transition.get("ok",false) and not last_transition.get("duplicate",false):
		host.unsaved=true;await host.save_world()
	refresh()

func _physics_process(delta: float) -> void:
	if npc==null or host.busy or host.unsaved or host.pending_native_blocked or paused_for_resume:return
	var d: Dictionary=host.world.military_state.training_group
	var status: String=d.order.get("status","IDLE")
	if status not in ["OUTBOUND","RETURNING"]:return
	var permission: Dictionary=service.authorize("execute")
	if not permission.get("ok",false):host.notice.text="观察员执行权限失效；任务保留。";return
	var target: Vector3=State.TARGET if status=="OUTBOUND" else host.actor.position
	var offset:=target-npc.position;offset.y=0
	var threshold:=0.25 if status=="OUTBOUND" else 2.0
	if offset.length()>threshold:
		var before:=npc.position
		var speed:=minf(1.8,offset.length()/delta)
		var direction:=offset.normalized()
		npc.velocity=Vector3(direction.x*speed,-0.1 if npc.is_on_floor() else npc.velocity.y-18*delta,direction.z*speed)
		npc.move_and_slide()
		d.position=npc.position;d.travelled+=before.distance_to(npc.position);d.physics_steps+=1;d.elapsed_usec+=int(round(delta*1000000.0))
		pose_dirty=true
		if d.physics_steps%30==0:refresh()
		return
	if status=="OUTBOUND":
		var origin:=npc.position+Vector3(0,1.5,0)
		var query:=PhysicsRayQueryParameters3D.create(origin,Vector3(0,1.5,-22),169,[npc.get_rid(),host.actor.get_rid()])
		var hit:=get_world_3d().direct_space_state.intersect_ray(query)
		last_transition=service.observe(self,hit,origin)
	else:last_transition=service.report(self)
	if not last_transition.get("ok",false):host.notice.text="训练动作未完成："+str(last_transition.get("reason"));return
	host.record("group_observation_private" if status=="OUTBOUND" else "group_report_delivered")
	host.unsaved=true
	if status=="OUTBOUND" and OS.get_cmdline_user_args().has("--group-stop-observed"):paused_for_resume=true
	await host.save_world()
	refresh()

func refresh() -> void:
	if facts==null:return
	var d: Dictionary=host.world.military_state.training_group
	var status: String=d.order.get("status","IDLE")
	var visible_report: Dictionary=d.order.get("report",{})
	var known_status: String="尚未下达指示" if status=="IDLE" else "已收到近距回报" if not visible_report.is_empty() else "指示已发出；等待回报"
	facts.text="同一世界：带队人 0001 → 无武器观察员 0002\n两个正式人口 claim；岗位仅限新建虚构训练场。\n任务：%s\n%s"%[known_status,"观察员报告：从指定黄标看见合成靶板。" if not visible_report.is_empty() else "尚无回报。带队人未取得观察员的观察内容。"]
	(host.buttons.order as Button).disabled=host.busy or host.unsaved or host.pending_native_blocked or not d.order.is_empty()
	(host.buttons.group_resume as Button).visible=paused_for_resume
