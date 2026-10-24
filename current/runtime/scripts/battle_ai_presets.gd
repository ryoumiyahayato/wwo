extends RefCounted
## Fictional game tuning, not real combat specifications.
const Visibility = preload("res://scripts/visibility.gd")
const VISION := {"clear":360.0,"rain":190.0,"fog":85.0}
const MEMORY_TTL := 12.0
static func weapon_range(weapon: String) -> float:
 if weapon=="cannon": return 260.0
 return 220.0 if weapon in ["at","rocket","sniper"] else (160.0 if weapon in ["mg","hmg"] else (85.0 if weapon in ["grenade","grenade_launcher","heavy_grenade"] else 125.0))
static func reason(origin: Vector3, destination: Vector3, weather: String, center: Vector3, smoke: bool, blocked: bool, radius: float = 6.5) -> String:
 if origin.distance_to(destination)>float(VISION.get(weather,85.0)): return "range"
 if smoke and radius>0.0 and Visibility.segment_sphere(origin,destination,center,radius): return "smoke"
 return "obstacle" if blocked else "visible"
