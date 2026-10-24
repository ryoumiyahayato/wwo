extends Node
## Thin prototype adapter. Core construction rules remain reusable without this host.
const Rules = preload("res://modules/construction/construction_system.gd")
const Planner = preload("res://modules/construction/autonomous_planner.gd")
const View = preload("res://modules/construction/construction_view.gd")
var main
var planner := Planner.new()
var autonomous_enabled := true
var engineering_controls: Array[Control] = []
var support_controls: HBoxContainer
var terrain_work_kind := ""
var terrain_job: Dictionary = {}
var terrain_worker: CharacterBody3D
var terrain_worker_processing := true
var terrain_job_serial := 0
var registered_forts:Dictionary={}
var model := Rules.new()
var views := {}
var selected_id := ""
var selected_position := Vector3.ZERO
var site_selected := false
var selecting := false
var panel: PanelContainer
var toggle_button: Button
var presets: OptionButton
var existing: OptionButton
var status: Label
var build_button: Button
var use_button: Button
var occupied_use_button: Button
var leave_button: Button
var tester_controls: HBoxContainer
var placement_preview: MeshInstance3D
var preview_active := false
var preview_issue := ""
var preview_last_ms := 0
var entry_button: Button
var occupied_controls: HBoxContainer
var preset_ids: Array = Rules.PRESETS.keys()
var outside_hero := Transform3D.IDENTITY
var outside_camera := Transform3D.IDENTITY
var excavation_ok := {}
var tester: CharacterBody3D
var tester_kind := "person"
var tester_direction := Vector3.FORWARD
var tester_distance := 0.0
var tester_hp := 10
var tester_size := Vector3.ONE
var tester_ground_exclusions: Array[RID] = []
var cooldown := 0.0
var ai_build: Dictionary = {}
var ai_builder: CharacterBody3D
var ai_builder_was_processing := true
var connected_ai_host: Node

func setup(owner_main: Node) -> void:
 main = owner_main
 toggle_button = Button.new()
 toggle_button.text = "工事 / 工程试验"
 toggle_button.position = Vector2(80,247)
 toggle_button.size = Vector2(188,40)
 toggle_button.pressed.connect(_toggle_panel)
 main.hud.add_child(toggle_button)
 panel = PanelContainer.new()
 panel.position = Vector2(32,295)
 panel.custom_minimum_size = Vector2(650,165)
 main.hud.add_child(panel)
 if main.font:
  panel.add_theme_font_override("font",main.font)
  toggle_button.add_theme_font_override("font",main.font)
 var layout := VBoxContainer.new()
 panel.add_child(layout)
 var row := HBoxContainer.new()
 layout.add_child(row)
 engineering_controls.append(row)
 presets = OptionButton.new()
 for id in preset_ids: presets.add_item(Rules.PRESETS[id].label)
 row.add_child(presets)
 presets.item_selected.connect(func(_index):
  if preview_active and site_selected: _update_preview()
 )
 _button(row,"选择地面",_begin_selection)
 build_button = _button(row,"建造",_build)
 _button(row,"取消施工",_cancel)
 var second := HBoxContainer.new()
 layout.add_child(second)
 engineering_controls.append(second)
 existing = OptionButton.new()
 existing.custom_minimum_size.x = 170
 existing.item_selected.connect(func(index): selected_id=str(existing.get_item_metadata(index)))
 second.add_child(existing)
 entry_button = _button(second,"进入",_enter)
 use_button = _button(second,"使用 / 开火",_use)
 leave_button=_button(second,"离开",_exit)
 var third := HBoxContainer.new()
 tester_controls=third
 layout.add_child(third)
 _button(third,"步兵测试靶经过",func(): _spawn_tester("person"))
 _button(third,"车辆测试靶经过",func(): _spawn_tester("vehicle"))
 var earth := HBoxContainer.new()
 layout.add_child(earth)
 engineering_controls.append(earth)
 _button(earth,"浅挖 0.22m",func(): _begin_ground_selection("dig"))
 _button(earth,"回填地坑",func(): _begin_ground_selection("fill"))
 _button(earth,"取消土方",func(): _cancel_ground_work("已取消土方任务"))
 support_controls=HBoxContainer.new()
 layout.add_child(support_controls)
 _button(support_controls,"联络：请求掩护",func():request_support("cover"))
 _button(support_controls,"联络：工程支援",func():request_support("engineering"))
 status = Label.new()
 status.add_theme_font_size_override("font_size",14)
 layout.add_child(status)
 panel.hide()
 occupied_controls=HBoxContainer.new()
 occupied_controls.position=Vector2(230,247)
 if main.font: occupied_controls.add_theme_font_override("font",main.font)
 main.hud.add_child(occupied_controls)
 occupied_use_button = _button(occupied_controls,"观察视野",_use)
 _button(occupied_controls,"离开工事",_exit)
 occupied_controls.hide()

func _button(parent: Node, label: String, action: Callable) -> Button:
 var button := Button.new()
 button.text = label
 button.custom_minimum_size.y = 38
 button.pressed.connect(action)
 parent.add_child(button)
 return button

func _say(text: String) -> void:
 if is_instance_valid(main.battle_controls):main.battle_controls.show_notice(text)
 main.message = text
 main.refresh_hud()

func _input(event: InputEvent) -> void:
 if not _engineering_available() or not selecting: return
 var pointer := Vector2.ZERO
 var pressed := false
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
  pointer = event.position
  pressed = true
 elif event is InputEventScreenTouch and event.pressed:
  pointer = event.position
  pressed = true
 var hovering := event is InputEventMouseMotion or event is InputEventScreenDrag
 if not pressed and not hovering: return
 if hovering:
  if Time.get_ticks_msec()-preview_last_ms<100: return
  pointer=event.position
 preview_last_ms=Time.get_ticks_msec()
 # Leave HUD presses to the normal Control input dispatch.
 if toggle_button.get_global_rect().has_point(pointer) or (panel.visible and panel.get_global_rect().has_point(pointer)): return
 if _ai_mode():
  if pointer.y<120 or pointer.y>get_viewport().get_visible_rect().size.y-65:return
 else:
  if pointer.y < 240 or pointer.y > 535 or pointer.x > 1050: return
 var start: Vector3 = main.camera.project_ray_origin(pointer)
 var direction: Vector3 = main.camera.project_ray_normal(pointer)
 var query := PhysicsRayQueryParameters3D.create(start,start+direction*160.0,8)
 var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
 get_viewport().set_input_as_handled()
 if hit.is_empty():
  if is_instance_valid(placement_preview): placement_preview.hide()
  if pressed: _say("这里没有可施工地表")
  return
 selected_position = hit.position
 if terrain_work_kind!="":
  if not pressed:return
  selecting=false
  _start_ground_work(terrain_work_kind,selected_position)
  terrain_work_kind=""
  return
 preview_active=true
 _update_preview()
 if not pressed: return
 site_selected = true
 selecting = false
 if _ai_mode() and is_instance_valid(main.battle_controls):main.battle_controls.set_menu(true)
 panel.show()
 _say("绿色范围可建，点击建造" if preview_issue=="" else "红色范围不可建："+preview_issue)

