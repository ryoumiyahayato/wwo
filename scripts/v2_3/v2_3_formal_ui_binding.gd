class_name V23FormalUiBinding
extends V23LifeLoopUiBinding
## Player-facing projection and commands for formal-map personal finance.

var formal_simulation: V23FormalSimulation


func _init(
	life_simulation: V2LifeLoopSimulation,
	enable_developer_mode: bool = false
) -> void:
	super._init(life_simulation, enable_developer_mode)
	formal_simulation = life_simulation as V23FormalSimulation


func finance_view(person_id: String = "") -> Dictionary:
	if formal_simulation == null:
		return {}
	var resolved_id: String = selected_person_id() if person_id.is_empty() else person_id
	var household: Dictionary = formal_simulation.households.household_for_person(resolved_id)
	var position: Dictionary = formal_simulation.spatial_locations.position_for(resolved_id)
	var current_location_id: String = str(position.get("current_location_id", ""))
	var lender_views: Array[Dictionary] = []
	for lender: Dictionary in formal_simulation.finance.lender_records():
		var lender_id: String = str(lender.get("lender_id", ""))
		var lender_location_id: String = str(lender.get("location_id", ""))
		var products: Array[Dictionary] = []
		for product: Dictionary in formal_simulation.finance.product_records():
			if str(product.get("lender_id", "")) == lender_id:
				products.append(product.duplicate(true))
		lender_views.append({
			"lender_id": lender_id,
			"display_name": str(lender.get("display_name", lender_id)),
			"location_id": lender_location_id,
			"location_name": formal_simulation.spatial_locations.location_name(
				lender_location_id, resolved_id, formal_simulation.truth_view
			),
			"at_location": (
				str(position.get("location_state", "")) == "at_location"
				and current_location_id == lender_location_id
			),
			"open_now": formal_simulation.finance.is_lender_open(
				lender_id, formal_simulation.clock.total_hours
			),
			"products": products,
		})
	var applications: Array[Dictionary] = []
	for application: Dictionary in formal_simulation.finance.applications_for_person(resolved_id):
		var decorated: Dictionary = application.duplicate(true)
		var product: Dictionary = formal_simulation.finance.products.get(
			str(application.get("product_id", "")), {}
		) as Dictionary
		decorated["product_name"] = str(product.get("display_name", application.get("product_id", "")))
		decorated["review_due_datetime"] = V2DateTime.iso_from_total_hour(
			int(application.get("review_due_hour", 0))
		)
		decorated["offer_expires_datetime"] = (
			V2DateTime.iso_from_total_hour(int(application.get("offer_expires_hour", 0)))
			if int(application.get("offer_expires_hour", -1)) >= 0 else ""
		)
		applications.append(decorated)
	var contracts: Array[Dictionary] = []
	for contract: Dictionary in formal_simulation.finance.contracts_for_person(resolved_id):
		var decorated: Dictionary = contract.duplicate(true)
		var product: Dictionary = formal_simulation.finance.products.get(
			str(contract.get("product_id", "")), {}
		) as Dictionary
		decorated["product_name"] = str(product.get("display_name", contract.get("product_id", "")))
		decorated["due_datetime"] = V2DateTime.iso_from_total_hour(int(contract.get("end_hour", 0)))
		decorated["outstanding_centimes"] = int(contract.get("principal_outstanding_centimes", 0)) + int(
			contract.get("interest_outstanding_centimes", 0)
		)
		contracts.append(decorated)
	return {
		"person_id": resolved_id,
		"cash_centimes": int(household.get("cash_centimes", 0)),
		"total_debt_centimes": formal_simulation.finance.total_debt_for_person(resolved_id),
		"current_location_id": current_location_id,
		"current_location_name": formal_simulation.spatial_locations.location_name(
			current_location_id, resolved_id, formal_simulation.truth_view
		),
		"lenders": lender_views,
		"applications": applications,
		"contracts": contracts,
	}


func apply_for_loan(product_id: String, amount_centimes: int) -> V2LifeLoopResult:
	if formal_simulation == null:
		return V2LifeLoopResult.fail("formal_finance_unavailable", "正式金融服务不可用")
	last_command_result = formal_simulation.submit_loan_application(
		selected_person_id(), product_id, amount_centimes
	)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func accept_loan_offer(application_id: String) -> V2LifeLoopResult:
	if formal_simulation == null:
		return V2LifeLoopResult.fail("formal_finance_unavailable", "正式金融服务不可用")
	last_command_result = formal_simulation.accept_loan_offer(application_id)
	_view_revision += 1
	view_changed.emit()
	return last_command_result


func repay_loan(contract_id: String, amount_centimes: int) -> V2LifeLoopResult:
	if formal_simulation == null:
		return V2LifeLoopResult.fail("formal_finance_unavailable", "正式金融服务不可用")
	last_command_result = formal_simulation.repay_personal_loan(contract_id, amount_centimes)
	_view_revision += 1
	view_changed.emit()
	return last_command_result
