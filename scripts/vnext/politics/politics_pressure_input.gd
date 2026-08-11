class_name VNextPoliticsPressureInput
extends RefCounted

## Typed boundary for signals supplied by future economy and military adapters.
## This object records signals; it never calculates market or army outcomes.

const SNAPSHOT_SCHEMA_ID: String = "vnext_politics_pressure_input_v1"
const MAX_PERIOD_DAYS: int = 366
const MIN_SIGNAL: float = -100.0
const MAX_SIGNAL: float = 100.0

const ECONOMIC_SIGNAL_KEYS: Array[String] = [
	"price_pressure",
	"unemployment_pressure",
	"fiscal_pressure",
	"shortage_pressure",
	"growth_signal",
]
const WAR_SIGNAL_KEYS: Array[String] = [
	"war_pressure",
	"casualty_pressure",
	"mobilization_pressure",
	"military_result_signal",
]

var _period_days: int = 0
var _price_pressure: float = 0.0
var _unemployment_pressure: float = 0.0
var _fiscal_pressure: float = 0.0
var _shortage_pressure: float = 0.0
var _growth_signal: float = 0.0
var _war_pressure: float = 0.0
var _casualty_pressure: float = 0.0
var _mobilization_pressure: float = 0.0
var _military_result_signal: float = 0.0


static func create(
	period_days: int,
	price_pressure: float = 0.0,
	unemployment_pressure: float = 0.0,
	fiscal_pressure: float = 0.0,
	shortage_pressure: float = 0.0,
	growth_signal: float = 0.0,
	war_pressure: float = 0.0,
	casualty_pressure: float = 0.0,
	mobilization_pressure: float = 0.0,
	military_result_signal: float = 0.0
) -> VNextPoliticsPressureInput:
	var result := VNextPoliticsPressureInput.new()
	if not result.initialize(
		period_days,
		price_pressure,
		unemployment_pressure,
		fiscal_pressure,
		shortage_pressure,
		growth_signal,
		war_pressure,
		casualty_pressure,
		mobilization_pressure,
		military_result_signal
	):
		return null
	return result


static func from_snapshot(snapshot_value: Dictionary) -> VNextPoliticsPressureInput:
	var result := VNextPoliticsPressureInput.new()
	if not result.restore(snapshot_value):
		return null
	return result


func initialize(
	period_days: int,
	price_pressure: float,
	unemployment_pressure: float,
	fiscal_pressure: float,
	shortage_pressure: float,
	growth_signal: float,
	war_pressure: float,
	casualty_pressure: float,
	mobilization_pressure: float,
	military_result_signal: float
) -> bool:
	if period_days <= 0 or period_days > MAX_PERIOD_DAYS:
		return false
	for signal_value: float in [
		price_pressure,
		unemployment_pressure,
		fiscal_pressure,
		shortage_pressure,
		growth_signal,
		war_pressure,
		casualty_pressure,
		mobilization_pressure,
		military_result_signal,
	]:
		if not _is_valid_signal(signal_value):
			return false
	_period_days = period_days
	_price_pressure = price_pressure
	_unemployment_pressure = unemployment_pressure
	_fiscal_pressure = fiscal_pressure
	_shortage_pressure = shortage_pressure
	_growth_signal = growth_signal
	_war_pressure = war_pressure
	_casualty_pressure = casualty_pressure
	_mobilization_pressure = mobilization_pressure
	_military_result_signal = military_result_signal
	return true


func is_valid() -> bool:
	return (
		_period_days > 0
		and _period_days <= MAX_PERIOD_DAYS
		and _is_valid_signal(_price_pressure)
		and _is_valid_signal(_unemployment_pressure)
		and _is_valid_signal(_fiscal_pressure)
		and _is_valid_signal(_shortage_pressure)
		and _is_valid_signal(_growth_signal)
		and _is_valid_signal(_war_pressure)
		and _is_valid_signal(_casualty_pressure)
		and _is_valid_signal(_mobilization_pressure)
		and _is_valid_signal(_military_result_signal)
	)


