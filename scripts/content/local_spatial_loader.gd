class_name LocalSpatialLoader
extends RefCounted
## Lazy preparation through the existing source/fact contracts, off the UI thread.

const PARIS_PATH: String = "res://data/local/paris_northern_france_1900.json"
const ANCHOR: Vector2 = Vector2(2.3522, 48.8566)
const GIZA_ANCHOR: Vector2 = Vector2(31.131557,29.976122)
const GIZA_PATH: String = "res://data/local/giza_pyramids_1900.json"
const SOURCES: Array[Dictionary] = [
	{"path":PARIS_PATH,"anchor":ANCHOR,"anchor_id":"place:paris","radius_km":300.0,"city_overview_path":"res://data/local/paris_city_reference.json","city_overview_profiles":[{"place_id":"place:rouen","path":"res://data/local/rouen_city_reference.json"},{"place_id":"place:lyon","path":"res://data/local/lyon_city_reference.json"},{"place_id":"place:le_havre","path":"res://data/local/le_havre_city_reference.json"},{"place_id":"","path":"res://data/local/france_settlement_context.json"},{"place_id":"","path":"res://data/local/benelux_settlement_context.json"}]},
	{"path":GIZA_PATH,"anchor":GIZA_ANCHOR,"anchor_id":"landmark:giza_pyramids_1900","radius_km":20.0},
	{"path":"res://data/local/london_westminster_1900.json","anchor":Vector2(-0.1246,51.5007),"anchor_id":"place:london","radius_km":15.0,"city_overview_path":"res://data/local/london_city_overview.json","city_overview_profiles":[{"place_id":"","path":"res://data/local/british_settlement_context.json"}]},
	{"path":"res://data/local/zermatt_west_physical_reference.json","anchor":Vector2(7.703304,46.010743),"anchor_id":"geographic_region:zermatt_west_reference","radius_km":14.0},
	{"path":"res://data/local/berlin_transport_1900.json","anchor":Vector2(13.388,52.5219),"anchor_id":"place:berlin","radius_km":20.0},
	{"path":"res://data/local/internal_preview_r23/pont_du_gard.json","anchor":Vector2(4.535278,43.947222),"anchor_id":"landmark:pont_du_gard_reference","radius_km":15.0,"internal_preview":true,"display_name":"加尔桥","parent_country_id":"country_fra"},
	{"path":"res://data/local/internal_preview_r23/stonehenge.json","anchor":Vector2(-1.826277,51.178905),"anchor_id":"landmark:stonehenge_reference","radius_km":15.0,"internal_preview":true,"display_name":"巨石阵","parent_country_id":"british_isles_1900"},
	{"path":"res://data/local/internal_preview_r23/colosseum.json","anchor":Vector2(12.4922,41.8902),"anchor_id":"landmark:colosseum_reference","radius_km":15.0,"internal_preview":true,"display_name":"罗马斗兽场","parent_country_id":"kingdom_of_italy"},
	{"path":"res://data/local/internal_preview_r41/orange.json","anchor":Vector2(4.808417,44.135722),"anchor_id":"landmark:orange_reference","radius_km":8.0,"internal_preview":true,"display_name":"奥朗日古剧场","parent_country_id":"country_fra"},
	{"path":"res://data/local/internal_preview_r41/pisa.json","anchor":Vector2(10.396389,43.723056),"anchor_id":"landmark:pisa_reference","radius_km":8.0,"internal_preview":true,"display_name":"比萨斜塔","parent_country_id":"kingdom_of_italy"},
	{"path":"res://data/local/internal_preview_r41/parthenon.json","anchor":Vector2(23.72618,37.97087),"anchor_id":"landmark:parthenon_reference","radius_km":8.0,"internal_preview":true,"display_name":"帕特农神庙遗址","parent_country_id":"kingdom_of_greece"},
	{"path":"res://data/local/internal_preview_r41/petra.json","anchor":Vector2(35.45154,30.32208),"anchor_id":"landmark:petra_reference","radius_km":8.0,"internal_preview":true,"display_name":"佩特拉宝库立面","parent_country_id":"ottoman_empire"},
	{"path":"res://data/local/internal_preview_r41/taj_mahal.json","anchor":Vector2(78.04222,27.17417),"anchor_id":"landmark:taj_mahal_reference","radius_km":8.0,"internal_preview":true,"display_name":"泰姬陵主体","parent_country_id":"cshapes_gw_750"},
	{"path":"res://data/local/internal_preview_r41/temple_heaven.json","anchor":Vector2(116.406667,39.882167),"anchor_id":"landmark:temple_heaven_reference","radius_km":8.0,"internal_preview":true,"display_name":"天坛祈年殿","parent_country_id":"qing_empire"},
	{"path":"res://data/local/internal_preview_r41/hagia_sophia.json","anchor":Vector2(28.98,41.00833),"anchor_id":"landmark:hagia_sophia_reference","radius_km":8.0,"internal_preview":true,"display_name":"圣索菲亚主体","parent_country_id":"ottoman_empire"}]
