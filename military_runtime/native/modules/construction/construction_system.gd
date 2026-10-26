extends RefCounted
## Portable, deterministic fictional game construction. No scene-tree dependencies.
signal event_emitted(event: Dictionary)
const VERSION := 1
const PRESETS := {
 "barricade": {"label":"拒马", "time_ms":4500, "cost":2, "radius":2.0, "use_y":0.0, "weapon":"", "observe_y":1.6},
 "mine_vehicle": {"label":"反坦克雷", "time_ms":2500, "cost":1, "radius":0.7, "use_y":0.0, "weapon":"", "observe_y":1.6, "trigger":"vehicle"},
 "mine_person": {"label":"反步兵雷", "time_ms":2500, "cost":1, "radius":0.7, "use_y":0.0, "weapon":"", "observe_y":1.6, "trigger":"person"},
 "mine_any": {"label":"普通雷", "time_ms":2500, "cost":1, "radius":0.7, "use_y":0.0, "weapon":"", "observe_y":1.6, "trigger":"any"},
 "foxhole": {"label":"散兵坑", "time_ms":4000, "cost":1, "radius":1.7, "use_y":-0.65, "weapon":"", "observe_y":0.65},
 "breastwork": {"label":"简易胸墙", "time_ms":5000, "cost":2, "radius":2.0, "use_y":0.0, "weapon":"", "observe_y":1.6},
 "mg": {"label":"机枪阵地", "time_ms":6000, "cost":3, "radius":2.1, "use_y":0.0, "weapon":"mg_direct", "observe_y":1.6},
 "mortar": {"label":"迫击炮阵地", "time_ms":7000, "cost":3, "radius":2.1, "use_y":0.0, "weapon":"mortar_arc", "observe_y":1.6},
 "at": {"label":"反坦克炮阵地", "time_ms":8000, "cost":4, "radius":2.6, "use_y":0.0, "weapon":"at_direct", "observe_y":1.6},
 "tower": {"label":"观察塔", "time_ms":9000, "cost":4, "radius":2.2, "use_y":3.2, "weapon":"", "observe_y":4.8}
}
var structures: Dictionary = {}
var worker_id := "infantry_1"
var worker_busy := ""
var occupied := ""
var resources := 24
var next_id := 1
var sequence := 0
var events: Array = []

func _emit(kind: String, data: Dictionary = {}) -> Dictionary:
 sequence += 1
 var event := data.duplicate(true)
 event["kind"] = kind
 event["seq"] = sequence
 events.append(event)
 event_emitted.emit(event.duplicate(true))
 return event

func drain_events() -> Array:
 var result := events.duplicate(true)
 events.clear()
 return result

func _refuse(reason: String) -> Dictionary:
 return _emit("refused", {"reason":reason})

func command(input: Dictionary) -> Dictionary:
 var op := str(input.get("op", ""))
 if op == "reset":
  structures.clear()
  worker_busy = ""
  occupied = ""
  resources = 24
  next_id = 1
  return _emit("reset", {"restore_terrain":true})
 if str(input.get("worker_id", worker_id)) != worker_id: return _refuse("unknown_worker")
 if op == "place": return _place(input)
 var id := str(input.get("id", ""))
 if not structures.has(id): return _refuse("unknown_structure")
 var s: Dictionary = structures[id]
 match op:
  "confirm_excavation":
   if s.state != "awaiting_excavation": return _refuse("wrong_state")
   if not bool(input.get("success",false)): return _refuse("excavation_failed")
   s.state = "finished"
   s.excavation_ready = true
   return _emit("finished", {"id":id,"preset":s.preset})
  "trigger":
   if s.state != "armed": return _refuse("not_armed")
   var actor_kind := str(input.get("actor_kind", ""))
   if actor_kind not in ["person", "vehicle"]: return _refuse("invalid_actor")
   var filter: String = PRESETS[s.preset].trigger
   if filter != "any" and actor_kind != filter: return _refuse("actor_filtered")
   s.state = "consumed"
   return _emit("mine_triggered", {"id":id, "position":s.position.duplicate(), "preset":s.preset, "actor_kind":actor_kind, "target_id":str(input.get("target_id", "")), "terrain_preset":"crater", "game_damage":4})
  "start":
   if s.state != "placement": return _refuse("wrong_state")
   if worker_busy != "" or occupied != "": return _refuse("worker_busy")
   s.state = "building"
   worker_busy = id
   return _emit("building_started", {"id":id})
  "cancel":
   if s.state not in ["placement", "building", "awaiting_excavation"]: return _refuse("already_finished")
   if worker_busy == id: worker_busy = ""
   resources += int(PRESETS[s.preset].cost)
   structures.erase(id)
   return _emit("cancelled", {"id":id, "restore_terrain":s.preset == "foxhole"})
  "enter":
   if s.state != "finished": return _refuse("not_finished")
   if s.preset == "barricade": return _refuse("not_enterable")
   if worker_busy != "" or occupied != "": return _refuse("worker_busy")
   occupied = id
   s.state = "occupied"
   return _emit("entered", {"id":id, "use_y":PRESETS[s.preset].use_y, "observe_y":PRESETS[s.preset].observe_y})
  "use":
   if occupied != id or s.state != "occupied": return _refuse("not_occupied")
   return _emit("use_requested", {"id":id, "weapon":PRESETS[s.preset].weapon, "requires_line_of_sight":false, "identification_requires_line_of_sight":true})
  "exit":
   if occupied != id: return _refuse("not_occupied")
   occupied = ""
   s.state = "finished"
   return _emit("exited", {"id":id})
 return _refuse("unknown_command")

