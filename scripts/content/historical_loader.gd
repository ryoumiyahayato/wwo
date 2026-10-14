class_name HistoricalLoader
extends RefCounted
## Content preparation only. Current politics and player identity remain in the world.

var geography := GeographyLoader.new()
var administration := AdministrativeLoader.new()
var evidence := EvidenceLoader.new()
var errors: Array[String] = []
const REGIONS_PATH: String = "res://data/presentation/arabia_political_map_regions_1900.json"
var _display_document: Dictionary = {}
var _geographic_records: Dictionary = {}
var _selected_display_place: Dictionary = {}
var geometry_content: MapGeometryContent
var local_spatial := LocalSpatialLoader.new()
var strategic_spatial := StrategicSpatialLoader.new()
var _display_change_dates: Array[String] = []

func remember_geographic_reference(reference: Dictionary) -> void:
	# A selected display reference is not inserted into SpatialWorld or politics.
	_selected_display_place = reference.duplicate(true)

func load_current(gate: HistoricalProvenanceGate) -> bool:
	geography.load_current(gate)
	administration.load_current(gate)
	evidence.load_current()
	_display_document = ContentDocument.read(REGIONS_PATH, errors)
	geometry_content = MapGeometryContent.new(geography.parts_by_feature, geography.presentation)
	for annotation: Dictionary in geography.presentation.get("geographic_annotations", {}).get("annotations", []) as Array:
		var record := annotation.duplicate()
		record.erase("geometry")
		record["place_id"] = record.id
		_geographic_records[str(record.id)] = record
	_display_change_dates.clear()
	for metadata: Variant in [_display_document, geography.presentation, evidence.flag_records, administration.authority_assignments, administration.france_identity, administration.reference_documents]:
		_collect_display_dates(metadata)
	_display_change_dates.sort()
	errors.append_array(geography.errors)
	errors.append_array(administration.errors)
	errors.append_array(evidence.errors)
	return errors.is_empty()

func _collect_display_dates(metadata: Variant) -> void:
	if metadata is Dictionary:
		for key: Variant in metadata:
			if str(key) in ["valid_from", "valid_to", "exists_from", "exists_to"]:
				var date := str(metadata[key])
				if date.length()==10 and not date in _display_change_dates: _display_change_dates.append(date)
			elif metadata[key] is Dictionary or metadata[key] is Array:
				_collect_display_dates(metadata[key])
	elif metadata is Array:
		for entry: Variant in metadata:
			if entry is Dictionary or entry is Array: _collect_display_dates(entry)

func display_changes_between(previous: String, current: String) -> bool:
	for date: String in _display_change_dates:
		if date>previous and date<=current: return true
	return false

func flag_texture(time: Dictionary, flag_id: String) -> Texture2D:
	var date := _date_key(time)
	var flag := evidence.flag_record(flag_id)
	if date<str(flag.get("valid_from","")) or date>=str(flag.get("valid_to","")) or str(flag.get("render_mode",""))!="source_asset": return null
	var path := str(flag.get("asset_path",""))
	return ResourceLoader.load(path,"Texture2D") as Texture2D if ResourceLoader.exists(path,"Texture2D") else null

func resolve_map(time: Dictionary, current_units: Array[Dictionary]) -> ResolvedMapContent:
	var date := _date_key(time)
	var document: Dictionary = {}
	if str(_display_document.get("valid_from", "")) <= date and date < str(_display_document.get("valid_to", "")):
		document = _display_document.duplicate(true)
	var units: Array[Dictionary] = []
	units.assign(current_units.duplicate(true))
	var occupied: Dictionary = {}
	for unit: Dictionary in units:
		occupied[str(unit.get("geometry_feature_id", ""))] = true
	for authority: Dictionary in administration.authorities_active_on(date):
		if authority.has("geometry_component_indices"):
			continue
		var feature_id := str(authority.geometry_feature_id)
		if not occupied.has(feature_id) and geometry_content.has_feature(feature_id):
			units.append(authority)
			occupied[feature_id] = true
	var visuals: Dictionary = {}
	var textures: Dictionary = {}
	var visual_units := units.duplicate(true)
	for region: Dictionary in document.get("political_map_regions", []) as Array:
		visual_units.append({"id": region.id, "source_historical_id": region.historical_authority_id,
			"geometry_feature_id": "arabia_undelimited_desert_1900", "representative_visual_id": region.representative_visual_id})
	for unit: Dictionary in visual_units:
		var owner := str(unit.id)
		var resolved := evidence.visual_resolver.resolve(unit, geometry_content.has_feature(str(unit.get("geometry_feature_id", ""))), date, str(unit.get("representative_visual_id", "")))
		visuals[owner] = resolved
		var texture := evidence.visual_resolver.texture_for(resolved)
		if texture != null:
			textures[owner] = texture
	return ResolvedMapContent.new(date, units, document, visuals, textures)