const PREWARM_KM_PER_PIXEL: float = 0.35
var content: LocalSpatialContent
var _thread: Thread
var _request_mutex := Mutex.new()
var _request_generation: int = 0
var _wanted: bool = false
var _wanted_path: String = PARIS_PATH
var _loading_path: String = ""
var _wanted_anchor := ANCHOR
var _inspection_source: Dictionary = {}

func set_inspection_source(path: String, anchor_id: String) -> bool:
	# Only the menu's presentation preview can select an installed candidate.
	# It retains the original geographic identity and the original parser/gate.
	if not OS.has_feature("editor") and not OS.has_feature("map_resource_acceptance"): return false
	for source: Dictionary in SOURCES:
		if str(source.anchor_id) != anchor_id or not _source_enabled(source): continue
		if not path.begins_with("res://data/local/candidates/") or not FileAccess.file_exists(path): return false
		release()
		_inspection_source = source.duplicate()
		_inspection_source["path"] = path
		return true
	return false

func clear_inspection_source() -> void:
	if _inspection_source.is_empty(): return
	release()
	_inspection_source.clear()

static func covers(lon_lat: Vector2) -> bool:
	return not source_at(lon_lat).is_empty()

static func source_at(lon_lat: Vector2) -> Dictionary:
	var unit := GlobeProjection.lon_lat_to_unit(lon_lat)
	for source: Dictionary in SOURCES:
		if not _source_enabled(source): continue
		if unit.angle_to(GlobeProjection.lon_lat_to_unit(source.anchor as Vector2))*6371.0088<=float(source.radius_km): return source
	return {}

static func anchors() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for source: Dictionary in SOURCES:
		if _source_enabled(source): result.append(source.anchor as Vector2)
	return result

static func _source_enabled(source: Dictionary) -> bool:
	return not bool(source.get("internal_preview",false)) or OS.has_feature("editor") or OS.has_feature("internal_landmark_preview")

static func internal_landmark_sources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in SOURCES:
		if bool(source.get("internal_preview",false)) and _source_enabled(source): result.append(source)
	return result

func request(lon_lat: Vector2 = ANCHOR) -> void:
	var source := source_at(lon_lat)
	if source.is_empty(): return
	if not _inspection_source.is_empty() and source.anchor_id == _inspection_source.anchor_id:
		source = _inspection_source
	var changed := not _wanted or _wanted_path!=str(source.path)
	_wanted = true
	_wanted_path = str(source.path)
	_wanted_anchor = source.anchor as Vector2
	if _thread!=null:
		if changed and _loading_path!=_wanted_path:
			_request_mutex.lock()
			_request_generation += 1
			_request_mutex.unlock()
		return
	if content!=null and str(content.metadata.get("content_path",""))==_wanted_path: return
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()
	_thread = Thread.new()
	_loading_path = _wanted_path
	_thread.start(_load.bind(_wanted_path,_request_current.bind(_request_generation),str(source.anchor_id)))

func cancel_pending() -> void:
	if not _wanted: return
	_wanted = false
	if _thread == null: return
	_request_mutex.lock()
	_request_generation += 1
	_request_mutex.unlock()

func _request_current(generation: int) -> bool:
	_request_mutex.lock()
	var current := generation == _request_generation
	_request_mutex.unlock()
	return current

func preparing() -> bool:
	return _thread != null

func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	var result := _thread.wait_to_finish() as LocalSpatialContent
	_thread = null
	if result.cancelled or not _wanted or _loading_path!=_wanted_path:
		if _wanted: request(_wanted_anchor)
		return false
	content = result
	return true

func dispose() -> void:
	release()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func release() -> void:
	cancel_pending()
	content = null

