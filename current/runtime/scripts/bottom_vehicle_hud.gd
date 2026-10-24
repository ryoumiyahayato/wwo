extends Control
## Display-only shared meshes. No actor scripts, physics bodies, AI or ammunition copies.
var controls: Control
var main: Node3D
var viewport: SubViewport
var texture: TextureRect
var display_root: Node3D
var camera: Camera3D
var hero_source: Node3D
var mesh_pairs: Array = []
var crew_pairs: Array = []
var pointers: Dictionary = {}
var generation := -1
var refresh_clock := 0.0
var last_sync_usec := 0
var max_sync_usec := 0
var shell_material: StandardMaterial3D
func setup(owner_controls: Control) -> void:
 controls=owner_controls;main=controls.main
 name="BottomVehicleHUD";mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 controls.add_child(self)
 viewport=SubViewport.new();viewport.size=Vector2i(256,176);viewport.transparent_bg=true
 viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
 viewport.msaa_3d=Viewport.MSAA_DISABLED;add_child(viewport)
 display_root=Node3D.new();viewport.add_child(display_root)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5.2
 viewport.add_child(camera);camera.position=Vector3(3,9,5);camera.look_at(Vector3(0,1,0));camera.current=true
 texture=TextureRect.new();texture.texture=viewport.get_texture();texture.mouse_filter=Control.MOUSE_FILTER_IGNORE
 texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;add_child(texture)
 shell_material=StandardMaterial3D.new();shell_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 shell_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;shell_material.albedo_color=Color(.08,.22,.25,.14)
 shell_material.cull_mode=BaseMaterial3D.CULL_DISABLED;shell_material.no_depth_test=true
func panel_rect() -> Rect2:
 var safe:Rect2=controls.fire_layout_rect if controls.fire_layout_rect.size.x>0 else Rect2(Vector2.ZERO,controls.size)
 var left:float=maxf(safe.position.x+safe.size.x*.24,controls.center_stick().x+104)
 var right:float=controls.center_mg().x-controls.action_radius("mg")-14
 # Never expand across compact fire-control touch regions on narrow safe areas.
 var width:float=minf(332,maxf(1,right-left))
 return Rect2(Vector2(left+(right-left-width)*.5,safe.end.y-126),Vector2(width,116))
func crew_rect() -> Rect2:
 var p:=panel_rect()
 return Rect2(p.position,Vector2(p.size.x*.42,p.size.y-20))
func ammo_buttons() -> Array[Dictionary]:
 var out:Array[Dictionary]=[]
 if not is_instance_valid(main) or not is_instance_valid(main.hero):return out
 var p:=panel_rect();var weapon:String=main.primary_weapon()
 var mount:String="mg" if weapon=="mg" else "primary"
 var state:Dictionary=main.vehicle_ammo.status(main.PLAYER_VEHICLE_ID,mount)
 if state.is_empty():return out
 var allowed:Array=["tracer","ap","incendiary"] if weapon=="mg" else ["he"] if weapon=="short_rocket" else ["ap","he","smoke"]
 var names:Dictionary={"ap":"AP","he":"HE","smoke":"SMK","tracer":"TR","incendiary":"INC","":""}
 var types:Array=[]
 # Reserve keys are the registered loadout, including exhausted types. Never reflow on firing.
 for kind in allowed:
  if state.reserve.has(kind):types.append(kind)
 var center:=Vector2(p.position.x+p.size.x*.72,p.position.y+66)
 for i in types.size():
  var kind:String=types[i]
  var count:int=int(state.reserve.get(kind,0))+int(str(state.loaded)==kind)+int(str(state.loading)==kind)
  var angle:float=-PI*.5+TAU*float(i)/maxi(1,types.size())
  var position:Vector2=center+(Vector2(cos(angle),sin(angle))*38 if types.size()>1 else Vector2.ZERO)
  out.append({"id":"round_"+kind,"type":kind,"label":str(names.get(kind,kind)),"index":allowed.find(kind),"rect":Rect2(position-Vector2(28,28),Vector2(56,56)),"count":count,"selected":str(state.next)==kind})
 return out