func _place(input: Dictionary) -> Dictionary:
 var preset := str(input.get("preset", ""))
 if not PRESETS.has(preset): return _refuse("unknown_preset")
 if worker_busy != "" or occupied != "": return _refuse("worker_busy")
 for other in structures.values():
  if other.state == "placement": return _refuse("placement_pending")
 var p = input.get("position", [])
 if not p is Array or p.size() != 3: return _refuse("invalid_position")
 for value in p:
  if not (value is int or value is float) or not is_finite(float(value)): return _refuse("invalid_position")
 if not bool(input.get("site_valid", false)): return _refuse("invalid_site")
 var slope := float(input.get("slope_degrees", 90.0))
 if not is_finite(slope) or absf(slope) > 12.0: return _refuse("slope")
 # Host must make the ground physically open before confirming excavation_ready.
 if preset == "foxhole" and not (bool(input.get("excavation_ready", false)) or bool(input.get("excavation_reserved", false))): return _refuse("excavation_required")
 var radius: float = PRESETS[preset].radius
 for other in structures.values():
  var dx := float(p[0]) - float(other.position[0])
  var dz := float(p[2]) - float(other.position[2])
  if Vector2(dx, dz).length() < radius + float(PRESETS[other.preset].radius): return _refuse("overlap")
 if resources < int(PRESETS[preset].cost): return _refuse("resources")
 var yaw := float(input.get("yaw", 0.0))
 if not is_finite(yaw): return _refuse("invalid_yaw")
 var id := "construction_%d" % next_id
 next_id += 1
 resources -= int(PRESETS[preset].cost)
 structures[id] = {"id":id, "preset":preset, "position":p.duplicate(), "yaw":yaw, "state":"placement", "elapsed_ms":0, "excavation_ready":bool(input.get("excavation_ready",false))}
 return _emit("placed", {"id":id, "preset":preset})

func advance(milliseconds: int) -> void:
 if milliseconds <= 0 or worker_busy == "": return
 var s: Dictionary = structures[worker_busy]
 var duration: int = PRESETS[s.preset].time_ms
 s.elapsed_ms = mini(duration, int(s.elapsed_ms) + milliseconds)
 _emit("progress", {"id":s.id, "elapsed_ms":s.elapsed_ms, "duration_ms":duration})
 if s.elapsed_ms == duration:
  s.state = "armed" if PRESETS[s.preset].has("trigger") else "finished"
  worker_busy = ""
  if s.preset == "foxhole" and not s.get("excavation_ready",false):
   s.state = "awaiting_excavation"
   _emit("excavation_requested", {"id":s.id,"preset":s.preset})
  else: _emit("finished", {"id":s.id, "preset":s.preset})

func tick(delta: float) -> void:
 # For lockstep/replay use integer advance(), avoiding float time quantization.
 if is_finite(delta): advance(roundi(maxf(delta, 0.0) * 1000.0))

func serialize() -> Dictionary:
 return {"version":VERSION, "structures":structures.duplicate(true), "worker_id":worker_id, "worker_busy":worker_busy, "occupied":occupied, "resources":resources, "next_id":next_id, "sequence":sequence}

func restore(data: Dictionary) -> bool:
 if int(data.get("version", 0)) != VERSION: return false
 var incoming = data.get("structures", null)
 if not incoming is Dictionary: return false
 for id in incoming:
  var s = incoming[id]
  if not s is Dictionary or not PRESETS.has(s.get("preset", "")): return false
  if s.get("id", "") != id or s.get("state", "") not in ["placement", "building", "finished", "occupied", "armed", "consumed", "awaiting_excavation"]: return false
  var p = s.get("position", [])
  if not p is Array or p.size() != 3: return false
  for value in p:
   if not (value is int or value is float) or not is_finite(float(value)): return false
  if not is_finite(float(s.get("yaw", NAN))): return false
  var elapsed := int(s.get("elapsed_ms", -1))
  if elapsed < 0 or elapsed > int(PRESETS[s.preset].time_ms): return false
 var busy := str(data.get("worker_busy", ""))
 var occupant := str(data.get("occupied", ""))
 if busy != "" and (not incoming.has(busy) or incoming[busy].state != "building"): return false
 if occupant != "" and (not incoming.has(occupant) or incoming[occupant].state != "occupied"): return false
 if busy != "" and occupant != "": return false
 for id in incoming:
  if incoming[id].state == "building" and id != busy: return false
  if incoming[id].state == "occupied" and id != occupant: return false
 for id in incoming:
  var mine: bool = PRESETS[incoming[id].preset].has("trigger")
  if incoming[id].state in ["armed", "consumed"] and not mine: return false
  if incoming[id].state in ["finished", "occupied"] and mine: return false
 if int(data.get("resources", -1)) < 0 or int(data.get("next_id", 0)) < 1: return false
 structures = incoming.duplicate(true)
 worker_id = str(data.get("worker_id", "infantry_1"))
 worker_busy = busy
 occupied = occupant
 resources = int(data.resources)
 next_id = int(data.next_id)
 sequence = int(data.get("sequence", 0))
 events.clear()
 return true
