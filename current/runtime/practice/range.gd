extends Node3D
## A local physical view over the installed formal owners. Fictional geometry.
signal closed
const MaterialLedger = preload("res://scripts/vnext/military/military_material_state.gd")
const Service = preload("res://scripts/vnext/military/military_material_service.gd")
const Custody = preload("res://custody/scenario.gd")
const Scenario = preload("res://practice/scenario.gd")
const Shot = preload("res://practice/shot_contract.gd")
const Actor = preload("res://practice/actor.gd")
const Recovery = preload("res://practice/recovery.gd")
const NativeReturn = preload("res://practice/native_return.gd")
var world: WorldState
var simulation: SimulationStep
var persistence: FormalPersistence
var service: RefCounted
var actor: CharacterBody3D
var camera: Camera3D
var weapon_model: Node3D
var blocker: StaticBody3D
var flash: MeshInstance3D
var busy:=false
var unsaved:=false
var reload_prepared:=false
var input_sequence:=0
var last_input_id:=""
var pending_receipt: Dictionary={}
var last_receipt: Dictionary={}
var last_result: Dictionary={}
var last_adoption: Dictionary={}
var rows: Array=[]
var costs: Array=[]
var frame_samples: Array[float]=[]
var buttons: Dictionary={}
var hud: CanvasLayer
var facts: Label
var notice: Label
var aim_marker: Label
var trace_lifetime:=0.0
var trace_mesh: MeshInstance3D
var tour_mode:=""
var output_path:="user://practice_manual.json"
var capture_path:=""
var boot_tick:=0
var first_draw_ms:= -1
var _last_ui_tick:=0
var native_boundary: Dictionary={}
var recovery_assessment: Dictionary={}
var action_qualification: Dictionary={}
var shot_cost: Dictionary={}
var legacy_stage_replay:=false
var pending_native_blocked:=false
var instance_id:=""
var formal_combat_request: Dictionary={}
var custody_is_not_fire_permission: Dictionary={}
var time_advance_while_open: Dictionary={}
var economy_at_entry: Dictionary={}
var ledger_at_entry: Dictionary={}
var person_at_entry: Dictionary={}
var clock_at_entry: Dictionary={}
var entry_performance: Dictionary={}
var first_draw_performance: Dictionary={}
var group_view: Node3D