static func _load(path: String, current: Callable, expected_anchor: String = "") -> LocalSpatialContent:
	var result := LocalSpatialContent.new()
	result.metadata["content_path"] = path
	if not current.call():
		result.cancelled = true
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.metadata["content_path"] = path
		result.errors.append("Local shard unavailable: "+path)
		return result
	var text := file.get_as_text()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		result.errors.append("Invalid Local shard JSON")
		return result
	var document := parser.data as Dictionary
	result.metadata = document.get("metadata", {}) as Dictionary
	result.metadata["content_path"] = path
	var expected := expected_anchor
	for source: Dictionary in SOURCES:
		if str(source.path)==path: expected = str(source.anchor_id); break
	if str(result.metadata.get("schema_id", "")) != "local_spatial_content_r1" or str(result.metadata.get("anchor_place_id", "")) != expected:
		result.errors.append("Unsupported Local content shard")
		return result
	var sources := HistoricalSourceRegistry.new()
	var facts := HistoricalEvidenceCatalog.new()
	if not sources.load_document(document.get("source_registry", {}) as Dictionary) or not facts.load_document(document.get("evidence_catalog", {}) as Dictionary):
		result.errors.append_array(sources.errors())
		result.errors.append_array(facts.errors())
		return result
	var gate := HistoricalProvenanceGate.new(sources, facts)
	var ids: Dictionary = {}
	for fact_id: String in facts.fact_ids():
		if not current.call():
			result.cancelled = true
			return result
		var fact := facts.fact(fact_id)
		if not fact.value is Dictionary:
			result.errors.append("Local spatial fact requires a feature")
			return result
		if not gate.admit_runtime_fact(fact_id, fact.domain, fact.output_material()):
			result.errors.append_array(gate.errors())
			return result
		var feature := (fact.value as Dictionary).duplicate(true)
		var id := str(feature.get("id", ""))
		if ids.has(id) or not _valid_feature(feature) or fact.subject_id != id or str(feature.get("source_id", "")) != fact.source_id:
			result.errors.append("Invalid or duplicate Local feature: " + id)
			return result
		if feature.has("miniature_layout") and not _valid_miniature(feature,expected):
			result.errors.append("Invalid bounded settlement composition: "+id)
			return result
		ids[id] = true
		if not LocalSpatialContent.historical_rail_alignment(feature): continue
		result.features.append(feature)
	# Concept placements may reuse an admitted point in this same shard. The
	# offset remains bounded around that point; no new place identity is made.
	var composition_points: Dictionary={}
	for feature: Dictionary in result.features:
		if str(feature.geometry.type)=="Point":composition_points[str(feature.id)]=feature.geometry.coordinates
	for feature: Dictionary in result.features:
		for placement: Dictionary in (feature.get("miniature_layout",{}) as Dictionary).get("placements",[]):
			if not placement.has("reference_anchor_id"):continue
			var reference:=str(placement.reference_anchor_id)
			if not composition_points.has(reference):
				result.errors.append("Concept composition requires an admitted point: "+reference)
				return result
			placement["reference_anchor_lon_lat"]=(composition_points[reference] as Array).duplicate()
	for visual: Dictionary in result.landmark_visuals():
		if not ids.has(str(visual.get("anchor_place_id",""))) or not _valid_feature(visual) or str(visual.get("kind",""))!="landmark" or not str(visual.get("model_path","")).begins_with("res://assets/landmarks/") or str(visual.get("source_reference","")).is_empty():
			result.errors.append("Invalid landmark placement reference")
			return result
		# A transport decoration retains its admitted point ID, while LOCAL uses
		# the shard's existing city anchor. It cannot introduce another locality.
		if visual.has("local_anchor_id") and str(visual.local_anchor_id)!=expected:
			result.errors.append("Landmark local anchor differs from its content shard")
			return result
	var surface_path := str(result.metadata.get("surface_reference_path",""))
	if not surface_path.is_empty():
		var surface_errors: Array[String] = []
		var surface := ContentDocument.read(surface_path,surface_errors)
		if surface_errors.is_empty() and _valid_surface(surface):
			surface["content_path"] = surface_path
			# Presentation parameters are detached from raw DEM/DSM and cover facts.
			surface["presentation"] = result.metadata.get("surface_presentation",{})
			result.surface_reference = surface
		else:
			result.metadata["terrain_note_zh"] = "局部高程资料不可用，地表保持平面。"
	# These acquired open-river panels do not establish a complete channel.
	# Keep their admitted facts for reading, but use the existing centrelines
	# consistently in both chart and terrain. Never turn a study cut into a bank.
	var bounded_river_panel := false
	var has_river_line := false
	for feature: Dictionary in result.features:
		if str(feature.kind)=="river" and str(feature.geometry.type)=="LineString": has_river_line = true
		if str(feature.kind)=="water_surface" and str(feature.get("geometry_role",""))=="MODERN_WATER_POLYGON_NOT_1900_BANK":
			bounded_river_panel = true
	bounded_river_panel = bounded_river_panel and has_river_line
	if bounded_river_panel:
		result.metadata["water_display_note_zh"] = "有限现代河面不作完整河道显示；沿用已有中心线，不推定河宽。"
		if not result.surface_reference.is_empty():
			var covers: Array = []
			for cover: Dictionary in result.surface_reference.get("cover_meshes",[]) as Array:
				if str(cover.kind)!="water_surface": covers.append(cover)
			result.surface_reference["cover_meshes"] = covers
			result.surface_reference["river_chart_only"] = true
	# Legacy source files package cover references beside their DEM. Detach
	# the inputs here: cover kinds never become DEM values or terrain classes.
	result.surface_covers.assign(result.surface_reference.get("cover_meshes",[]) as Array)
	result.surface_reference.erase("cover_meshes")
	for feature: Dictionary in result.features:
		if not current.call():
			result.cancelled = true
			return result
		if str(feature.kind) == "rail":
			for place_id: String in feature.get("places", []) as Array:
				if not ids.has(place_id):
					result.errors.append("Unresolved railway place: " + place_id)
	var groups: Dictionary = {}
	var segment_counts: Dictionary = {}
	for feature: Dictionary in result.features:
		if not current.call():
			result.cancelled = true
			return result
		# Local hydrographic banks are a separate reference, not the exterior
		# of Natural Earth's physical land. Keep the fact, use the coast that
		# belongs to the installed physical fill for the actual map outline.
		if str(feature.kind)=="coast": continue
		if str(feature.kind) in ["settlement","landmark","geographic_region"]:
			continue
		if str(feature.kind)=="water_surface":
			if bounded_river_panel: continue
			var geometry := feature.geometry as Dictionary
			var polygons: Array = [geometry.coordinates] if str(geometry.type)=="Polygon" else geometry.coordinates as Array
			var chunk := {"kind":"water_surface","polygons":polygons,"feature_id":str(feature.id),"max_mpp":200.0}
			result.line_chunks.append(chunk)
			continue
		var lines: Array=[feature.geometry.coordinates]
		if feature.has("display_geometry"):
			if not feature.display_geometry is Dictionary:
				result.errors.append("Invalid local display geometry: "+str(feature.id));return result
			var display: Dictionary=feature.display_geometry
			if str(feature.get("display_geometry_role",""))!="RIVER_STROKE_CLIPPED_AT_INSTALLED_MODERN_SEA" or str(feature.kind)!="river" or display.get("type")!="MultiLineString" or not display.get("coordinates") is Array or (display.coordinates as Array).size()>32:
				result.errors.append("Invalid local display clipping: "+str(feature.id));return result
			lines=display.coordinates
			for raw: Variant in lines:
				if not raw is Array:
					result.errors.append("Invalid local display coordinates: "+str(feature.id));return result
				var copy := feature.duplicate()
				copy["geometry"]={"type":"LineString","coordinates":raw}
				if not _valid_feature(copy):
					result.errors.append("Invalid local display line: "+str(feature.id));return result
		var kind := str(feature.kind)
		if not groups.has(kind):
			groups[kind] = []
			segment_counts[kind] = 0
		for line: Array in lines:
			var points := PackedVector3Array()
			for coordinate: Array in line:
				var lon := deg_to_rad(float(coordinate[0]))
				var lat := deg_to_rad(float(coordinate[1]))
				points.append(Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)))
			for offset: int in range(0, points.size() - 1, 128):
				var part := points.slice(offset, mini(offset + 129, points.size()))
				(groups[kind] as Array).append({"kind": kind, "points": part, "feature_id":str(feature.id)})
				segment_counts[kind] += part.size() - 1
				if int(segment_counts[kind]) >= 256:
					result.line_chunks.append({"kind": kind, "boundaries": groups[kind], "max_mpp": 200.0})
					groups[kind] = []
					segment_counts[kind] = 0
	for kind: String in groups:
		if not (groups[kind] as Array).is_empty():
			result.line_chunks.append({"kind": kind, "boundaries": groups[kind], "max_mpp": 200.0})
	result.has_content = not result.features.is_empty()
	if not current.call(): result.cancelled = true
	return result

