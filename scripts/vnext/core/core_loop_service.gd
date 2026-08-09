class_name VNextCoreLoopService
extends RefCounted


func execute_paid_travel(
	runtime: VNextWorldRuntime, quote: VNextTravelQuote
) -> bool:
	if runtime == null or quote == null:
		return false
	if not runtime.is_valid() or not quote.is_valid():
		return false

	var wallet: VNextPersonalWallet = runtime.wallet()
	var location: VNextLocationState = runtime.location()
	if wallet == null or location == null:
		return false
	if not wallet.is_valid() or not location.is_valid():
		return false
	if wallet.owner_id() != runtime.player_id():
		return false
	if location.player_id() != runtime.player_id():
		return false
	if location.place_id() != quote.origin_place_id():
		return false
	if not runtime.can_advance_minutes(quote.duration_minutes()):
		return false
	if quote.cost_minor() > 0 and not wallet.can_debit(quote.cost_minor()):
		return false

	if quote.cost_minor() > 0 and not wallet.debit(quote.cost_minor()):
		return false
	return VNextTravelService.new().execute(runtime, location, quote)