func _ready() -> void:
	boot_tick=Time.get_ticks_msec()
	service=Service.new()
	service.reuse_validated_stage=OS.get_cmdline_user_args().has("--experimental-stage-reuse")
	if not service.bind(world,persistence):push_error("PRACTICE_WORLD_BIND_FAILED");get_tree().quit(1);return
	if not service.register_physical_executor(self):push_error("PRACTICE_EXECUTOR_BIND_FAILED");get_tree().quit(1);return
	economy_at_entry=world.economy_state.get_persistent_state();ledger_at_entry=world.ledger_state.snapshot();person_at_entry=world.person_overlay.snapshot();clock_at_entry=world.game_clock.snapshot()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--practice-tour="):tour_mode=arg.trim_prefix("--practice-tour=")
		if arg.begins_with("--practice-output="):output_path=arg.trim_prefix("--practice-output=")
		if arg.begins_with("--capture-dir="):capture_path=arg.trim_prefix("--capture-dir=")
	instance_id=str(persistence._save_metadata.get("military_scenario",{}).get("practice_instance_id",""))
	build_geometry();build_hud();restore_pose();inspect_native_boundary();refresh()
	if not world.military_state.training_group.is_empty():
		group_view=load("res://practice/group_view.gd").new();group_view.host=self;add_child(group_view)
	var combat:=FormalLocalSession.new();combat.world=world;combat.step=simulation;combat.persistence=persistence
	formal_combat_request=combat.issue(world.player_state.player_id(),"combat")
	custody_is_not_fire_permission=Scenario.authorize(world,persistence,"fire",Custody.context(world,"use"))
	time_advance_while_open=simulation.advance_minutes(1)
	if not service.view().get("receipts",{}).is_empty():last_receipt=service.view().receipts.values().back().duplicate(true)
	restore_shot_projection()
	record("practice_entered")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		first_draw_ms=Time.get_ticks_msec()-boot_tick
		first_draw_performance={"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"render_total_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"render_texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
	print("PRACTICE_READY "+JSON.stringify({"pid":OS.get_process_id(),"person_id":world.player_state.player_id(),"world_instance":world.get_instance_id(),"persistence_instance":persistence.get_instance_id(),"area_id":Shot.AREA,"first_draw_ms":first_draw_ms,"time_contract":Shot.TIME_CONTRACT}))
	if not tour_mode.is_empty():
		var tour_script: String="res://practice/group_replay.gd" if tour_mode.begins_with("group") else "res://practice/continuous_replay.gd" if tour_mode in ["continuous","continue","recover","frozen","before"] else "res://practice/replay.gd"
		var tour: Node=load(tour_script).new();tour.host=self;add_child(tour)

func _material(color: Color, unshaded:=false) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=0.85
	if unshaded:m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _box(parent: Node3D, size_value: Vector3, position_value: Vector3, color: Color) -> MeshInstance3D:
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size_value;mesh.mesh=box;mesh.position=position_value;mesh.material_override=_material(color);parent.add_child(mesh);return mesh

func _solid(id: String, size_value: Vector3, position_value: Vector3, color: Color, layer:=1) -> StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=layer;body.collision_mask=0;body.set_meta("practice_target_id",id);add_child(body);body.position=position_value
	_box(body,size_value,Vector3.ZERO,color)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size_value;shape.shape=box;body.add_child(shape);return body

func build_geometry() -> void:
	var environment_node:=WorldEnvironment.new();var environment_value:=Environment.new();environment_value.background_mode=Environment.BG_COLOR;environment_value.background_color=Color("93b5ce");environment_value.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment_value.ambient_light_color=Color("dce8e5");environment_value.ambient_light_energy=0.75;environment_node.environment=environment_value;add_child(environment_node)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-25,0);sun.light_energy=0.65;sun.shadow_enabled=true;add_child(sun)
	_solid("practice_target:ground",Vector3(70,0.3,90),Vector3(0,-0.16,-13),Color("9c977c"),8)
	_solid("practice_target:backstop",Vector3(18,5,1.5),Vector3(0,2.4,-26),Color("625d4b"))
	_solid("practice_target:board_01",Vector3(2.4,2.4,0.18),Vector3(0,1.5,-22),Color("d9d1b2"))
	for i: int in 5:
		var ring:=MeshInstance3D.new();var disk:=CylinderMesh.new();disk.top_radius=1.02-float(i)*0.18;disk.bottom_radius=disk.top_radius;disk.height=0.008;ring.mesh=disk;ring.rotation.x=PI/2;ring.position=Vector3(0,1.5,-21.90+float(i)*0.012);ring.material_override=_material(Color("b34632") if i%2==0 else Color("ece4ca"));add_child(ring)
	for x: float in [-8.0,8.0]:
		_box(self,Vector3(0.04,0.01,38),Vector3(x,0.01,-5),Color("ece1b9"))
	for z: float in [0.0,5.0,10.0]:_box(self,Vector3(16,0.015,0.05),Vector3(0,0.02,z),Color("ece1b9"))
	var label:=Label3D.new();label.text="1900 · FICTIONAL PRACTICE RANGE\nNO HISTORICAL INVENTORY / NO POPULATION TARGET";label.font_size=44;label.pixel_size=0.008;label.position=Vector3(0,5.6,-25);label.modulate=Color("faf0d0");add_child(label)
	actor=Actor.new();actor.configure(world.player_state.player_id(),"practice",self);actor.set_meta("player_controlled",true);actor.weapon="rifle";actor.weapon_id=MaterialLedger.config().asset_id;actor.damage=0.0;actor.penetration=0;actor.collision_mask_for_shots=169;actor.fire_audit_enabled=true;add_child(actor);actor.position=Vector3(0,0.05,5)
	var visual: Node3D=load("res://assets/user_derived/models/user_rifleman_armed.glb").instantiate();visual.name="InfantryVisual";actor.add_child(visual)
	var old_rifle:=visual.find_child("Rifle",true,false)
	if old_rifle!=null:old_rifle.hide()
	weapon_model=Node3D.new();weapon_model.name="SourcedSingleShotRifle";actor.add_child(weapon_model);weapon_model.position=Vector3(0.27,1.18,-0.28)
	_box(weapon_model,Vector3(0.075,0.10,0.78),Vector3(0,-0.015,0.18),Color("69452e"))
	_box(weapon_model,Vector3(0.040,0.045,0.85),Vector3(0,0.045,-0.32),Color("252d31"))
	_box(weapon_model,Vector3(0.10,0.02,0.12),Vector3(0.04,0.05,0.12),Color("39434a"))
	var muzzle:=Marker3D.new();muzzle.name="ActualMuzzle";muzzle.position=Vector3(0,0.045,-0.75);weapon_model.add_child(muzzle);actor.bind_weapon_geometry(weapon_model,muzzle)
	flash=MeshInstance3D.new();var flash_shape:=SphereMesh.new();flash_shape.radius=0.075;flash_shape.height=0.15;flash.mesh=flash_shape;flash.material_override=_material(Color("ffcc54"),true);muzzle.add_child(flash);flash.visible=false
	actor.aim_point=Vector3(0,1.5,-22)
	camera=Camera3D.new();camera.fov=62;camera.current=true;add_child(camera)
	trace_mesh=MeshInstance3D.new();add_child(trace_mesh)

