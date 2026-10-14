class_name LocalSpatialContent
extends RefCounted
## A detached Content shard; no simulation owner or persistent state.

var metadata: Dictionary = {}
var features: Array[Dictionary] = []
var shards: Dictionary = {}
var has_content: bool = false
var cancelled: bool = false
var errors: Array[String] = []
var line_chunks: Array[Dictionary] = []
var surface_reference: Dictionary = {}
var geometry_mutex := Mutex.new()

func landmark_visuals() -> Array[Dictionary]:
	# Placement references decorate admitted places; they never become world places.
	var result: Array[Dictionary] = []
	for visual: Dictionary in metadata.get("landmark_visuals",[]) as Array:
		result.append(visual)
	return result

func active_on(date: String) -> bool:
	return errors.is_empty() and (has_content or not features.is_empty()) and str(metadata.get("valid_from", "")) <= date and date < str(metadata.get("valid_to", ""))

static func landmark_visible_on(visual: Dictionary, date: String) -> bool:
	# A snapshot's exclusive end is not a demolition date. Later viewing retains
	# the explicitly labelled model form; it does not assert a later survey.
	return date>=str(visual.get("existence_confirmed_on",visual.get("valid_from","9999-12-31"))) and (str(visual.get("display_until","")).is_empty() or date<str(visual.display_until))

func display_active_on(date: String) -> bool:
	if not errors.is_empty(): return false
	if active_on(date): return true
	for visual: Dictionary in landmark_visuals():
		if landmark_visible_on(visual,date): return true
	return false

func covers(lon_lat: Vector2) -> bool:
	var anchor := metadata.get("anchor_lon_lat",[]) as Array
	if anchor.size()!=2: return false
	return GlobeProjection.lon_lat_to_unit(lon_lat).angle_to(GlobeProjection.lon_lat_to_unit(Vector2(float(anchor[0]),float(anchor[1]))))*6371.0088<=float(metadata.get("radius_km",0.0))

func dated_features(date: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for feature: Dictionary in features:
		if str(feature.valid_from) <= date and date < str(feature.valid_to):
			result.append(feature.duplicate(true))
	return result

static func historical_rail_alignment(feature: Dictionary) -> bool:
	# Corridor existence and surveyed alignment are separate source assertions.
	if str(feature.get("kind",""))!="rail": return true
	if str(feature.get("geometry_evidence_type",""))=="BOUNDED_ASSUMPTION": return false
	if str(feature.get("geometry_status",""))=="BOUNDED_HISTORICAL_CORRIDOR_REFERENCE": return false
	return str(feature.get("geometry_evidence_type",""))=="HISTORICAL_EVIDENCE" and not str(feature.get("source_reference","")).is_empty() and str(feature.get("geometry_role","")) in ["HISTORICAL_TRACK_ALIGNMENT","GEOREFERENCED_HISTORICAL_ALIGNMENT"]
