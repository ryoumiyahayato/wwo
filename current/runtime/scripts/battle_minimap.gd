extends Control
## North-up map. Host supplies only currently observed hostile IDs.
var controls:Control
var main:Node3D
var expanded:=false
var pointer_ids:Dictionary={}
var local_center:=Vector2.ZERO
var cached_center:=Vector2(INF,INF)
var cached_generation:=-1
var local_texture:ImageTexture
var global_texture:ImageTexture
var elapsed:=0.0
var enemies:Array=[]
var observed_world:Node
var attack_orders=preload("res://scripts/tactical_attack_orders.gd").new()
var command_mode:=false
var command_near:=true
func setup(owner_controls:Control)->void:
 controls=owner_controls;main=controls.main;attack_orders.setup(main);mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 z_index=60;main.hud.add_child(self)
func _active()->bool:
 return controls.active() or (not main.garage and not main.battle_finished and main.mounted_kind()=="mortar")
func _input(event:InputEvent):
 # Vehicle input remains with its existing dispatcher; engineering mortar shares
 # this same map without enabling vehicle driving controls or changing camera.
 if controls.active() or not _active():return
 var handled:=false
 if event is InputEventScreenTouch:handled=handle_pointer(event.index,event.position,event.pressed)
 elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:handled=handle_pointer(-1,event.position,event.pressed)
 elif event is InputEventScreenDrag:handled=handle_motion(event.index)
 elif event is InputEventMouseMotion and expanded:handled=true
 if handled:get_viewport().set_input_as_handled()
func map_rect()->Rect2:
 if expanded:
  var edge:float=minf(size.y-100,size.x-180)
  return Rect2((size-Vector2.ONE*edge)*.5,Vector2.ONE*edge)
 return Rect2(Vector2(18,14),Vector2(200,170))
func command_view()->bool:return expanded and (command_mode or not main.indirect_fire_mode())
func near_view()->bool:return not expanded or (command_view() and command_near)
func map_center()->Vector2:return local_center if near_view() else Vector2.ZERO
func map_span()->float:return 200.0 if near_view() else 5000.0
func world_to_map(p:Vector3)->Vector2:
 return map_rect().position+((Vector2(p.x,p.z)-map_center())/map_span()+Vector2.ONE*.5)*map_rect().size
func map_to_world(p:Vector2)->Vector3:
 var q:Vector2=((p-map_rect().position)/map_rect().size-Vector2.ONE*.5)*map_span()+map_center()
 return Vector3(q.x,0,q.y)
func handle_pointer(id:int,p:Vector2,pressed:bool)->bool:
 if not pressed:
  if pointer_ids.has(id):pointer_ids.erase(id);return true
  return false
 if expanded or map_rect().has_point(p):
  pointer_ids[id]=true
  if expanded and command_rect().has_point(p):
   command_mode=not command_mode
  elif command_view() and scale_rect().has_point(p):
   command_near=not command_near
  elif expanded and map_rect().has_point(p) and (command_mode or not main.indirect_fire_mode()):
   var observed:Array=main.ai_host.minimap_visible_enemy_ids()
   var picked:=pick_unit(p,observed)
   if not picked.is_empty():
    if attack_orders.eligible(picked):attack_orders.toggle(picked)
    else:attack_orders.issue(picked,observed)
   else:expanded=false
  elif expanded and map_rect().has_point(p) and main.indirect_fire_mode():
   main.select_artillery_target(map_to_world(p));expanded=false
  else:expanded=not expanded
  controls.reset_pointers();queue_redraw();return true
 return false
func handle_motion(id:int)->bool:return pointer_ids.has(id) or expanded
func cancel()->void:pointer_ids.clear();expanded=false
func _process(delta:float)->void:
 visible=_active()
 if not visible:return
 elapsed+=delta
 if elapsed<.2:return
 var observation_delta:=elapsed
 elapsed=0
 if is_instance_valid(main.terrain_damage) and observed_world!=main.terrain_damage:
  observed_world=main.terrain_damage
  if observed_world.has_signal("terrain_changed"):observed_world.terrain_changed.connect(_terrain_changed)
 var player:Node3D=main.player_infantry_controller.actor() if controls.on_foot() else main.hero
 local_center=Vector2(roundf(player.position.x/25)*25,roundf(player.position.z/25)*25)
 if cached_generation!=main.stage_generation:
  cached_generation=main.stage_generation;cached_center=Vector2(INF,INF);global_texture=null
 if local_texture==null or local_center!=cached_center:
  cached_center=local_center
  local_texture=_terrain_texture(cached_center,200,48)
 if expanded and global_texture==null:global_texture=_terrain_texture(Vector2.ZERO,5000,96)
 enemies=main.ai_host.minimap_visible_enemy_ids() if main.ai_host.has_method("minimap_visible_enemy_ids") else []
 attack_orders.update(observation_delta,enemies)
 queue_redraw()
