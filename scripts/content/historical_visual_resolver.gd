class_name HistoricalVisualResolver
extends RefCounted
## Resolves display evidence only; never creates or changes a runtime polity.

const CATALOG_PATH: String = "res://data/world_map/historical/political_visuals_1900.json"
const STYLE_PATH: String = "res://data/presentation/flag_visuals.json"
const UNITS_PATH: String = "res://data/world_map/historical/political_units_1900.json"
const PRIORITY: Array[String] = [
	"LOCAL_OFFICIAL_FLAG", "COLONIAL_FLAG", "PROTECTORATE_FLAG", "DOMINION_FLAG",
	"ADMINISTRATIVE_STANDARD", "GOVERNOR_STANDARD", "COMPANY_FLAG",
	"METROPOLITAN_FLAG", "COLOR_FALLBACK",
]
const DATE: String = "1900-01-01"
var errors: Array[String] = []
var _assets: Dictionary = {}
var _bindings: Dictionary = {}
var _units: Dictionary = {}
var _styles: Dictionary = {}
var _defaults: Dictionary = {}
var _textures: Dictionary = {}

func configure(flags: Dictionary) -> bool:
	errors.clear()
	_textures.clear()
	_assets = flags.duplicate(true)
	var catalog := ContentDocument.read(CATALOG_PATH, errors)
	_assets.merge(catalog.get("records", {}) as Dictionary, true)
	_bindings = catalog.get("territories", {}) as Dictionary
	_units.clear()
	var units := ContentDocument.read(UNITS_PATH, errors)
	for unit: Dictionary in units.get("units", []) as Array:
		_units[str(unit.id)] = unit
	var styles := ContentDocument.read(STYLE_PATH, errors)
	_defaults = styles.get("defaults", {}) as Dictionary
	_styles = styles.get("flags", {}) as Dictionary
	return errors.is_empty()

func resolve(unit: Dictionary, geometry_present: bool = true, date: String = DATE, candidate_id: String = "") -> Dictionary:
	if not geometry_present:
		return {"coverage_state": "SOURCE_NOT_PRESENT"}
	if unit.is_empty():
		return {"coverage_state": "GEOGRAPHY_PRESENT_NO_POLITY"}
	var source_id := str(unit.get("source_historical_id", unit.get("id", "")))
	var historical := _units.get(source_id, unit) as Dictionary
	var binding := _bindings.get(source_id, {}) as Dictionary
	var candidates: Array[Dictionary] = []
	for visual_id: String in binding.get("visual_ids", []) as Array:
		var asset := _assets.get(visual_id, {}) as Dictionary
		if _eligible(asset, date):
			candidates.append(asset)
	var flag := _assets.get(str(historical.get("flag_id", "")), {}) as Dictionary
	var flag_mode := str(historical.get("flag_mode", ""))
	if flag_mode == "local_historical_flag" and _eligible(flag, date):
		candidates.append(flag)
	# A protecting power's national flag remains national in its own evidence
	# record. Its use over a dependency is explicitly a presentation livery.
	if candidates.is_empty():
		var authority_asset := flag
		if flag_mode == "documented_absence":
			var authority := _units.get(str(historical.get("controller_id", "")), {}) as Dictionary
			authority_asset = _assets.get(str(authority.get("flag_id", "")), {}) as Dictionary
		if _eligible(authority_asset, date):
			candidates.append({
				"id": "authority:" + source_id,
				"visual_kind": "AUTHORITY_LIVERY",
				"display_role": "METROPOLITAN_FLAG",
				"components": [str(authority_asset.id)],
				"layout": "single",
				"source_page": str(authority_asset.get("source_page", "")),
				"historical_design_claim": false,
			})
	var resolved: Dictionary = {}
	for kind: String in PRIORITY:
		for asset: Dictionary in candidates:
			if str(asset.get("priority_role", asset.get("display_role", ""))) == kind:
				resolved = asset.duplicate(true)
				break
		if not resolved.is_empty():
			break
	# Candidate overrides are explicit review choices among dated evidence,
	# never a renderer exception or a country-dependent material rule.
	if not candidate_id.is_empty():
		for asset: Dictionary in candidates:
			if str(asset.id) == candidate_id:
				resolved = asset.duplicate(true)
	if resolved.is_empty():
		resolved = {"id": "color:" + source_id, "visual_kind": "POLITY_COLOR_FALLBACK", "display_role": "COLOR_FALLBACK",
			"color": binding.get("fallback_color", "#6b8075"), "historical_design_claim": false}
	var kind := str(resolved.visual_kind)
	resolved["presentation_visual_kind"] = kind
	resolved["historical_national_flag"] = binding.get("historical_national_flag",
		"NONE" if flag_mode == "documented_absence" else (
			str(flag.get("id", "")) if flag_mode == "local_historical_flag" and str(flag.get("visual_kind", "")) == "NATIONAL_FLAG" else "NOT_ASSERTED"))
	resolved["coverage_state"] = "POLITY_PRESENT_WITH_FLAG" if kind in ["NATIONAL_FLAG", "STATE_FLAG", "COLONIAL_FLAG"] else (
		"POLITY_PRESENT_NO_NATIONAL_FLAG" if kind == "POLITY_COLOR_FALLBACK" else "POLITY_PRESENT_WITH_ADMINISTRATIVE_VISUAL")
	resolved["historical_context"] = binding.duplicate(true)
	var components := resolved.get("components", []) as Array
	resolved["display_asset"] = resolved.get("asset_path", resolved.get("color", "presentation:" + str(resolved.id)))
	if components.size() == 1:
		resolved["display_asset"] = (_assets.get(str(components[0]), {}) as Dictionary).get("asset_path", "")
	resolved["source"] = resolved.get("source_page", "Presentation palette; no historical flag claim")
	resolved["confidence"] = resolved.get("confidence", "medium" if kind == "AUTHORITY_LIVERY" else "presentation_only")
	var style := _defaults.duplicate(true)
	style.merge(_styles.get(str(resolved.id), {}) as Dictionary, true)
	resolved["map_visual"] = style
	return resolved

