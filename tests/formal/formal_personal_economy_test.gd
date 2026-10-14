extends SceneTree

const PERSON: String = WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
const FRA: String = "country_fra"
const WEEK: int = 7 * 24 * 60
var test := FormalTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_ledger()
	_test_opening_and_no_job()
	_test_wage_and_partition()
	_test_exhaustion()
	_test_persistence_rejections()
	test.finish(self, "Formal personal economy and wages")


func _test_ledger() -> void:
	var ledger := FormalLedgerState.new()
	test.expect(ledger.configure(100), "Ledger has a finite explicit scenario endowment")
	test.expect(ledger.open_account("account:person", "person:one", "personal_cash"), "Personal account starts at zero")
	test.expect(ledger.open_account("account:payer", "employer:one", "background_payer"), "Payer account starts at zero")
	test.equal(ledger.balance("account:person"), 0, "Account creation never grants unexplained cash")
	test.equal(ledger.balance("account:missing"), null, "Unavailable account is not zero")
	test.expect(ledger.transfer("opening:one", FormalLedgerState.SOURCE_ACCOUNT, "account:person", 60, 0, "opening_cash", "person:one"), "Opening cash moves from finite source through a transaction")
	var before := ledger.snapshot()
	test.expect(ledger.transfer("opening:one", FormalLedgerState.SOURCE_ACCOUNT, "account:person", 60, 0, "opening_cash", "person:one"), "Exact opening retry is idempotent")
	test.equal(ledger.snapshot(), before, "Opening retry does not grant more cash")
	test.expect(not ledger.transfer("opening:one", FormalLedgerState.SOURCE_ACCOUNT, "account:person", 61, 0, "opening_cash", "person:one"), "Conflicting idempotency key is rejected")
	test.expect(not ledger.open_account("account:person", "person:one", "personal_cash"), "Duplicate account rejected")
	test.expect(not ledger.open_account("account:second", "person:one", "personal_cash"), "Same person cannot acquire a second personal cash account under another ID")
	test.equal(ledger.snapshot(), before, "Rejected transactions/accounts do not mutate money")
	test.expect(ledger.transfer("reserve:one", FormalLedgerState.SOURCE_ACCOUNT, "account:payer", 40, 0, "employer_reserve", "employer:one"), "Payer reserve is a recorded opening transfer")
	before = ledger.snapshot()
	test.expect(not ledger.transfer("wage:too_much", "account:payer", "account:person", 41, WEEK, "wage", "period:1"), "Insufficient payer cannot make a partial payment")
	test.equal(ledger.snapshot(), before, "Failed wage preserves both account balances and receipts")
	test.expect(ledger.transfer("wage:one", "account:payer", "account:person", 10, WEEK, "wage", "period:1"), "Funded wage uses the normal Ledger transfer")
	test.equal(ledger.balance("account:payer"), 30, "Payer decreases by exactly the wage")
	test.equal(ledger.balance("account:person"), 70, "Person increases by exactly the wage")
	test.equal(ledger.transaction("wage:one")["denomination"], FormalLedgerState.DENOMINATION, "Wage and accounts use one neutral denomination")
	var saved := ledger.snapshot()
	var restored := FormalLedgerState.new()
	test.expect(restored.restore(saved), "Ledger restores by validating and replaying receipts")
	test.equal(restored.snapshot(), saved, "Ledger snapshot restores exactly")
	for corruption: String in ["balance", "denomination", "duplicate", "float_amount"]:
		var invalid := saved.duplicate(true)
		match corruption:
			"balance": invalid["accounts"][0]["balance"] += 1
			"denomination": invalid["accounts"][0]["denomination"] = "historical_franc"
			"duplicate": invalid["transactions"].append(invalid["transactions"][0])
			"float_amount": invalid["transactions"][0]["amount"] = 60.0
		test.expect(not restored.restore(invalid), "Ledger corruption rejected: " + corruption)
		test.equal(restored.snapshot(), saved, "Failed ledger restore preserves current state: " + corruption)
	var detached := ledger.account("account:person")
	detached["balance"] = 999
	test.equal(ledger.balance("account:person"), 70, "Read-only account observation is detached")