func _build() -> void:
 if not _engineering_available(): return
 if not site_selected: _say("请先点“选择地面”再点地面"); return
 var preset: String = preset_ids[presets.selected]
 if _ai_mode():
  _connect_ai_events()
  if not ai_build.is_empty(): _say("友军工兵已有施工任务，可先取消"); return
  ai_builder=_choose_ai_builder()
  if not is_instance_valid(ai_builder) or ai_builder.brain.hp<=0.0 or ai_builder.embarked:
   ai_builder=null
   _say("没有空闲且存活的友军，工程暂缓")
   return
 var issue := _placement_issue(preset,selected_position)
 if issue!="":
  _say(issue)
  if preview_active: _update_preview()
  return
 var radius: float=Rules.PRESETS[preset].radius
 var center_y: float=main.terrain_height(selected_position.x,selected_position.z)
 # Assign the single infantry worker to the validated site.
 selected_position.y = center_y
 var placement_yaw := 0.0
 if preset=="foxhole" and is_instance_valid(main.target) and main.target_is_visible():
  var facing: Vector3=main.target.global_position-selected_position
  placement_yaw=atan2(-facing.x,-facing.z)
 var result := model.command({"op":"place","yaw":placement_yaw,"preset":preset,"position":[selected_position.x,selected_position.y,selected_position.z],"site_valid":true,"slope_degrees":0,"excavation_reserved":main.has_method("damage_terrain")})
 if result.kind == "refused":
  if result.reason == "resources": _say("材料不足：当前 %d，需要 %d。工程暂缓。" % [model.resources,Rules.PRESETS[preset].cost])
  else: _say("无法放置："+str(result.reason))
  return
 _hide_preview()
 selected_id = result.id
 var view := View.new()
 main.stage.add_child(view)
 views[selected_id] = view
 view.sync(model.structures[selected_id])
 if _ai_mode():
  var worksite:=selected_position+Vector3(0,0,radius+0.65)
  worksite.y=main.terrain_height(worksite.x,worksite.z)+0.12
  ai_build={"id":selected_id,"actor_id":str(ai_builder.brain.actor_id),"preset":preset,"worksite":worksite,"phase":"travelling","start_hp":float(ai_builder.brain.hp)}
  ai_builder_was_processing=ai_builder.is_physics_processing()
  ai_builder.set_meta("construction_order",true)
  if not ai_builder.order_build(worksite,preset,true):
   _abort_ai_build("工兵拒绝任务，材料已返还")
   return
  _refresh_choices()
  panel.hide()
  _say("友军自主决定施工，正在前往工位；实际到达后才开始")
  return
 outside_hero = main.hero.global_transform
 main.hero.global_position = selected_position+Vector3(0,0,radius+0.4)
 model.command({"op":"start","id":selected_id})
 _refresh_choices()
 _say("单名步兵施工中："+str(Rules.PRESETS[preset].label))

func _cancel() -> void:
 if not terrain_job.is_empty():
  _cancel_ground_work("已取消土方任务");return
 if not _engineering_available(): return
 if not ai_build.is_empty():
  _abort_ai_build("已取消友军施工，材料已返还")
  return
 var id := model.worker_busy if model.worker_busy != "" else selected_id
 if not model.structures.has(id): return
 var result := model.command({"op":"cancel","id":id})
 if result.kind == "refused": _say("无法取消："+str(result.reason)); return
 if is_instance_valid(views.get(id)): views[id].queue_free()
 views.erase(id)
 if is_instance_valid(main.hero): main.hero.global_transform = outside_hero
 _refresh_choices()
 _say("已取消施工并返还材料")

func _enter() -> void:
 if main == null or main.garage or main.unit != 2: return
 if not model.structures.has(selected_id): return
 var s: Dictionary = model.structures[selected_id]
 if s.preset == "foxhole" and not excavation_ok.get(selected_id,false): _say("真实地面开挖未成功，禁止进入"); return
 var result := model.command({"op":"enter","id":selected_id})
 if result.kind == "refused": _say("无法进入："+str(result.reason)); return
 if main.scoped: main.toggle_scope()
 outside_hero = main.hero.global_transform
 outside_camera = main.camera.global_transform
 var view: Node3D = views[selected_id]
 view.sync(s)
 panel.hide()
 _hide_preview()
 _refresh_use_labels()
 occupied_controls.show()
 main.hero.visible = false
 main.hero.global_position = view.use_position.global_position
 if s.preset == "foxhole": main.hero.global_position.y = main.terrain_height(float(s.position[0]),float(s.position[2]))
 main.camera.global_position = view.observation.global_position
 main.weapon_override = view.muzzle if Rules.PRESETS[s.preset].weapon != "" else null
 main.update_visibility()
 # Initial alignment is permitted only for an identified target; later use never re-aims.
 if is_instance_valid(main.target) and main.target_is_visible():
  main.camera.look_at(main.target.global_position+Vector3(0,1,0))
  if Rules.PRESETS[s.preset].weapon != "": view.aim_at(main.target.global_position+Vector3(0,1,0))
  else: main.aim_weapon(main.target.global_position+Vector3(0,1,0),true)
 if s.preset == "mortar":
  _place_mortar_observer(view)
  main.update_visibility()
 _say("迫击炮观察视角；视野仍受天气和遮挡限制" if s.preset=="mortar" else "已进入"+str(Rules.PRESETS[s.preset].label)+"；视野仍受天气和遮挡限制")

func _place_mortar_observer(view: Node3D) -> void:
 # Fixed ground-level oblique demo view, independent of firing and target identification.
 var forward: Vector3=-view.muzzle.global_basis.z
 forward.y=0.0
 forward=forward.normalized()
 var side: Vector3=forward.cross(Vector3.UP)
 var origin: Vector3=view.observation.global_position
 var desired: Vector3=origin-forward*6.0+side*7.0
 desired.y=main.terrain_height(desired.x,desired.z)+float(Rules.PRESETS.mortar.observe_y)
 var query:=PhysicsRayQueryParameters3D.create(origin,desired,9)
 var hit: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(query)
 if not hit.is_empty():
  desired=hit.position+hit.normal*0.25
 main.camera.global_position=desired
 var look_point: Vector3=view.global_position+forward*5.0
 look_point.y=main.terrain_height(look_point.x,look_point.z)+2.0
 main.camera.look_at(look_point)

