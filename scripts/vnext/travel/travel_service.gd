class_name VNextTravelService
extends RefCounted


func execute(
	runtime: VNextWorldRuntime,
	location_or_quote: Variant,
	quote: VNextTravelQuote = null
) -> bool:
	if quote == null:
		if typeof(location_or_quote) != TYPE_OBJECT:
			return false
		var paid_quote := location_or_quote as VNextTravelQuote
		return execute_paid(runtime, paid_quote)

	if typeof(location_or_quote) != TYPE_OBJECT:
		return false
	var location := location_or_quote as VNextLocationState
	return _execute_unpaid(runtime, location, quote)


func execute_paid(
	runtime: VNextWorldRuntime, quote: VNextTravelQuote
) -> bool:
	if runtime == null or quote == null:
		return false
	if not runtime.is_valid() or not quote.is_valid():
		return false

	var location: VNextLocationState = runtime.location()
	var wallet: VNextPersonalWallet = runtime.wallet()
	if location == null or wallet == null:
		return false
	if not location.is_valid() or not wallet.is_valid():
		return false
	if location.player_id() != runtime.player_id():
		return false
	if location.place_id() != quote.origin_place_id():
		return false
	if quote.cost_minor() > 0 and not wallet.can_debit(quote.cost_minor()):
		return false

	var runtime_before: Dictionary = runtime.snapshot()
	if quote.cost_minor() > 0 and not wallet.debit(quote.cost_minor()):
		return false
	if not runtime.advance_minutes(quote.duration_minutes()):
		runtime.restore(runtime_before)
		return false
	if not location.move_to(quote.destination_place_id()):
		runtime.restore(runtime_before)
		return false
	return true


func _execute_unpaid(
	runtime: VNextWorldRuntime,
	location: VNextLocationState,
	quote: VNextTravelQuote
) -> bool:
	if runtime == null or location == null or quote == null:
		return false
	if not runtime.is_valid() or not location.is_valid() or not quote.is_valid():
		return false
	if location.player_id() != runtime.player_id():
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
