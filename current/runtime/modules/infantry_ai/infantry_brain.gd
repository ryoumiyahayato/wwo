extends RefCounted
## Deterministic fictional game state; only filtered observations enter this brain.
signal event_emitted(event: Dictionary)
const VERSION := 1
const MAGAZINE := 4
const SHOT_INTERVAL := 1.1
var actor_id := ""
var team_id := ""
var state := "idle"
var hp := 10.0
var ammo := MAGAZINE
var reserve_ammo := 16
var magazine_size := MAGAZINE
var shot_interval := SHOT_INTERVAL
var cooldown := 0.0
var _shot_overshoot := 0.0
var state_time := 0.0
var target_id := ""
var preferred_target_id := ""
var prefer_vehicles := false
var nearby_vehicle_radius := 28.0
var engagement_range := 125.0
var memory_ttl := 2.5
var reaction_time := 0.6
var last_known := Vector3.ZERO
var memory_remaining := 0.0
var patrol_points: Array = []
var cover_points: Array = []
var patrol_index := 0
var cover_used := false
var order: Dictionary = {}
var tactical_order: Dictionary = {}
var sequence := 0

func setup(id: String, team: String) -> void:
 actor_id = id
 team_id = team

func _set_state(value: String) -> void:
 if state == value: return
 state = value
 state_time = 0.0
 sequence += 1
 event_emitted.emit({"kind":"state_changed", "actor_id":actor_id,"state":state,"seq":sequence})

func receive_damage(amount: float) -> void:
 if hp <= 0.0 or amount <= 0.0: return
 hp = maxf(0.0, hp - amount)
 _set_state("disabled" if hp <= 0.0 else "wounded")
 if hp <= 0.0: order.clear()

func order_build(site: Vector3, preset: String, approved: bool) -> bool:
 if not approved or hp <= 0.0 or preset.is_empty(): return false
 order = {"site":site,"preset":preset}
 target_id = ""
 memory_remaining = 0.0
 _set_state("move_to_build")
 return true