func _use() -> void:
 if main == null or main.garage or main.unit != 2: return
 var id: String = model.occupied
 if id == "": _say("请先进入已完成工事"); return
 if cooldown > 0.0: return
 var result := model.command({"op":"use","id":id})
 if result.kind != "use_requested": return
 var view: Node3D = views[id]
 main.weapon_override = view.muzzle if result.weapon != "" else null
 # Blind fire uses the current visible barrel direction; identification alone needs LOS.
 match result.weapon:
  "mg_direct": main.fire_mg(); cooldown=0.15
  "at_direct": main.fire_cannon(); cooldown=1.0
  "mortar_arc":
   if main.has_method("fire_mortar"): main.fire_mortar(view.muzzle); cooldown=1.2
  _: main.update_visibility(); _say("正在观察 / 利用掩体；并非全图透视")

func _exit() -> void:
 if main == null or main.garage or main.unit != 2: return
 if model.occupied == "": return
 model.command({"op":"exit","id":model.occupied})
 occupied_controls.hide()
 if main.scoped: main.toggle_scope()
 main.weapon_override = null
 main.hero.global_transform = outside_hero
 main.hero.visible = true
 main.camera.global_transform = outside_camera
 main.update_visibility()
 _say("已离开工事")

func _process(delta: float) -> void:
 if _ai_mode() and not _battle_active():
  planner.pending=""
  if not terrain_job.is_empty():_cancel_ground_work("战斗结束，未完成土方已取消")
  if not ai_build.is_empty():_abort_ai_build("战斗结束，未完成工程已取消，材料已返还")
 _tick_ground_work(delta)
 if main == null or not is_instance_valid(panel): return
 _connect_ai_events()
 var active: bool = _engineering_available()
 toggle_button.text="联络友军" if _ai_mode() else "工事 / 工程试验"
 for control in engineering_controls:control.visible=not _ai_mode()
 support_controls.visible=_ai_mode()
 build_button.text="建造"
 toggle_button.visible = active
 entry_button.visible=not _ai_mode()
 use_button.visible=not _ai_mode()
 leave_button.visible=not _ai_mode()
 tester_controls.visible=not _ai_mode()
 occupied_controls.visible = active and model.occupied != ""
 if not active: panel.hide(); selecting=false; _hide_preview(); return
 if _ai_mode() and autonomous_enabled:_tick_autonomous(delta)
 cooldown = maxf(0,cooldown-delta)
 if not ai_build.is_empty() and (not is_instance_valid(ai_builder) or ai_builder.brain.hp<float(ai_build.start_hp) or ai_builder.embarked):
  _abort_ai_build("工兵受伤、失能或离场，施工已取消，材料已返还")
 if not ai_build.is_empty() and is_instance_valid(main.terrain_damage) and main.terrain_damage.has_method("is_position_loaded"):
  var build_state: Dictionary=model.structures.get(str(ai_build.id),{})
  if not build_state.is_empty():
   var coordinates: Array=build_state.position
   if not main.terrain_damage.is_position_loaded(Vector3(coordinates[0],coordinates[1],coordinates[2])):
    _abort_ai_build("施工地块已卸载，工程已取消，材料已返还")
 if not ai_build.is_empty():
  ai_build["travel_time"]=float(ai_build.get("travel_time",0.0))+delta
  if ai_build.phase=="travelling" and float(ai_build.travel_time)>45.0:
   _abort_ai_build("工兵无法到达工位，工程已取消，材料已返还")
  elif ai_build.phase=="building" and ai_builder.global_position.distance_to(ai_build.worksite)>1.5:
   _abort_ai_build("工兵已离开工位，工程已取消，材料已返还")
 model.tick(delta)
 for event in model.drain_events():
  if event.kind == "excavation_requested":
   if event.preset == "foxhole":
    var p: Array = model.structures[event.id].position
    var result = main.damage_terrain(Vector3(p[0],p[1],p[2]),"dig")
    excavation_ok[event.id] = bool(result.get("ok",false)) if result is Dictionary else (result == true)
    model.command({"op":"confirm_excavation","id":event.id,"success":excavation_ok[event.id]})
    if not excavation_ok[event.id]: _say("开挖失败，工事未完成；可取消")
  elif event.kind == "finished":
   if not ai_build.is_empty() and str(event.id)==str(ai_build.id):
    _release_ai_builder()
    _say(str(Rules.PRESETS[event.preset].label)+"已由友军工兵建成")
    continue
   _say(str(Rules.PRESETS[event.preset].label)+("已设好，可测试" if event.preset=="barricade" or str(event.preset).begins_with("mine_") else "完成，可进入使用"))
  elif event.kind == "mine_triggered":
   var affected: Node3D=null
   var target_id:=str(event.get("target_id",""))
   if target_id=="construction_test_actor" and is_instance_valid(tester):
    affected=tester
    tester_hp=maxi(0,tester_hp-int(event.game_damage))
    tester.set_meta("game_hp",tester_hp)
    tester.set_meta("last_mine",event.id)
   elif is_instance_valid(main.ai_host) and main.ai_host.actors.has(target_id):
    affected=main.ai_host.actors[target_id]
    # This API updates the existing canonical person shared with vehicle crew.
    main.ai_host.apply_actor_damage(target_id,float(event.game_damage),"mine:"+str(event.id))
   var p: Array = event.position
   if main.has_method("explode_terrain"): main.explode_terrain(Vector3(p[0],p[1],p[2]),0.3)
   elif main.has_method("damage_terrain"): main.damage_terrain(Vector3(p[0],p[1],p[2]),"crater")
   if is_instance_valid(affected) and affected.visible and main.visibility_for_node(affected)=="visible":
    _say(("测试靶" if target_id=="construction_test_actor" else "步兵")+"实际经过触发地雷：一次性消耗，虚构伤害 %d，地面凹坑" % event.game_damage)
   else:
    _say("远处发生爆炸，目标状态无法确认")
 for id in views:
  if is_instance_valid(views[id]) and model.structures.has(id):
   views[id].sync(model.structures[id])
   _register_built_fortification(str(id))
 if model.occupied != "" and views.has(model.occupied):
  var s: Dictionary = model.structures[model.occupied]
  if Rules.PRESETS[s.preset].weapon != "": main.weapon_override=views[model.occupied].muzzle
 var detail := "友军自主评估工程；联络仅提出支援需求" if _ai_mode() else "选择地面 → 建造 → 进入 → 使用 → 离开"
 if not terrain_job.is_empty():detail=("挖坑" if terrain_job.kind=="dig" else "回填")+" · "+str(terrain_job.phase)
 if not ai_build.is_empty() and ai_build.phase=="travelling": detail="友军工兵前往自主选定的工位；受伤会取消"
 if model.worker_busy != "":
  var s: Dictionary = model.structures[model.worker_busy]
  detail = "%s · %d%%" % [Rules.PRESETS[s.preset].label,100*int(s.elapsed_ms)/int(Rules.PRESETS[s.preset].time_ms)]
 elif selected_id != "" and model.structures.has(selected_id): detail += " / "+str(model.structures[selected_id].state)
 status.text = "材料 %d / %s" % [model.resources,detail]
 var enterable := false
 var selected_has_use := false
 if model.structures.has(selected_id):
  var state: Dictionary=model.structures[selected_id]
  selected_has_use=state.preset!="barricade" and not str(state.preset).begins_with("mine_")
  enterable=selected_has_use and state.state=="finished"
 entry_button.disabled=_ai_mode() or not enterable
 use_button.disabled=_ai_mode() or model.occupied=="" or not selected_has_use
 _refresh_use_labels()