func build_hud() -> void:
	hud=CanvasLayer.new();hud.layer=220;add_child(hud)
	var theme_value:=Theme.new();theme_value.default_font=load("res://cedar/system_font.tres");theme_value.default_font_size=17
	var root:=Control.new();root.theme=theme_value;hud.add_child(root);root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var top:=ColorRect.new();top.color=Color(0.035,0.065,0.075,0.91);top.position=Vector2(0,0);top.size=Vector2(1280,91);top.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(top)
	var load_label:="冷启动" if "--practice-cold" in OS.get_cmdline_user_args() else "全新场景"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--practice-source="):load_label="保存副本"
	var title:=Label.new();title.position=Vector2(20,10);title.text="正式来源装备 · 1900虚构试射场 / PRACTICE · "+load_label+" · PID %d"%OS.get_process_id();title.add_theme_font_size_override("font_size",23);root.add_child(title)
	var help:=Label.new();help.position=Vector2(20,49);help.text="WASD 移动 · 方向键 / 右键拖动瞄准 · 左键/F 扣扳机 · R 离散装填 · E 领用 · B 遮挡枪口";root.add_child(help)
	var panel:=ColorRect.new();panel.position=Vector2(877,112);panel.size=Vector2(383,437);panel.color=Color(0.035,0.065,0.075,0.91);panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(panel)
	facts=Label.new();facts.position=Vector2(892,124);facts.size=Vector2(351,375);facts.add_theme_font_size_override("font_size",15);facts.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;root.add_child(facts)
	var names: Array=[["equip","E 领用步枪与6发"],["return","归还剩余装备"],["duplicate","重复回执"],["revoke","撤销击发资格"],["save","保存"],["leave","归还并返回主界面"]]
	for i: int in names.size():
		var button:=Button.new();button.position=Vector2(20+(i%3)*275,568+(i/3)*43);button.size=Vector2(264,35);button.text=names[i][1];button.pressed.connect(action.bind(names[i][0]));root.add_child(button);buttons[names[i][0]]=button
	var extra: Array=[["export","导出完整恢复资料"],["diagnostic","导出冻结诊断"],["safeexit","保留占用并安全退出"]]
	for i: int in extra.size():
		var b:=Button.new();b.position=Vector2(20+i*275,650);b.size=Vector2(264,35);b.text=extra[i][1];b.pressed.connect(action.bind(extra[i][0]));root.add_child(b);buttons[extra[i][0]]=b
	var recover_button:=Button.new();recover_button.position=Vector2(887,568);recover_button.size=Vector2(373,35);recover_button.text="核对证据并恢复 / 接管租约";recover_button.pressed.connect(action.bind("recover"));root.add_child(recover_button);buttons.recover=recover_button
	var notice_back:=ColorRect.new();notice_back.position=Vector2(10,510);notice_back.size=Vector2(840,53);notice_back.color=Color(0.035,0.065,0.075,0.94);notice_back.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(notice_back)
	notice=Label.new();notice.position=Vector2(20,520);notice.size=Vector2(825,46);notice.add_theme_color_override("font_color",Color("ffda8c"));notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.text="同一正式人物。靶标为合成物体。参数为原型配置。正式战争combat继续关闭。";root.add_child(notice)
	aim_marker=Label.new();aim_marker.text="+";aim_marker.add_theme_font_size_override("font_size",28);aim_marker.add_theme_color_override("font_color",Color("ffd36b"));aim_marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(aim_marker)

func _process(delta: float) -> void:
	if actor==null:return
	frame_samples.append(delta*1000.0)
	if frame_samples.size()>18000:frame_samples.pop_front()
	var axis:=Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_DOWN)))
	if not busy:actor.aim_point+=Vector3(axis.x,axis.y,0)*delta*3.0
	camera.position=actor.position+Vector3(2.3,2.35,4.3);camera.look_at(actor.position+Vector3(0,1.0,-12))
	if not camera.is_position_behind(actor.aim_point):aim_marker.position=camera.unproject_position(actor.aim_point)-Vector2(8,18)
	trace_lifetime=maxf(0,trace_lifetime-delta);flash.visible=trace_lifetime>0.33;trace_mesh.visible=trace_lifetime>0
	if Time.get_ticks_msec()-_last_ui_tick>150:_last_ui_tick=Time.get_ticks_msec();refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):actor.aim_point+=Vector3(event.relative.x*0.012,-event.relative.y*0.012,0)
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:queue_trigger("mouse_left");get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F:queue_trigger("keyboard_F")
			KEY_E:action("equip")
			KEY_R:reload_prepared=true;notice.text="已请求原型离散装填；不推进正式分钟，不增加弹药。"
			KEY_B:toggle_blocker()
		if event.physical_keycode in [KEY_F,KEY_E,KEY_R,KEY_B]:get_viewport().set_input_as_handled()