func period_days() -> int:
	return _period_days


func price_pressure() -> float:
	return _price_pressure


func unemployment_pressure() -> float:
	return _unemployment_pressure


func fiscal_pressure() -> float:
	return _fiscal_pressure


func shortage_pressure() -> float:
	return _shortage_pressure


func growth_signal() -> float:
	return _growth_signal


func war_pressure() -> float:
	return _war_pressure


func casualty_pressure() -> float:
	return _casualty_pressure


func mobilization_pressure() -> float:
	return _mobilization_pressure


func military_result_signal() -> float:
	return _military_result_signal


func snapshot() -> Dictionary:
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"period_days": _period_days,
		"price_pressure": _price_pressure,
		"unemployment_pressure": _unemployment_pressure,
		"fiscal_pressure": _fiscal_pressure,
		"shortage_pressure": _shortage_pressure,
		"growth_signal": _growth_signal,
		"war_pressure": _war_pressure,
		"casualty_pressure": _casualty_pressure,
		"mobilization_pressure": _mobilization_pressure,
		"military_result_signal": _military_result_signal,
	}


func restore(snapshot_value: Dictionary) -> bool:
	if snapshot_value.size() != 11:
		return false
	for required_field: String in [
		"schema_id",
		"period_days",
		"price_pressure",
		"unemployment_pressure",
		"fiscal_pressure",
		"shortage_pressure",
		"growth_signal",
		"war_pressure",
		"casualty_pressure",
		"mobilization_pressure",
		"military_result_signal",
	]:
		if not snapshot_value.has(required_field):
			return false
	if snapshot_value.get("schema_id") != SNAPSHOT_SCHEMA_ID:
		return false
	var period_days: int = _normalize_int(
		snapshot_value.get("period_days"), 1, MAX_PERIOD_DAYS
	)
	if period_days < 0:
		return false
	var values: Array[float] = []
	for field_name: String in [
		"price_pressure",
		"unemployment_pressure",
		"fiscal_pressure",
		"shortage_pressure",
		"growth_signal",
		"war_pressure",
		"casualty_pressure",
		"mobilization_pressure",
		"military_result_signal",
	]:
		var value: float = _normalize_signal(snapshot_value.get(field_name))
		if value < MIN_SIGNAL - 0.001:
			return false
		values.append(value)
	return initialize(
		period_days,
		values[0],
		values[1],
		values[2],
		values[3],
		values[4],
		values[5],
		values[6],
		values[7],
		values[8]
	)


func economic_signal_value(signal_key: String) -> float:
	match signal_key:
		"price_pressure": return _price_pressure
		"unemployment_pressure": return _unemployment_pressure
		"fiscal_pressure": return _fiscal_pressure
		"shortage_pressure": return _shortage_pressure
		"growth_signal": return _growth_signal
	return 0.0


func war_signal_value(signal_key: String) -> float:
	match signal_key:
		"war_pressure": return _war_pressure
		"casualty_pressure": return _casualty_pressure
		"mobilization_pressure": return _mobilization_pressure
		"military_result_signal": return _military_result_signal
	return 0.0


static func _is_valid_signal(value: float) -> bool:
	return is_finite(value) and value >= MIN_SIGNAL and value <= MAX_SIGNAL


static func _normalize_signal(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return MIN_SIGNAL - 1.0
	var normalized: float = float(value)
	return normalized if _is_valid_signal(normalized) else MIN_SIGNAL - 1.0


static func _normalize_int(value: Variant, minimum: int, maximum: int) -> int:
	if typeof(value) == TYPE_INT:
		var integer_value: int = int(value)
		return integer_value if integer_value >= minimum and integer_value <= maximum else -1
	if typeof(value) != TYPE_FLOAT:
		return -1
	var float_value: float = float(value)
	if not is_finite(float_value) or float_value != floor(float_value):
		return -1
	var normalized: int = int(float_value)
	return normalized if normalized >= minimum and normalized <= maximum else -1