func _use_label(preset: String) -> String:
 match preset:
  "mg": return "机枪射击"
  "at": return "反坦克炮射击"
  "mortar": return "迫击炮射击"
  _: return "观察视野"

func _refresh_use_labels() -> void:
 var id: String=model.occupied if model.occupied!="" else selected_id
 var preset: String=str(model.structures[id].preset) if model.structures.has(id) else ""
 var label: String=_use_label(preset)
 use_button.text=label
 occupied_use_button.text=label

func _refresh_choices() -> void:
 existing.clear()
 for id in model.structures:
  existing.add_item(str(Rules.PRESETS[model.structures[id].preset].label)+" #"+id.trim_prefix("construction_"))
  existing.set_item_metadata(existing.item_count-1,id)
  if id == selected_id: existing.select(existing.item_count-1)
 if not model.structures.has(selected_id): selected_id=str(model.structures.keys()[0]) if not model.structures.is_empty() else ""

func _spawn_tester(kind: String) -> void:
 if main == null or main.garage or main.unit != 2: return
 if not model.structures.has(selected_id): _say("请先完成地雷或拒马"); return
 var s: Dictionary = model.structures[selected_id]
 if s.state not in ["armed","finished"] or (not s.preset.begins_with("mine_") and s.preset != "barricade"):
  _say("请选择已就绪的地雷或拒马"); return
 if is_instance_valid(tester): tester.queue_free()
 tester = CharacterBody3D.new()
 tester_kind = kind
 tester.collision_layer = 16 if kind == "person" else 32
 tester.collision_mask = 1|8
 tester.name = "ConstructionTestActor"
 tester.set_meta("actor_kind",kind)
 tester_hp=10
 tester.set_meta("game_hp",tester_hp)
 var size := Vector3(0.45,1.6,0.45) if kind == "person" else Vector3(1.0,0.65,1.5)
 tester_size=size
 var mesh := MeshInstance3D.new()
 var box := BoxMesh.new()
 box.size=size
 mesh.mesh=box
 mesh.position.y=size.y/2
 var mat := StandardMaterial3D.new()
 mat.albedo_color=Color("66c8bc") if kind=="person" else Color("d8b365")
 mesh.material_override=mat
 tester.add_child(mesh)
 var shape := CollisionShape3D.new()
 var box_shape := BoxShape3D.new()
 box_shape.size=size
 shape.shape=box_shape
 shape.position.y=size.y/2
 tester.add_child(shape)
 main.stage.add_child(tester)
 var p: Array=s.position
 var center := Vector3(p[0],p[1],p[2])
 var route_found := false
 for approach in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
  var start: Vector3 = center+approach*3.0
  start.y=main.terrain_height(start.x,start.z)+0.08
  var direction: Vector3 = -approach
  var yaw := atan2(-direction.x,-direction.z)
  var probe := PhysicsShapeQueryParameters3D.new()
  probe.shape=box_shape
  probe.collision_mask=9
  probe.transform=Transform3D(Basis(Vector3.UP,yaw),start+Vector3.UP*size.y/2.0)
  var excluded: Array[RID] = []
  if is_instance_valid(main.terrain_damage) and is_instance_valid(main.terrain_damage.body): excluded.append(main.terrain_damage.body.get_rid())
  for ground in get_tree().get_nodes_in_group("drivable_ground"):
   if ground is CollisionObject3D:excluded.append(ground.get_rid())
  # Only preflight ignores the obstacle being tested; runtime collision still includes it.
  if s.preset == "barricade" and views.has(selected_id): _collect_body_rids(views[selected_id],excluded)
  probe.exclude=excluded
  var space: PhysicsDirectSpaceState3D=main.get_world_3d().direct_space_state
  if not space.intersect_shape(probe,1).is_empty(): continue
  probe.motion=direction*6.0
  var fractions: PackedFloat32Array=space.cast_motion(probe)
  if not fractions.is_empty() and fractions[0]<0.99: continue
  tester.position=start
  tester.rotation.y=yaw
  tester_direction=direction
  route_found=true
  break
 if not route_found:
  tester.queue_free()
  tester=null
  _say("测试路径被步兵、目标或道具占用，请换一个空旷施工点")
  return
 tester_distance=0
 tester_ground_exclusions.clear()
 _collect_body_rids(main.stage,tester_ground_exclusions)
 if is_instance_valid(main.terrain_damage) and is_instance_valid(main.terrain_damage.body): tester_ground_exclusions.erase(main.terrain_damage.body.get_rid())
 _say("测试靶正在实际移动；碰到拒马停止，进入匹配雷区才触发")

func _physics_process(delta: float) -> void:
 _check_ai_mines()
 if not is_instance_valid(tester) or tester_distance >= 6.0: return
 tester.position.y = _tester_ground_height(tester.position)+0.08
 var motion := tester_direction*delta*1.6
 var next_position := tester.position + motion
 motion.y = _tester_ground_height(next_position)+0.08-tester.position.y
 var collision := tester.move_and_collide(motion)
 tester_distance += motion.length()
 if collision:
  tester_distance=6
  tester.set_meta("blocked_by_name",str(collision.get_collider().name))
  tester.set_meta("blocked_normal",collision.get_normal())
  tester.set_meta("blocked_by_construction",str(collision.get_collider().get_meta("construction_id","")))
  _say("测试靶被真实碰撞阻挡")
 for id in model.structures:
  var s: Dictionary = model.structures[id]
  if s.state != "armed": continue
  var p: Array=s.position
  if Vector2(tester.global_position.x-p[0],tester.global_position.z-p[2]).length() <= 0.7 and absf(tester.global_position.y-float(p[1])) < 1.0:
   model.command({"op":"trigger","id":id,"actor_kind":tester_kind,"target_id":"construction_test_actor"})