func queue_trigger(input_kind: String) -> void:
	if busy:return
	input_sequence+=1;last_input_id="%d:%s:input:%d"%[OS.get_process_id(),input_kind,input_sequence];actor.trigger_pending=true

func active() -> String:
	return str(service.view().get("asset",{}).get("lease_id",""))

func custody_context(operation: String) -> Dictionary:
	return Custody.context(world,operation)

func action(name: String) -> void:
	if busy:return
	if name in ["recover","export","diagnostic","safeexit"]:
		await recovery_action(name);return
	if pending_native_blocked and name!="revoke":notice.text="租约冻结："+str(recovery_assessment.get("reason","未知"));return
	if unsaved and name!="save":notice.text="已发生的变更尚未保存；先重试保存。";return
	var result: Dictionary={"ok":true}
	if name=="equip":
		result=Scenario.authorize(world,persistence,"carry",Scenario.context(world,"carry"))
		if result.ok:
			result=service.command("reserve",custody_context("reserve"),{"quantity":6})
			if result.ok:result=service.command("issue",custody_context("issue"),{"lease_id":result.lease_id})
	elif name in ["return","leave"]:
		if not active().is_empty():result=service.command("return",custody_context("return"),{"lease_id":active(),"reason":"practice_remaining_kit_returned"})
	elif name=="recover":result=service.command("recover",custody_context("recover"),{"lease_id":active()})
	elif name=="duplicate":result=service.adopt_use(custody_context("use"),last_receipt)
	elif name=="revoke":result={"ok":world.organization_state.revoke_authority(Scenario.authority_id("fire"),world.game_clock.current_hour())}
	last_result=result
	notice.text=("已采用。" if result.get("ok",false) else "拒绝："+str(result.get("reason","操作失败")))+(" 相同回执未再次扣弹。" if result.get("duplicate",false) else "")
	record(name+"_accepted" if result.get("ok",false) else name+"_rejected")
	if result.get("ok",false) and not result.get("duplicate",false):
		unsaved=true
		if name=="equip":
			var marker_error:=write_boundary("idle",{})
			if not marker_error.is_empty():pending_native_blocked=true;notice.text=marker_error;return
		unsaved=true;await save_world()
		if name=="equip" and OS.get_cmdline_user_args().has("--hold=before"):
			busy=true;print("RECOVERY_HOLD before pid="+str(OS.get_process_id()))
	refresh()
	if name=="leave" and result.get("ok",false) and not unsaved:record("returned_to_formal_application");write_rows();closed.emit()

func fire_from_input() -> void:
	if busy or unsaved:return
	if pending_native_blocked:last_result={"ok":false,"reason":"UNCOMMITTED_NATIVE_SHOT_BOUNDARY"};record("pending_native_trigger_refused");write_rows();return
	var begun:=Time.get_ticks_usec()
	shot_cost={"action":"shot_components","pid":OS.get_process_id()}
	var authorization:=Scenario.authorize(world,persistence,"fire",Scenario.context(world,"fire"))
	if not authorization.ok:
		last_result=authorization;notice.text="拒绝："+str(authorization.reason);record("trigger_rejected");write_rows();return
	var before_sequence: int=actor.shot_sequence
	var fired: bool=actor._shoot("",actor.aim_point,false)
	if not fired:
		var equipment_reason:=str(last_result.get("reason",""))
		last_result={"ok":false,"reason":str(actor.fire_attempts.back().get("reason","native_rejected")) if not actor.fire_attempts.is_empty() else "native_rejected","equipment_reason":equipment_reason};notice.text="原生射击拒绝："+str(last_result.reason)+" / "+equipment_reason+"；军备账未扣耗。";record("native_trigger_rejected");write_rows()
	costs.append(shot_cost.duplicate(true))
	costs.append({"action":"native_trigger","cpu_usec":Time.get_ticks_usec()-begun,"fired":fired,"sequence_before":before_sequence,"sequence_after":actor.shot_sequence})

