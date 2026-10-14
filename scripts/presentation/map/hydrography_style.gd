class_name HydrographyStyle
extends RefCounted
## Display semantics only. Source feature kinds and territorial identities stay authoritative.
const LINE_COLORS: Dictionary = {
	"rail": Color(0.78, 0.69, 0.48, 0.90),
	"river": Color(0.29, 0.52, 0.61, 0.88),
	"coast": Color(0.26, 0.42, 0.48, 0.85),
}
const WIDTHS: Dictionary = {"rail": 2.4, "river": 1.25, "coast": 0.9}
const SURFACE_COLORS: Dictionary = {
	"lake": Color(0.13, 0.29, 0.36, 1.0),
	"inland_sea": Color(0.10, 0.21, 0.27, 1.0),
}
const WATER_MITER_LIMIT: float = 1.5
const WATER_FEATHER: float = 0.70
const LEGACY_MITER_LIMIT: float = 3.0
const LEGACY_FEATHER: float = 1.25

static func surface_class(feature: Dictionary) -> String:
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
	if kind == "ocean_reference": return Color(0.10, 0.14, 0.16, 1.0)
	if kind == "land_reference": return Color(0.66,0.73,0.76,1.0) if water_class == "antarctic_land" else Color(0.27, 0.32, 0.29, 1.0)
	return SURFACE_COLORS[water_class] as Color if kind == "lake" else LINE_COLORS[kind] as Color

static func miter_limit(kind: String) -> float:
	return WATER_MITER_LIMIT if kind in ["river", "coast"] else LEGACY_MITER_LIMIT

static func feather(kind: String) -> float:
	return WATER_FEATHER if kind in ["river", "coast"] else LEGACY_FEATHER