func _test_opening_and_no_job() -> void:
	var built := WorldBootstrap.new().build()
	test.expect(built.success, "No-job Formal world initializes: " + built.error)
	if not built.success:
		return
	var state := built.world.personal_economy_state
	var ledger := built.world.ledger_state
	var account_id := state.account_id_for_person(PERSON)
	test.equal(account_id, "account:personal:formal_generated_country_fra_0001", "Player has a stable personal account ID")
	test.equal(ledger.account_ids().size(), 2, "New player has exactly one personal account plus one finite opening source")
	test.equal(ledger.balance(account_id), 2500, "Opening cash is the documented stable simulation amount")
	test.equal(ledger.balance(FormalLedgerState.SOURCE_ACCOUNT), 0, "Opening source is finite and spent, not an infinite faucet")
	test.equal(ledger.transactions().size(), 1, "Opening transaction exists exactly once")
	test.equal(ledger.transaction("opening:" + PERSON)["basis"], "GENERATED_SIMULATION_ASSUMPTION", "Opening money is explicitly generated, not historical wealth")
	test.equal(state.person_economy(PERSON)["livelihood"], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, "No-job livelihood is explicit")
	test.equal(state.employment(PERSON), {}, "No job has no fake wage or employer")
	test.equal(state.snapshot()["employers"], {}, "No job creates no payer sector")
	var population := built.world.population_state.snapshot()
	var politics := built.world.political_registry.snapshot()
	var control := built.world.territory_state.snapshot()
	var opening := ledger.snapshot()
	built.simulation_step.advance_minutes(WEEK)
	test.equal(ledger.snapshot(), opening, "Time cannot invent cash for an unemployed person")
	test.equal(built.world.population_state.snapshot(), population, "Opening and no-job livelihood conserve Population")
	test.equal(built.world.political_registry.snapshot(), politics, "Opening cash does not change sovereignty")
	test.equal(built.world.territory_state.snapshot(), control, "Opening cash does not change controller")
	var invalid_build := WorldBootstrap.new().build(null, [], [], "INVALID_LIVELIHOOD")
	test.expect(not invalid_build.success, "Invalid New Game livelihood cannot install a candidate")
	test.equal(ledger.snapshot(), opening, "Failed construction leaves the installed personal Ledger unchanged")


func _test_wage_and_partition() -> void:
	var bulk := _wage_world()
	var split := _wage_world()
	var no_job := WorldBootstrap.new().build()
	test.expect(bulk.success and split.success and no_job.success, "Wage and partition comparison worlds initialize")
	if not bulk.success or not split.success or not no_job.success:
		return
	var state := bulk.world.personal_economy_state
	var employment := state.employment(PERSON)
	var employer := state.employer(employment["employer_id"])
	var account_id := state.account_id_for_person(PERSON)
	var payer_id := str(employment["payer_account_id"])
	test.equal(employer["population_unit_id"], FRA, "French person receives wages from the same population scope")
	test.equal(employer["economic_aggregate_id"], FRA, "Payer explicitly references the same economic scope")
	test.equal(employer["initial_reserve"], 12000, "Employer reserve is a finite scenario amount")
	test.equal(bulk.world.ledger_state.balance(payer_id), 12000, "Finite payer has real Ledger money")
	test.equal(employment["wage_amount"], 1000, "General labor has a fixed wage")
	test.equal(employment["pay_period_minutes"], WEEK, "Pay period is seven days of GameClock minutes")
	test.equal(employment["next_pay_boundary"], WEEK, "First wage boundary is Jan 8 midnight")
	var population := bulk.world.population_state.snapshot()
	var politics := bulk.world.political_registry.snapshot()
	var control := bulk.world.territory_state.snapshot()
	bulk.simulation_step.advance_minutes(WEEK - 1)
	test.equal(bulk.world.ledger_state.balance(account_id), 2500, "No wage is paid before its exact boundary")
	var change := bulk.simulation_step.advance_minutes(1)
	test.equal(change["wages_paid"], 1, "SimulationStep dispatches one due wage")
	for day: int in 7:
		split.simulation_step.advance_minutes(24 * 60)
	no_job.simulation_step.advance_minutes(WEEK)
	test.equal(bulk.world.ledger_state.balance(account_id), 3500, "Boundary credits the real personal account")
	test.equal(bulk.world.ledger_state.balance(payer_id), 11000, "Boundary debits the real payer account")
	test.equal(state.employment(PERSON)["settled_periods"], [1], "One stable pay period is settled")
	test.equal(state.employment(PERSON)["next_pay_boundary"], WEEK * 2, "Next boundary advances exactly one period")
	test.equal(bulk.world.ledger_state.snapshot(), split.world.ledger_state.snapshot(), "Bulk and daily advancement have identical Ledger results")
	test.equal(state.snapshot(), split.world.personal_economy_state.snapshot(), "Bulk and daily advancement have identical employment results")
	test.equal(bulk.world.economy_state.legacy_regression_snapshot(), no_job.world.economy_state.legacy_regression_snapshot(), "Employment and wages do not alter aggregate demand or production")
	test.equal(bulk.world.population_state.snapshot(), population, "Employment neither materializes people nor increases Population")
	test.equal(bulk.world.political_registry.snapshot(), politics, "Employment does not change sovereignty")
	test.equal(bulk.world.territory_state.snapshot(), control, "Employment does not change controller")
	var ledger_before := bulk.world.ledger_state.snapshot()
	state.settle_due_wages()
	bulk.simulation_step.advance_minutes(0)
	test.equal(bulk.world.ledger_state.snapshot(), ledger_before, "Repeated boundary settlement cannot pay twice")
	var saved := bulk.persistence.snapshot()
	var restored := bulk.persistence.restore_candidate(saved)
	test.expect(restored.success, "Paid wage world restores: " + restored.error)
	if restored.success:
		test.equal(restored.persistence.snapshot(), saved, "Paid wage save/load is exact")
		restored.world.personal_economy_state.settle_due_wages()
		test.equal(restored.persistence.snapshot(), saved, "Load cannot reopen a settled wage period")
		restored.simulation_step.advance_minutes(WEEK)
		test.equal(restored.world.ledger_state.balance(account_id), 4500, "Next period pays normally after load")
		test.equal(restored.world.ledger_state.balance(payer_id), 10000, "Loaded finite reserve is debited again only for the next period")