func before_infantry_shot(body: CharacterBody3D, hit: Dictionary) -> bool:
	if body!=actor or body.brain.actor_id!=world.player_state.player_id() or not pending_receipt.is_empty():return false
	if not hit.is_empty() and (hit.collider as Node).has_meta("formal_person_id"):
		last_result={"ok":false,"reason":"FORMAL_PERSON_NOT_A_TRAINING_TARGET"};return false
	var timer:=Time.get_ticks_usec()
	action_qualification={}
	for operation: String in ["carry","fire"]:
		var authorized:=Scenario.authorize(world,persistence,operation,Scenario.context(world,operation))
		if not authorized.ok:last_result=authorized;return false
		action_qualification[operation]=authorized.authorization.duplicate(true)
	shot_cost["qualification_usec"]=Time.get_ticks_usec()-timer;timer=Time.get_ticks_usec()
	var requested: Dictionary=service.request_use(custody_context("use"),active())
	if not requested.ok:last_result=requested;return false
	shot_cost["custody_request_usec"]=Time.get_ticks_usec()-timer;timer=Time.get_ticks_usec()
	var request: Dictionary=requested.request
	var ammo:=MaterialLedger.native(int(request.quantity),int(request.before.epoch))
	if not ammo.restore(request.before).get("ok",false):return false
	var preparation:=1000 if reload_prepared else 0
	if preparation>0:ammo.advance(0.001)
	var committed: Dictionary=ammo.commit_fire(MaterialLedger.config().asset_id,"primary",ammo.request_id(),0.001,true,true)
	if not committed.get("ok",false):last_result=committed;return false
	shot_cost["native_ammo_usec"]=Time.get_ticks_usec()-timer;timer=Time.get_ticks_usec()
	var rid: String="%s:g%d:commit:%d"%[request.lease_id,int(request.generation),int(ammo.sequence)]
	var origin: Vector3=actor.muzzle.global_position
	var direction: Vector3= -actor.muzzle.global_basis.z.normalized()
	var hit_id: String="" if hit.is_empty() else str((hit.collider as Node).get_meta("practice_target_id",""))
	var physical: Dictionary={"schema":Shot.SCHEMA,"shot_id":rid+":shot","person_id":world.player_state.player_id(),"asset_id":MaterialLedger.config().asset_id,"lot_id":MaterialLedger.config().lot_id,"source_id":MaterialLedger.config().source_id,"area_id":Shot.AREA,"anchor_place_id":world.person_overlay.current_place(world.player_state.player_id()),"minute":world.game_clock.total_minutes(),"input_id":last_input_id,"physics_frame":Engine.get_physics_frames(),"actor_shot_sequence":actor.shot_sequence+1,"body_position":actor.global_position,"origin":origin,"direction":direction,"endpoint":hit.get("position",origin+direction*125.0),"normal":hit.get("normal",Vector3.ZERO),"hit_id":hit_id,"target_kind":"LEGAL_MISS_NO_POPULATION" if hit_id.is_empty() else "SYNTHETIC_NON_POPULATION","collision_model":"GODOT_PHYSICS_MUZZLE_RAY","collision_mask":actor.collision_mask_for_shots,"max_range":125.0,"native_preparation_usec":preparation,"time_contract":Shot.TIME_CONTRACT,"carry_context":Scenario.context(world,"carry"),"fire_context":Scenario.context(world,"fire")}
	pending_receipt={"lease_id":request.lease_id,"issuer_id":request.issuer_id,"generation":request.generation,"receipt_id":rid,"before":request.before.duplicate(true),"after":ammo.snapshot(),"commit":committed,"physical":physical}
	var staged: Dictionary=service.stage_physical_use(self,custody_context("use"),pending_receipt)
	if not staged.ok:pending_receipt={};last_result=staged;return false
	shot_cost["stage_validation_usec"]=Time.get_ticks_usec()-timer;timer=Time.get_ticks_usec()
	var boundary_error:=write_boundary("prepared_after_muzzle_ray",pending_receipt)
	shot_cost["prepared_durable_usec"]=Time.get_ticks_usec()-timer
	if OS.get_cmdline_user_args().has("--hold=prepared"):
		busy=true;print("RECOVERY_HOLD prepared pid="+str(OS.get_process_id()));return false
	if not boundary_error.is_empty():service.discard_staged_physical(self);pending_receipt={};last_result={"ok":false,"reason":boundary_error};return false
	return true

