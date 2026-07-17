class_name V2LifeLoopConfig
extends RefCounted
## Validated aggregate of the small V2.2 scenario documents.

const PATHS: Dictionary = {
	"balance": "res://data/v2_2/v2_2_balance.json",
	"living_costs": "res://data/v2_2/lille_demo_living_costs.json",
	"locations": "res://data/v2_2/lille_demo_locations.json",
	"employment": "res://data/v2_2/lille_demo_employment.json",
	"people": "res://data/v2_2/lille_demo_people.json",
	"scenario": "res://data/scenarios/v2_2_lille_life_loop.json",
}

var documents: Dictionary = {}
var errors: Array[String] = []


func load_all() -> Error:
	documents.clear()
	errors.clear()
	for key_variant: Variant in PATHS.keys():
		var key: String = str(key_variant)
		var path: String = str(PATHS[key])
		var document: Dictionary = _load_document(path)
		if not document.is_empty():
			documents[key] = document
	_validate()
	return OK if errors.is_empty() else ERR_INVALID_DATA


func get_document(key: String) -> Dictionary:
	var value: Variant = documents.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func person_records() -> Array:
	return get_document("people").get("people", []) as Array


func household_records() -> Array:
	return get_document("people").get("households", []) as Array


func contract_records() -> Array:
	return get_document("employment").get("contracts", []) as Array


func person_record(person_id: String) -> Dictionary:
	for record_variant: Variant in person_records():
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("person_id", "")) == person_id:
			return record.duplicate(true)
	return {}


func contract_for_person(person_id: String) -> Dictionary:
	for record_variant: Variant in contract_records():
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("person_id", "")) == person_id:
			return record.duplicate(true)
	return {}


func location_name(location_id: String) -> String:
	for record_variant: Variant in get_document("locations").get("locations", []):
		var record: Dictionary = record_variant as Dictionary
		if str(record.get("id", "")) == location_id:
			return str(record.get("name", location_id))
	return location_id


func _load_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("无法读取 V2.2 配置：%s" % path)
		return {}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		errors.append("V2.2 配置 JSON 无效：%s:%d %s" % [
			path, parser.get_error_line(), parser.get_error_message()
		])
		return {}
	if not parser.data is Dictionary:
		errors.append("V2.2 配置顶层必须是对象：%s" % path)
		return {}
	return _normalize_json_value(parser.data) as Dictionary


static func _normalize_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		for raw_key: Variant in (value as Dictionary).keys():
			normalized[str(raw_key)] = _normalize_json_value((value as Dictionary)[raw_key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for item: Variant in value as Array:
			normalized.append(_normalize_json_value(item))
		return normalized
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value))):
		return int(roundf(float(value)))
	return value


func _validate() -> void:
	if documents.size() != PATHS.size():
		return
	_validate_document_headers()
	_validate_balance()
	_validate_locations()
	_validate_people_households_and_contracts()
	_validate_relationships_and_memberships()
	_validate_living_costs()
	_validate_scenario()


func _validate_document_headers() -> void:
	for key_variant: Variant in documents.keys():
		var key: String = str(key_variant)
		var document: Dictionary = documents[key] as Dictionary
		if int(document.get("config_version", document.get("schema_version", 0))) != 1:
			errors.append("%s 配置版本不是 1" % key)
		if bool(document.get("prototype_balance_value", false)) != true:
			errors.append("%s 未标记 prototype_balance_value" % key)


func _validate_balance() -> void:
	var balance: Dictionary = documents["balance"] as Dictionary
	var time_rules: Dictionary = balance.get("time", {}) as Dictionary
	var parsed_speeds: Array[int] = []
	for raw_speed: Variant in time_rules.get("allowed_speed_multipliers", []) as Array:
		parsed_speeds.append(int(raw_speed))
	if parsed_speeds != [1, 2, 4, 8]:
		errors.append("V2.2 倍率配置必须为 1/2/4/8")
	if float(time_rules.get("real_seconds_per_game_hour", 0.0)) <= 0.0:
		errors.append("V2.2 每游戏小时现实秒数必须大于 0")
	var minimum_horizon: int = int(time_rules.get("minimum_schedule_horizon_hours", 0))
	var refill_threshold: int = int(time_rules.get("schedule_refill_threshold_hours", 0))
	if minimum_horizon < 24 or refill_threshold < 1 or refill_threshold >= minimum_horizon:
		errors.append("V2.2 日程补足阈值必须小于最小未来日程，且最小未来日程至少 24 小时")
	var condition: Dictionary = balance.get("condition", {}) as Dictionary
	var minimum: int = int(condition.get("minimum", -1))
	var maximum: int = int(condition.get("maximum", -1))
	var forced_rest: int = int(condition.get("forced_rest_fatigue", -1))
	if minimum != 0 or maximum != 1000 or forced_rest < minimum or forced_rest > maximum:
		errors.append("V2.2 状态范围或强制休息阈值无效")
	for key: String in [
		"completed_activities", "causal_events", "notifications",
		"transactions_per_household", "attendance_records",
	]:
		if int((balance.get("history_limits", {}) as Dictionary).get(key, 0)) < 16:
			errors.append("V2.2 历史上限过小：%s" % key)


