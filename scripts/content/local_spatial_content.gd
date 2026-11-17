class_name LocalSpatialContent
extends RefCounted
## A detached Content shard; no simulation owner or persistent state.
const OUTPUT_SAMPLE_PIXELS: float = 2.0

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
var _observation_regions: Array[Dictionary] = []

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
	if bool(metadata.get("concept_settlements_debug_only",false)): return result
	for feature: Dictionary in features:
		if feature.has("miniature_layout") and str(feature.valid_from)<=date and date<str(feature.valid_to):
			result.append(feature)
	return result

func minimum_observation_mpp(ll: Vector2, date: String) -> float:
	if not display_active_on(date): return INF
	var result := INF
	for region: Dictionary in observation_regions():
		if Geometry2D.is_point_in_polygon(ll,region.polygon as PackedVector2Array): result=minf(result,float(region.minimum_mpp))
	return result

func observation_regions() -> Array[Dictionary]:
	# Display samples, not the resolution of the original survey or loader disc.
	if not _observation_regions.is_empty() or surface_reference.is_empty(): return _observation_regions
	var d := surface_reference
	var step := float(d.step_degrees)
	var bounds := Rect2(Vector2(float(d.west_cell_centre),float(d.north_cell_centre)-(int(d.height)-1)*step),Vector2(int(d.width)-1,int(d.height)-1)*step)
	_observation_regions.append({"polygon":_bounds_polygon(bounds),"minimum_mpp":maxf(float(metadata.get("local_min_mpp",2.0)),step*111195.0/OUTPUT_SAMPLE_PIXELS),"grade":"survey"})
	var layout := context_layout(d)
	if not layout.is_empty():
		var context := (d.presentation as Dictionary).context_height_asset as Dictionary
		var spacing := context.display_spacing_m_approx as Array
		var output_step := maxf(float(spacing[0]),float(spacing[1]))
		output_step=maxf(output_step,float(layout.stride)*step*111195.0)
		_observation_regions.append({"polygon":_bounds_polygon(layout.bounds as Rect2),"minimum_mpp":output_step/OUTPUT_SAMPLE_PIXELS,"grade":"generalized"})
	return _observation_regions

static func _bounds_polygon(bounds: Rect2) -> PackedVector2Array:
	return PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])

static func context_layout(d: Dictionary) -> Dictionary:
	# This is also the terrain worker's layout. Its cell-centre clipping and
	# bounded strip count are the actual geometry, not an advertised radius.
	var options := d.get("presentation",{}) as Dictionary
	var source := options.get("context_height_asset",{}) as Dictionary
	if source.is_empty(): return {}
	var step := float(d.step_degrees)
	var extent := Vector2i(int(d.width)-1,int(d.height)-1)
	var anchor := d.anchor_lon_lat as Array
	var metres := Vector2(cos(deg_to_rad(float(anchor[1]))),1.0)*step*111195.0
	var radius := clampf(float(options.get("context_radius_m",8000.0)),1000.0,12000.0)
	var stride := clampi(roundi(float(source.display_spacing_degrees[1])/step),2,16)
	var b := source.bounds_lon_lat as Array
	var pad := Vector2(float(source.display_spacing_degrees[0]),float(source.display_spacing_degrees[1]))*.5
	var west := float(d.west_cell_centre);var north := float(d.north_cell_centre)
	var available_low := Vector2((west-float(b[0])-pad.x)/step,(float(b[3])-pad.y-north)/step)
	var available_high := Vector2((float(b[2])-pad.x-west)/step-extent.x,(north-float(b[1])-pad.y)/step-extent.y)
	var low := Vector2i.ZERO;var high := Vector2i.ZERO
	for axis: int in range(2):
		low[axis]=clampi(floori(minf(radius/metres[axis],available_low[axis])/stride),0,64)
		high[axis]=clampi(floori(minf(radius/metres[axis],available_high[axis])/stride),0,64)
	var xs: Array[int]=[];var ys: Array[int]=[]
	for axis: int in range(2):
		var values: Array[int]=xs if axis==0 else ys
		for cell: int in range(-low[axis]*stride,0,stride): values.append(cell)
		for cell: int in range(extent[axis]+1): values.append(cell)
		for cell: int in range(extent[axis]+stride,extent[axis]+high[axis]*stride+1,stride): values.append(cell)
	return {"xs":xs,"ys":ys,"low":low,"stride":stride,"bounds":Rect2(Vector2(west+xs[0]*step,north-ys[-1]*step),Vector2(xs[-1]-xs[0],ys[-1]-ys[0])*step)}

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
