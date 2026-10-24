extends RefCounted
## Original dry Ridgevale C1 field. Runtime support and terrain collider share this source.
const SOURCE_ID := "ridgevale_5km_c1_20261020"
const WIDTH := 1251
const STEP := 4.0
const ORIGIN := -2500.0
const HEIGHT_FILE := "res://ridgevale/assets/height_4m.f32"
var heights := PackedFloat32Array()
var valid := false

func _init() -> void:
	var file := FileAccess.open(HEIGHT_FILE, FileAccess.READ)
	if file == null or file.get_length() != WIDTH * WIDTH * 4:
		push_error("Ridgevale heightfield missing or incorrect byte count")
		return
	heights = file.get_buffer(file.get_length()).to_float32_array()
	valid = heights.size() == WIDTH * WIDTH
	if valid:
		for height in heights:
			if not is_finite(height):
				valid = false
				push_error("Ridgevale heightfield contains non-finite data")
				break

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
	return Vector3(sample(x - 2.0, z) - sample(x + 2.0, z), 4.0, sample(x, z - 2.0) - sample(x, z + 2.0)).normalized()