func infantry_event(event: Dictionary) -> void:
	if event.get("kind")!="shot":return
	if pending_receipt.is_empty() or event.actor_id!=pending_receipt.physical.person_id or event.origin!=pending_receipt.physical.origin or event.position!=pending_receipt.physical.endpoint or event.seq!=pending_receipt.physical.actor_shot_sequence:
		push_error("PHYSICAL_SHOT_PENDING_EVENT_MISMATCH");unsaved=true;busy=true;return
	last_receipt=pending_receipt.duplicate(true);pending_receipt={}
	var timer:=Time.get_ticks_usec()
	var boundary_error:=write_boundary("emitted_pending_formal_save",last_receipt)
	shot_cost["emitted_durable_usec"]=Time.get_ticks_usec()-timer;timer=Time.get_ticks_usec()
	if not boundary_error.is_empty():push_error(boundary_error);pending_native_blocked=true;record("native_boundary_write_failed_after_emission");write_rows();return
	if "--practice-hold-after-native" in OS.get_cmdline_user_args():
		pending_native_blocked=true;record("emitted_native_result_not_adopted_or_saved");write_rows();print("PRACTICE_NATIVE_EMITTED_HOLD pid="+str(OS.get_process_id()));return
	last_adoption=service.adopt_use(custody_context("use"),last_receipt);last_result=last_adoption;reload_prepared=false
	shot_cost["adoption_usec"]=Time.get_ticks_usec()-timer
	if not last_adoption.get("ok",false):
		push_error("PHYSICAL_SHOT_ADOPTION_FAILED "+JSON.stringify(last_adoption));unsaved=false;busy=false;pending_native_blocked=true;record("physical_shot_unadopted");write_rows();return
	var line:=ImmediateMesh.new();line.surface_begin(Mesh.PRIMITIVE_LINES,_material(Color("ffde90"),true));line.surface_add_vertex(event.origin);line.surface_add_vertex(event.position);line.surface_end();trace_mesh.mesh=line;trace_lifetime=0.45
	if not event.hit.is_empty():
		add_impact_mark(event.position,event.hit.normal)
	var remaining: int=int(service.view().lot.issued)
	notice.text="原生枪口射线已发射；"+("命中合成靶标" if not event.hit.is_empty() else "合法射偏")+"。正式军备账采用1发，剩余在手%d发。"%remaining
	unsaved=true;record("native_physical_shot_adopted");write_rows();save_world.call_deferred()

func save_world() -> void:
	if busy:return
	busy=true
	persistence._save_metadata["practice_last_receipt"]=str(last_receipt.get("receipt_id",""))
	persistence._save_metadata["practice_pose"]={"person_id":world.player_state.player_id(),"area_id":Shot.AREA,"body_position":[actor.position.x,actor.position.y,actor.position.z],"aim_point":[actor.aim_point.x,actor.aim_point.y,actor.aim_point.z],"scope":"LOCAL_VIEW_POSE_NOT_FORMAL_TRAVEL"}
	var saved: SaveOperationResult=await persistence.save_to_user_async(3)
	busy=false;unsaved=not saved.success;costs.append(persistence.last_save_costs.duplicate(true));last_result={"ok":saved.success,"message":saved.message}
	if saved.success:record("formal_save_durable")
	else:notice.text=saved.message;record("formal_save_failed")
	if saved.success and group_view!=null:group_view.pose_dirty=false
	if saved.success and not last_receipt.is_empty():
		if OS.get_cmdline_user_args().has("--hold=covered") and service.view().receipts.has(last_receipt.receipt_id):
			busy=true;print("RECOVERY_HOLD covered pid="+str(OS.get_process_id()));return
		var marker_error:=write_boundary("covered_by_formal_save",last_receipt)
		if not marker_error.is_empty():notice.text="正式保存成功；原生回执边界标记未更新："+marker_error
	write_rows();refresh()

func inspect_native_boundary() -> void:
	if not NativeReturn.valid_instance_id(instance_id):pending_native_blocked=true;return
	var exists:=FileAccess.file_exists(NativeReturn.path(instance_id))
	if not exists and persistence._save_metadata.get("practice_recovery_protocol","")=="" and active().is_empty() and world.military_state.material_registry.get("schema")!=MaterialLedger.RECOVERY_SCHEMA:
		persistence._save_metadata["practice_recovery_protocol"]=Recovery.PROTOCOL
		write_boundary("idle",{})
	native_boundary=Recovery.evidence(persistence)
	recovery_assessment=Recovery.assess(world,persistence,native_boundary)
	recovery_assessment.erase("candidate")
	if native_boundary.get("ok",false) and persistence._save_metadata.get("practice_recovery_protocol")==Recovery.PROTOCOL:world.military_state.material_registry.schema=MaterialLedger.RECOVERY_SCHEMA
	pending_native_blocked=not recovery_assessment.get("ok",false) or recovery_assessment.get("state")=="EMITTED_UNADOPTED"
	if pending_native_blocked:notice.text=recovery_hint()

func write_boundary(status: String, receipt: Dictionary) -> String:
	persistence._save_metadata["practice_recovery_protocol"]=Recovery.PROTOCOL
	return NativeReturn.write(instance_id,status,receipt,action_qualification,custody_context("use"),service.view().get("leases",{}).get(active(),{}))

func record_native_ray_cost(usec: int) -> void:
	shot_cost["actor_and_rays_usec"]=usec

