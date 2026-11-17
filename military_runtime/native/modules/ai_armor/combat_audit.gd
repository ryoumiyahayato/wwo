extends RefCounted
## Bounded in-memory diagnostic data, never retains scene Objects or writes files.
const LIMIT := 64
var entries: Array[Dictionary] = []
var sequence := 0
func clear() -> void:
 entries.clear()
 sequence=0
func append(record: Dictionary) -> int:
 sequence+=1
 var clean: Dictionary=_plain(record)
 clean["audit_id"]=sequence
 entries.append(clean)
 if entries.size()>LIMIT:entries.pop_front()
 return sequence
func attach_impact(audit_id: int, source: String, impact: Dictionary) -> bool:
 for i in range(entries.size()-1,-1,-1):
  if int(entries[i].audit_id)==audit_id and str(entries[i].get("source",""))==source:
   entries[i]["player_impact"]=_plain(impact)
   return true
 return false
func snapshot() -> Array:
 return entries.duplicate(true)
func last_player_impact() -> Dictionary:
 for i in range(entries.size()-1,-1,-1):
  if entries[i].has("player_impact"):return entries[i].duplicate(true)
 return {}
func _plain(value, depth := 0):
 if depth>8:return null
 if value is Vector3:return [value.x,value.y,value.z]
 if value is Dictionary:
  var out: Dictionary={}
  for key in value:
   if key is String:out[key]=_plain(value[key],depth+1)
  return out
 if value is Array:
  var out: Array=[]
  for item in value:out.append(_plain(item,depth+1))
  return out
 if value==null or value is bool or value is int or value is String:return value
 if value is float:return value if is_finite(value) else null
 return null