func pointer(id:int,p:Vector2,pressed:bool) -> bool:
 if not pressed:
  if pointers.has(id):pointers.erase(id);return true
  return false
 if not visible or not panel_rect().has_point(p):return false
 pointers[id]=true
 for button in ammo_buttons():
  if not button.rect.has_point(p):continue
  if main.battle_finished or controls.menu_open or controls.on_foot():return true
  if main.primary_weapon()=="cannon":main.select_ammo(button.index)
  elif main.primary_weapon()=="mg":
   # Reuse the existing wrapper; cycling does not fire, refill or reset cooldown.
   for step in range(3):
    if main.mg_ammo==button.index:break
    main.cycle_mg()
  break
 return true
func _process(delta:float) -> void:
 visible=controls.active() and not controls.on_foot() and not controls.menu_open and not main.battle_finished
 if not visible:
  viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;pointers.clear();return
 texture.position=crew_rect().position;texture.size=crew_rect().size
 if hero_source!=main.hero or generation!=main.stage_generation:rebuild()
 refresh_clock+=delta
 # At most 20 Hz and 256x176 pixels; the main world renders independently.
 if refresh_clock>=.05:
  refresh_clock=0;sync_display();viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;queue_redraw()
func rebuild() -> void:
 for child in display_root.get_children():child.free()
 mesh_pairs.clear();crew_pairs.clear();hero_source=main.hero;generation=main.stage_generation
 for source in hero_source.find_children("*","MeshInstance3D",true,false):
  if source.mesh==null:continue
  var view:=MeshInstance3D.new();view.mesh=source.mesh;view.material_override=shell_material
  view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;display_root.add_child(view)
  mesh_pairs.append({"source":source,"view":view})
 for source in hero_source.find_children("*","CollisionObject3D",true,false):
  if not source.has_meta("crew_index") or str(source.get_meta("key",""))!="torso":continue
  var view:=MeshInstance3D.new();var marker:=CapsuleMesh.new();marker.radius=.17;marker.height=.58;view.mesh=marker
  var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.no_depth_test=true;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.render_priority=1
  view.material_override=material;view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  display_root.add_child(view);crew_pairs.append({"source":source,"view":view,"index":int(source.get_meta("crew_index"))})
func sync_display() -> void:
 if not is_instance_valid(hero_source):return
 var start:=Time.get_ticks_usec()
 # Cancel world translation only. Full hull attitude and live articulated geometry remain.
 display_root.transform=Transform3D(hero_source.global_basis,Vector3.ZERO)
 var inverse:Transform3D=hero_source.global_transform.affine_inverse()
 for pair in mesh_pairs:
  if not is_instance_valid(pair.source):continue
  pair.view.transform=inverse*pair.source.global_transform;pair.view.visible=pair.source.visible
 var onboard:Array=main.player_onboard_indices()
 for pair in crew_pairs:
  if not is_instance_valid(pair.source):continue
  pair.view.transform=inverse*pair.source.global_transform
  var crew:Dictionary=main.player_combat.crew[pair.index]
  var alive:bool=bool(crew.alive) and float(crew.hp)>0
  pair.view.material_override.albedo_color=Color("84939b") if pair.index not in onboard else Color("df6262") if not alive else Color("e6bb65") if float(crew.hp)<10 else Color("9fe6c3")
  pair.view.scale=Vector3.ONE*(.65 if pair.index not in onboard else 1.0)
 last_sync_usec=Time.get_ticks_usec()-start;max_sync_usec=maxi(max_sync_usec,last_sync_usec)
func speed_readout() -> Dictionary:
 var signed_speed:float=float(main.hero.get_meta("vehicle_speed",0.0)) if is_instance_valid(main.hero) else 0.0
 return {"signed":signed_speed,"forward":maxf(0,signed_speed)*3.6,"reverse":maxf(0,-signed_speed)*3.6,"unit":"km/h"}
