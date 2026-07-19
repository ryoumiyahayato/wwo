class_name AlphaScenarioRunner
extends RefCounted
## Deterministic cross-system Alpha journeys using only formal services.

const SCENARIO_IDS: Array[String] = [
	"employment_and_migration",
	"leveraged_business_success",
	"leveraged_business_failure",
	"low_skill_with_professional_partner",
	"organization_position_policy",
	"corruption_and_investigation",
	"three_year_unattended_world",
	"save_load_mid_contract",
	"save_load_mid_debt_default",
	"save_load_mid_policy_implementation",
]
const FIXED_SEEDS: Dictionary = {
	"employment_and_migration": 1900101,
	"leveraged_business_success": 1900202,
	"leveraged_business_failure": 1900303,
	"low_skill_with_professional_partner": 1900404,
	"organization_position_policy": 1900505,
	"corruption_and_investigation": 1900606,
	"three_year_unattended_world": 1900707,
	"save_load_mid_contract": 1900808,
	"save_load_mid_debt_default": 1900909,
	"save_load_mid_policy_implementation": 1901010,
}

var last_simulation: AlphaSimulationService


func run(scenario_id: String) -> Dictionary:
	last_simulation = null
	match scenario_id:
		"employment_and_migration":
			return _employment_and_migration()
		"leveraged_business_success":
			return _leveraged_business_success()
		"leveraged_business_failure":
			return _leveraged_business_failure()
		"low_skill_with_professional_partner":
			return _low_skill_with_professional_partner()
		"organization_position_policy":
			return _organization_position_policy()
		"corruption_and_investigation":
			return _corruption_and_investigation()
		"three_year_unattended_world":
			return _three_year_unattended_world()
		"save_load_mid_contract":
			return _save_load_mid_contract()
		"save_load_mid_debt_default":
			return _save_load_mid_debt_default()
		"save_load_mid_policy_implementation":
			return _save_load_mid_policy_implementation()
	return _failed(scenario_id, "unknown_scenario", [])


