class_name VNextTravelService
extends RefCounted


func execute(
	runtime: VNextWorldRuntime,
	location: VNextLocationState,
	quote: VNextTravelQuote
) -> bool:
	if runtime == null or location == null or quote == null:
		return false
	if not location.is_valid() or not quote.is_valid():
		return false
	if location.place_id() != quote.origin_place_id():
		return false

	var runtime_before: Dictionary = runtime.snapshot()
	var location_before: Dictionary = location.snapshot()
	if not runtime.advance_minutes(quote.duration_minutes()):
		return false
	if not location.move_to(quote.destination_place_id()):
		runtime.restore(runtime_before)
		location.restore(location_before)
		return false
	return true