func _test_exhaustion() -> void:
	var built := _wage_world()
	test.expect(built.success, "Finite reserve exhaustion world initializes")
	if not built.success:
		return
	var state := built.world.personal_economy_state
	var payer_id := str(state.employment(PERSON)["payer_account_id"])
	built.simulation_step.advance_minutes(12 * WEEK)
	test.equal(built.world.ledger_state.balance(payer_id), 0, "Twelve wages exhaust the finite reserve")
	test.equal(built.world.ledger_state.balance(state.account_id_for_person(PERSON)), 14500, "Player receives exactly twelve funded wages")
	var before := built.world.ledger_state.snapshot()
	var employment_before := state.snapshot()
	var failed := built.simulation_step.advance_minutes(WEEK)
	test.expect(int(failed["wages_failed"]) > 0, "Thirteenth pay period reports real insufficient funds")
	test.equal(built.world.ledger_state.snapshot(), before, "Failed payment leaves both balances and transactions unchanged")
	test.equal(state.snapshot(), employment_before, "Failed period is not marked settled and boundary stays pending")
	test.equal((state.employment(PERSON)["settled_periods"] as Array).size(), 12, "No phantom paid period after exhaustion")
	test.expect(bool(state.person_economy(PERSON)["wage_unpaid"]), "Player observation explains the overdue wage")
	var restored := built.persistence.restore_candidate(built.persistence.snapshot())
	test.expect(restored.success, "Overdue unpaid period restores without granting reserve: " + restored.error)
	if restored.success:
		restored.simulation_step.advance_minutes(1)
		test.equal(restored.world.ledger_state.snapshot(), before, "Retry after load neither refills nor partially pays")


func _test_persistence_rejections() -> void:
	var built := _wage_world()
	if not built.success:
		test.expect(false, "Persistence rejection world initializes")
		return
	built.simulation_step.advance_minutes(WEEK)
	var saved := built.persistence.snapshot()
	for corruption: String in ["cash", "missing_ledger", "missing_finance", "opening_amount", "payer_scope", "wage", "period", "duplicate_period", "next_boundary", "extra_employment", "old_v13"]:
		var invalid := saved.duplicate(true)
		match corruption:
			"cash": invalid["ledger"]["accounts"][0]["balance"] += 1
			"missing_ledger": invalid.erase("ledger")
			"missing_finance": invalid.erase("personal_economy")
			"opening_amount": invalid["ledger"]["transactions"][0]["amount"] += 1
			"payer_scope": invalid["personal_economy"]["employers"].values()[0]["population_unit_id"] = "german_empire"
			"wage": invalid["personal_economy"]["employments"][PERSON]["wage_amount"] += 1
			"period": invalid["personal_economy"]["employments"][PERSON]["settled_periods"] = []
			"duplicate_period": invalid["personal_economy"]["employments"][PERSON]["settled_periods"] = [1, 1]
			"next_boundary": invalid["personal_economy"]["employments"][PERSON]["next_pay_boundary"] += 1
			"extra_employment": invalid["personal_economy"]["employments"]["person:uncreated"] = invalid["personal_economy"]["employments"][PERSON].duplicate(true)
			"old_v13": invalid["schema_id"] = "formal_world_simulation_v13"
		var rejected := built.persistence.restore_candidate(invalid)
		test.expect(not rejected.success, "Corrupt personal economy candidate rejected: " + corruption)
		test.equal(built.persistence.snapshot(), saved, "Rejected candidate cannot pollute installed world: " + corruption)


func _wage_world() -> WorldBuildResult:
	return WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.GENERAL_WAGE_LABOR)
