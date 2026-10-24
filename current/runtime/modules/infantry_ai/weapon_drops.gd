extends RefCounted
## Fictional fixed inventory rules. One record/owner for each physical weapon.
const CATEGORIES := ["pistol","rifle","sniper","smg","hmg","grenade","rocket"]
const STATS := {
 "pistol":{"magazine":8,"interval":0.65,"penetration":10},
 "rifle":{"magazine":4,"interval":1.1,"penetration":9},
 "sniper":{"magazine":3,"interval":2.2,"penetration":10},
 "smg":{"magazine":16,"interval":0.2,"penetration":10},
 "hmg":{"magazine":24,"interval":0.3,"penetration":10},
 "grenade":{"magazine":1,"interval":3.5,"penetration":15},
 "rocket":{"magazine":1,"interval":4.5,"penetration":110}}
var records: Dictionary = {}
var next_id := 0
func category(kind: String) -> String:
 if kind=="at": return "rocket"
 if kind in ["grenade_launcher","heavy_grenade"]: return "grenade"
 return kind
func rank(kind: String) -> int:
 return CATEGORIES.find(category(kind))+1
func create(kind: String, owner: String, ammo: int, reserve: int) -> String:
 kind = category(kind)
 if not STATS.has(kind): return ""
 next_id += 1
 var id := "weapon_%d"%next_id
 records[id] = {"id":id,"category":kind,"owner":owner,"ammo":maxi(0,ammo),"reserve":maxi(0,reserve),"position":Vector3.ZERO,"blocked_until":0.0}
 return id
func sync_ammo(id: String, ammo: int, reserve: int) -> void:
 if records.has(id):
  records[id].ammo = maxi(0,ammo)
  records[id].reserve = maxi(0,reserve)
func drop(id: String, owner: String, point: Vector3, until: float = 0.0) -> bool:
 if not records.has(id) or str(records[id].owner)!=owner: return false
 records[id].owner = ""
 records[id].position = point
 records[id].blocked_until = until
 return true
func claim(id: String, owner: String, point: Vector3, now: float) -> Dictionary:
 if not records.has(id) or owner.is_empty(): return {}
 var record: Dictionary = records[id]
 if not str(record.owner).is_empty() or now<float(record.blocked_until): return {}
 if point.distance_to(record.position)>1.4 or int(record.ammo)+int(record.reserve)<=0: return {}
 # Synchronous owner transition; a competing second claimant immediately fails.
 record.owner = owner
 return record.duplicate(true)
func choose(point: Vector3, current_kind: String, now: float, usable: Callable, radius := 12.0) -> String:
 var selected := ""
 var best_distance := INF
 var best_rank := 0
 var current_rank := rank(current_kind)
 for id in records:
  var record: Dictionary = records[id]
  var grade := rank(str(record.category))
  var distance := point.distance_to(record.position)
  if not str(record.owner).is_empty() or now<float(record.blocked_until): continue
  if int(record.ammo)+int(record.reserve)<=0 or distance>radius or grade<=current_rank: continue
  if not usable.call(record): continue
  if current_rank==0:
   if distance>best_distance: continue
   if is_equal_approx(distance,best_distance) and grade<=best_rank: continue
  else:
   if grade<best_rank or (grade==best_rank and distance>=best_distance): continue
  selected = id
  best_distance = distance
  best_rank = grade
 return selected