func _employment_and_migration() -> Dictionary:
	var scenario_id: String = "employment_and_migration"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "employed_worker"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var employment_id: String = _active_employment_id(simulation, player.id)
	var trace: Array[Dictionary] = []
	var worked: Dictionary = simulation.labor.work_shift(
		"scenario:employment:work", employment_id,
		simulation.clock.total_hours + 8, 8, 9000
	)
	if not _succeeded(worked):
		return _failed(scenario_id, "work_failed", trace)
	simulation.labor.pay_wage(
		"scenario:employment:wage", employment_id,
		simulation.clock.total_hours + 7 * 24
	)
	trace.append(_fact("work_and_wage", {
		"employment_contract_id": employment_id,
		"cash_centimes": simulation.economy.ledger.owner_cash(player.id),
	}))
	var cash: int = simulation.economy.ledger.owner_cash(player.id)
	var life_cost: int = maxi(0, cash - 180)
	var paid_life: Dictionary = simulation.economy.pay_life_costs(
		"scenario:employment:life",
		player.id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		simulation.clock.total_hours + 8 * 24,
		life_cost,
		0,
		0
	)
	if not _succeeded(paid_life):
		return _failed(scenario_id, "life_cost_failed", trace)
	var loan: Dictionary = _borrow_person(
		simulation, player, 2600, "scenario:employment:loan"
	)
	if not _succeeded(loan):
		trace.append(_fact("loan_rejected", loan))
		return _failed(
			scenario_id,
			"loan_failed:%s" % str(loan.get("code", "")),
			trace
		)
	var loan_id: String = str(
		((loan.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	trace.append(_fact("cash_shortage_and_loan", {
		"loan_contract_id": loan_id,
		"debt_centimes": simulation.economy.total_debt(player.id),
	}))
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	player = simulation.player_character()
	employment_id = _active_employment_id(simulation, player.id)
	simulation.labor.resign(
		"scenario:employment:resign", employment_id,
		simulation.clock.total_hours
	)
	var migrated: Dictionary = simulation.labor.migrate(
		"scenario:employment:migrate",
		player.id,
		"country:vesta_union",
		"region:vesta_silverfield",
		"city:starhold",
		"organization:vesta_enterprise",
		160,
		simulation.clock.total_hours
	)
	if not _succeeded(migrated):
		return _failed(scenario_id, "migration_failed", trace)
	player.country_id = "country:vesta_union"
	player.region_id = "region:vesta_silverfield"
	player.current_status["city_id"] = "city:starhold"
	var rehired: Dictionary = simulation.labor.direct_hire(
		"scenario:employment:rehire",
		player.id,
		"job:trade_agent",
		simulation.clock.total_hours
	)
	if not _succeeded(rehired):
		return _failed(scenario_id, "rehire_failed", trace)
	var debt_before: int = simulation.economy.total_debt(player.id)
	var repaid: Dictionary = simulation.economy.repay_loan(
		"scenario:employment:repay",
		loan_id,
		simulation.clock.total_hours,
		500
	)
	if not _succeeded(repaid):
		return _failed(scenario_id, "repayment_failed", trace)
	trace.append(_fact("migration_new_job_and_repayment", {
		"region_id": player.region_id,
		"employment_contract_id": _active_employment_id(
			simulation, player.id
		),
		"debt_before": debt_before,
		"debt_after": simulation.economy.total_debt(player.id),
	}))
	return _completed(scenario_id, simulation, trace, [
		life_cost > 0,
		not loan_id.is_empty(),
		player.region_id == "region:vesta_silverfield",
		not _active_employment_id(simulation, player.id).is_empty(),
		simulation.economy.total_debt(player.id) < debt_before,
	])


func _leveraged_business_success() -> Dictionary:
	var scenario_id: String = "leveraged_business_success"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "leveraged_enterprise"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var enterprise_id: String = _controlled_enterprise_id(
		simulation, player.id
	)
	var state: Dictionary = simulation.enterprise.enterprises[
		enterprise_id
	] as Dictionary
	var capacity_before: int = int(state.get("capacity_units_per_day", 0))
	var debt_before: int = simulation.economy.total_debt(enterprise_id)
	var trace: Array[Dictionary] = [
		_fact("leveraged_enterprise_ready", {
			"enterprise_id": enterprise_id,
			"debt_centimes": debt_before,
		})
	]
	var ordered: Dictionary = simulation.enterprise.accept_order(
		"scenario:success:order",
		enterprise_id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		4,
		player.region_id,
		simulation.clock.total_hours,
		0
	)
	if not _succeeded(ordered):
		return _failed(scenario_id, "order_failed", trace)
	var order_id: String = str(
		((ordered.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var procured: Dictionary = simulation.enterprise.procure_inputs(
		"scenario:success:procure",
		enterprise_id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		4,
		player.region_id,
		simulation.clock.total_hours,
		0
	)
	if not _succeeded(procured):
		return _failed(scenario_id, "procurement_failed", trace)
	if not _succeeded(simulation.enterprise.produce(
		"scenario:success:produce",
		enterprise_id,
		4,
		simulation.clock.total_hours,
		player.id
	)):
		return _failed(scenario_id, "production_failed", trace)
	if not _succeeded(simulation.enterprise.deliver_order(
		"scenario:success:deliver",
		enterprise_id,
		order_id,
		simulation.clock.total_hours
	)):
		return _failed(scenario_id, "delivery_failed", trace)
	var loan_id: String = _first_loan_id(simulation, enterprise_id)
	simulation.economy.repay_loan(
		"scenario:success:repay",
		loan_id,
		simulation.clock.total_hours,
		500
	)
	var expanded: Dictionary = simulation.enterprise.expand(
		"scenario:success:expand",
		enterprise_id,
		400,
		3,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		simulation.clock.total_hours
	)
	if not _succeeded(expanded):
		return _failed(scenario_id, "expansion_failed", trace)
	state = simulation.enterprise.enterprises[enterprise_id] as Dictionary
	trace.append(_fact("order_delivered_and_expanded", {
		"completed_orders": state.get("completed_orders", 0),
		"capacity_before": capacity_before,
		"capacity_after": state.get("capacity_units_per_day", 0),
		"debt_before": debt_before,
		"debt_after": simulation.economy.total_debt(enterprise_id),
	}))
	return _completed(scenario_id, simulation, trace, [
		int(state.get("completed_orders", 0)) >= 1,
		int(state.get("capacity_units_per_day", 0)) > capacity_before,
		simulation.economy.total_debt(enterprise_id) < debt_before,
		str(state.get("status", "")) == "operating",
	])


func _leveraged_business_failure() -> Dictionary:
	var scenario_id: String = "leveraged_business_failure"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "enterprise_near_bankruptcy"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var enterprise_id: String = "organization:vesta_redhill_industry"
	var state: Dictionary = simulation.enterprise.enterprises[
		enterprise_id
	] as Dictionary
	var trace: Array[Dictionary] = []
	var order: Dictionary = simulation.enterprise.accept_order(
		"scenario:failure:order",
		enterprise_id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		60,
		"region:loran_dawnbay",
		simulation.clock.total_hours,
		6
	)
	if not _succeeded(order):
		return _failed(scenario_id, "order_failed", trace)
	var order_id: String = str(
		((order.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	simulation.economy.contracts.delay(
		"scenario:failure:delay",
		order_id,
		simulation.clock.total_hours + 6 * 24,
		"投入品和执行能力不足"
	)
	var collateral_id: String = str(
		(state.get("asset_ids", []) as Array)[0]
	)
	var refinanced: Dictionary = simulation.enterprise.borrow_for_operations(
		"scenario:failure:refinance",
		enterprise_id,
		"organization:vesta_public_credit",
		5000,
		simulation.clock.total_hours,
		[collateral_id]
	)
	if not _succeeded(refinanced):
		return _failed(scenario_id, "refinance_failed", trace)
	var new_loan_id: String = str(
		((refinanced.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	var old_loan_id: String = _opening_loan_id(simulation, enterprise_id)
	simulation.economy.repay_loan(
		"scenario:failure:old_repay",
		old_loan_id,
		simulation.clock.total_hours,
		1000
	)
	trace.append(_fact("delay_refinance_and_rollover", {
		"order_contract_id": order_id,
		"old_loan_id": old_loan_id,
		"new_loan_id": new_loan_id,
	}))
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var loan_contract: Dictionary = simulation.economy.contracts.contracts[
		new_loan_id
	] as Dictionary
	var due_hour: int = int(loan_contract.get("end_hour", 0))
	simulation.economy.mark_loan_overdue(
		"scenario:failure:overdue", new_loan_id, due_hour + 1
	)
	simulation.economy.default_loan(
		"scenario:failure:default",
		new_loan_id,
		due_hour + 30 * 24,
		"再融资后仍无力偿还"
	)
	simulation.economy.seize_collateral(
		"scenario:failure:seize",
		new_loan_id,
		due_hour + 30 * 24
	)
	var bankrupt: Dictionary = simulation.enterprise.bankrupt(
		"scenario:failure:bankrupt",
		enterprise_id,
		due_hour + 30 * 24,
		"订单延期、借新还旧后违约"
	)
	if not _succeeded(bankrupt):
		return _failed(scenario_id, "bankruptcy_failed", trace)
	state = simulation.enterprise.enterprises[enterprise_id] as Dictionary
	trace.append(_fact("default_collateral_and_bankruptcy", {
		"enterprise_status": state.get("status", ""),
		"controller_id": state.get("controller_id", ""),
		"disposed_asset_ids": state.get("disposed_asset_ids", []),
	}))
	return _completed(scenario_id, simulation, trace, [
		str(state.get("status", "")) == "bankrupt",
		not (state.get("disposed_asset_ids", []) as Array).is_empty(),
		str((simulation.economy.contracts.contracts[
			new_loan_id
		] as Dictionary).get("status", "")) in ["defaulted", "enforced"],
	])


func _low_skill_with_professional_partner() -> Dictionary:
	var scenario_id: String = "low_skill_with_professional_partner"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "weak_owner_strong_partner"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var helper: CharacterData = simulation.roster.get_active(
		"character_lucien_moreau"
	)
	player.skills["finance"] = 15
	player.hidden_aptitudes["reasoning"] = 24
	player.domain_experience["trade"] = 6
	helper.skills["finance"] = 88
	helper.hidden_aptitudes["reasoning"] = 82
	var unassisted: Dictionary = simulation.character_service.assess_action(
		player, "operate_enterprise", "finance", "trade", 72, 24, 5000
	)
	var assisted: Dictionary = simulation.character_service.assess_action(
		player, "operate_enterprise", "finance", "trade", 72, 24, 5000,
		"", helper
	)
	var estimate: Dictionary = simulation.character_service.estimate_unknown_value(
		player, "fact:cash_runway", 1700, "finance", 70
	)
	var enterprise_id: String = _controlled_enterprise_id(
		simulation, player.id
	)
	var trace: Array[Dictionary] = [
		_fact("low_skill_estimate", {
			"error_risk": unassisted.get("error_risk", 0),
			"estimate": estimate.get("data", {}),
		}),
		_fact("professional_assessment", {
			"error_risk": assisted.get("error_risk", 0),
			"method_reliability": assisted.get("method_reliability", 0),
		}),
	]
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var service: Dictionary = simulation.enterprise.outsource_service(
		"scenario:partner:service",
		enterprise_id,
		helper.id,
		"现金与合同复核",
		300,
		simulation.clock.total_hours
	)
	if not _succeeded(service):
		return _failed(
			scenario_id,
			"professional_service_failed:%s" % str(
				service.get("code", "")
			),
			trace
		)
	var shrunk: Dictionary = simulation.enterprise.shrink(
		"scenario:partner:shrink", enterprise_id, 2
	)
	if not _succeeded(shrunk):
		return _failed(scenario_id, "orderly_exit_failed", trace)
	var state: Dictionary = simulation.enterprise.enterprises[
		enterprise_id
	] as Dictionary
	trace.append(_fact("professional_service_and_contraction", {
		"enterprise_status": state.get("status", ""),
		"capacity_units_per_day": state.get("capacity_units_per_day", 0),
	}))
	return _completed(scenario_id, simulation, trace, [
		bool(unassisted.get("can_attempt", false)),
		int(unassisted.get("error_risk", 0)) > int(
			assisted.get("error_risk", 0)
		),
		int(assisted.get("method_reliability", 0)) > int(
			unassisted.get("method_reliability", 0)
		),
		str(state.get("status", "")) == "distressed",
		_has_contract_type(simulation, enterprise_id, "partnership"),
		_has_contract_type(simulation, enterprise_id, "service"),
	])


func _organization_position_policy() -> Dictionary:
	var scenario_id: String = "organization_position_policy"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "policy_changed_region"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var organization_id: String = "organization:loran_commerce_registry"
	var implementation_id: String = str(
		simulation.politics.policy_implementations.keys()[0]
	)
	var implementation: Dictionary = simulation.politics.policy_implementations[
		implementation_id
	] as Dictionary
	var trace: Array[Dictionary] = [
		_fact("position_and_policy_completed", {
			"position_id": simulation.organization_service.get_position_id(
				player.id, organization_id
			),
			"implementation": implementation,
		})
	]
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	player = simulation.player_character()
	var lost: Dictionary = simulation.politics.lose_position(
		"scenario:policy:resign",
		player,
		organization_id,
		"resignation",
		simulation.clock.total_hours
	)
	if not _succeeded(lost):
		return _failed(scenario_id, "position_loss_failed", trace)
	var wage_index: int = int((
		simulation.world.regions["region:loran_dawnbay"] as Dictionary
	).get("wage_index", 0))
	trace.append(_fact("position_lost_after_policy", {
		"new_position_id": simulation.organization_service.get_position_id(
			player.id, organization_id
		),
		"wage_index": wage_index,
	}))
	return _completed(scenario_id, simulation, trace, [
		str(implementation.get("status", "")) == "completed",
		wage_index > 112,
		simulation.organization_service.get_position_id(
			player.id, organization_id
		) == "clerk",
		not (implementation.get("support_reactions", []) as Array).is_empty(),
		not (implementation.get("opposition_reactions", []) as Array).is_empty(),
	])


func _corruption_and_investigation() -> Dictionary:
	var scenario_id: String = "corruption_and_investigation"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "local_official"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var actor: CharacterData = simulation.player_character()
	var investigator: CharacterData = simulation.roster.get_active(
		"character_lucien_moreau"
	)
	investigator.skills["investigation"] = 95
	investigator.hidden_aptitudes["reasoning"] = 88
	var organization_id: String = "organization:loran_commerce_registry"
	var beneficiary_id: String = "organization:loran_dawnbay_trade"
	var benefit_before: int = simulation.economy.ledger.owner_cash(
		beneficiary_id
	)
	var corrupted: Dictionary = simulation.politics.perform_corruption(
		"scenario:corruption:steer",
		"corruption:steer_contract",
		actor,
		organization_id,
		beneficiary_id,
		800,
		simulation.clock.total_hours,
		[investigator.id],
		{"relationship": "关联企业"}
	)
	if not _succeeded(corrupted):
		return _failed(scenario_id, "corruption_failed", [])
	var corruption_case: Dictionary = (
		corrupted.get("data", {}) as Dictionary
	).get("corruption_case", {}) as Dictionary
	var case_id: String = str(corruption_case.get("case_id", ""))
	var trace: Array[Dictionary] = [
		_fact("contract_steered_with_evidence", corruption_case)
	]
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	actor = simulation.player_character()
	investigator = simulation.roster.get_active("character_lucien_moreau")
	var investigated: Dictionary = simulation.politics.investigate_corruption(
		"scenario:corruption:investigate",
		case_id,
		investigator,
		organization_id,
		simulation.clock.total_hours
	)
	if not _succeeded(investigated):
		return _failed(scenario_id, "investigation_failed", trace)
	var investigation: Dictionary = (
		investigated.get("data", {}) as Dictionary
	).get("investigation", {}) as Dictionary
	var resolved: Dictionary = simulation.politics.resolve_investigation(
		"scenario:corruption:resolve",
		str(investigation.get("investigation_id", "")),
		actor,
		simulation.clock.total_hours
	)
	if not _succeeded(resolved):
		return _failed(scenario_id, "resolution_failed", trace)
	trace.append(_fact("investigation_and_sanction", {
		"investigation_status": investigation.get("status", ""),
		"resolution": resolved.get("data", {}),
	}))
	return _completed(scenario_id, simulation, trace, [
		simulation.economy.ledger.owner_cash(beneficiary_id)
		== benefit_before + 800,
		not str(corruption_case.get("transaction_id", "")).is_empty(),
		not str(corruption_case.get("document_id", "")).is_empty(),
		not (corruption_case.get("witness_ids", []) as Array).is_empty(),
		str(investigation.get("status", "")) == "substantiated",
		simulation.organization_service.get_position_id(
			actor.id, organization_id
		) == "clerk",
		not simulation.politics.public_events.is_empty(),
	])


func _three_year_unattended_world() -> Dictionary:
	var scenario_id: String = "three_year_unattended_world"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "employed_worker"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var initial_prices: Dictionary = _price_snapshot(simulation)
	var initial_appointments: int = simulation.politics.appointments.size()
	var trace: Array[Dictionary] = []
	var performance_started_usec: int = Time.get_ticks_usec()
	simulation.advance_hours(30 * 24)
	var thirty_day_usec: int = Time.get_ticks_usec() - performance_started_usec
	simulation.advance_hours((365 - 30) * 24)
	var year_usec: int = Time.get_ticks_usec() - performance_started_usec
	simulation.advance_hours((18 * 30 - 365) * 24)
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "midpoint_checkpoint_failed", trace)
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var remaining_hours: int = 3 * 365 * 24 - 18 * 30 * 24
	simulation.advance_hours(remaining_hours)
	var three_year_usec: int = (
		Time.get_ticks_usec() - performance_started_usec
	)
	var summary: Dictionary = simulation.world_dynamics.summary()
	var counters: Dictionary = summary.get("counters", {}) as Dictionary
	var region_counts: Dictionary = summary.get(
		"background_by_region", {}
	) as Dictionary
	var enterprise_statuses: Dictionary = summary.get(
		"enterprise_statuses", {}
	) as Dictionary
	var max_region_population: int = 0
	for raw_count: Variant in region_counts.values():
		max_region_population = maxi(max_region_population, int(raw_count))
	var active_enterprises: int = (
		int(enterprise_statuses.get("operating", 0))
		+ int(enterprise_statuses.get("distressed", 0))
		+ int(enterprise_statuses.get("contracting", 0))
	)
	var matters_bounded: bool = true
	for background: Dictionary in simulation.world_dynamics.background_states.values():
		if (background.get("important_matters", []) as Array).size() > 3:
			matters_bounded = false
			break
	var national_issues_changed: bool = true
	for issue: Dictionary in simulation.world_dynamics.national_issues.values():
		if int(issue.get("last_changed_hour", 0)) <= 0:
			national_issues_changed = false
			break
	var price_changed: bool = (
		_price_snapshot(simulation) != initial_prices
	)
	trace.append(_fact("three_year_world_summary", {
		"elapsed_hours": simulation.alpha_hours_processed,
		"world_summary": summary,
		"appointments": simulation.politics.appointments.size(),
		"prices_changed": price_changed,
		"counts": simulation.alpha_counts(),
		"performance": {
			"thirty_day_usec": thirty_day_usec,
			"year_usec": year_usec,
			"three_year_usec": three_year_usec,
			"checkpoint_snapshot_usec": checkpoint.get(
				"snapshot_usec", 0
			),
			"checkpoint_restore_usec": checkpoint.get(
				"restore_usec", 0
			),
			"checkpoint_size_bytes": checkpoint.get(
				"snapshot_size_bytes", 0
			),
		},
	}))
	return _completed(scenario_id, simulation, trace, [
		simulation.alpha_hours_processed == 3 * 365 * 24,
		int(summary.get("background_employed", 0)) > 0,
		int(summary.get("background_unemployed", 0)) > 0,
		int(counters.get("background_job_changes", 0)) > 0,
		int(counters.get("background_migrations", 0)) > 0,
		int(counters.get("enterprise_bankruptcies", 0)) > 0,
		int(counters.get("loan_defaults", 0)) > 0,
		int(counters.get("policy_changes", 0)) > 0,
		price_changed,
		active_enterprises > 0,
		region_counts.size() == 8,
		max_region_population < 60,
		simulation.politics.appointments.size() > initial_appointments,
		simulation.world_dynamics.national_issues.size() >= 6,
		national_issues_changed,
		simulation.world_dynamics.events.size()
		<= AlphaWorldDynamicsService.EVENT_LIMIT,
		simulation.alpha_ai.decisions.size() <= AlphaAiService.HISTORY_LIMIT,
		matters_bounded,
	])


func _save_load_mid_contract() -> Dictionary:
	var scenario_id: String = "save_load_mid_contract"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "employed_worker"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var trade: Dictionary = simulation.economy.create_trade(
		"scenario:contract:create",
		player.id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		"grain",
		2,
		"region:loran_southridge",
		player.region_id,
		simulation.clock.total_hours,
		5
	)
	if not _succeeded(trade):
		return _failed(scenario_id, "contract_creation_failed", [])
	var contract_id: String = str(
		((trade.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", [])
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var settled: Dictionary = simulation.economy.settle_trade(
		"scenario:contract:settle",
		contract_id,
		simulation.clock.total_hours + 5 * 24
	)
	var duplicate: Dictionary = simulation.economy.settle_trade(
		"scenario:contract:settle",
		contract_id,
		simulation.clock.total_hours + 5 * 24
	)
	var contract: Dictionary = simulation.economy.contracts.contracts[
		contract_id
	] as Dictionary
	var trace: Array[Dictionary] = [_fact("contract_resumed_and_settled", {
		"contract_id": contract_id,
		"status": contract.get("status", ""),
		"duplicate": duplicate.get("data", {}).get("duplicate", false),
	})]
	return _completed(scenario_id, simulation, trace, [
		_succeeded(settled),
		_succeeded(duplicate),
		str(contract.get("status", "")) in ["fulfilled", "settled"],
	])


func _save_load_mid_debt_default() -> Dictionary:
	var scenario_id: String = "save_load_mid_debt_default"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "indebted_low_income"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var loan_id: String = _first_loan_id(simulation, player.id)
	var loan: Dictionary = simulation.economy.contracts.contracts[
		loan_id
	] as Dictionary
	var due_hour: int = int(loan.get("end_hour", 0))
	var overdue: Dictionary = simulation.economy.mark_loan_overdue(
		"scenario:debt:overdue", loan_id, due_hour + 1
	)
	if not _succeeded(overdue):
		return _failed(scenario_id, "overdue_failed", [])
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", [])
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var defaulted: Dictionary = simulation.economy.default_loan(
		"scenario:debt:default",
		loan_id,
		due_hour + 30 * 24,
		"个人现金不足且重组未达成"
	)
	var duplicate: Dictionary = simulation.economy.default_loan(
		"scenario:debt:default",
		loan_id,
		due_hour + 30 * 24,
		"个人现金不足且重组未达成"
	)
	var contract: Dictionary = simulation.economy.contracts.contracts[
		loan_id
	] as Dictionary
	var trace: Array[Dictionary] = [_fact("debt_default_resumed", {
		"loan_contract_id": loan_id,
		"status": contract.get("status", ""),
	})]
	return _completed(scenario_id, simulation, trace, [
		_succeeded(defaulted),
		_succeeded(duplicate),
		str(contract.get("status", "")) == "defaulted",
		simulation.economy.total_debt(player.id) > 0,
	])


func _save_load_mid_policy_implementation() -> Dictionary:
	var scenario_id: String = "save_load_mid_policy_implementation"
	var simulation: AlphaSimulationService = _new_simulation(
		scenario_id, "local_official"
	)
	if simulation == null:
		return _failed(scenario_id, "initialization_failed", [])
	var player: CharacterData = simulation.player_character()
	var organization_id: String = "organization:loran_commerce_registry"
	var wage_before: int = int((
		simulation.world.regions["region:loran_dawnbay"] as Dictionary
	).get("wage_index", 0))
	var proposed: Dictionary = simulation.politics.propose_policy(
		"scenario:policy_save:propose",
		player,
		organization_id,
		"policy:loran_wage_floor",
		["region:loran_dawnbay"],
		simulation.clock.total_hours
	)
	if not _succeeded(proposed):
		return _failed(scenario_id, "proposal_failed", [])
	var implementation_id: String = str(
		((proposed.get("data", {}) as Dictionary).get(
			"implementation", {}
		) as Dictionary).get("implementation_id", "")
	)
	var funded: Dictionary = simulation.politics.fund_and_start_policy(
		"scenario:policy_save:fund",
		implementation_id,
		simulation.clock.total_hours
	)
	if not _succeeded(funded):
		return _failed(scenario_id, "funding_failed", [])
	var checkpoint: Dictionary = _checkpoint(simulation)
	if not bool(checkpoint.get("success", false)):
		return _failed(scenario_id, "checkpoint_failed", [])
	simulation = checkpoint["simulation"] as AlphaSimulationService
	var advanced: Dictionary = simulation.politics.advance_policy(
		"scenario:policy_save:advance",
		implementation_id,
		simulation.clock.total_hours,
		12
	)
	var implementation: Dictionary = simulation.politics.policy_implementations[
		implementation_id
	] as Dictionary
	var wage_after: int = int((
		simulation.world.regions["region:loran_dawnbay"] as Dictionary
	).get("wage_index", 0))
	var trace: Array[Dictionary] = [_fact("policy_resumed_and_completed", {
		"implementation_id": implementation_id,
		"status": implementation.get("status", ""),
		"wage_before": wage_before,
		"wage_after": wage_after,
	})]
	return _completed(scenario_id, simulation, trace, [
		_succeeded(advanced),
		str(implementation.get("status", "")) == "completed",
		wage_after > wage_before,
	])


func _new_simulation(
	scenario_id: String, review_state_id: String
) -> AlphaSimulationService:
	var simulation := AlphaSimulationService.new()
	if not simulation.set_launch_review_state(review_state_id):
		return null
	if not simulation.initialize():
		return null
	simulation.random.set_seed(int(FIXED_SEEDS[scenario_id]))
	return simulation


func _checkpoint(simulation: AlphaSimulationService) -> Dictionary:
	var service := AlphaSaveService.new()
	var snapshot_started_usec: int = Time.get_ticks_usec()
	var snapshot: Dictionary = service.build_snapshot(simulation)
	var snapshot_usec: int = Time.get_ticks_usec() - snapshot_started_usec
	if not service.validate_snapshot(snapshot).is_empty():
		return {"success": false}
	var restored := AlphaSimulationService.new()
	if not restored.initialize():
		return {"success": false}
	var restore_started_usec: int = Time.get_ticks_usec()
	var result: SaveOperationResult = service.restore(snapshot, restored)
	return {
		"success": result.success,
		"simulation": restored,
		"snapshot_size_bytes": JSON.stringify(snapshot).to_utf8_buffer().size(),
		"snapshot_usec": snapshot_usec,
		"restore_usec": Time.get_ticks_usec() - restore_started_usec,
	}


func _completed(
	scenario_id: String,
	simulation: AlphaSimulationService,
	trace: Array[Dictionary],
	assertions: Array
) -> Dictionary:
	last_simulation = simulation
	var assertion_success: bool = true
	for raw_assertion: Variant in assertions:
		assertion_success = assertion_success and bool(raw_assertion)
	var integrity: Dictionary = simulation.validate_alpha_integrity()
	var save_service := AlphaSaveService.new()
	var snapshot: Dictionary = save_service.build_snapshot(simulation)
	var snapshot_errors: Array[String] = save_service.validate_snapshot(snapshot)
	var success: bool = (
		assertion_success
		and bool(integrity.get("success", false))
		and snapshot_errors.is_empty()
	)
	return {
		"success": success,
		"scenario_id": scenario_id,
		"fixed_seed": int(FIXED_SEEDS.get(scenario_id, 0)),
		"summary": "%s：%d 个事实节点；统一引用%s；账本%s。" % [
			scenario_id,
			trace.size(),
			"闭合" if bool(integrity.get("success", false)) else "失败",
			"平衡" if bool(
				simulation.economy.ledger.validate_balances().get(
					"success", false
				)
			) else "失衡",
		],
		"trace": trace,
		"assertion_count": assertions.size(),
		"assertions_passed": assertion_success,
		"integrity": integrity,
		"snapshot_errors": snapshot_errors,
		"snapshot_size_bytes": JSON.stringify(
			snapshot
		).to_utf8_buffer().size(),
		"counts": simulation.alpha_counts(),
		"maximum_hour_usec": simulation.alpha_maximum_hour_usec,
	}


func _failed(
	scenario_id: String, code: String, trace: Array[Dictionary]
) -> Dictionary:
	return {
		"success": false,
		"scenario_id": scenario_id,
		"fixed_seed": int(FIXED_SEEDS.get(scenario_id, 0)),
		"code": code,
		"summary": "%s 在 %s 停止。" % [scenario_id, code],
		"trace": trace,
	}


func _borrow_person(
	simulation: AlphaSimulationService,
	player: CharacterData,
	amount: int,
	key: String
) -> Dictionary:
	var lender_id: String = (
		"organization:loran_public_credit"
		if player.country_id == "country:loran_federation"
		else "organization:vesta_public_credit"
	)
	var applied: Dictionary = simulation.economy.apply_for_loan(
		"%s:apply" % key,
		player.id,
		lender_id,
		"credit:personal_unsecured",
		amount,
		simulation.clock.total_hours,
		[],
		["character_albert_dumont", "jeanne"],
		{
			"existing_debt_centimes": simulation.economy.total_debt(
				player.id
			),
		}
	)
	if not _succeeded(applied):
		return applied
	var application_id: String = str(
		((applied.get("data", {}) as Dictionary).get(
			"application", {}
		) as Dictionary).get("application_id", "")
	)
	var reviewed: Dictionary = simulation.economy.review_application(
		"%s:review" % key,
		application_id,
		simulation.clock.total_hours
	)
	if not _succeeded(reviewed):
		return reviewed
	var application: Dictionary = (
		reviewed.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	if str(application.get("status", "")) != "offered":
		return {
			"success": false,
			"code": "credit_rejected",
			"message": "正式信用审查未提出条件",
			"data": {"application": application},
		}
	return simulation.economy.accept_loan_offer(
		"%s:accept" % key,
		application_id,
		simulation.clock.total_hours
	)


func _active_employment_id(
	simulation: AlphaSimulationService, person_id: String
) -> String:
	var profile: Dictionary = simulation.labor.person_profiles.get(
		person_id, {}
	) as Dictionary
	for contract_id: String in DataRecordUtils.to_string_array(
		profile.get("employment_contract_ids", [])
	):
		var state: Dictionary = simulation.labor.employment_states.get(
			contract_id, {}
		) as Dictionary
		if str(state.get("status", "")) in (
			AlphaLaborService.ACTIVE_EMPLOYMENT_STATUSES
		):
			return contract_id
	return ""


func _controlled_enterprise_id(
	simulation: AlphaSimulationService, controller_id: String
) -> String:
	for raw_id: Variant in simulation.enterprise.enterprises:
		var enterprise_id: String = str(raw_id)
		var state: Dictionary = simulation.enterprise.enterprises[
			enterprise_id
		] as Dictionary
		if str(state.get("controller_id", "")) == controller_id:
			return enterprise_id
	return ""


func _first_loan_id(
	simulation: AlphaSimulationService, borrower_id: String
) -> String:
	for contract: Dictionary in (
		simulation.economy.contracts.contracts_for_party(
			borrower_id, false
		)
	):
		if (
			str(contract.get("contract_type", "")) == "loan"
			and _party_with_role(contract, "borrower") == borrower_id
		):
			return str(contract.get("contract_id", ""))
	return ""


func _opening_loan_id(
	simulation: AlphaSimulationService, borrower_id: String
) -> String:
	for contract: Dictionary in (
		simulation.economy.contracts.contracts_for_party(
			borrower_id, false
		)
	):
		if (
			str(contract.get("contract_type", "")) == "loan"
			and _party_with_role(contract, "borrower") == borrower_id
			and bool((contract.get("subject", {}) as Dictionary).get(
				"opening_obligation", false
			))
		):
			return str(contract.get("contract_id", ""))
	return ""


func _has_contract_type(
	simulation: AlphaSimulationService,
	party_id: String,
	contract_type: String
) -> bool:
	for contract: Dictionary in (
		simulation.economy.contracts.contracts_for_party(party_id, true)
	):
		if str(contract.get("contract_type", "")) == contract_type:
			return true
	return false


func _price_snapshot(simulation: AlphaSimulationService) -> Dictionary:
	var result: Dictionary = {}
	var region_ids: Array[String] = []
	for raw_region_id: Variant in simulation.economy.markets:
		region_ids.append(str(raw_region_id))
	region_ids.sort()
	var good_ids: Array[String] = []
	for raw_good_id: Variant in simulation.economy.goods:
		good_ids.append(str(raw_good_id))
	good_ids.sort()
	for region_id: String in region_ids:
		for good_id: String in good_ids:
			result["%s|%s" % [region_id, good_id]] = (
				simulation.economy.market_price(region_id, good_id)
			)
	return result


static func _party_with_role(contract: Dictionary, role: String) -> String:
	for raw_party: Variant in contract.get("parties", []) as Array:
		var party: Dictionary = raw_party as Dictionary
		if str(party.get("role", "")) == role:
			return str(party.get("party_id", ""))
	return ""


static func _fact(kind: String, data: Dictionary) -> Dictionary:
	return {"kind": kind, "data": data.duplicate(true)}


static func _succeeded(result: Dictionary) -> bool:
	return bool(result.get("success", false))