func _terrain_changed(_payload:Dictionary)->void:
 local_texture=null;global_texture=null

func _terrain_texture(center:Vector2,span:float,resolution:int)->ImageTexture:
 var img:=Image.create(resolution,resolution,false,Image.FORMAT_RGB8)
 for z in resolution:
  for x in resolution:
   var p:Vector2=center+(Vector2(x+.5,z+.5)/resolution-Vector2.ONE*.5)*span
   var h:float=main.indirect_surface_height(p.x,p.y)
   if not is_finite(h):h=0.0
   var shade:float=clampf(.46+h*.018,.25,.78)
   img.set_pixel(x,z,Color(shade*.83,shade,shade*.62))
 return ImageTexture.create_from_image(img)
func _draw()->void:
 if not _active():return
 var r:=map_rect()
 if expanded:draw_rect(Rect2(Vector2.ZERO,size),Color(.02,.04,.05,.88))
 draw_rect(r,Color(.12,.18,.13))
 var tex:Texture2D=local_texture if near_view() else global_texture
 if tex!=null:draw_texture_rect(tex,r,false)
 for k in range(1,4):
  draw_line(r.position+Vector2(r.size.x*k/4,0),r.position+Vector2(r.size.x*k/4,r.size.y),Color(1,1,1,.12))
  draw_line(r.position+Vector2(0,r.size.y*k/4),r.position+Vector2(r.size.x,r.size.y*k/4),Color(1,1,1,.12))
 for id in main.ai_host.actors:
  var a=main.ai_host.actors[id]
  if not is_instance_valid(a) or a.embarked or a.brain.hp<=0:continue
  if a.brain.team_id!="blue" and id not in enemies:continue
  var p:=world_to_map(a.position)
  if r.grow(-5).has_point(p):draw_circle(p,3 if expanded else 3.5,Color("69bcff") if a.brain.team_id=="blue" else Color("ff775d"))
 if is_instance_valid(main.armor_host):
  for u in main.armor_host.units.values():
   if not is_instance_valid(u.model) or (u.team!="blue" and u.id not in enemies):continue
   var point:=world_to_map(u.model.global_position)
   if r.grow(-5).has_point(point):draw_rect(Rect2(point-Vector2.ONE*4,Vector2.ONE*8),Color("69bcff") if u.team=="blue" else Color("ff775d"))
 # Known own deployment cover and flank path are orientation aids, never targets.
 if not expanded and main.hero.has_meta("deployment_home"):
  var home:Vector3=main.hero.get_meta("deployment_home")
  var cover_a:=world_to_map(home+Vector3(-12,0,14))
  var cover_b:=world_to_map(home+Vector3(12,0,22))
  var cover_rect:=Rect2(cover_a,cover_b-cover_a).intersection(r)
  if cover_rect.has_area():draw_rect(cover_rect,Color(.38,.25,.12,.85))
  var route:=[home,home+Vector3(-20,0,8),home+Vector3(-20,0,40)]
  for k in range(2):
   var a:=world_to_map(route[k]);var b:=world_to_map(route[k+1])
   if r.has_point(a) and r.has_point(b):draw_dashed_line(a,b,Color(.95,.88,.6,.65),1,4)
 if controls.on_foot():
  var vehicle:=world_to_map(main.hero.global_position)
  var edge:=r.grow(-8)
  var marker:=Vector2(clampf(vehicle.x,edge.position.x,edge.end.x),clampf(vehicle.y,edge.position.y,edge.end.y))
  draw_rect(Rect2(marker-Vector2.ONE*5,Vector2.ONE*10),Color("fff1a0"),false,2)
  if not edge.has_point(vehicle):
   var toward:Vector2=(vehicle-marker).normalized()
   draw_line(marker-toward*7,marker+toward*5,Color("fff1a0"),2,true)
 var player:Node3D=main.player_infantry_controller.actor() if controls.on_foot() else main.hero
 var hero:=world_to_map(player.position)
 _draw_view_directions(hero,r)
 var direction:=Vector2(-sin(player.rotation.y),-cos(player.rotation.y))
 var side:=Vector2(-direction.y,direction.x)
 draw_colored_polygon(PackedVector2Array([hero+direction*9,hero-direction*6+side*5,hero-direction*6-side*5]),Color("fff1a0"))
 draw_orders(r)
 draw_rect(r,Color(.85,.89,.77),false,2)
 if main.indirect_fire_mode() and main.artillery_aim.selected:
  var mark:=world_to_map(main.artillery_aim.target)
  var inset:=r.grow(-8)
  mark=Vector2(clampf(mark.x,inset.position.x,inset.end.x),clampf(mark.y,inset.position.y,inset.end.y))
  var color:=Color("78e8a0") if main.artillery_aim.status=="可射" else Color("ffc36b")
  draw_hollow_cross(mark,color,10,4)
  if expanded:
   var predicted:=world_to_map(main.artillery_aim.predicted)
   if inset.has_point(predicted):draw_circle(predicted,2.5,color)
  draw_string(main.font,r.position+Vector2(66,19),main.artillery_aim.status,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
 draw_string(main.font,r.position+Vector2(7,19),"N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.WHITE)
 var caption:String="200 m" if near_view() else "5 km"
 if command_view():caption+=" ↔"
 draw_string(main.font,r.position+Vector2(7,r.size.y-8),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)

func _direction_tip(center:Vector2,direction:Vector3,length_px:float,r:Rect2) -> Vector2:
 var flat:=Vector2(direction.x,direction.z)
 if flat.length_squared()<.00001:return center
 var tip:=center+flat.normalized()*length_px
 return Vector2(clampf(tip.x,r.position.x+2,r.end.x-2),clampf(tip.y,r.position.y+2,r.end.y-2))

func _draw_view_directions(center:Vector2,r:Rect2) -> void:
 # Camera optical direction is distinct from both hull and actual weapon bore.
 var view:Vector3=-main.camera.global_basis.z.normalized()
 var aspect:float=main.get_viewport().get_visible_rect().size.aspect()
 var half_angle:=atan(tan(deg_to_rad(main.camera.fov)*.5)*aspect)
 var left:=_direction_tip(center,view.rotated(Vector3.UP,half_angle),30,r)
 var right:=_direction_tip(center,view.rotated(Vector3.UP,-half_angle),30,r)
 draw_colored_polygon(PackedVector2Array([center,left,right]),Color(.25,.9,.95,.18))
 draw_line(center,left,Color(.25,.9,.95,.7),1,true)
 draw_line(center,right,Color(.25,.9,.95,.7),1,true)
 draw_line(center,_direction_tip(center,view,30,r),Color(.25,.9,.95,.9),1,true)
 if not controls.on_foot():
  var muzzle:Node3D=main.weapon_muzzle()
  if muzzle!=null:draw_line(center,_direction_tip(center,-muzzle.global_basis.z,22,r),Color(1,.6,.2),3,true)

func scale_rect()->Rect2:return Rect2(map_rect().position+Vector2(3,map_rect().size.y-28),Vector2(60,26))
func command_rect()->Rect2:
 return Rect2(map_rect().end-Vector2(32,map_rect().size.y-4),Vector2(28,28))
func pick_unit(p:Vector2,observed:Array)->String:
 var best:=""
 var distance:=14.0
 for id in main.ai_host.actors:
  var a=main.ai_host.actors[id]
  if not is_instance_valid(a) or a.brain.hp<=0 or a.embarked:continue
  if not attack_orders.eligible(str(id)) and id not in observed:continue
  var d:=p.distance_to(world_to_map(a.global_position))
  if d<distance:distance=d;best=str(id)
 if is_instance_valid(main.armor_host):
  for id in main.armor_host.units:
   var u=main.armor_host.units[id]
   if not is_instance_valid(u.model) or not main.armor_host._alive(u):continue
   if not attack_orders.eligible(str(id)) and id not in observed:continue
   var d:=p.distance_to(world_to_map(u.model.global_position))
   if d<distance:distance=d;best=str(id)
 return best
func draw_orders(r:Rect2)->void:
 for id in attack_orders.selected:
  var a=main.ai_host.actors.get(id)
  var pos:Vector3
  if is_instance_valid(a):pos=a.global_position
  elif is_instance_valid(main.armor_host) and main.armor_host.units.has(id):pos=main.armor_host.units[id].model.global_position
  else:continue
  var point:=world_to_map(pos)
  if r.grow(-8).has_point(point):draw_arc(point,7,0,TAU,20,Color("8cd7ff"),2,true)
 if not attack_orders.mark.is_empty():
  var point:=world_to_map(attack_orders.mark.position)
  if r.grow(-9).has_point(point):
   var color:=Color("ff7055") if attack_orders.mark.visible else Color("d8b367")
   draw_arc(point,9,0,TAU,24,color,2,true)
   draw_hollow_cross(point,color,13,5)
 if expanded:
  var button:=command_rect()
  var color:=Color("78d8ff") if command_mode or not main.indirect_fire_mode() else Color("999999")
  draw_rect(button,Color(.05,.08,.10,.95))
  draw_rect(button,color,false,1)
  var center:=button.get_center()
  draw_arc(center,6,0,TAU,16,color,1.5,true)
  draw_line(center-Vector2(9,0),center+Vector2(9,0),color,1)
  draw_line(center-Vector2(0,9),center+Vector2(0,9),color,1)
  if not attack_orders.status.is_empty():draw_string(main.font,r.position+Vector2(65,r.size.y-8),attack_orders.status,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)

func draw_hollow_cross(point:Vector2,color:Color,outer:float,gap:float)->void:
 for axis in [Vector2.RIGHT,Vector2.DOWN]:
  draw_line(point+axis*gap,point+axis*outer,color,2,true)
  draw_line(point-axis*gap,point-axis*outer,color,2,true)