func _validate_locations() -> void:
	var locations: Array = (documents["locations"] as Dictionary).get("locations", []) as Array
	var ids: Dictionary = {}
	for raw_location: Variant in locations:
		if not raw_location is Dictionary:
			errors.append("地点记录必须是对象")
			continue
		var location: Dictionary = raw_location as Dictionary
		var location_id: String = str(location.get("id", ""))
		if location_id.is_empty() or ids.has(location_id):
			errors.append("地点 ID 缺失或重复：%s" % location_id)
		else:
			ids[location_id] = true
		if str(location.get("name", "")).is_empty():
			errors.append("地点缺少显示名称：%s" % location_id)
		if str(location.get("kind", "")).is_empty():
			errors.append("地点缺少类型：%s" % location_id)
	if int((documents["locations"] as Dictionary).get("commute_duration_hours", 0)) < 1:
		errors.append("通勤占位时长必须至少 1 小时")


func _validate_people_households_and_contracts() -> void:
	var people_doc: Dictionary = documents["people"] as Dictionary
	var people: Array = people_doc.get("people", []) as Array
	var households: Array = people_doc.get("households", []) as Array
	var contracts: Array = (documents["employment"] as Dictionary).get("contracts", []) as Array
	if people.size() != 2 or households.size() != 2 or contracts.size() != 2:
		errors.append("V2.2 评审场景必须恰好包含两个人物、住户和合同")

	var location_ids: Dictionary = _id_set(
		(documents["locations"] as Dictionary).get("locations", []) as Array, "id"
	)
	var person_ids: Dictionary = {}
	var person_households: Dictionary = {}
	for raw_person: Variant in people:
		if not raw_person is Dictionary:
			errors.append("人物记录必须是对象")
			continue
		var person: Dictionary = raw_person as Dictionary
		var person_id: String = str(person.get("person_id", ""))
		if person_id.is_empty() or person_ids.has(person_id):
			errors.append("人物 ID 缺失或重复：%s" % person_id)
		else:
			person_ids[person_id] = true
		for field: String in [
			"identity_id", "display_name_zh", "native_name", "occupation",
			"organization_id", "position_name", "household_id",
			"home_location_id", "workplace_location_id", "initial_location_id",
		]:
			if str(person.get(field, "")).is_empty():
				errors.append("人物 %s 缺少字段：%s" % [person_id, field])
		for field: String in ["home_location_id", "workplace_location_id", "initial_location_id"]:
			var location_id: String = str(person.get(field, ""))
			if not location_ids.has(location_id):
				errors.append("人物 %s 引用未知地点：%s" % [person_id, location_id])
		var condition: Dictionary = person.get("initial_condition", {}) as Dictionary
		for stat: String in ["health", "fatigue", "stress"]:
			var value: int = int(condition.get(stat, -1))
			if value < 0 or value > 1000:
				errors.append("人物 %s 初始状态无效：%s" % [person_id, stat])
		var routine: Dictionary = person.get("default_schedule", {}) as Dictionary
		for field: String in [
			"sleep_start_hour", "sleep_end_hour", "commute_to_work_start_hour",
			"meal_break_start_hour", "commute_home_start_hour",
		]:
			var hour: int = int(routine.get(field, -1))
			if hour < 0 or hour > 23:
				errors.append("人物 %s 默认日程小时无效：%s" % [person_id, field])
		person_households[person_id] = str(person.get("household_id", ""))

	var household_ids: Dictionary = {}
	var member_owner: Dictionary = {}
	for raw_household: Variant in households:
		if not raw_household is Dictionary:
			errors.append("住户记录必须是对象")
			continue
		var household: Dictionary = raw_household as Dictionary
		var household_id: String = str(household.get("household_id", ""))
		if household_id.is_empty() or household_ids.has(household_id):
			errors.append("住户 ID 缺失或重复：%s" % household_id)
		else:
			household_ids[household_id] = true
		var members: Array = household.get("member_ids", []) as Array
		if members.is_empty():
			errors.append("住户没有成员：%s" % household_id)
		for raw_member: Variant in members:
			var member_id: String = str(raw_member)
			if not person_ids.has(member_id):
				errors.append("住户 %s 引用未知人物：%s" % [household_id, member_id])
			elif member_owner.has(member_id):
				errors.append("人物同时属于多个住户：%s" % member_id)
			else:
				member_owner[member_id] = household_id
		if not location_ids.has(str(household.get("home_location_id", ""))):
			errors.append("住户 %s 引用未知住所" % household_id)
		for field: String in [
			"cash_centimes", "food_stock_person_days", "essentials_stock_person_days",
			"rent_amount_centimes", "rent_arrears_centimes", "other_debt_centimes",
		]:
			if int(household.get(field, -1)) < 0:
				errors.append("住户 %s 数值不能为负：%s" % [household_id, field])
		if str(household.get("rent_period", "")) not in ["days:7", "monthly"]:
			errors.append("住户 %s 房租周期无效" % household_id)
		if V2DateTime.total_hour_from_iso(str(household.get("first_rent_due_datetime", ""))) < 0:
			errors.append("住户 %s 首次房租日期无效" % household_id)

	for person_id_variant: Variant in person_ids.keys():
		var person_id: String = str(person_id_variant)
		var expected_household: String = str(person_households.get(person_id, ""))
		if not household_ids.has(expected_household):
			errors.append("人物 %s 引用未知住户：%s" % [person_id, expected_household])
		elif str(member_owner.get(person_id, "")) != expected_household:
			errors.append("人物与住户成员表不一致：%s" % person_id)

	var contract_ids: Dictionary = {}
	var contract_people: Dictionary = {}
	for raw_contract: Variant in contracts:
		if not raw_contract is Dictionary:
			errors.append("劳动合同记录必须是对象")
			continue
		var contract: Dictionary = raw_contract as Dictionary
		var contract_id: String = str(contract.get("contract_id", ""))
		var person_id: String = str(contract.get("person_id", ""))
		if contract_id.is_empty() or contract_ids.has(contract_id):
			errors.append("劳动合同 ID 缺失或重复：%s" % contract_id)
		else:
			contract_ids[contract_id] = true
		if not person_ids.has(person_id):
			errors.append("劳动合同引用未知人物：%s" % person_id)
		elif contract_people.has(person_id):
			errors.append("人物存在多个 V2.2 劳动合同：%s" % person_id)
		else:
			contract_people[person_id] = true
		if str(contract.get("contract_status", "")) != "active":
			errors.append("V2.2 合同必须为 active：%s" % contract_id)
		if not location_ids.has(str(contract.get("workplace_location_id", ""))):
			errors.append("劳动合同引用未知工作地点：%s" % contract_id)
		var work_days: Array = contract.get("work_days", []) as Array
		var seen_days: Dictionary = {}
		for raw_day: Variant in work_days:
			var day: int = int(raw_day)
			if day < 0 or day > 6 or seen_days.has(day):
				errors.append("劳动合同工作日无效或重复：%s" % contract_id)
			seen_days[day] = true
		var segment_hours: int = 0
		var previous_end: int = -1
		for raw_segment: Variant in contract.get("shift_segments", []) as Array:
			if not raw_segment is Dictionary:
				errors.append("劳动合同班次必须是对象：%s" % contract_id)
				continue
			var segment: Dictionary = raw_segment as Dictionary
			var start_hour: int = int(segment.get("start_hour", -1))
			var end_hour: int = int(segment.get("end_hour", -1))
			if start_hour < 0 or end_hour > 24 or end_hour <= start_hour or start_hour < previous_end:
				errors.append("劳动合同班次无效或重叠：%s" % contract_id)
			previous_end = end_hour
			segment_hours += maxi(0, end_hour - start_hour)
		if segment_hours * work_days.size() != int(contract.get("required_paid_hours_per_week", -1)):
			errors.append("劳动合同周工时与班次不一致：%s" % contract_id)
		var wage_period: String = str(contract.get("wage_period", ""))
		if wage_period not in ["weekly", "monthly"]:
			errors.append("劳动合同工资周期无效：%s" % contract_id)
		if int(contract.get("base_wage_centimes", -1)) < 0:
			errors.append("劳动合同工资不能为负：%s" % contract_id)
		var pay_rule: Dictionary = contract.get("pay_day_rule", {}) as Dictionary
		if wage_period == "weekly":
			var pay_weekday: int = int(pay_rule.get("weekday_monday_zero", -1))
			var pay_hour: int = int(pay_rule.get("hour", -1))
			if pay_weekday < 0 or pay_weekday > 6 or pay_hour < 0 or pay_hour > 23:
				errors.append("周薪支付规则无效：%s" % contract_id)
		else:
			var pay_day: int = int(pay_rule.get("day_of_month", -1))
			var monthly_hour: int = int(pay_rule.get("hour", -1))
			if pay_day < 1 or pay_day > 28 or monthly_hour < 0 or monthly_hour > 23:
				errors.append("月薪支付规则无效：%s" % contract_id)

	for person_id_variant: Variant in person_ids.keys():
		if not contract_people.has(str(person_id_variant)):
			errors.append("人物缺少劳动合同：%s" % str(person_id_variant))


