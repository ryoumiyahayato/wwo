class_name MapScaleStyle
extends RefCounted
## Visual bands only; neither aggregation cells nor administrative identities.
const REGION_MID_MPP: float = 2400.0
const REGION_NEAR_MPP: float = 650.0
const LOCAL_DETAIL_MPP: float = 115.0
const PHYSICAL_MAX_MPP: float = 6500.0
const MEDIUM_LOD_MPP: float = StrategicSpatialLoader.MEDIUM_LOD_MPP
const LOCAL_LOD_MPP: float = 220.0
# Installed global assets: 1024x512 overview and 4096x2048 detail. Admit
# detail while an overview sample grows from two to four screen pixels.
# These are output sampling limits, not ETOPO's native measurement spacing.
const GLOBAL_OVERVIEW_SAMPLE_M: float = TAU * 6371008.8 / 1024.0
const GLOBAL_RELIEF_DETAIL_BEGIN_MPP: float = GLOBAL_OVERVIEW_SAMPLE_M * 0.5
const GLOBAL_RELIEF_DETAIL_FULL_MPP: float = GLOBAL_OVERVIEW_SAMPLE_M * 0.25
const GLOBAL_RELIEF_RELEASE_MPP: float = GLOBAL_OVERVIEW_SAMPLE_M * 0.65
const REGIONAL_NODES: Array[String] = ["place:versailles", "place:saint_denis", "place:creil", "place:longueau", "place:melun", "place:meaux", "place:chantilly", "place:mantes", "place:vernon", "place:chateau_thierry"]
const FLAG_STOPS: Array[Vector2] = [
	Vector2(300.0, 0.0), Vector2(650.0, 0.18), Vector2(1200.0, 0.52),
	Vector2(3000.0, 0.92), Vector2(5500.0, 1.0),
]
const SETTLEMENT_RADII: Dictionary = {0:2.2,1:1.7,2:1.1}

static func flag_weight(mpp: float) -> float:
	if mpp <= FLAG_STOPS[0].x:
		return FLAG_STOPS[0].y
	for index: int in range(1, FLAG_STOPS.size()):
		var a := FLAG_STOPS[index - 1]
		var b := FLAG_STOPS[index]
		if mpp <= b.x:
			var ratio := smoothstep(0.0, 1.0, (log(mpp) - log(a.x)) / (log(b.x) - log(a.x)))
			return lerpf(a.y, b.y, ratio)
	return 1.0

static func relief_weight(mpp: float, map_mode: String) -> float:
	# Keep broad ETOPO forms at close scales without claiming finer samples.
	# LOCAL adds its admitted native relief over this continuous reference.
	var weight := lerpf(0.26,0.84,1.0-smoothstep(log(1800.0),log(18000.0),log(maxf(mpp,1.0))))
	if map_mode in ["geographic","military"]: return lerpf(0.92,0.70,smoothstep(log(1800.0),log(18000.0),log(maxf(mpp,1.0))))
	return weight * (1.0 if map_mode=="political" else 0.28)

static func relief_detail_weight(mpp: float) -> float:
	return 1.0 - smoothstep(log(GLOBAL_RELIEF_DETAIL_FULL_MPP), log(GLOBAL_RELIEF_DETAIL_BEGIN_MPP), log(maxf(mpp, 1.0)))

static func political_weight(mpp: float) -> float:
	# Physical ground dominates near views; dated ink remains at strategic scales.
	return lerpf(0.12,0.68,smoothstep(log(300.0),log(6500.0),log(maxf(mpp,1.0))))*smoothstep(150.0,450.0,mpp)

static func economic_country_weight(mpp: float) -> float:
	# Country employment colour is strategic information. At street/city
	# scales use physical ground and actual hubs, without extending old ink
	# into newly resolved modern coast or claiming parcel-level industry.
	return .92*smoothstep(log(250.0),log(1200.0),log(maxf(mpp,1.0)))

static func physical_weight(kind: String, mpp: float) -> float:
	var begin := 4000.0 if kind == "rail" else 5500.0 if kind == "river" else PHYSICAL_MAX_MPP
	var full := 1800.0 if kind == "rail" else 1600.0 if kind == "river" else 3500.0
	return 1.0 - smoothstep(log(full), log(begin), log(maxf(mpp, 1.0)))

static func strategic_weight(kind: String, mpp: float) -> float:
	var begin := 6500.0 if kind == "rail" else 8500.0
	var full := 2500.0 if kind == "rail" else 5500.0 if kind == "lake" else 4000.0
	return 1.0 - smoothstep(log(full), log(begin), log(maxf(mpp, 1.0)))

static func strategic_rail_width(mpp: float) -> float:
	return lerpf(1.15,1.85,1.0-smoothstep(log(900.0),log(6500.0),log(maxf(mpp,1.0))))

static func settlement_limit(rank: int, id: String = "") -> float:
	return 6000.0 if rank == 0 else 5000.0 if rank == 1 else 900.0 if id in REGIONAL_NODES else LOCAL_DETAIL_MPP

static func lod(mpp: float) -> String:
	return "coarse" if mpp > MEDIUM_LOD_MPP else "medium" if mpp > LOCAL_LOD_MPP else "local"

static func band(mpp: float, regional: bool, local: bool) -> String:
	if not regional:
		return "WORLD"
	if local:
		return "LOCAL CLOSE" if mpp <= LOCAL_DETAIL_MPP else "LOCAL FAR"
	return "REGION FAR" if mpp > REGION_MID_MPP else "REGION MID" if mpp > REGION_NEAR_MPP else "REGION NEAR"
