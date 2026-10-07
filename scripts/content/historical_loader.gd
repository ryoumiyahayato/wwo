class_name HistoricalLoader
extends RefCounted
## Content preparation only. Current politics and player identity remain in the world.

var geography := GeographyLoader.new()
var administration := AdministrativeLoader.new()
var evidence := EvidenceLoader.new()
var errors: Array[String] = []
const REGIONS_PATH: String = "res://data/presentation/arabia_political_map_regions_1900.json"
var _display_document: Dictionary = {}
var geometry_content: MapGeometryContent
var local_spatial := LocalSpatialLoader.new()
var strategic_spatial := StrategicSpatialLoader.new()

func load_current(gate: HistoricalProvenanceGate) -> bool:
	geography.load_current(gate)
	administration.load_current(gate)
	evidence.load_current()
	_display_document = ContentDocument.read(REGIONS_PATH, errors)
	geometry_content = MapGeometryContent.new(geography.parts_by_feature)
	errors.append_array(geography.errors)
	errors.append_array(administration.errors)
	errors.append_array(evidence.errors)
	return errors.is_empty()

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
	var texture: Texture2D = null
	# The dossier retains the historical flag record even outside its interval.
	# Only its display texture is date-gated; missing evidence stays missing.
	if str(flag.get("valid_from", "")) <= date and date < str(flag.get("valid_to", "")) and str(flag.get("render_mode", "")) == "source_asset":
		var path := str(flag.get("asset_path", ""))
		if ResourceLoader.exists(path, "Texture2D"):
			texture = ResourceLoader.load(path, "Texture2D") as Texture2D
	var place: Dictionary = {}
	if local_spatial.content != null and local_spatial.content.active_on(date):
		for feature: Dictionary in local_spatial.content.features:
			if str(feature.id) == selected_place_id and str(feature.kind) == "settlement":
				place = feature.duplicate(true)
				place["place_id"] = feature.id
				place["name"] = feature.display_name
				place["spatial_kind"] = "historical settlement"
				break
	if place.is_empty() and strategic_spatial.content != null and strategic_spatial.content.active_on(date):
		for feature: Dictionary in strategic_spatial.content.features:
			if str(feature.id) == selected_place_id and str(feature.kind) == "settlement":
				place = feature.duplicate(true)
				place["place_id"] = feature.id
				place["name"] = feature.display_name
				place["spatial_kind"] = "historical strategic settlement"
				break
	return WorldPageContent.new(date, administration.profiles.get(source_id, {}) as Dictionary, administration.historical_by_source.get(source_id, {}) as Dictionary, flag, texture, place)

static func _date_key(time: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(time.year), int(time.month), int(time.day)]
