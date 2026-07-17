extends SceneTree
## Complete V2.2 configuration references and strict hourly calendar parsing.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := V2LifeLoopConfig.new()
	test.equal(config.load_all(), OK, "正式 V2.2 配置通过完整引用校验")
	test.equal(config.errors.size(), 0, "正式 V2.2 配置没有校验错误")
	test.equal(config.person_records().size(), 2, "配置包含两个人物")
	test.equal(config.household_records().size(), 2, "配置包含两个住户")
	test.equal(config.contract_records().size(), 2, "配置包含两份劳动合同")

	var start_iso: String = "1900-03-12T05:00:00"
	var start_hour: int = V2DateTime.total_hour_from_iso(start_iso)
	test.expect(start_hour >= 0, "严格 ISO 小时格式可解析")
	test.equal(V2DateTime.iso_from_total_hour(start_hour), start_iso, "日期小时往返一致")
	test.equal(
		int(V2DateTime.from_total_hour(start_hour).get("weekday", -1)),
		0,
		"1900-03-12 为星期一"
	)
	test.expect(not V2DateTime.is_leap_year(1900), "1900 年不是格里高利闰年")
	test.expect(V2DateTime.is_leap_year(2000), "2000 年是格里高利闰年")
	test.equal(V2DateTime.days_in_month(1900, 2), 28, "1900 年二月为 28 天")
	test.equal(V2DateTime.days_in_month(2000, 2), 29, "2000 年二月为 29 天")

	for invalid_iso: String in [
		"1900-03-12 05:00:00",
		"1900-03-12T05:30:00",
		"1900-03-12T05:00:01",
		"1900-02-29T05:00:00",
		"1899-12-31T23:00:00",
		"1900-13-01T00:00:00",
		"1900-03-12T24:00:00",
		"1900-3-12T05:00:00",
	]:
		test.equal(
			V2DateTime.total_hour_from_iso(invalid_iso),
			-1,
			"拒绝无效时间：%s" % invalid_iso
		)
	test.equal(V2DateTime.iso_from_total_hour(-1), "", "负权威小时不会伪装成有效日期")
	test.equal(V2DateTime.display_from_total_hour(-1), "无效时间", "负权威小时显示明确错误")

	var invalid_reference := V2LifeLoopConfig.new()
	invalid_reference.load_all()
	var people_doc: Dictionary = (
		invalid_reference.documents["people"] as Dictionary
	).duplicate(true)
	var people: Array = people_doc["people"] as Array
	var first_person: Dictionary = (people[0] as Dictionary).duplicate(true)
	first_person["home_location_id"] = "location:missing"
	people[0] = first_person
	people_doc["people"] = people
	invalid_reference.documents["people"] = people_doc
	invalid_reference.errors.clear()
	invalid_reference._validate()
	test.expect(
		not invalid_reference.errors.is_empty(),
		"配置校验拒绝人物引用未知地点"
	)

	var invalid_contract := V2LifeLoopConfig.new()
	invalid_contract.load_all()
	var employment_doc: Dictionary = (
		invalid_contract.documents["employment"] as Dictionary
	).duplicate(true)
	var contracts: Array = employment_doc["contracts"] as Array
	var first_contract: Dictionary = (contracts[0] as Dictionary).duplicate(true)
	first_contract["required_paid_hours_per_week"] = 53
	contracts[0] = first_contract
	employment_doc["contracts"] = contracts
	invalid_contract.documents["employment"] = employment_doc
	invalid_contract.errors.clear()
	invalid_contract._validate()
	test.expect(
		not invalid_contract.errors.is_empty(),
		"配置校验拒绝班次与周工时不一致"
	)

	test.finish(self, "V2.2 config and datetime")