func _validate_relationships_and_memberships() -> void:
	var people_doc: Dictionary = documents["people"] as Dictionary
	var person_ids: Dictionary = _id_set(people_doc.get("people", []) as Array, "person_id")
	var relationship_keys: Dictionary = {}
	for raw_relation: Variant in people_doc.get("relationships", []) as Array:
		if not raw_relation is Dictionary:
			errors.append("关系记录必须是对象")
			continue
		var relation: Dictionary = raw_relation as Dictionary
		var person_id: String = str(relation.get("person_id", ""))
		var target_id: String = str(relation.get("target_id", ""))
		var key: String = "%s|%s" % [person_id, target_id]
		if not person_ids.has(person_id) or target_id.is_empty() or relationship_keys.has(key):
			errors.append("关系引用无效或重复：%s" % key)
		else:
			relationship_keys[key] = true
		for field: String in ["familiarity", "trust"]:
			var value: int = int(relation.get(field, -1))
			if value < 0 or value > 1000:
				errors.append("关系数值无效：%s/%s" % [key, field])
	var membership_keys: Dictionary = {}
	for raw_membership: Variant in people_doc.get("organization_memberships", []) as Array:
		if not raw_membership is Dictionary:
			errors.append("组织成员记录必须是对象")
			continue
		var membership: Dictionary = raw_membership as Dictionary
		var person_id: String = str(membership.get("person_id", ""))
		var organization_id: String = str(membership.get("organization_id", ""))
		var key: String = "%s|%s" % [person_id, organization_id]
		if not person_ids.has(person_id) or organization_id.is_empty() or membership_keys.has(key):
			errors.append("组织成员引用无效或重复：%s" % key)
		else:
			membership_keys[key] = true
		var participation: int = int(membership.get("participation", -1))
		if participation < 0 or participation > 1000:
			errors.append("组织参与度无效：%s" % key)