static func _valid_surface(surface: Dictionary) -> bool:
	if surface.get("schema_id")!="local_native_height_reference_r1" or surface.get("horizontal_crs")!="EPSG:4326": return false
	var width := int(surface.get("width",0))
	var height := int(surface.get("height",0))
	var rows := surface.get("height_rows_m",[]) as Array
	if width<2 or height<2 or width>128 or height>128 or rows.size()!=height or float(surface.get("step_degrees",0.0))<=0.0 or (surface.get("anchor_lon_lat",[]) as Array).size()!=2: return false
	for row: Variant in rows:
		if not row is Array or (row as Array).size()!=width: return false
		for value: Variant in row:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)): return false
	for cover: Variant in surface.get("cover_meshes",[]) as Array:
		if not cover is Dictionary or str(cover.get("kind","")) not in ["water_surface","woodland"] or str(cover.get("source_reference","")).is_empty(): return false
		for triangle: Variant in cover.get("triangles",[]) as Array:
			if not triangle is Array or triangle.size()!=3: return false
			for coordinate: Variant in triangle:
				if not coordinate is Array or coordinate.size()!=2: return false
				for value: Variant in coordinate:
					if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)): return false
	return true

static func _valid_miniature(feature: Dictionary, anchor_id: String) -> bool:
	var layout: Variant = feature.miniature_layout
	if not layout is Dictionary or str(feature.kind)!="geographic_region" or str(feature.geometry.type)!="Point": return false
	if str(layout.get("anchor_place_id",""))!=anchor_id or str(layout.get("model_path",""))!="res://assets/settlements/urban_landscape_r40.glb" or str(layout.get("geometry_role",""))!="ABSTRACT_MINIATURE_COMPOSITION": return false
	if str(layout.get("placement_notice_zh","" )).is_empty() or float(layout.get("max_mpp",0))<=0 or float(layout.max_mpp)>24.0 or float(layout.get("scale_max",0))<=0 or float(layout.scale_max)>3.0: return false
	for field: String in ["max_mpp","scale_max","target_height_px"]:
		var value: Variant = layout.get(field,null)
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<=0.0: return false
	if float(layout.target_height_px)>16.0: return false
	var placements: Variant = layout.get("placements",[])
	if not placements is Array or placements.size()>96: return false
	for entry: Variant in placements:
		if not entry is Dictionary or str(entry.get("module","")) not in ["paris_mansard","paris_corner","london_terrace","london_gabled","civic_hall","warehouse","sawtooth_workshop","quay_platform"]: return false
		if entry.has("reference_anchor_id") and (not entry.reference_anchor_id is String or str(entry.reference_anchor_id).is_empty()):return false
		var offset: Variant = entry.get("offset_m",[])
		var scale: Variant = entry.get("scale",[])
		if not offset is Array or offset.size()!=2 or not scale is Array or scale.size()!=3: return false
		for value: Variant in offset:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>500.0: return false
		for value: Variant in scale:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<=0 or float(value)>1.0: return false
		var heading: Variant = entry.get("heading_degrees",null)
		if typeof(heading) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(heading)): return false
	return true

