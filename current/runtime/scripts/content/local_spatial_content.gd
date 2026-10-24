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
var surface_covers: Array[Dictionary] = []
var geometry_mutex := Mutex.new()

func landmark_visuals() -> Array[Dictionary]:
	# Placement references decorate admitted places; they never become world places.
	var result: Array[Dictionary] = []
	for visual: Dictionary in metadata.get("landmark_visuals",[]) as Array:
		result.append(visual)
	return result

func settlement_visuals(date: String) -> Array[Dictionary]:
	# Admitted geographic references carry display-only module placements.
	# They never create a settlement, building owner or transport operator.
	var result: Array[Dictionary] = []
	for feature: Dictionary in features:
		if feature.has("miniature_layout") and str(feature.valid_from)<=date and date<str(feature.valid_to):
			result.append(feature)
	return result

func minimum_observation_mpp(ll: Vector2, date: String) -> float:
	# A shard's 300km query disc is not 300km of detailed urban terrain.
	if not display_active_on(date): return INF
	var result := INF
	var surface := surface_reference
	if not surface.is_empty():
		var west := float(surface.west_cell_centre)
		var north := float(surface.north_cell_centre)
		var step := float(surface.step_degrees)
		if ll.x>=west and ll.x<=west+(int(surface.width)-1)*step and ll.y<=north and ll.y>=north-(int(surface.height)-1)*step:
			result = maxf(float(metadata.get("local_min_mpp",25.0)),step*111195.0*.25)
	var unit := GlobeProjection.lon_lat_to_unit(ll)
	for visual: Dictionary in landmark_visuals():
		if not landmark_visible_on(visual,date) or str(visual.get("model_path","")).is_empty(): continue
		var p := (visual.geometry as Dictionary).coordinates as Array
		var distance := unit.angle_to(GlobeProjection.lon_lat_to_unit(Vector2(float(p[0]),float(p[1]))))*6371.0088
		# The finite model neighbourhood permits observation, not invented blocks.
		if distance<=2.5: result=minf(result,float(metadata.get("local_min_mpp",25.0)))
	return result

func active_on(date: String) -> bool:
	return errors.is_empty() and (has_content or not features.is_empty()) and str(metadata.get("valid_from", "")) <= date and date < str(metadata.get("valid_to", ""))

static func landmark_visible_on(visual: Dictionary, date: String) -> bool:
	# A snapshot's exclusive end is not a demolition date. Later viewing retains
	# the explicitly labelled model form; it does not assert a later survey.
	return date>=str(visual.get("existence_confirmed_on",visual.get("valid_from","9999-12-31"))) and (str(visual.get("display_until","")).is_empty() or date<str(visual.display_until))

func display_active_on(date: String) -> bool:
	if not errors.is_empty(): return false
	# Modern physical reference is not a one-year political snapshot.
	if bool(metadata.get("physical_foundation",false)): return true
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