func resolve_world_page(time: Dictionary, polity: Dictionary, selected_place_id: String = "") -> WorldPageContent:
	var date := _date_key(time)
	var source_id := str(polity.get("source_historical_id", ""))
	var flag := evidence.flag_record(str(polity.get("flag_id", ""))).duplicate(true)
	var texture := flag_texture(time,str(polity.get("flag_id","")))
	# The dossier retains the historical flag record even outside its interval.
	# Only its display texture is date-gated; missing evidence stays missing.
	var place: Dictionary = {}
	if _geographic_records.has(selected_place_id):
		var annotation := _geographic_records[selected_place_id] as Dictionary
		if date >= str(annotation.get("valid_from","")) and date < str(annotation.get("valid_to","9999-12-31")):
			place = annotation.duplicate()
			# Dated dossier metadata only; no political entity or world fact changes.
			for period: Dictionary in annotation.get("historical_political_periods",[]) as Array:
				if date<str(period.get("valid_from","")) or date>=str(period.get("valid_to","9999-12-31")): continue
				for field: String in ["historical_political_identity","political_reference_date","note_zh"]:
					if period.has(field): place[field] = period[field]
				break
	if local_spatial.content != null and local_spatial.content.display_active_on(date):
		for visual: Dictionary in local_spatial.content.landmark_visuals():
			if str(visual.id)==selected_place_id and LocalSpatialContent.landmark_visible_on(visual,date):
				place = visual.duplicate(true)
				place.merge({"place_id":str(visual.id),"name":str(visual.display_name),"spatial_kind":"historical_landmark"})
				break
		for feature: Dictionary in local_spatial.content.features:
			if local_spatial.content.active_on(date) and str(feature.id) == selected_place_id and str(feature.kind) in ["settlement","geographic_region"]:
				place = feature.duplicate(true)
				place["place_id"] = feature.id
				place["name"] = feature.display_name
				place["spatial_kind"] = "geographic_region" if str(feature.kind)=="geographic_region" else "historical settlement"
				break
	if place.is_empty() and strategic_spatial.content != null and strategic_spatial.content.active_on(date):
		for feature: Dictionary in strategic_spatial.content.features:
			if str(feature.id) == selected_place_id and str(feature.kind) == "settlement":
				place = feature.duplicate(true)
				place["place_id"] = feature.id
				place["name"] = feature.display_name
				place["spatial_kind"] = "historical strategic settlement"
				break
	var cached_active := LocalSpatialContent.landmark_visible_on(_selected_display_place,date) if str(_selected_display_place.get("kind",""))=="landmark" else date>=str(_selected_display_place.get("valid_from","")) and date<str(_selected_display_place.get("valid_to","9999-12-31"))
	if place.is_empty() and str(_selected_display_place.get("place_id",""))==selected_place_id and cached_active:
		place = _selected_display_place
	if not selected_place_id.is_empty():
		if not place.is_empty(): _selected_display_place = place
		elif str(_selected_display_place.get("place_id","")) != selected_place_id: _selected_display_place = {}
	return WorldPageContent.new(date, administration.profiles.get(source_id, {}) as Dictionary, administration.administration_for(source_id, date), flag, texture, place)

static func _date_key(time: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(time.year), int(time.month), int(time.day)]