func on_stage_reset() -> void:
 planner.reset()
 if main!=null and is_instance_valid(main.ai_host):
  for id in registered_forts:main.ai_host.fortifications.erase("built_"+str(id))
 registered_forts.clear()
 _cancel_ground_work("",false)
 terrain_work_kind=""
 _release_ai_builder()
 if main != null:
  if model.occupied != "" and is_instance_valid(main.camera): main.camera.global_transform=outside_camera
  main.weapon_override=null
  if is_instance_valid(main.hero): main.hero.visible=true
 for view in views.values():
  if is_instance_valid(view): view.queue_free()
 views.clear()
 model.command({"op":"reset"})
 model.drain_events()
 selected_id=""
 excavation_ok.clear()
 site_selected=false
 selecting=false
 _hide_preview()
 if is_instance_valid(placement_preview): placement_preview.queue_free()
 placement_preview=null
 if is_instance_valid(tester): tester.queue_free()
 tester=null
 if is_instance_valid(existing): _refresh_choices()
 if is_instance_valid(panel): panel.hide()
 if is_instance_valid(occupied_controls): occupied_controls.hide()

func _collect_body_rids(node: Node, result: Array[RID]) -> void:
 if node is CollisionObject3D: result.append(node.get_rid())
 for child in node.get_children(): _collect_body_rids(child,result)

func _tester_ground_height(at: Vector3) -> float:
 # Ground support is sampled under the whole footprint, using ONLY terrain.
 # Prop tops and barricades never become step-up surfaces for this test actor.
 var height: float = -INF
 for x in [-0.5,0.0,0.5]:
  for z in [-0.5,0.0,0.5]:
   var point: Vector3=at+tester.basis*Vector3(x*tester_size.x,0,z*tester_size.z)
   var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,40,point.z),Vector3(point.x,-40,point.z),8)
   ray.exclude=tester_ground_exclusions
   var hit: Dictionary=main.get_world_3d().direct_space_state.intersect_ray(ray)
   if not hit.is_empty(): height=maxf(height,float(hit.position.y))
 return height if is_finite(height) else at.y

func _placement_issue(preset: String, at: Vector3, reserved_id: String = "") -> String:
 # Validate five support samples, player distance, and nearby opaque structures.
 var radius: float = Rules.PRESETS[preset].radius
 var center_y: float = main.terrain_height(at.x,at.z)
 # Only the tagged deformable ground is buildable; arch/prop tops are not ground.
 if is_instance_valid(main.terrain_damage):
  if main.terrain_damage.has_method("is_position_loaded") and not main.terrain_damage.is_position_loaded(at):return "施工地块未加载"
  var ground_y: float = main.terrain_damage.terrain_height(at)
  if not is_finite(ground_y) or absf(ground_y-center_y)>0.25:
   return "这里是道具或不支持的表面，请选择地面"
 var max_delta := 0.0
 for offset in [Vector2(radius,0),Vector2(-radius,0),Vector2(0,radius),Vector2(0,-radius)]:
  var point := at + Vector3(offset.x,0,offset.y)
  var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*4,point-Vector3.UP*4,8)
  var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
  if hit.is_empty(): return "工事边缘缺少地面支撑"
  max_delta = maxf(max_delta,absf(float(hit.position.y)-center_y))
 if max_delta > radius*tan(deg_to_rad(12.0)): return "地面起伏过大，拒绝施工"
 if is_instance_valid(main.target) and Vector2(at.x-main.target.position.x,at.z-main.target.position.z).length()<radius+2:
  return "施工点与测试目标重叠"
 if model.worker_busy != "" or model.occupied != "": return "请先完成施工或离开工事"
 var clearance := PhysicsShapeQueryParameters3D.new()
 var volume := BoxShape3D.new()
 var clearance_height := 5.0 if preset == "tower" else 1.8
 volume.size = Vector3(radius*1.6,clearance_height,radius*1.6)
 clearance.shape = volume
 clearance.transform = Transform3D(Basis.IDENTITY,Vector3(at.x,center_y+clearance_height/2.0+0.15,at.z))
 clearance.collision_mask=9|128
 var ignored: Array[RID]=[]
 if is_instance_valid(main.terrain_damage) and is_instance_valid(main.terrain_damage.body): ignored.append(main.terrain_damage.body.get_rid())
 for ground in get_tree().get_nodes_in_group("drivable_ground"):
  if ground is CollisionObject3D:ignored.append(ground.get_rid())
 if _ai_mode():
  var worker: CharacterBody3D=ai_builder if is_instance_valid(ai_builder) else (terrain_worker if is_instance_valid(terrain_worker) else _choose_ai_builder())
  # The assigned worker physically vacates the footprint for an outside work position.
  if is_instance_valid(worker): ignored.append(worker.get_rid())
 clearance.exclude=ignored
 if not main.get_world_3d().direct_space_state.intersect_shape(clearance,1).is_empty():
  return "施工体积与现有道具或工事相交"
 if reserved_id=="" and model.resources<int(Rules.PRESETS[preset].cost): return "材料不足：当前 %d，需要 %d。工程暂缓。" % [model.resources,Rules.PRESETS[preset].cost]
 for other in model.structures.values():
  if str(other.id)==reserved_id: continue
  if other.state=="placement": return "已有待施工工事"
  if Vector2(at.x-float(other.position[0]),at.z-float(other.position[2])).length()<radius+float(Rules.PRESETS[other.preset].radius): return "与现有工事范围重叠"
 return ""

func _toggle_panel() -> void:
 selecting=false
 panel.visible=not panel.visible
 if not panel.visible: _hide_preview()

func _begin_selection() -> void:
 terrain_work_kind=""
 if not _engineering_available(): return
 selecting=true
 preview_active=true
 panel.hide()
 if _ai_mode() and is_instance_valid(main.battle_controls):main.battle_controls.set_menu(false)
 if site_selected: _update_preview()
 _say("工程选址：绿圈可建，红圈不可建；点地面确认范围")

func _hide_preview() -> void:
 selecting=false
 preview_active=false
 if is_instance_valid(placement_preview): placement_preview.hide()

