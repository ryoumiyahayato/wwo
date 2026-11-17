class_name HydrographyStyle
extends RefCounted
## Display semantics only. Source feature kinds and territorial identities stay authoritative.
const OCEAN_COLOR: Color = Color(0.12,0.20,0.23,1.0)
const BANK_COLOR: Color = Color(0.40,0.47,0.43,1.0)
const LINE_COLORS: Dictionary = {
	"rail": Color(0.78, 0.69, 0.48, 0.90),
	"river": Color(0.30, 0.43, 0.44, 0.88),
	"coast": Color(0.27, 0.37, 0.38, 0.64),
}
const WIDTHS: Dictionary = {"rail": 2.4, "river": 0.95, "coast": 0.7}
const SURFACE_COLORS: Dictionary = {
	"river_surface": Color(0.34,0.46,0.45,1.0),
	"lake": Color(0.25, 0.36, 0.37, 1.0),
	"inland_sea": Color(0.13, 0.23, 0.27, 1.0),
	"historical_sea_reference": OCEAN_COLOR,
	"modern_sea_reference": OCEAN_COLOR,
	"historical_lake_reference": Color(0.25,0.36,0.37,1.0),
	"playa_reference": Color(0.62,0.59,0.48,1.0),
}
const WATER_MITER_LIMIT: float = 1.5
const WATER_FEATHER: float = 0.70
const LEGACY_MITER_LIMIT: float = 3.0
const LEGACY_FEATHER: float = 1.25
static var _london_water_transition: Vector2 = Vector2.INF

static func surface_transition(feature_id: String) -> Vector2:
	if not feature_id.begins_with("lake:london_thames_surface:"): return Vector2.ZERO
	if not _london_water_transition.is_finite():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/settlements/london_1890s/index.json"))
		var data: Dictionary = value if value is Dictionary else {}
		var limits: Array = (data.get("water_lods",{}) as Dictionary).get("color_transition_longitudes",[])
		_london_water_transition = Vector2(float(limits[0]),float(limits[1])) if limits.size()==2 else Vector2.ZERO
	return _london_water_transition

static func surface_class(feature: Dictionary) -> String:
	if str(feature.get("water_class","")) == "river_surface": return "river_surface"
	if str(feature.get("kind",""))=="lake" and str(feature.get("water_class",""))=="playa_reference": return "playa_reference"
	if str(feature.get("kind",""))=="lake" and str(feature.get("water_class",""))=="modern_sea_reference": return "modern_sea_reference"
	# Explicit admitted chart-derived water, never inferred from height/name.
	if str(feature.get("kind",""))=="lake" and str(feature.get("water_class",""))=="historical_sea_reference": return "historical_sea_reference"
	if str(feature.get("kind",""))=="lake" and str(feature.get("water_class",""))=="historical_lake_reference": return "historical_lake_reference"
	# These existing physical land shards cover Antarctica south of 60 S.
	# Colour only admitted land triangles; ocean/sea ice is never classified here.
	if str(feature.get("kind", "")) == "land_reference":
		var id := str(feature.get("id",feature.get("feature_id","")))
		for reference: String in ["land_reference:physical_0_0","land_reference:physical_1_0","land_reference:physical_2_0","land_reference:physical_3_0"]:
			if id == reference or id.begins_with(reference+"_"): return "antarctic_land"
	# The admitted Caspian geometry is the NE ocean dataset's closed inland
	# component. Do not infer a sea from area, a name substring or ownership.
	if str(feature.get("kind", "")) == "lake" and str(feature.get("id", feature.get("feature_id", ""))) == "lake:caspiansea" and str(feature.get("source_geometry_file", "")) in ["ne_50m_ocean.geojson", "ne_10m_ocean.geojson"]:
		return "inland_sea"
	return "lake"

static func color(kind: String, water_class: String = "lake") -> Color:
	if kind == "ocean_reference": return OCEAN_COLOR
	if kind == "land_reference": return Color(0.66,0.73,0.76,1.0) if water_class == "antarctic_land" else Color(0.40,0.44,0.36,1.0)
	return SURFACE_COLORS[water_class] as Color if kind in ["lake","water_surface"] else LINE_COLORS[kind] as Color

static func water_ink(bank_weight: float) -> Color:
	# Shore proximity is a print tone, never an inferred water-depth value.
	return color("water_surface").lerp(BANK_COLOR,clampf(bank_weight,0.0,1.0)*0.22)

static func miter_limit(kind: String) -> float:
	return WATER_MITER_LIMIT if kind in ["river", "coast"] else LEGACY_MITER_LIMIT

static func feather(kind: String) -> float:
	return WATER_FEATHER if kind in ["river", "coast"] else LEGACY_FEATHER

static func line_color(kind: String, style: String = "") -> Color:
	if kind!="river": return color(kind)
	match style:
		"unknown": return Color(0.48,0.47,0.38,0.76)
		"dry_valley": return Color(0.51,0.43,0.31,0.80)
		"seasonal", "intermittent": return Color(0.36,0.47,0.46,0.80)
		"canal": return Color(0.39,0.52,0.55,0.90)
	return color(kind)

static func line_dash(style: String) -> Vector2:
	match style:
		"unknown": return Vector2(9.0,0.40)
		"dry_valley": return Vector2(10.0,0.60)
		"seasonal", "intermittent": return Vector2(8.0,0.55)
		"canal": return Vector2(12.0,0.82)
	return Vector2.ZERO