func texture_for(resolved: Dictionary) -> Texture2D:
	var visual_id := str(resolved.get("id", ""))
	if _textures.has(visual_id):
		return _textures[visual_id] as Texture2D
	var texture: Texture2D
	var components := resolved.get("components", []) as Array
	if not components.is_empty():
		var images: Array[Image] = []
		for component_id: String in components:
			var component := texture_for(_assets.get(component_id, {}) as Dictionary)
			if component == null:
				return null
			images.append(component.get_image())
		if images.size() == 1:
			texture = ImageTexture.create_from_image(images[0])
		else:
			var width := images[0].get_width()
			var height := images[0].get_height()
			var combined := Image.create(width, height * images.size(), false, Image.FORMAT_RGBA8)
			for index: int in range(images.size()):
				var image := images[index].duplicate() as Image
				image.convert(Image.FORMAT_RGBA8)
				image.resize(width, height, Image.INTERPOLATE_LANCZOS)
				combined.blit_rect(image, Rect2i(0, 0, width, height), Vector2i(0, height * index))
			texture = ImageTexture.create_from_image(combined)
	else:
		var path := str(resolved.get("asset_path", ""))
		if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
			return null
		texture = ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture == null:
			return null
		var image := texture.get_image()
		var used := image.get_used_rect()
		if used != Rect2i(Vector2i.ZERO, image.get_size()):
			texture = ImageTexture.create_from_image(image.get_region(used))
	_textures[visual_id] = texture
	return texture

func _eligible(asset: Dictionary, date: String) -> bool:
	if asset.is_empty() or str(asset.get("priority_role", asset.get("display_role", ""))) not in PRIORITY:
		return false
	var dated := str(asset.get("display_valid_from", asset.get("valid_from", "9999"))) <= date and date < str(asset.get("valid_to", "0000"))
	if str(asset.get("display_role", "")) == "APPROXIMATE_HISTORICAL_VISUAL":
		dated = dated or (str(asset.get("approximate_valid_from", "9999")) <= date and date < str(asset.get("approximate_valid_to", "0000")))
	if not dated:
		return false
	var components := asset.get("components", []) as Array
	if not components.is_empty():
		for component_id: String in components:
			if not _eligible(_assets.get(component_id, {}) as Dictionary, date):
				return false
		return true
	var path := str(asset.get("asset_path", ""))
	return not path.is_empty() and ResourceLoader.exists(path, "Texture2D")
