class_name RealProductionE1Numeric
extends RefCounted
## Integer/fixed-point helpers shared by the E1 physical economy.
##
## Authoritative quantities are stored as QUANTITY_SCALE units.  The helper
## methods deliberately avoid float arithmetic so a source-record reorder
## cannot change a settlement result.

const BASIS_POINTS: int = 10_000
const QUANTITY_SCALE: int = 1_000
const RECIPE_RATIO_SCALE: int = 1_000_000


static func mul_div_floor(a: int, b: int, denominator: int) -> int:
	if denominator <= 0:
		return 0
	var product: int = a * b
	if product >= 0:
		@warning_ignore("integer_division")
		return product / denominator
	@warning_ignore("integer_division")
	return -((-product + denominator - 1) / denominator)


static func mul_div_ceil(a: int, b: int, denominator: int) -> int:
	if denominator <= 0:
		return 0
	if a < 0 or b < 0:
		return -mul_div_floor(-a, b, denominator)
	if a == 0 or b == 0:
		return 0
	@warning_ignore("integer_division")
	return (a * b + denominator - 1) / denominator


static func clamp_bp(value: int) -> int:
	return clampi(value, -BASIS_POINTS, BASIS_POINTS)


static func ratio_to_output(input_quantity: int, ratio: int) -> int:
	if input_quantity <= 0 or ratio <= 0:
		return 0
	return mul_div_floor(input_quantity, RECIPE_RATIO_SCALE, ratio)


static func required_from_output(output_quantity: int, ratio: int) -> int:
	if output_quantity <= 0 or ratio <= 0:
		return 0
	return mul_div_ceil(output_quantity, ratio, RECIPE_RATIO_SCALE)


static func sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in source:
		result.append(str(raw_key))
	result.sort()
	return result


static func canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value as Dictionary
		var result: Dictionary = {}
		var keys: Array[String] = sorted_string_keys(source)
		for key: String in keys:
			result[key] = canonicalize(source[key])
		return result
	if value is Array:
		var array_result: Array = []
		for item: Variant in value as Array:
			array_result.append(canonicalize(item))
		return array_result
	return value


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(canonicalize(value))


static func sha256(value: Variant) -> String:
	return canonical_json(value).sha256_text()
