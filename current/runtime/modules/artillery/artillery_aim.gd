extends RefCounted
const Arc=preload("res://modules/artillery/arc_solution.gd")
const Collision=preload("res://modules/artillery/arc_collision.gd")
const Shell=preload("res://modules/artillery/artillery_shell.gd")
var selected:=false
var manual:=false
var target:=Vector3.ZERO
var predicted:=Vector3.ZERO
var pitch:=PI/3.0
var status:=""
var elapsed:=0.0
var recheck:=0.0
var last_origin:=Vector3(INF,INF,INF)
func reset():manual=false;selected=false;status="";elapsed=0;recheck=0;last_origin=Vector3(INF,INF,INF)
func select(main,point:Vector3)->bool:
 if not point.is_finite() or absf(point.x)>2500 or absf(point.z)>2500:return false
 manual=false
 target=point;target.y=main.indirect_surface_height(target.x,target.z)
 selected=true;status="调炮";elapsed=0;recheck=0;last_origin=Vector3(INF,INF,INF)
 # Physics ray queries are deferred to tick, never performed from pointer callbacks.
 return true
func exclusions(main)->Array[RID]:
 if main.mounted_kind()=="mortar":return main.mortar_adapter.exclusions(main,main.weapon_override)
 var items:Array[RID]=[]
 for body in main.hero.find_children("*","CollisionObject3D",true,false):items.append(body.get_rid())
 return items
func trace(main,origin:Vector3,velocity:Vector3)->Dictionary:
 var pos:=origin
 var excluded:=exclusions(main)
 # Preview uses the same gravity and exact analytic step; only preview chord resolution differs.
 for i in range(360):
  var next:=pos+velocity*.1+Vector3.DOWN*Arc.GRAVITY*.005
  var hit:Dictionary=Collision.segment(main.get_world_3d().direct_space_state,pos,next,excluded,Callable(main,"indirect_surface_height"),true)
  if not hit.is_empty():return hit
  pos=next;velocity+=Vector3.DOWN*Arc.GRAVITY*.1
 return {}
func choose(main):
 if not target.is_finite():status="无地形";return
 var muzzle:Node3D=main.weapon_muzzle()
 if not is_instance_valid(muzzle):status="无炮";return
 var valid:=false
 var first:Dictionary={}
 var angle_limited:=false
 for degrees in [60.0,70.0,50.0,40.0,30.0]:
  var solution:Dictionary=Arc.solve(muzzle.global_position,target,deg_to_rad(degrees))
  if not solution.valid:continue
  valid=true
  if main.mounted_kind()=="mortar":
   var view:Node3D=main.mortar_adapter._view(muzzle)
   var group:Node3D=view.weapon_group
   var local_direction:Vector3=group.get_parent().global_basis.inverse()*solution.direction
   var local_pitch:=atan2(local_direction.y,Vector2(local_direction.x,local_direction.z).length())
   if local_pitch<main.mortar_adapter.MIN_PITCH or local_pitch>main.mortar_adapter.MAX_PITCH:angle_limited=true;continue
  else:
   var turret:Node3D=main.hero.find_child("Turret",true,false)
   var local_direction:Vector3=turret.get_parent().global_basis.inverse()*solution.direction
   var local_pitch:=atan2(local_direction.y,Vector2(local_direction.x,local_direction.z).length())
   var limits:Vector2=main.catalog_pitch_limits()
   if local_pitch<limits.x or local_pitch>limits.y:angle_limited=true;continue
  var hit:=trace(main,muzzle.global_position,solution.direction*solution.speed)
  if first.is_empty():first={"pitch":deg_to_rad(degrees),"speed":solution.speed,"hit":hit}
  if not hit.is_empty() and hit.position.distance_to(target)<2.0:
   pitch=deg_to_rad(degrees);main.artillery_launch_speed=solution.speed;status="调炮";return
 if not valid:status="超程";return
 if first.is_empty():status="限角" if angle_limited else "超程";return
 pitch=first.pitch;main.artillery_launch_speed=first.speed;status="受阻"
func tick(main,delta:float):
 if not selected or not main.indirect_fire_mode():return
 if manual:
  tick_manual(main,delta)
  return
 if status=="可射" and target.is_finite():
  var live_muzzle:Node3D=main.weapon_muzzle()
  if is_instance_valid(live_muzzle):
   var live_solution:Dictionary=Arc.solve(live_muzzle.global_position,target,pitch)
   if not live_solution.valid or (-live_muzzle.global_basis.z.normalized()).dot(live_solution.direction)<.9995:status="调炮"
 elapsed+=delta;recheck+=delta
 if elapsed<.5:return
 elapsed=0
 var muzzle:Node3D=main.weapon_muzzle()
 if not is_instance_valid(muzzle):return
 target.y=main.indirect_surface_height(target.x,target.z)
 if not target.is_finite():status="无地形";return
 if not last_origin.is_finite() or muzzle.global_position.distance_to(last_origin)>1 or recheck>3.0:
  choose(main);last_origin=muzzle.global_position;recheck=0
 var solution:Dictionary=Arc.solve(muzzle.global_position,target,pitch)
 if not solution.valid:status="超程";return
 main.artillery_launch_speed=solution.speed
 var hit:=trace(main,muzzle.global_position,-muzzle.global_basis.z.normalized()*solution.speed)
 if hit.is_empty():status="超程";return
 predicted=hit.position
 var aligned:bool=(-muzzle.global_basis.z.normalized()).dot(solution.direction)>.9995
 if main.aim_contact_blocked:status="受阻";return
 if main.aim_limited:
  status="转车" if "水平" in main.aim_limit_reason else "限角"
  return
 status="可射" if aligned and predicted.distance_to(target)<2.0 else "调炮" if not aligned else "受阻"
 if status=="可射" and main.mounted_kind()!="mortar":
  if not main.player_can_fire():status="缺员"
  elif main.vehicle_ammo.total(main.PLAYER_VEHICLE_ID,"primary")<=0:status="无弹"
  elif float(main.vehicle_ammo.status(main.PLAYER_VEHICLE_ID,"primary").remaining)>0:status="装填"

 if status=="可射" and main.mounted_kind()=="mortar":
  var inventory:Dictionary=main.mortar_adapter.status(main)
  if int(inventory.rounds)<=0:status="无弹"
  elif float(inventory.remaining)>0:status="装填"

func enter_manual(main):
 manual=true;selected=true;elapsed=0;status="手动"
 main.aiming_pending=false
 var muzzle:Node3D=main.weapon_muzzle()
 if is_instance_valid(muzzle):
  if main.mounted_kind()=="mortar":main.artillery_launch_speed=float(muzzle.get_meta("mortar_launch_speed",Arc.MIN_SPEED))
  target=muzzle.global_position;predicted=target
 # Scope input and existing mount slew own direction; no automatic steering/shot.
func tick_manual(main,delta:float):
 elapsed+=delta
 if elapsed<.1:return
 elapsed=0
 var muzzle:Node3D=main.weapon_muzzle()
 if not is_instance_valid(muzzle):status="无炮";return
 var hit:=trace(main,muzzle.global_position,-muzzle.global_basis.z.normalized()*main.artillery_launch_speed)
 if hit.is_empty():status="超程";return
 predicted=hit.position;target=predicted
 status="限角" if main.aim_limited else "手动"
 if main.reload_remaining>0:status="装填"