func _validate_living_costs() -> void:
	var costs: Dictionary = documents["living_costs"] as Dictionary
	var location_ids: Dictionary = _id_set(
		(documents["locations"] as Dictionary).get("locations", []) as Array, "id"
	)
	if not location_ids.has(str(costs.get("purchase_location_id", ""))):
		errors.append("生活成本配置引用未知购买地点")
	var open_hour: int = int(costs.get("business_open_hour", -1))
	var close_hour: int = int(costs.get("business_close_hour", -1))
	if open_hour < 0 or close_hour > 24 or close_hour <= open_hour:
		errors.append("购买地点营业时间无效")
	if int(costs.get("purchase_duration_hours", 0)) < 1:
		errors.append("购买活动持续时间必须至少 1 小时")
	for package_key: String in ["food_package", "essentials_package"]:
		var package: Dictionary = costs.get(package_key, {}) as Dictionary
		if int(package.get("price_centimes", -1)) < 0 or int(package.get("stock_person_days", 0)) < 1:
			errors.append("生活物资包配置无效：%s" % package_key)
	var consumption_hour: int = int(costs.get("daily_consumption_hour", -1))
	if consumption_hour < 0 or consumption_hour > 23:
		errors.append("每日消费结算小时无效")


func _validate_scenario() -> void:
	var scenario: Dictionary = documents["scenario"] as Dictionary
	for field: String in [
		"scenario_id", "start_datetime", "default_selected_person_id",
		"random_seed", "review_save_path", "window_title",
	]:
		if not scenario.has(field) or str(scenario.get(field, "")).is_empty():
			errors.append("评审场景缺少字段：%s" % field)
	var start_hour: int = V2DateTime.total_hour_from_iso(str(scenario.get("start_datetime", "")))
	if start_hour < 0:
		errors.append("评审场景起始时间无效")
	var person_ids: Dictionary = _id_set(
		(documents["people"] as Dictionary).get("people", []) as Array, "person_id"
	)
	if not person_ids.has(str(scenario.get("default_selected_person_id", ""))):
		errors.append("评审场景默认人物引用无效")
	var save_path: String = str(scenario.get("review_save_path", ""))
	if not save_path.begins_with("user://") or not save_path.ends_with(".json"):
		errors.append("评审存档路径必须位于 user:// 且为 JSON")


static func _id_set(records: Array, field: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			var value: String = str((raw_record as Dictionary).get(field, ""))
			if not value.is_empty():
				result[value] = true
	return result