func recovery_action(name: String) -> void:
	if name=="safeexit":
		if group_view!=null and group_view.pose_dirty and not pending_native_blocked:
			await save_world()
		if unsaved:notice.text="有未保存的正式变更；先保存或导出，不能丢弃。";return
		record("safe_exit_preserved_lease");write_rows();closed.emit();return
	if name=="diagnostic":
		inspect_native_boundary();record("diagnostic_exported");write_rows();notice.text="诊断："+output_path;return
	if name=="export":
		if unsaved:await save_world()
		if unsaved:return
		var destination:=output_path.get_base_dir()+"/portable_practice.json"
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--bundle-output="):destination=arg.trim_prefix("--bundle-output=")
		busy=true
		var problem:=Recovery.export_portable(destination,persistence)
		busy=false;last_result={"ok":problem.is_empty(),"path":destination,"reason":problem}
		record("portable_export");write_rows();notice.text="完整恢复资料："+destination if problem.is_empty() else "导出拒绝："+problem;return
	native_boundary=Recovery.evidence(persistence)
	var inspected:=Recovery.assess(world,persistence,native_boundary)
	if not inspected.get("ok",false):last_result=inspected;notice.text=recovery_hint();record("recovery_refused");write_rows();return
	if inspected.state in ["EMITTED_UNADOPTED","ALREADY_ADOPTED"]:
		last_result=service.recover_emitted(custody_context("recover"),native_boundary)
		if not last_result.get("ok",false):notice.text=str(last_result.get("reason",""));record("recovery_refused");write_rows();return
		last_receipt=native_boundary.receipt.duplicate(true);action_qualification=native_boundary.get("qualification",{}).duplicate(true)
		record("same_emitted_event_recovered_without_native_replay")
		unsaved=true;await save_world()
		if unsaved:return
	if not active().is_empty():
		last_result=service.command("recover",custody_context("recover"),{"lease_id":active()})
		if not last_result.get("ok",false):record("lease_recovery_refused");write_rows();return
		if inspected.state=="NOT_EMITTED":write_boundary("idle",{})
		unsaved=true;await save_world()
	pending_native_blocked=false;restore_shot_projection();notice.text="恢复完成：已核对原事件；没有重放射线或补发弹药。可归还原租约剩余资源。";record("recovery_completed");write_rows();refresh()

func restore_pose() -> void:
	var pose: Dictionary=persistence._save_metadata.get("practice_pose",{})
	if pose.get("person_id")==world.player_state.player_id() and pose.get("area_id")==Shot.AREA:
		var p: Array=pose.get("body_position",[]);var a: Array=pose.get("aim_point",[])
		if p.size()==3:actor.position=Vector3(float(p[0]),float(p[1]),float(p[2]))
		if a.size()==3:actor.aim_point=Vector3(float(a[0]),float(a[1]),float(a[2]))

func add_impact_mark(position_value: Vector3, normal_value: Vector3) -> void:
	var mark:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=0.055;sphere.height=0.11;mark.mesh=sphere;mark.material_override=_material(Color("1d2222"),true);add_child(mark);mark.global_position=position_value+normal_value*0.025

func restore_shot_projection() -> void:
	for receipt: Dictionary in service.view().get("receipts",{}).values():
		var physical: Dictionary=receipt.get("physical",{})
		if physical.get("person_id")!=world.player_state.player_id() or physical.get("area_id")!=Shot.AREA:continue
		actor.shot_sequence=maxi(actor.shot_sequence,int(physical.actor_shot_sequence))
		if physical.hit_id!="":add_impact_mark(physical.endpoint,physical.normal)

func toggle_blocker() -> void:
	if busy:return
	if is_instance_valid(blocker):blocker.free();blocker=null;notice.text="枪口遮挡已移除。";return
	blocker=_solid("practice_target:barrel_blocker",Vector3(0.5,0.5,0.15),(actor.weapon_pivot.global_position+actor.muzzle.global_position)*0.5,Color("bb6b42"))
	notice.text="已放置有碰撞的枪管遮挡物。扣扳机应拒绝，不能扣耗。"

func refresh() -> void:
	if facts==null:return
	var view: Dictionary=service.view();var lot: Dictionary=view.get("lot",{});var asset: Dictionary=view.get("asset",{})
	var held: bool=asset.get("status")=="issued" and asset.get("holder_id")==world.player_state.player_id()
	var pool: Dictionary=view.get("leases",{}).get(active(),{}).get("native",{}).get("vehicles",{}).get(MaterialLedger.config().asset_id,{}).get("primary",{})
	# Informational views for the inherited actor; only the native owner commits.
	actor.brain.ammo=int(not str(pool.get("loaded","")).is_empty())
	actor.brain.reserve_ammo=maxi(0,int(lot.get("issued",0))-actor.brain.ammo)
	weapon_model.visible=held
	facts.text="人物：%s\n\n来源：%s\n步枪：%s\n所有者：%s\n保管：%s\n租约：%s\n\n20 = 可用%d + 预留%d\n     + 在手%d + 已耗%d + 已损%d\n\n场地：虚构1900靶场\n分钟：%d / 离散练习\n正式作战：拒绝\n\n%s"%[world.player_state.player_id(),view.get("source",{}).get("source_id","UNKNOWN"),asset.get("asset_id","UNKNOWN"),asset.get("owner_id",""),asset.get("holder_id",""),active(),int(lot.get("available",0)),int(lot.get("reserved",0)),int(lot.get("issued",0)),int(lot.get("consumed",0)),int(lot.get("lost",0)),world.game_clock.total_minutes(),"正在原子保存…" if busy else "证据待核对" if pending_native_blocked else "已保存" if not unsaved else "待保存"]
	if pending_native_blocked:facts.text+="\n未提交原生回执：租约冻结"
	for name: String in buttons:(buttons[name] as Button).disabled=busy or (pending_native_blocked and name not in ["recover","export","diagnostic","safeexit","revoke"]) or (unsaved and name not in ["save","export","diagnostic"])
	(buttons.equip as Button).disabled=busy or pending_native_blocked or unsaved or not active().is_empty()
	(buttons.recover as Button).disabled=busy or unsaved
	if group_view!=null:group_view.refresh()