func _update_preview() -> void:
 if not preview_active: return
 var preset: String=preset_ids[presets.selected]
 preview_issue=_placement_issue(preset,selected_position)
 if not is_instance_valid(placement_preview):
  placement_preview=MeshInstance3D.new()
  placement_preview.name="EngineeringFootprintOnly"
  placement_preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  main.stage.add_child(placement_preview)
 placement_preview.visible=true
 placement_preview.position=selected_position
 var radius: float=Rules.PRESETS[preset].radius
 var mat:=StandardMaterial3D.new()
 mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.cull_mode=BaseMaterial3D.CULL_DISABLED
 mat.albedo_color=Color(0.15,1.0,0.5,0.9) if preview_issue=="" else Color(1.0,0.18,0.12,0.9)
 var ring:=ImmediateMesh.new()
 ring.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP,mat)
 for i in range(65):
  var angle:=TAU*float(i)/64.0
  for r in [maxf(0.1,radius-0.16),radius]:
   var x: float=cos(angle)*r
   var z: float=sin(angle)*r
   var y: float=main.terrain_height(selected_position.x+x,selected_position.z+z)-selected_position.y+0.075
   ring.surface_add_vertex(Vector3(x,y,z))
 ring.surface_end()
 placement_preview.mesh=ring

func _ai_mode() -> bool:
 return main != null and main.game_mode=="skirmish" and not main.garage

func _engineering_available() -> bool:
 return main != null and not main.garage and (main.unit==2 or _ai_mode()) and (not _ai_mode() or _battle_active())

func _connect_ai_events() -> void:
 if not is_instance_valid(main.ai_host) or connected_ai_host==main.ai_host: return
 connected_ai_host=main.ai_host
 if not connected_ai_host.event_emitted.is_connected(_on_ai_event): connected_ai_host.event_emitted.connect(_on_ai_event)

func _on_ai_event(event: Dictionary) -> void:
 if event.get("kind","")!="build_requested" or ai_build.is_empty() or not _ai_mode() or not _battle_active(): return
 if str(event.get("actor_id",""))!=str(ai_build.actor_id) or str(event.get("preset",""))!=str(ai_build.preset): return
 if not is_instance_valid(ai_builder) or ai_builder.brain.hp<=0.0: return
 if ai_builder.global_position.distance_to(ai_build.worksite)>1.0: return
 if ai_build.phase!="travelling": return
 var state: Dictionary=model.structures[ai_build.id]
 var point:=Vector3(state.position[0],state.position[1],state.position[2])
 var issue:=_placement_issue(str(ai_build.preset),point,str(ai_build.id))
 if issue!="": _abort_ai_build("工位到达后复核失败："+issue); return
 # The actor reached the approved work position through its CharacterBody movement.
 # It remains physically present and damageable, but does not move/fire while working.
 var result:=model.command({"op":"start","id":ai_build.id})
 if result.kind!="building_started": _abort_ai_build("工兵无法开始施工，材料已返还"); return
 ai_build.phase="building"
 ai_builder.velocity=Vector3.ZERO
 ai_builder.set_physics_process(false)
 _say("友军工兵已实际到达，正在施工："+str(Rules.PRESETS[ai_build.preset].label))

func _release_ai_builder() -> void:
 if is_instance_valid(ai_builder) and not ai_build.is_empty():
  ai_builder.set_meta("construction_order",false)
  ai_builder.brain.order.clear()
  ai_builder.set_physics_process(ai_builder_was_processing)
 ai_builder=null
 ai_build.clear()

func _abort_ai_build(reason: String) -> void:
 if not ai_build.is_empty():
  var id:=str(ai_build.id)
  if model.structures.has(id): model.command({"op":"cancel","id":id})
  if is_instance_valid(views.get(id)): views[id].queue_free()
  views.erase(id)
 _release_ai_builder()
 _refresh_choices()
 _say(reason)

func _check_ai_mines() -> void:
 if not _ai_mode() or not is_instance_valid(main.ai_host): return
 var actor_ids: Array=main.ai_host.actors.keys()
 actor_ids.sort()
 for mine_id in model.structures:
  var mine: Dictionary=model.structures[mine_id]
  if mine.state!="armed" or mine.preset=="mine_vehicle": continue
  var p: Array=mine.position
  for actor_id in actor_ids:
   var actor=main.ai_host.actors[actor_id]
   if not is_instance_valid(actor) or actor.embarked or actor.brain.hp<=0.0: continue
   var person: Dictionary=main.ai_host.persons.get(actor_id,{})
   if not person.get("alive",false) or float(person.get("hp",0))<=0.0: continue
   var point: Vector3=actor.global_position
   if Vector2(point.x-float(p[0]),point.z-float(p[2])).length()>0.7 or absf(point.y-float(p[1]))>=1.0: continue
   model.command({"op":"trigger","id":mine_id,"actor_kind":"person","target_id":str(actor_id)})
   break

func _choose_ai_builder() -> CharacterBody3D:
 if not is_instance_valid(main.ai_host): return null
 var commander_id:=""
 if is_instance_valid(main.crew_host):
  var seats: Dictionary=main.crew_host.registry.vehicle(main.crew_host.vehicle_id).get("seats",{})
  for index in main.crew_host.person_ids.size():
   if str(seats.get(str(index),{}).get("role",""))=="commander":commander_id=str(main.crew_host.person_ids[index]);break
 var ids: Array=main.ai_host.actors.keys()
 ids.sort()
 var nearest: CharacterBody3D=null
 var nearest_distance:=INF
 for id in ids:
  if str(id)==commander_id:continue
  var actor=main.ai_host.actors[id]
  if not is_instance_valid(actor) or actor.embarked or actor.brain.hp<=0.0: continue
  if bool(actor.get_meta("player_controlled",false)):continue
  if str(actor.brain.team_id)!=str(main.ai_host.player_team): continue
  var person: Dictionary=main.ai_host.persons.get(id,{})
  if not bool(person.get("alive",false)) or float(person.get("hp",0))<=0: continue
  if bool(actor.get_meta("construction_order",false)) or not actor.get_meta("crew_return_order",{}).is_empty() or not actor.brain.order.is_empty() or not actor.is_physics_processing(): continue
  var distance: float=actor.global_position.distance_squared_to(main.hero.global_position)
  if distance<nearest_distance:
   nearest=actor
   nearest_distance=distance
 return nearest


func _begin_ground_selection(kind: String) -> void:
 if not _ai_mode():_say("土方任务需要实际下车工兵；请进入交战模式");return
 if not terrain_job.is_empty() or not ai_build.is_empty():_say("已有工程任务，请先完成或取消");return
 terrain_work_kind=kind
 selecting=true
 preview_active=false
 panel.hide()
 if is_instance_valid(main.battle_controls):main.battle_controls.set_menu(false)
 _say("点选地面："+("浅挖约 0.22 米" if kind=="dig" else "回填已有地坑"))

