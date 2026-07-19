class_name V23FormalSimulation
extends V23LifeLoopSimulation
## Formal V2.3 composition root with personal credit attached to the existing map and cash ledger.

var finance_config := V23FinanceConfig.new()
var finance := V23FinanceService.new()


func initialize(simulation_clock: SimulationClock = null) -> bool:
	if not super.initialize(simulation_clock):
		return false
	var location_ids: Array[String] = []
	for raw_location: Variant in v2_3_config.location_records():
		location_ids.append(str((raw_location as Dictionary).get("location_id", "")))
	if finance_config.load_all(location_ids) != OK:
		return _fail_v2_3_initialization("; ".join(finance_config.errors))
	var finance_result: V2LifeLoopResult = finance.configure(
		finance_config, households, ledger
	)
	if not finance_result.success:
		return _fail_v2_3_initialization(finance_result.user_message)
	state_changed.emit({"formal_finance_initialized": true})
	return true


func submit_loan_application(
	person_id: String,
	product_id: String,
	amount_centimes: int
) -> V2LifeLoopResult:
	var position: Dictionary = spatial_locations.position_for(person_id)
	if str(position.get("location_state", "")) != "at_location":
		return V2LifeLoopResult.fail("person_in_transit", "途中不能办理借款申请", person_id)
	var employment_contract: Dictionary = employment.contract_for_person(person_id)
	var result: V2LifeLoopResult = finance.submit_application(
		"v2_3:loan_application:%s:%s:%d:%d" % [
			person_id, product_id, amount_centimes, clock.total_hours,
		],
		person_id,
		product_id,
		amount_centimes,
		clock.total_hours,
		str(position.get("current_location_id", "")),
		_monthly_income_for(person_id),
		str(employment_contract.get("contract_status", "")) == "active"
	)
	if result.success:
		state_changed.emit({"finance": true, "loan_application": true})
	return result


func accept_loan_offer(application_id: String) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = finance.accept_offer(
		"v2_3:loan_accept:%s:%d" % [application_id, clock.total_hours],
		application_id,
		clock.total_hours
	)
	if result.success:
		notifications.add(
			"personal", "event", "借款已经放款", result.user_message,
			clock.total_hours, "loan_disbursed:%s" % application_id,
			result.affected_entity_ids
		)
		state_changed.emit({"finance": true, "households": true, "ledger": true})
	return result


func repay_personal_loan(contract_id: String, requested_centimes: int) -> V2LifeLoopResult:
	var result: V2LifeLoopResult = finance.repay(
		"v2_3:loan_repay:%s:%d:%d" % [
			contract_id, requested_centimes, clock.total_hours,
		],
		contract_id,
		clock.total_hours,
		requested_centimes
	)
	if result.success:
		notifications.add(
			"personal", "event", "借款发生还款", result.user_message,
			clock.total_hours,
			"loan_repayment:%s:%d" % [contract_id, clock.total_hours],
			result.affected_entity_ids
		)
		state_changed.emit({"finance": true, "households": true, "ledger": true})
	return result


func get_persistent_state() -> Dictionary:
	var state: Dictionary = super.get_persistent_state()
	state["formal_finance_state"] = finance.get_persistent_state()
	return state


func validate_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var base_result: V2LifeLoopResult = super.validate_v2_3_state(state)
	if not base_result.success:
		return base_result
	if state.has("formal_finance_state") and not finance.validate_persistent_state(
		state.get("formal_finance_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("corrupt_save", "正式金融存档字段损坏")
	return V2LifeLoopResult.ok("V2.3 正式存档结构有效")


func restore_v2_3_state(state: Dictionary) -> V2LifeLoopResult:
	var validation: V2LifeLoopResult = validate_v2_3_state(state)
	if not validation.success:
		return validation
	var base_result: V2LifeLoopResult = super.restore_v2_3_state(state)
	if not base_result.success:
		return base_result
	var configured: V2LifeLoopResult = finance.configure(finance_config, households, ledger)
	if not configured.success:
		return configured
	if state.has("formal_finance_state") and not finance.restore_persistent_state(
		state.get("formal_finance_state", {}) as Dictionary
	):
		return V2LifeLoopResult.fail("finance_restore_failed", "正式金融状态恢复失败")
	state_changed.emit({"loaded": true, "formal_finance": true})
	return V2LifeLoopResult.ok("V2.3 正式存档已载入")


func determinism_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.determinism_snapshot()
	snapshot["formal_finance"] = finance.get_persistent_state()
	return snapshot


func _settle_hour(total_hour: int) -> void:
	super._settle_hour(total_hour)
	var finance_events: Array[Dictionary] = finance.process_hour(total_hour + 1)
	if finance_events.is_empty():
		return
	for event: Dictionary in finance_events:
		var event_type: String = str(event.get("event_type", ""))
		var title: String = {
			"loan_offer": "借款方提出条件",
			"loan_rejected": "借款申请被拒绝",
			"loan_offer_expired": "借款条件已过期",
			"loan_overdue": "借款已经逾期",
			"loan_defaulted": "借款已经违约",
		}.get(event_type, "金融状态发生变化")
		notifications.add(
			"personal",
			"notification" if event_type in ["loan_offer", "loan_overdue", "loan_defaulted"] else "event",
			title,
			str(event.get("summary", title)),
			int(event.get("total_hour", total_hour + 1)),
			str(event.get("event_id", "finance:%s:%d" % [event_type, total_hour + 1])),
			DataRecordUtils.to_string_array(event.get("entity_ids", []))
		)
	state_changed.emit({"finance": finance_events.size(), "households": true})


func _monthly_income_for(person_id: String) -> int:
	var contract: Dictionary = employment.contract_for_person(person_id)
	if contract.is_empty() or str(contract.get("contract_status", "")) != "active":
		return 0
	var base_wage: int = int(contract.get("base_wage_centimes", 0))
	var allowance: int = int(contract.get("allowance_centimes", 0))
	if str(contract.get("wage_period", "")) == "weekly":
		return base_wage * 52 / 12 + allowance
	return base_wage + allowance