func record(stage: String) -> void:
	rows.append({"training_group":world.military_state.training_group.duplicate(true),"stage":stage,"pid":OS.get_process_id(),"project":ProjectSettings.globalize_path("res://"),"world_instance":world.get_instance_id(),"persistence_instance":persistence.get_instance_id(),"person_id":world.player_state.player_id(),"appointments":world.organization_state.appointments_for_person(world.player_state.player_id()),"place_id":world.person_overlay.current_place(world.player_state.player_id()),"area_id":Shot.AREA,"practice_instance_id":instance_id,"pending_native_blocked":pending_native_blocked,"native_boundary":native_boundary.duplicate(true),"recovery":recovery_assessment.duplicate(true),"recovery_audit":persistence._save_metadata.get("practice_recovery_audit",[]).duplicate(true),"actor_shot_sequence":actor.shot_sequence,"world_minute":world.game_clock.total_minutes(),"world_schema":FormalPersistence.SCHEMA_ID,"military_schema":world.military_state.snapshot().schema_id,"body_position":actor.position,"aim_point":actor.aim_point,"registry":world.military_state.material_registry.duplicate(true),"result":last_result.duplicate(true)})

func _plain(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[key]=_plain(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(_plain(item))
		return result
	return value

func write_rows() -> void:
	var samples:=frame_samples.duplicate();samples.sort()
	var performance_value: Dictionary={"first_range_draw_ms":first_draw_ms,"render_mode":DisplayServer.get_name(),"movie_mode":OS.get_cmdline_user_args().has("--practice-movie"),"frame_samples":samples.size(),"frame_median_ms":samples[int(samples.size()*0.5)] if not samples.is_empty() else 0,"frame_p95_ms":samples[mini(samples.size()-1,int(samples.size()*0.95))] if not samples.is_empty() else 0,"process_frame_seconds":Performance.get_monitor(Performance.TIME_PROCESS),"physics_frame_seconds":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"render_total_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"render_texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
	performance_value["before_range_assembly"]=entry_performance
	performance_value["after_first_range_draw"]=first_draw_performance
	var preserved: Dictionary={"economy_exact":economy_at_entry==world.economy_state.get_persistent_state(),"ledger_exact":ledger_at_entry==world.ledger_state.snapshot(),"person_exact":person_at_entry==world.person_overlay.snapshot(),"clock_exact":clock_at_entry==world.game_clock.snapshot()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(_plain({"input_source":"GODOT_NATIVE_INPUT_EVENT_REPLAY" if not tour_mode.is_empty() else "DESKTOP_OR_NATIVE_INPUT","persons":world.person_overlay.snapshot(),"population":world.population_state.snapshot(),"organization":world.organization_state.snapshot(),"rows":rows,"costs":costs,"performance":performance_value,"preserved_authorities":preserved,"formal_combat_request":formal_combat_request,"custody_is_not_fire_permission":custody_is_not_fire_permission,"time_advance_while_open":time_advance_while_open,"same_formal_world":true,"formal_combat_ready":false}),"\t"))

func capture(name_value: String) -> void:
	if capture_path.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_path)
	get_viewport().get_texture().get_image().save_png(capture_path+"/"+name_value+".png")

func recovery_hint() -> String:
	var state: String=str(recovery_assessment.get("state","FROZEN"))
	var explanation: String={"UNCERTAIN":"枪口已准备，不能证明是否发出。保留冻结；可导出诊断并安全退出。","EMITTED_UNADOPTED":"原生已发出，正式账尚未采用。可核对恢复同一事件一次。","FROZEN":"证据缺失或冲突。保留占用；请保留存档及诊断，不要删除标记。"}.get(state,"可核对原记录。")
	return explanation+"\n租约 "+active()+" / 事件 "+str(native_boundary.get("receipt",{}).get("receipt_id","未取得"))
