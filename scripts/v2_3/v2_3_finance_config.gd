class_name V23FinanceConfig
extends RefCounted
## Validated Lille lender and personal-credit data for the formal V2.3 world.

const PATH: String = "res://data/v2_3/lille_finance.json"

var document: Dictionary = {}
var errors: Array[String] = []


func load_all(valid_location_ids: Array[String]) -> Error:
	document.clear()
	errors.clear()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		errors.append("无法读取正式金融配置：%s" % PATH)
		return ERR_FILE_CANT_OPEN
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		errors.append("正式金融配置 JSON 无效：%s" % PATH)
		return ERR_PARSE_ERROR
	document = _normalize(parser.data) as Dictionary
	_validate(valid_location_ids)
	return OK if errors.is_empty() else ERR_INVALID_DATA


func lenders() -> Array:
	return (document.get("lenders", []) as Array).duplicate(true)


func products() -> Array:
	return (document.get("products", []) as Array).duplicate(true)


func _validate(valid_location_ids: Array[String]) -> void:
	if int(document.get("config_version", 0)) != 1:
		errors.append("正式金融配置版本不是 1")
	if not bool(document.get("prototype_balance_value", false)):
		errors.append("正式金融配置缺少原型数值标记")
	var location_set: Dictionary = {}
	for location_id: String in valid_location_ids:
		location_set[location_id] = true
	var lender_ids: Dictionary = {}
	for raw_lender: Variant in document.get("lenders", []) as Array:
		if not raw_lender is Dictionary:
			errors.append("放贷方记录必须是对象")
			continue
		var lender: Dictionary = raw_lender as Dictionary
		var lender_id: String = str(lender.get("lender_id", ""))
		var location_id: String = str(lender.get("location_id", ""))
		if lender_id.is_empty() or lender_ids.has(lender_id):
			errors.append("放贷方 ID 缺失或重复：%s" % lender_id)
		else:
			lender_ids[lender_id] = true
		if not location_set.has(location_id):
			errors.append("放贷方引用未知正式地点：%s" % location_id)
		if int(lender.get("opening_capital_centimes", 0)) <= 0:
			errors.append("放贷方初始资金无效：%s" % lender_id)
		if not lender.get("opening_hours", {}) is Dictionary:
			errors.append("放贷方营业时间无效：%s" % lender_id)
	var product_ids: Dictionary = {}
	for raw_product: Variant in document.get("products", []) as Array:
		if not raw_product is Dictionary:
			errors.append("信贷产品记录必须是对象")
			continue
		var product: Dictionary = raw_product as Dictionary
		var product_id: String = str(product.get("product_id", ""))
		var lender_id: String = str(product.get("lender_id", ""))
		if product_id.is_empty() or product_ids.has(product_id):
			errors.append("信贷产品 ID 缺失或重复：%s" % product_id)
		else:
			product_ids[product_id] = true
		if not lender_ids.has(lender_id):
			errors.append("信贷产品引用未知放贷方：%s" % product_id)
		var options: Array = product.get("amount_options_centimes", []) as Array
		if options.is_empty():
			errors.append("信贷产品没有可申请金额：%s" % product_id)
		for raw_amount: Variant in options:
			if int(raw_amount) <= 0:
				errors.append("信贷产品金额无效：%s" % product_id)
		for field: String in [
			"term_days", "annual_rate_bp", "review_delay_hours",
			"offer_valid_hours", "grace_days", "approval_threshold",
		]:
			if int(product.get(field, 0)) <= 0:
				errors.append("信贷产品字段无效：%s/%s" % [product_id, field])


static func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for raw_key: Variant in (value as Dictionary).keys():
			result[str(raw_key)] = _normalize((value as Dictionary)[raw_key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_normalize(item))
		return result
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value
