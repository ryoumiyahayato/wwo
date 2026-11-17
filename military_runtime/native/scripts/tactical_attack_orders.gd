extends RefCounted
## Commands share only map-observed snapshots; never grant firing permission.
const MEMORY_SECONDS := 12.0
var main:Node3D
var selected:Array[String]=[]
var mark:Dictionary={}
var generation := -1
var status := ""
func setup(owner_main:Node3D)->void:
 main=owner_main
 generation=main.stage_generation
func _actor(id:String):
 return main.ai_host.actors.get(id)
func _vehicle(id:String)->Dictionary:
 return main.armor_host.units.get(id,{}) if is_instance_valid(main.armor_host) else {}
func eligible(id:String)->bool:
 var a=_actor(id)
 if is_instance_valid(a):
  return a.brain.team_id==main.ai_host.player_team and a.brain.hp>0 and not a.embarked and not bool(a.get_meta("player_controlled",false)) and not bool(a.get_meta("construction_order",false)) and a.get_meta("crew_return_order",{}).is_empty() and a.brain.order.is_empty()
 var u:=_vehicle(id)
 return not u.is_empty() and str(u.team)==main.ai_host.player_team and main.armor_host._alive(u)
func _sync_generation()->void:
 if generation!=main.stage_generation:
  clear_mark();selected.clear();generation=main.stage_generation;status=""
func toggle(id:String)->bool:
 _sync_generation()
 if not eligible(id):return false
 if id in selected:selected.erase(id)
 else:selected.append(id)
 status="已选 %d"%selected.size()
 return true
func visible_position(id:String,visible_ids:Array)->Dictionary:
 if id not in visible_ids:return {}
 var a=_actor(id)
 if is_instance_valid(a) and a.brain.hp>0 and not a.embarked and a.brain.team_id!=main.ai_host.player_team:
  return {"position":a.global_position}
 var u:=_vehicle(id)
 if not u.is_empty() and str(u.team)!=main.ai_host.player_team and main.armor_host._alive(u):
  return {"position":u.model.global_position}
 return {}
func issue(id:String,visible_ids:Array)->bool:
 _sync_generation()
 var contact:=visible_position(id,visible_ids)
 if contact.is_empty():status="目标不可见";return false
 var recipients:Array[String]=[]
 for unit_id in selected:
  if eligible(unit_id):recipients.append(unit_id)
 if recipients.is_empty():status="先选友军";return false
 clear_mark()
 mark={"target_id":id,"position":contact.position,"visible":true,"remaining":MEMORY_SECONDS,"recipients":recipients}
 _publish()
 status="攻击标记"
 return true
func _publish()->void:
 for id in mark.get("recipients",[]):
  if not eligible(id):
   _clear_recipient(id)
   continue
  var order:Dictionary={"target_id":mark.target_id,"position":mark.position,"remaining":mark.remaining}
  var a=_actor(id)
  if is_instance_valid(a):a.brain.tactical_order=order
  else:
   var u:=_vehicle(id)
   u.tactical_order=order
   u.deployment_route=[]
func _clear_recipient(id:String)->void:
 var a=_actor(id)
 if is_instance_valid(a):a.brain.tactical_order={}
 else:
  var u:=_vehicle(id)
  if not u.is_empty():u.tactical_order={}
func clear_mark()->void:
 for id in mark.get("recipients",[]):_clear_recipient(id)
 mark={}
func update(delta:float,visible_ids:Array)->void:
 if generation!=main.stage_generation:
  clear_mark();selected.clear();generation=main.stage_generation;status="";return
 for id in selected.duplicate():
  if not eligible(id):selected.erase(id)
 if mark.is_empty():return
 # Lifetime/ownership may end safely; hidden positions are never sampled.
 var target=_actor(str(mark.target_id))
 var vehicle:=_vehicle(str(mark.target_id))
 if (not is_instance_valid(target) and vehicle.is_empty()) or (is_instance_valid(target) and target.brain.hp<=0) or (not vehicle.is_empty() and not main.armor_host._alive(vehicle)):
  clear_mark();status="标记结束";return
 var contact:=visible_position(str(mark.target_id),visible_ids)
 if not contact.is_empty():
  mark.position=contact.position;mark.visible=true;mark.remaining=MEMORY_SECONDS
 else:
  mark.visible=false;mark.remaining=maxf(0,float(mark.remaining)-delta)
  if float(mark.remaining)<=0:clear_mark();status="标记失效";return
 _publish()