func tick(delta: float, position: Vector3, observations: Array, commit_immediately := true) -> Dictionary:
 var dt := clampf(delta, 0.0, 0.25)
 if not tactical_order.is_empty():
  tactical_order.remaining=maxf(0.0,float(tactical_order.remaining)-dt)
  if float(tactical_order.remaining)<=0:tactical_order.clear()
 _shot_overshoot=maxf(0.0,dt-cooldown) if cooldown>0.0 else 0.0
 cooldown = maxf(0.0, cooldown - dt)
 memory_remaining = maxf(0.0, memory_remaining - dt)
 state_time += dt
 var out := {"move":false,"destination":position,"fire":false,"target_id":"","build":false}
 if hp <= 0.0:
  _set_state("disabled")
  return out
 if state == "wounded" and state_time < 0.65: return out
 if state == "reload":
  if state_time < 2.1: return out
  var transferred := mini(magazine_size-ammo,reserve_ammo)
  ammo += transferred
  reserve_ammo -= transferred
  _set_state("idle")
 var seen: Array = []
 for item in observations:
  if str(item.get("team_id",team_id)) != team_id and bool(item.get("alive",false)) and bool(item.get("visible",false)):
   # A remote vehicle cannot suppress fallback to genuinely visible local targets.
   if prefer_vehicles and str(item.get("actor_kind","infantry"))=="vehicle" and _planar_distance(position,item.position)>nearby_vehicle_radius: continue
   seen.append(item)
 # IDs, not distance/weak-point optimization, define fixed target priority.
 seen.sort_custom(func(a,b): return str(a.actor_id) < str(b.actor_id))
 if not seen.is_empty():
  var target: Dictionary = seen[0]
  # Optional fixed scenario pairing applies only among genuinely visible actors.
  for candidate in seen:
   if str(candidate.actor_id)==str(tactical_order.get("target_id",preferred_target_id)):
    target = candidate
    break
  if prefer_vehicles and tactical_order.is_empty():
   for candidate in seen:
    if str(candidate.get("actor_kind","infantry"))=="vehicle":
     target = candidate
     break
  if target_id != str(target.actor_id):
   _set_state("see_target")
   state_time = 0.0
  target_id = str(target.actor_id)
  last_known = target.position
  memory_remaining = memory_ttl
  if _planar_distance(position,last_known)>engagement_range*0.88:
   _set_state("approach")
   out.move = true
   out.destination = last_known
   return out
  if ammo <= 0:
   if reserve_ammo<=0:
    _set_state("empty")
    return out
   _set_state("reload")
   return out
  if state not in ["see_target","move_to_cover","fire"]:
   _set_state("see_target")
   return out
  if state == "see_target" and state_time < reaction_time: return out
  if not cover_used and not cover_points.is_empty():
   _set_state("move_to_cover")
   var point: Vector3 = cover_points[0]
   if _planar_distance(position,point) > 0.6 and state_time < 3.0:
    out.move = true
    out.destination = point
    return out
   cover_used = true
  _set_state("fire")
  if cooldown <= 0.0:
   out.fire = true
   out.target_id = target_id
   out.destination = last_known
   if commit_immediately: commit_shot()
  return out
 # Explicit order remains a search snapshot, not a visible observation.
 if seen.is_empty() and not tactical_order.is_empty():
  _set_state("search_order")
  out.destination=tactical_order.position
  out.move=_planar_distance(position,out.destination)>1.0
  return out
 # Immutable team reports allow search only, never blind firing.
 if seen.is_empty():
  for report in observations:
   if bool(report.get("reported",false)) and str(report.get("team_id",team_id))!=team_id and (prefer_vehicles or str(report.get("actor_kind","infantry"))=="infantry") and float(report.get("remaining",0.0))>memory_remaining:
    target_id = str(report.actor_id)
    last_known = report.position
    memory_remaining = minf(memory_ttl,float(report.remaining))
 # No hidden current positions are used: search only the last observed location.
 if memory_remaining > 0.0 and not target_id.is_empty():
  _set_state("search")
  out.move = _planar_distance(position,last_known) > 1.0
  out.destination = last_known
  return out
 target_id = ""
 cover_used = false
 if not order.is_empty():
  out.destination = order.site
  if _planar_distance(position,order.site) > 0.7:
   _set_state("move_to_build")
   out.move = true
  else:
   _set_state("build")
   out.build = true
   out.preset = order.preset
   order.clear()
  return out
 if not patrol_points.is_empty():
  _set_state("patrol")
  var point: Vector3 = patrol_points[patrol_index % patrol_points.size()]
  if _planar_distance(position,point) < 0.7:
   patrol_index = (patrol_index + 1) % patrol_points.size()
   point = patrol_points[patrol_index]
  out.move = _planar_distance(position,point) > 0.25
  out.destination = point
 else: _set_state("idle")
 return out

func commit_shot() -> void:
 # The physical actor commits only after a shot passes all muzzle/LOS gates.
 ammo = maxi(0,ammo-1)
 cooldown = maxf(0.0,shot_interval-_shot_overshoot)
 _shot_overshoot=0.0

func snapshot() -> Dictionary:
 return {"version":VERSION,"actor_id":actor_id,"team_id":team_id,"state":state,"hp":hp,"ammo":ammo,"reserve_ammo":reserve_ammo,"cooldown":cooldown,"state_time":state_time,"target_id":target_id,"last_known":[last_known.x,last_known.y,last_known.z],"memory_remaining":memory_remaining,"patrol_index":patrol_index,"cover_used":cover_used,"sequence":sequence}

func restore(data: Dictionary) -> bool:
 if int(data.get("version",0)) != VERSION or str(data.get("actor_id","")) != actor_id: return false
 hp = clampf(float(data.get("hp",10.0)),0.0,10.0)
 ammo = clampi(int(data.get("ammo",MAGAZINE)),0,magazine_size)
 reserve_ammo = maxi(0,int(data.get("reserve_ammo",16)))
 cooldown = maxf(0.0,float(data.get("cooldown",0.0)))
 state_time = maxf(0.0,float(data.get("state_time",0.0)))
 target_id = str(data.get("target_id",""))
 var p: Array = data.get("last_known",[0,0,0])
 if p.size() != 3: return false
 last_known = Vector3(float(p[0]),float(p[1]),float(p[2]))
 memory_remaining = maxf(0.0,float(data.get("memory_remaining",0.0)))
 patrol_index = maxi(0,int(data.get("patrol_index",0)))
 cover_used = bool(data.get("cover_used",false))
 sequence = maxi(0,int(data.get("sequence",0)))
 state = "disabled" if hp <= 0.0 else str(data.get("state","idle"))
 return true

func _planar_distance(a: Vector3, b: Vector3) -> float:
 return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))
