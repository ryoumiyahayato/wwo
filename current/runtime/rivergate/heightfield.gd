extends RefCounted
## Rivergate authoritative base samples for this map's visual terrain AND collision.
const WIDTH := 1251
const STEP := 4.0
const ORIGIN := -2500.0
const HEIGHT_FILE := "res://rivergate/assets/height_4m.f32"
const HYDRO_FILE := "res://rivergate/assets/hydrology.json"
var heights := PackedFloat32Array()
var hydro: Dictionary = {}
var valid := false

func _init() -> void:
	var file := FileAccess.open(HEIGHT_FILE, FileAccess.READ)
	if file == null or file.get_length() != WIDTH * WIDTH * 4:
		push_error("Rivergate heightfield missing/wrong byte count")
		return
	heights = file.get_buffer(file.get_length()).to_float32_array()
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(HYDRO_FILE))
	if not decoded is Dictionary or decoded.get("schema", "") != "rivergate-hydrology-v1":
		push_error("Rivergate hydrology invalid")
		return
	hydro = decoded
	valid = heights.size() == WIDTH * WIDTH and hydro.get("profile", []).size() == 1001

func sample(x: float, z: float) -> float:
	if not valid or not is_finite(x) or not is_finite(z): return NAN
	var fx := clampf((x - ORIGIN) / STEP, 0.0, WIDTH - 1.000001)
	var fz := clampf((z - ORIGIN) / STEP, 0.0, WIDTH - 1.000001)
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var row := iz * WIDTH + ix
	return lerpf(lerpf(heights[row], heights[row + 1], tx), lerpf(heights[row + WIDTH], heights[row + WIDTH + 1], tx), tz)

func normal_at(x: float, z: float) -> Vector3:
	return Vector3(sample(x - 2.0,z) - sample(x + 2.0,z), 4.0, sample(x,z - 2.0) - sample(x,z + 2.0)).normalized()

func profile_at(z: float) -> Dictionary:
	var coord := clampf((z + 2500.0) / 5.0, 0.0, 999.99999)
	var index := floori(coord)
	var t := coord - index
	var rows: Array = hydro.profile
	var a: Dictionary = rows[index]
	var b: Dictionary = rows[index + 1]
	return {"z": z, "x": lerpf(float(a.x), float(b.x),t), "half_width": lerpf(float(a.half_width),float(b.half_width),t), "water_y": lerpf(float(a.water_y),float(b.water_y),t)}

func bridge_surface_height(x: float, z: float) -> float:
	var b: Dictionary = hydro.bridge
	if absf(z - float(b.center_z)) <= float(b.width_m) * 0.5 and absf(x - float(b.center_x)) <= float(b.half_span_m):
		return float(b.deck_top_y)
	return -INF