func _start_ground_work(kind: String, point: Vector3) -> bool:
 if not _ai_mode() or not _battle_active() or not terrain_job.is_empty() or not ai_build.is_empty():return false
 if model.resources<1:_say("工程材料不足，土方暂缓");return false
 if not is_instance_valid(main.terrain_damage) or not main.terrain_damage.has_method("sample_height"):
  _say("土方任务仅在大地图交战中可用");return false
 if not main.terrain_damage.is_position_loaded(point):_say("该地块尚未加载，请靠近后再施工");return false
 var floor_y: float=main.terrain_damage.sample_height(point.x,point.z)
 if not is_finite(floor_y) or absf(floor_y-point.y)>.3:_say("请选真实地面，不能在道具顶部开挖");return false
 if Vector2(point.x-main.hero.position.x,point.z-main.hero.position.z).length()<3.2:_say("施工范围离战车太近");return false
 terrain_worker=_choose_ai_builder()
 if not is_instance_valid(terrain_worker):_say("没有空闲且存活的友军，土方暂缓");return false
 var approach: Vector3=terrain_worker.global_position-point
 approach.y=0
 if approach.length()<.2:approach=Vector3.RIGHT
 var worksite: Vector3=point+approach.normalized()*2.2
 worksite.y=main.terrain_height(worksite.x,worksite.z)+.12
 terrain_worker_processing=terrain_worker.is_physics_processing()
 terrain_worker.set_meta("construction_order",true)
 model.resources-=1
 terrain_job_serial+=1
 terrain_job={"serial":terrain_job_serial,"kind":kind,"position":Vector3(point.x,floor_y,point.z),"worksite":worksite,"phase":"前往工位","elapsed":0.0,"start_hp":float(terrain_worker.brain.hp),"travel_time":0.0,"reserved_material":1,"committed":false}
 if not terrain_worker.order_build(worksite,"terrain_"+kind,true):
  _cancel_ground_work("工兵无法接受土方任务");return false
 _say("工兵前往工位，实际到达后施工4秒")
 return true

func _ground_committed(result: Dictionary) -> void:
 if terrain_job.is_empty() or int(result.get("serial",-1))!=int(terrain_job.get("edit_serial",-2)):return
 terrain_job.committed=true
 terrain_job.phase="完成同步"
 terrain_job.elapsed=0.0

func _tick_ground_work(delta: float) -> void:
 if terrain_job.is_empty():return
 if not _battle_active():_cancel_ground_work("战斗结束，未完成土方已取消");return
 if not is_instance_valid(terrain_worker) or terrain_worker.embarked or terrain_worker.brain.hp<float(terrain_job.start_hp) or terrain_worker.brain.hp<=0:
  _cancel_ground_work("工兵受伤、失能或离场，土方已取消");return
 if terrain_job.phase=="前往工位":
  terrain_job.travel_time+=delta
  if terrain_job.travel_time>45:
   _cancel_ground_work("工兵无法到达，土方已取消");return
  var site: Vector3=terrain_job.worksite
  if Vector2(terrain_worker.position.x-site.x,terrain_worker.position.z-site.z).length()>.85:return
  if absf(terrain_worker.position.y-site.y)>1.2:return
  var issue:=_ground_site_issue()
  if issue!="":_cancel_ground_work("工位复核失败："+issue);return
  terrain_job.phase="施工中"
  terrain_worker.velocity=Vector3.ZERO
  terrain_worker.set_physics_process(false)
  _say("工兵已到达，正在"+("挖掘" if terrain_job.kind=="dig" else "回填"))
 elif terrain_job.phase=="施工中":
  if terrain_worker.global_position.distance_to(terrain_job.worksite)>1.5:
   _cancel_ground_work("工兵离开工位，土方已取消");return
  terrain_job.elapsed+=delta
  if terrain_job.elapsed<4.0:return
  var issue:=_ground_site_issue()
  if issue!="":_cancel_ground_work("施工复核失败："+issue);return
  var world=main.terrain_damage
  if not world.terrain_changed.is_connected(_ground_committed):world.terrain_changed.connect(_ground_committed)
  var result: Dictionary=world.apply_command(terrain_job.position,str(terrain_job.kind))
  if not bool(result.get("ok",false)):
   _cancel_ground_work("土方失败："+str(result.get("error","地形拒绝")));return
  terrain_job.edit_serial=int(result.serial)
  terrain_job.phase="地形同步"
  world.flush_updates()
 elif terrain_job.phase=="完成同步":
  terrain_job.elapsed+=delta
  if terrain_job.elapsed<.1:return
  _cancel_ground_work("地坑挖掘完成" if terrain_job.kind=="dig" else "地坑回填完成")

func _cancel_ground_work(reason: String, notify: bool=true) -> void:
 if not terrain_job.is_empty() and not bool(terrain_job.get("committed",false)):
  if terrain_job.has("edit_serial") and main!=null and is_instance_valid(main.terrain_damage):
   var queued: Array=main.terrain_damage.pending
   for index in range(queued.size()-1,-1,-1):
    if int(queued[index].get("serial",-1))==int(terrain_job.edit_serial):queued.remove_at(index)
  model.resources+=int(terrain_job.get("reserved_material",0))
  terrain_job["reserved_material"]=0
 if is_instance_valid(terrain_worker):
  terrain_worker.set_meta("construction_order",false)
  terrain_worker.brain.order.clear()
  terrain_worker.set_physics_process(terrain_worker_processing)
 terrain_worker=null
 terrain_job.clear()
 terrain_work_kind=""
 if notify and reason!="":_say(reason)


func _register_built_fortification(id:String) -> void:
 if not _ai_mode() or not is_instance_valid(main.ai_host) or not model.structures.has(id):return
 var state:Dictionary=model.structures[id]
 if state.state not in ["finished","occupied"] or str(state.preset).begins_with("mine_"):return
 var view:Node3D=views.get(id)
 if not is_instance_valid(view):return
 var fort_id:="built_"+id
 if not registered_forts.has(id):
  var target:=Marker3D.new()
  target.name="FortificationTarget"
  view.add_child(target)
  var surfaces:Array=view.find_children("*","CollisionShape3D",true,false)
  if not surfaces.is_empty():target.global_position=surfaces[0].global_position
  else:target.position.y=.2
  var hp:=90.0 if state.preset in ["tower","at"] else 60.0
  main.ai_host.register_fortification(fort_id,target,str(main.ai_host.player_team),hp,func(_target_id):_destroy_built_fortification(id))
  registered_forts[id]=true
 # A view may rebuild geometry when occupation changes; stamp the current bodies.
 for body in view.find_children("*","CollisionObject3D",true,false):
  body.set_meta("actor_id",fort_id)
  body.set_meta("actor_kind","fortification")
  body.set_meta("kind","ai_fortification")
  body.set_meta("team_id",str(main.ai_host.player_team))