static func _valid_feature(feature: Dictionary) -> bool:
	if str(feature.get("id", "")).is_empty() or feature.has("owner") or feature.has("controller_id") or feature.has("polity_id"):
		return false
	if not HistoricalFactEvidence.valid_date(str(feature.get("valid_from", ""))) or not HistoricalFactEvidence.valid_date(str(feature.get("valid_to", ""))) or str(feature.valid_from) >= str(feature.valid_to):
		return false
	var kind := str(feature.get("kind", ""))
	if kind not in ["settlement", "landmark", "geographic_region", "rail", "river", "coast","water_surface"]:
		return false
	var geometry := feature.get("geometry", {}) as Dictionary
	var points: Array = []
	if kind in ["settlement","landmark","geographic_region"] and str(geometry.get("type", "")) == "Point":
		points.append(geometry.get("coordinates", []))
	elif str(geometry.get("type", "")) == "LineString":
		points = geometry.get("coordinates", []) as Array
		if points.size() < 2:
			return false
	elif kind=="water_surface" and str(geometry.get("type","")) in ["Polygon","MultiPolygon"]:
		var polygons: Array = [geometry.coordinates] if str(geometry.type)=="Polygon" else geometry.coordinates as Array
		if polygons.is_empty(): return false
		for polygon: Array in polygons:
			if polygon.is_empty(): return false
			for ring: Array in polygon:
				if ring.size()<4 or ring[0]!=ring[-1]: return false
				points.append_array(ring.slice(0,ring.size()-1))
	else:
		return false
	var previous: Array = []
	for raw: Variant in points:
		if not raw is Array or (raw as Array).size() != 2:
			return false
		var point := raw as Array
		if typeof(point[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(point[1]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(point[0])) or not is_finite(float(point[1])) or absf(float(point[0])) > 180.0 or absf(float(point[1])) > 90.0:
			return false
		if point == previous:
			return false
		previous = point
	return true
