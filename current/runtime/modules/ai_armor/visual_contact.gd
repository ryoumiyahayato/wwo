extends RefCounted
## Game-only bounded optical observation. This is geometric sensing, NOT RGB recognition.
## Exact world positions are sensor inputs only; consumers receive quantized observations.
const SAMPLE_TTL := 0.85
const HALF_FIELD := deg_to_rad(65.0)
const AZIMUTH_CELL := deg_to_rad(0.35)
const ELEVATION_CELL := deg_to_rad(0.18)
const MIN_ANGULAR_SIZE := deg_to_rad(0.10)

static func observe(origin: Vector3, forward: Vector3, point: Vector3, kind: String, now: float) -> Dictionary:
	var offset := point-origin
	var distance := offset.length()
	if distance<0.01: return {}
	var bearing := offset.normalized()
	if forward.normalized().dot(bearing)<cos(HALF_FIELD): return {}
	var silhouette := 2.2 if kind=="vehicle" else 0.5
	var angular_size := 2.0*atan2(silhouette*.5,distance)
	if angular_size<MIN_ANGULAR_SIZE: return {}
	var azimuth := snappedf(atan2(bearing.x,-bearing.z),AZIMUTH_CELL)
	var elevation := snappedf(asin(clampf(bearing.y,-1.0,1.0)),ELEVATION_CELL)
	# Range is an estimate: never expose exact measured distance to the gun controller.
	var range_cell := maxf(2.0,pow(2.0,floor(log(maxf(distance*.04,2.0))/log(2.0))))
	var estimated_range := maxf(range_cell,snappedf(distance,range_cell))
	var estimated_axis := Vector3(sin(azimuth)*cos(elevation),sin(elevation),-cos(azimuth)*cos(elevation))
	return {"position":origin+estimated_axis*estimated_range,"observed_at":now,"valid_until":now+SAMPLE_TTL,
		"angular_size":angular_size,"range_uncertainty":range_cell*.5,
		"acquire_seconds":clampf(1.0+deg_to_rad(.8)/angular_size,1.0,3.0),
		"bearing_cell":AZIMUTH_CELL,"sensor":"bounded_geometric_optics"}

static func fresh(contact: Dictionary, now: float) -> bool:
	return not contact.is_empty() and now<=float(contact.get("valid_until",-1.0)) and now>=float(contact.get("observed_at",INF))