func _destroy_built_fortification(id:String) -> void:
 if not model.structures.has(id):return
 if model.occupied==id:
  model.occupied=""
  main.weapon_override=null
  if main.scoped:main.toggle_scope()
  main.hero.global_transform=outside_hero
  main.hero.visible=true
  main.camera.global_transform=outside_camera
  occupied_controls.hide()
 if model.worker_busy==id:model.worker_busy=""
 if not ai_build.is_empty() and str(ai_build.id)==id:_release_ai_builder()
 model.structures.erase(id)
 excavation_ok.erase(id)
 registered_forts.erase(id)
 if is_instance_valid(main.ai_host):main.ai_host.fortifications.erase("built_"+id)
 var view=views.get(id)
 if is_instance_valid(view):
  for body in view.find_children("*","CollisionObject3D",true,false):body.collision_layer=0;body.collision_mask=0
  view.get_parent().remove_child(view)
  view.queue_free()
 views.erase(id)
 if selected_id==id:selected_id=""
 _refresh_choices()
 _say("工事已被摧毁，障碍与炮位已移除")

func _battle_active() -> bool:
 if not _ai_mode():return false
 if main.has_method("is_battle_active"):return bool(main.is_battle_active())
 for property in main.get_property_list():
  if str(property.name) in ["battle_finished","battle_over","battle_ended"] and bool(main.get(property.name)):return false
 return true

func request_support(kind: String) -> void:
 _say(planner.request(kind,_battle_active()))

func _tick_autonomous(delta: float) -> void:
 if not _battle_active():return
 var busy: bool=not ai_build.is_empty() or not terrain_job.is_empty() or model.worker_busy!=""
 var context: Dictionary={"active":true,"busy":busy,"materials":model.resources,"worker":false,"sites":[]}
 if planner.delay<=delta and not busy:
  var worker: CharacterBody3D=_choose_ai_builder()
  context.worker=is_instance_valid(worker)
  var covers:=0
  var emplacements:=0
  for state in model.structures.values():
   if state.state in ["finished","occupied"]:
    if state.preset in ["breastwork","foxhole"]:covers+=1
    if state.preset=="mg":emplacements+=1
  context.cover_count=covers
  context.emplacement_count=emplacements
  if is_instance_valid(worker) and model.resources>0 and (planner.pending!="" or planner.jobs<Planner.MAX_AUTONOMOUS_JOBS):context.sites=_autonomous_sites(worker)
 var decision: Dictionary=planner.advance(delta,context)
 if str(decision.get("message",""))!="":_say(str(decision.message))
 if decision.kind!="propose" or not _battle_active():return
 var action: String=str(decision.action)
 var point: Vector3=decision.position
 if action in ["dig","fill"]:
  if _start_ground_work(action,point):planner.accepted()
  return
 selected_position=point
 site_selected=true
 presets.select(preset_ids.find(action))
 _build()
 if not ai_build.is_empty():planner.accepted()

func _autonomous_sites(worker: CharacterBody3D) -> Array:
 var sites: Array=[]
 var points: Array[Vector3]=[]
 var origin: Vector3=worker.global_position
 var terrain=main.terrain_damage
 # Read only a bounded local patch, not the entire world edit history.
 if is_instance_valid(terrain) and terrain.has_method("base_height"):
  for x in range(-8,9,4):
   for z in range(-8,9,4):
    var px: int=roundi(origin.x)+x
    var pz: int=roundi(origin.z)+z
    var y: float=terrain.sample_height(px,pz)
    if is_finite(y) and y<terrain.base_height(px,pz)-.08:
     points.append(Vector3(px,y,pz))
     if points.size()>=4:break
   if points.size()>=4:break
 for offset in [Vector3(6,0,0),Vector3(-6,0,0),Vector3(0,0,6),Vector3(0,0,-6),Vector3(7,0,7),Vector3(-7,0,-7),Vector3(7,0,-7),Vector3(-7,0,7)]:
  var point: Vector3=origin+offset
  point.y=main.terrain_height(point.x,point.z)
  points.append(point)
 for point in points:
  if not point.is_finite() or point.distance_to(main.hero.global_position)>35.0 or point.distance_to(main.hero.global_position)<5.0:continue
  if is_instance_valid(terrain) and terrain.has_method("is_position_loaded") and not terrain.is_position_loaded(point):continue
  var safe:=true
  for other in main.ai_host.actors.values():
   if not is_instance_valid(other) or other.embarked or other.brain.hp<=0.0:continue
   if str(other.brain.team_id)==str(main.ai_host.player_team):
    if other!=worker and other.global_position.distance_to(point)<3.0:safe=false;break
   elif other.global_position.distance_to(point)<14.0 and main.visibility_for_node(other)=="visible":safe=false;break
  if not safe:continue
  var allowed: Array=[]
  for action in ["breastwork","mg","dig","fill"]:
   var preset: String=action if action in ["breastwork","mg"] else "foxhole"
   if _placement_issue(preset,point)!="":continue
   var worksite: Vector3
   if action in ["dig","fill"]:
    if not is_instance_valid(terrain) or not terrain.has_method("sample_height"):continue
    var direction: Vector3=origin-point
    direction.y=0.0
    if direction.length()<.2:direction=Vector3.RIGHT
    worksite=point+direction.normalized()*2.2
    if action=="fill":
     if not terrain.has_method("base_height"):continue
     if terrain.sample_height(roundi(point.x),roundi(point.z))>=terrain.base_height(roundi(point.x),roundi(point.z))-.08:continue
   else:worksite=point+Vector3(0,0,float(Rules.PRESETS[preset].radius)+.65)
   worksite.y=main.terrain_height(worksite.x,worksite.z)+.12
   if _local_worksite_reachable(worker,worksite):allowed.append(action)
  if not allowed.is_empty():sites.append({"position":point,"safe":true,"reachable":true,"allowed":allowed})
 return sites

func _local_worksite_reachable(worker: CharacterBody3D, destination: Vector3) -> bool:
 var origin: Vector3=worker.global_position
 if origin.distance_to(destination)>18.0:return false
 var previous: float=main.terrain_height(origin.x,origin.z)
 for step in range(1,9):
  var point: Vector3=origin.lerp(destination,float(step)/8.0)
  var height: float=main.terrain_height(point.x,point.z)
  if not is_finite(height) or absf(height-previous)>.6:return false
  previous=height
 var query:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP*.9,destination+Vector3.UP*.9,9|128)
 query.exclude=[worker.get_rid()]
 return main.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _ground_site_issue() -> String:
 if terrain_job.is_empty():return "任务不存在"
 var point: Vector3=terrain_job.position
 if not is_instance_valid(main.terrain_damage) or not main.terrain_damage.is_position_loaded(point):return "施工地块已离开加载范围"
 if point.distance_to(main.hero.global_position)<3.2:return "战车进入施工范围"
 return _placement_issue("foxhole",point,"terrain_job")