func _draw() -> void:
 if not visible:return
 var p:=panel_rect()
 var mount:String="mg" if main.primary_weapon()=="mg" else "primary"
 var state:Dictionary=main.vehicle_ammo.status(main.PLAYER_VEHICLE_ID,mount)
 if state.is_empty():return
 for button in ammo_buttons():
  var rect:Rect2=button.rect
  var c:Color=Color("f0d595") if button.selected else Color("c2d0cd")
  var center:Vector2=rect.get_center()-Vector2(0,5)
  # Tiny icon and abbreviation, with an invisible 56px touch target.
  draw_arc(center,18,0,TAU,32,Color(.02,.04,.05,.7),1.5,true)
  if button.selected:draw_arc(center,18,0,TAU,32,c,1.2,true)
  var tip:float=-13 if button.type=="ap" else -10
  var icon:=PackedVector2Array([center+Vector2(-6,10),center+Vector2(-6,-7),center+Vector2(0,tip),center+Vector2(6,-7),center+Vector2(6,10)])
  if button.type=="smoke":
   draw_rect(Rect2(center+Vector2(-7,-8),Vector2(14,19)),c)
   for j in range(3):draw_arc(center+Vector2(-5+j*5,-13-j%2*3),3,PI,TAU,8,c,1.5,true)
  else:
   draw_colored_polygon(icon,c)
   if button.type=="he":
    draw_line(center+Vector2(-6,-2),center+Vector2(6,-2),Color("b47a46"),3)
    draw_line(center+Vector2(-6,3),center+Vector2(6,3),Color("b47a46"),2)
   elif button.type=="ap":draw_line(center+Vector2(0,-12),center+Vector2(0,6),Color("435d67"),2)
  draw_line(center+Vector2(-8,12),center+Vector2(8,12),c,2)
  var label:String=str(button.label);var count:String=str(button.count)
  var label_x:float=center.x-main.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x*.5
  draw_string_outline(main.font,Vector2(label_x,center.y+24),label,HORIZONTAL_ALIGNMENT_LEFT,-1,11,3,Color(.02,.04,.05,.9))
  draw_string(main.font,Vector2(label_x,center.y+24),label,HORIZONTAL_ALIGNMENT_LEFT,-1,11,c)
  draw_string_outline(main.font,Vector2(label_x+main.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+1,center.y+19),count,HORIZONTAL_ALIGNMENT_LEFT,-1,9,3,Color(.02,.04,.05,.9))
  draw_string(main.font,Vector2(label_x+main.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+1,center.y+19),count,HORIZONTAL_ALIGNMENT_LEFT,-1,9,c)
  if str(state.loaded)==button.type:draw_circle(center+Vector2(14,-12),2,Color("e6f6f3"))
  if str(state.loading)==button.type:
   var progress:float=1.0-float(state.remaining)/maxf(.01,float(state.duration))
   draw_arc(center,20,-PI*.5,-PI*.5+TAU*progress,32,Color("e6f6f3"),2,true)
 # Signed speed is the movement solver's post-collision value, not desired throttle.
 var signed_speed:float=speed_readout().signed
 var crew:=crew_rect();var left:=Vector2(crew.position.x+7,p.end.y-5);var right:=Vector2(crew.end.x-54,p.end.y-5)
 var forward:bool=signed_speed>.05;var reverse:bool=signed_speed<-.05
 var active_color:=Color("d4e9e3");var idle_color:=Color(.72,.8,.78,.85)
 draw_string_outline(main.font,left,"▲ %.0f"%(maxf(0,signed_speed)*3.6),HORIZONTAL_ALIGNMENT_LEFT,-1,11,3,Color(.02,.04,.05,.8))
 draw_string_outline(main.font,right,"▼ %.0f"%(maxf(0,-signed_speed)*3.6),HORIZONTAL_ALIGNMENT_LEFT,-1,11,3,Color(.02,.04,.05,.8))
 draw_string(main.font,left,"▲ %.0f"%(maxf(0,signed_speed)*3.6),HORIZONTAL_ALIGNMENT_LEFT,-1,11,active_color if forward else idle_color)
 draw_string(main.font,right,"▼ %.0f"%(maxf(0,-signed_speed)*3.6),HORIZONTAL_ALIGNMENT_LEFT,-1,11,active_color if reverse else idle_color)
