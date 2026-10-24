extends RefCounted
## Explicit asset adapter. No damage state, copied crew, implicit ammo or guessed muzzles.
const Capability = preload("res://modules/vehicle_crew/role_capability.gd")
var mounts: Array[Dictionary] = []
func bind(model: Node3D) -> bool:
 mounts.clear()
 if not is_instance_valid(model):return false
 var hull := model.find_child("HullMG_Muzzle",true,false) as Node3D
 var turret := model.find_child("TurretMG_Muzzle",true,false) as Node3D
 if hull==null or turret==null:return false
 # Required named structural parents prevent mistaken aliases of the same gun.
 if hull.get_parent().name!="Hull" or turret.get_parent().name!="Barrel":return false
 mounts=[{"id":"mg","node":turret,"role":"gunner"},{"id":"mg_hull","node":hull,"role":"radio"}]
 return true
func loadout(base: Dictionary, hull_fraction: float = 0.5) -> Dictionary:
 var result:=base.duplicate(true)
 if mounts.size()!=2 or not result.has("mg"):return result
 result.mg_hull=result.mg.duplicate(true)
 # Configurable fictional allocation, NOT historical stowage data.
 # Preserve total existing game stock, never double it just because two guns exist.
 for kind in result.mg.rounds:
  var count:=int(result.mg.rounds[kind])
  result.mg_hull.rounds[kind]=int(floor(count*clampf(hull_fraction,0.0,1.0)))
  result.mg.rounds[kind]=count-int(result.mg_hull.rounds[kind])
 return result
static func role_available(combat, onboard: Array, role: String) -> bool:
 for i in onboard:
  if i<0 or i>=combat.crew.size():continue
  var person:Dictionary=combat.crew[i]
  var original:String=str(Capability.ROLE_NAMES.get(combat.crew_roles[i],""))
  var effective:String=str(person.get("state",{}).get("assigned_role",original))
  if effective==role and Capability.capable(person,"gunner"):return true
 return false
