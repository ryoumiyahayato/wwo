extends SceneTree

const SOURCE_PATH: String = "res://scripts/vnext/economy/market_economy.gd"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source: String = FileAccess.get_file_as_string(SOURCE_PATH)
	_check(not source.is_empty(), "market economy source is readable")
	source = source.replace("\r\n", "\n")

	var scale_anchor: String = "const MIN_PRICE_CENTIMES: int = 1\nconst SEASONAL_COMMODITY_CATEGORIES: Dictionary = {"
	var scale_replacement: String = "const MIN_PRICE_CENTIMES: int = 1\nconst PRICE_SCALE: int = 10000\nconst SEASONAL_COMMODITY_CATEGORIES: Dictionary = {"
	_check(source.contains(scale_anchor), "price scale anchor is exact")
	if source.contains(scale_anchor):
		source = source.replace(scale_anchor, scale_replacement)

	var policy_anchor: String = "\t\"price_smoothing_bp\": 1800,\n\t\"maximum_daily_price_change_bp\": 1400,"
	var policy_replacement: String = (
		"\t\"price_smoothing_bp\": 1800,\n"
		+ "\t\"maximum_daily_price_change_bp\": 1400,\n"
		+ "\t\"same_day_balance_pressure_bp\": 1800,"
	)
	_check(source.contains(policy_anchor), "price policy anchor is exact")
	if source.contains(policy_anchor):
		source = source.replace(policy_anchor, policy_replacement)

	var pressure_anchor: String = (
		"\t\t\tvar stock_pressure_bp: int = clampi(\n"
		+ "\t\t\t\tint(round((1.0 - coverage) * 3200.0)), -5000, 5000\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar shortage_pressure_bp: int = int(round(unmet_ratio * 6500.0))\n"
		+ "\t\t\tvar price_shock_bp: int = _active_price_modifier_bp(\n"
		+ "\t\t\t\tregion_id, commodity_id\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar target_multiplier_bp: int = (\n"
		+ "\t\t\t\tBASIS_POINTS + stock_pressure_bp + shortage_pressure_bp + price_shock_bp\n"
		+ "\t\t\t)"
	)
	var pressure_replacement: String = (
		"\t\t\tvar same_day_supply: float = maxf(\n"
		+ "\t\t\t\t0.0, float(commodity_state.get(\"supply_units\", 0.0))\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar flow_scale: float = maxf(1.0, maxf(demand, same_day_supply))\n"
		+ "\t\t\tvar flow_imbalance: float = clampf(\n"
		+ "\t\t\t\t(demand - same_day_supply) / flow_scale, -1.0, 1.0\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar same_day_pressure_bp: int = int(round(\n"
		+ "\t\t\t\tflow_imbalance\n"
		+ "\t\t\t\t* float(_policies.get(\"same_day_balance_pressure_bp\", 1800))\n"
		+ "\t\t\t))\n"
		+ "\t\t\tvar stock_pressure_bp: int = clampi(\n"
		+ "\t\t\t\tint(round((1.0 - coverage) * 3200.0)), -5000, 5000\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar shortage_pressure_bp: int = int(round(unmet_ratio * 6500.0))\n"
		+ "\t\t\tvar price_shock_bp: int = _active_price_modifier_bp(\n"
		+ "\t\t\t\tregion_id, commodity_id\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar target_multiplier_bp: int = (\n"
		+ "\t\t\t\tBASIS_POINTS\n"
		+ "\t\t\t\t+ stock_pressure_bp\n"
		+ "\t\t\t\t+ shortage_pressure_bp\n"
		+ "\t\t\t\t+ same_day_pressure_bp\n"
		+ "\t\t\t\t+ price_shock_bp\n"
		+ "\t\t\t)\n"
		+ "\t\t\tcommodity_state[\"same_day_balance_pressure_bp\"] = same_day_pressure_bp\n"
		+ "\t\t\tcommodity_state[\"same_day_supply_demand_ratio_bp\"] = int(round(\n"
		+ "\t\t\t\tflow_imbalance * BASIS_POINTS\n"
		+ "\t\t\t))"
	)
	_check(source.contains(pressure_anchor), "price pressure anchor is exact")
	if source.contains(pressure_anchor):
		source = source.replace(pressure_anchor, pressure_replacement)

	var precision_anchor: String = (
		"\t\t\tvar target_price: int = maxi(\n"
		+ "\t\t\t\tMIN_PRICE_CENTIMES, base_price * target_multiplier_bp / BASIS_POINTS\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar previous_price: int = maxi(\n"
		+ "\t\t\t\tMIN_PRICE_CENTIMES, int(commodity_state.get(\"price_centimes\", base_price))\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar smoothed: int = (\n"
		+ "\t\t\t\tprevious_price * (BASIS_POINTS - smoothing_bp)\n"
		+ "\t\t\t\t+ target_price * smoothing_bp\n"
		+ "\t\t\t) / BASIS_POINTS\n"
		+ "\t\t\tvar minimum_price: int = maxi(\n"
		+ "\t\t\t\tMIN_PRICE_CENTIMES,\n"
		+ "\t\t\t\tprevious_price * (BASIS_POINTS - max_change_bp) / BASIS_POINTS\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar maximum_price: int = maxi(\n"
		+ "\t\t\t\tminimum_price,\n"
		+ "\t\t\t\tprevious_price * (BASIS_POINTS + max_change_bp) / BASIS_POINTS\n"
		+ "\t\t\t)\n"
		+ "\t\t\tcommodity_state[\"price_centimes\"] = clampi(smoothed, minimum_price, maximum_price)\n"
		+ "\t\t\tcommodity_state[\"target_price_centimes\"] = target_price"
	)
	var precision_replacement: String = (
		"\t\t\tvar target_price_scaled: int = maxi(\n"
		+ "\t\t\t\tPRICE_SCALE,\n"
		+ "\t\t\t\tbase_price * PRICE_SCALE * target_multiplier_bp / BASIS_POINTS\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar previous_price: int = maxi(\n"
		+ "\t\t\t\tMIN_PRICE_CENTIMES, int(commodity_state.get(\"price_centimes\", base_price))\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar previous_price_scaled: int = maxi(\n"
		+ "\t\t\t\tPRICE_SCALE, int(commodity_state.get(\"price_scaled\", previous_price * PRICE_SCALE))\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar smoothed_scaled: int = (\n"
		+ "\t\t\t\tprevious_price_scaled * (BASIS_POINTS - smoothing_bp)\n"
		+ "\t\t\t\t+ target_price_scaled * smoothing_bp\n"
		+ "\t\t\t) / BASIS_POINTS\n"
		+ "\t\t\tvar minimum_price_scaled: int = maxi(\n"
		+ "\t\t\t\tPRICE_SCALE,\n"
		+ "\t\t\t\tprevious_price_scaled * (BASIS_POINTS - max_change_bp) / BASIS_POINTS\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar maximum_price_scaled: int = maxi(\n"
		+ "\t\t\t\tminimum_price_scaled,\n"
		+ "\t\t\t\tprevious_price_scaled * (BASIS_POINTS + max_change_bp) / BASIS_POINTS\n"
		+ "\t\t\t)\n"
		+ "\t\t\tvar next_price_scaled: int = clampi(\n"
		+ "\t\t\t\tsmoothed_scaled, minimum_price_scaled, maximum_price_scaled\n"
		+ "\t\t\t)\n"
		+ "\t\t\tcommodity_state[\"price_scaled\"] = next_price_scaled\n"
		+ "\t\t\tcommodity_state[\"target_price_scaled\"] = target_price_scaled\n"
		+ "\t\t\tcommodity_state[\"price_centimes\"] = maxi(\n"
		+ "\t\t\t\tMIN_PRICE_CENTIMES, int(round(float(next_price_scaled) / float(PRICE_SCALE)))\n"
		+ "\t\t\t)\n"
		+ "\t\t\tcommodity_state[\"target_price_centimes\"] = maxi(\n"
		+ "\t\t\t\tMIN_PRICE_CENTIMES, int(round(float(target_price_scaled) / float(PRICE_SCALE)))\n"
		+ "\t\t\t)"
	)
	_check(source.contains(precision_anchor), "price precision anchor is exact")
	if source.contains(precision_anchor):
		source = source.replace(precision_anchor, precision_replacement)

	var state_anchor: String = (
		"\t\t\"price_centimes\": maxi(MIN_PRICE_CENTIMES, base_price),\n"
		+ "\t\t\"target_price_centimes\": maxi(MIN_PRICE_CENTIMES, base_price),"
	)
	var state_replacement: String = (
		"\t\t\"price_centimes\": maxi(MIN_PRICE_CENTIMES, base_price),\n"
		+ "\t\t\"target_price_centimes\": maxi(MIN_PRICE_CENTIMES, base_price),\n"
		+ "\t\t\"price_scaled\": maxi(MIN_PRICE_CENTIMES, base_price) * PRICE_SCALE,\n"
		+ "\t\t\"target_price_scaled\": maxi(MIN_PRICE_CENTIMES, base_price) * PRICE_SCALE,"
	)
	_check(source.contains(state_anchor), "commodity state price precision anchor is exact")
	if source.contains(state_anchor):
		source = source.replace(state_anchor, state_replacement)

	if failures == 0:
		var file: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.WRITE)
		_check(file != null, "patched source is writable")
		if file != null:
			file.store_string(source)
			file.close()

	print("VNext market economy precision patch setup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + message)
