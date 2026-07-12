class_name DeterministicRandomService
extends RefCounted
## Sole project wrapper for deterministic random calls and restorable RNG state.

var _rng := RandomNumberGenerator.new()
var _initial_seed: int


func _init(seed_value: int) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_initial_seed = seed_value
	_rng.seed = seed_value


func get_seed() -> int:
	return _initial_seed


func get_state() -> int:
	return _rng.state


func restore_state(state_value: int) -> void:
	_rng.state = state_value


func next_int(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "随机整数下限不得大于上限")
	return _rng.randi_range(minimum, maximum)


func next_float(minimum: float = 0.0, maximum: float = 1.0) -> float:
	assert(minimum <= maximum, "随机浮点下限不得大于上限")
	return _rng.randf_range(minimum, maximum)


func chance(probability: float) -> bool:
	var clamped_probability: float = clampf(probability, 0.0, 1.0)
	return _rng.randf() < clamped_probability


func pick_index(item_count: int) -> int:
	if item_count <= 0:
		return -1
	return next_int(0, item_count - 1)


func pick(values: Array) -> Variant:
	var index: int = pick_index(values.size())
	return null if index < 0 else values[index]


func shuffled_copy(values: Array) -> Array:
	var output: Array = values.duplicate(true)
	for index: int in range(output.size() - 1, 0, -1):
		var swap_index: int = next_int(0, index)
		var temporary: Variant = output[index]
		output[index] = output[swap_index]
		output[swap_index] = temporary
	return output

