extends SceneTree

const PERSON: String = WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
const FRA: String = "country_fra"
const WEEK: int = 7 * 24 * 60
var test := FormalTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--native-multi-employer" in OS.get_cmdline_user_args():
		_test_native_multi_employer()
		_test_native_employment()
		_test_native_residents()
		_test_native_consumption()
		test.finish(self, "Formal Paris two employers")
		return
	if "--native-employment" in OS.get_cmdline_user_args():
		_test_native_employment()
		_test_native_residents()
		_test_native_consumption()
		test.finish(self, "Formal Paris employment circulation")
		return
	if "--native-residents" in OS.get_cmdline_user_args():
		_test_native_residents()
		_test_native_consumption()
		test.finish(self, "Formal Paris autonomous residents")
		return
	if "--native-consumption" in OS.get_cmdline_user_args():
		_test_native_consumption()
		test.finish(self, "Formal Paris personal consumption")
		return
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


func _test_native_consumption() -> void:
	# Isolated Opening variants use no live player save or research runtime.
	var settings := FormalEconomicOpening.single_employer(FRA)
	settings["production_enabled"] = false
	settings["firms"][0]["sites"][0]["stock"]["bread"] = 1
	var built := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, settings)
	var ready: bool = built.success and built.world.economy_r1 != null
	test.expect(ready, "Isolated one-loaf Opening: " + built.error + (built.world.native_economy_error if built.world != null else ""))
	if not ready: return
	var world := built.world
	var native := world.economy_r1
	var personal := world.personal_economy_state
	var site := "site:opening_paris_workshop:paris"
	var account := personal.account_id_for_person(PERSON)
	var payload := {"quote_id":"unknown", "seller":"firm:opening_paris_workshop", "seller_site":site, "good":"grain", "quantity":1, "purpose":"HOLDING"}
	test.equal(LivelihoodAction.execute_current(world,"buy",payload).reason,"UNKNOWN_SUPPLIER","Visible workshop does not reveal its undisclosed grain offer")
	test.equal(native.personal_market_rows(PERSON,10,0).size(),1,"Only Opening bread notice is known")
	test.expect(not personal.purchase_quote(PERSON,site,"native:bread",1).success,"Unstaffed shop cannot sell at Opening")
	test.expect(LivelihoodAction.execute_current(world,"apply",{"job_id":"job:opening_paris_workshop"}).accepted,"Existing job application accepted")
	test.expect(LivelihoodAction.execute_current(world,"work",{"hours":2}).accepted,"Existing work funds actual staffing")
	built.simulation_step.advance_minutes(1440)
	var quote := personal.purchase_quote(PERSON,site,"native:bread",1)
	test.expect(quote.get("success",false),"Actual staffed window has bread quote")
	test.expect(not world.person_travel.can_carry_extra(PERSON,"bread",5),"Explicit local carrying limit is enforced without creating travel routes")
	test.expect(world.ledger_state.reserve("test:available_cash",account,world.ledger_state.balance(account)),"Isolated ledger reservation uses existing available-funds mechanism")
	var cash_before := world.ledger_state.snapshot()
	var refused := personal.purchase(PERSON,site,"native:bread",1,2,quote)
	test.expect(not refused.success,"Reserved money cannot fund purchase")
	test.equal(world.ledger_state.snapshot(),cash_before,"Cash refusal performs no payment")
	world.ledger_state.release("test:available_cash",world.ledger_state.balance(account))
	built.simulation_step.advance_minutes(1)
	test.equal(personal.purchase(PERSON,site,"native:bread",1,2,quote).error,"EXPIRED_QUOTE","Old quote cannot survive formal minute change")
	quote = personal.purchase_quote(PERSON,site,"native:bread",1)
	test.expect(personal.purchase(PERSON,site,"native:bread",1,2,quote).success,"Existing personal purchase obtains actual loaf onsite")
	test.equal(personal.holding(PERSON,"native:bread").quantity,1,"Delivered loaf belongs to person")
	test.equal(native._stocks[site]["bread"],0,"Seller has no copy of delivered loaf")
	var command: Dictionary = {}
	for row: Dictionary in native._commands.values():
		if row.envelope.command.kind=="buy" and row.result.accepted: command=row.envelope.command.duplicate(true)
	var snapshot := native.snapshot()
	var ledger := world.ledger_state.snapshot()
	test.expect(LivelihoodAction.execute(world,PERSON,command).accepted,"Same action is replayed idempotently")
	test.equal(native.snapshot(),snapshot,"Duplicate action creates no order, receipt or batch")
	test.equal(world.ledger_state.snapshot(),ledger,"Duplicate action has no second payment")
	test.expect(not personal.purchase_quote(PERSON,site,"native:bread",1).success,"No remaining stock produces no purchasable quotation")
	test.expect(LivelihoodAction.query(world,PERSON).managed_firms.is_empty(),"Customer receives no enterprise permission")
	test.expect(not LivelihoodAction.execute_current(world,"buy",{"firm":"firm:opening_paris_workshop"}).accepted,"Consumer cannot bypass enterprise management")
	test.expect(personal.consume(PERSON,"native:bread",1).success,"Original native food adoption consumes actual bread")
	test.equal(personal.holding(PERSON,"native:bread").quantity,0,"Food portion was removed")
	test.equal(LivelihoodAction.query(world,PERSON).need_today.categories.food.satisfied,1,"Actual current food need is met")
	ledger=world.ledger_state.snapshot();snapshot=native.snapshot()
	test.expect(not personal.consume(PERSON,"native:bread",1).success,"Repeated use without food or unmet need is rejected")
	test.equal(native._lots.snapshot(),snapshot["stock_lots"],"Rejected repeat consumes no physical portions")
	test.equal(world.ledger_state.snapshot(),ledger,"Consumption does not invent money")
	var saved := built.persistence.snapshot()
	var restored := built.persistence.restore_candidate(saved)
	test.expect(restored.success,"Native consumed lot and food state restore: "+restored.error)
	if restored.success: test.equal(restored.persistence.snapshot(),saved,"Restored consumed state is exact")
	# Original transport purchase remains separate from onsite handover.
	settings.erase("retail_sites")
	var cargo_world := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, settings)
	test.expect(cargo_world.success,"Isolated original transport configuration builds")
	if not cargo_world.success:return
	world=cargo_world.world;personal=world.personal_economy_state
	quote=personal.purchase_quote(PERSON,site,"native:bread",1)
	test.expect(personal.purchase(PERSON,site,"native:bread",1,2,quote).success,"Original transport accepts known bread order")
	cargo_world.simulation_step.advance_minutes(1440)
	test.equal(personal.holding(PERSON,"native:bread").quantity,0,"In-transit bread is not usable inventory")
	test.expect(not personal.consume(PERSON,"native:bread",1).success,"In-transit bread cannot satisfy food need")


func _resident_restore(built: WorldBuildResult) -> WorldBuildResult:
	var saved := built.persistence.snapshot()
	var restored := built.persistence.restore_candidate(saved)
	test.expect(restored.success,"Resident state restores at minute %d: %s" % [built.world.game_clock.total_minutes(),restored.error])
	if not restored.success: return built
	test.equal(restored.persistence.snapshot(),saved,"Identity, accounts, duties, lots and needs restore exactly")
	restored.simulation_step.advance_minutes(0)
	test.equal(restored.persistence.snapshot(),saved,"Zero time does not repeat autonomous action or settlement")
	return restored


func _test_native_employment() -> void:
	var npc := "person:formal_generated_country_fra_0002"
	var job := "job:opening_paris_workshop"
	var site := "site:opening_paris_workshop:paris"
	var c := WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,FormalEconomicOpening.single_employer(FRA))
	test.expect(c.success and c.world.economy_r1 != null,"Ordinary C uses the same finite Opening")
	if not c.success or c.world.economy_r1 == null: return
	test.expect(LivelihoodAction.execute_current(c.world,"apply",{"job_id":job}).accepted,"Player occupies the original one-person job")
	test.expect(LivelihoodAction.execute_current(c.world,"work",{"hours":2}).accepted,"First actual work is registered")
	c=_resident_restore(c)
	c.simulation_step.advance_minutes(1440)
	var e:=c.world.economy_r1
	var first:=e._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply")
	test.expect(first.size()==1 and first[0].result.reason=="NO_VACANCY","Resident receives one real capacity refusal")
	test.equal(first[0].result.job_observation.vacancies,0,"Refusal records lawful local capacity information")
	c=_resident_restore(c)
	c.simulation_step.advance_minutes(1440)
	e=c.world.economy_r1
	test.equal(e._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply").size(),1,"Restored unchanged full job does not generate another application")
	test.expect(LivelihoodAction.execute_current(c.world,"work",{"hours":2}).accepted,"Second work booking matches original B")
	c.simulation_step.advance_minutes(60)
	var leave:=LivelihoodAction.execute_current(c.world,"leave_job",{})
	test.expect(leave.accepted and leave.boundary_minute==4320,"Original voluntary exit queues for the next boundary")
	var leaving: Dictionary={}
	for entry: Dictionary in e._commands.values():
		if entry.envelope.command.kind=="leave_job": leaving=entry.envelope.command.duplicate(true)
	var snapshot:=c.persistence.snapshot()
	test.equal(LivelihoodAction.execute(c.world,PERSON,leaving),leave,"Exit replay is idempotent")
	test.equal(c.persistence.snapshot(),snapshot,"Exit replay does not make another termination")
	test.expect(not LivelihoodAction.execute_current(c.world,"leave_job",{}).accepted,"Second distinct exit request is refused")
	test.expect(not c.world.personal_economy_state.person_economy(PERSON).employment.can_work_now,"Pending exit disables future work UI permission")
	test.expect(not LivelihoodAction.execute_current(c.world,"work",{"hours":2}).accepted,"Pending exit cannot book more work")
	c=_resident_restore(c)
	c.simulation_step.advance_minutes(1379)
	e=c.world.economy_r1
	test.expect(e._contracts.has(PERSON) and not e._contracts.has(npc),"Unadopted exit cannot release capacity early")
	test.equal(e._known_job(npc,job).vacancies,0,"Capacity stays occupied until the formal boundary")
	c.simulation_step.advance_minutes(1)
	e=c.world.economy_r1
	test.expect(not e._contracts.has(PERSON) and e._contracts.get(npc,{}).get("job")==job,"Boundary releases the original job and NPC passes original application")
	test.equal(e._contracts.size(),1,"Only one person occupies the same job after circulation")
	test.equal(e._employment_ends[leaving.action_id].status,"APPLIED","Voluntary termination has an adopted record")
	test.equal(e._employment_ends[leaving.action_id].effective_minute,4320,"Adoption time is exact")
	test.equal(e._wages["work:3:"+PERSON].remaining,6,"Completed pre-exit work retains unpaid wage claim")
	test.equal(e._totals[npc].income,0,"New contract does not grant immediate income")
	test.equal(e.personal_used(npc,"bread"),0,"Reemployment does not grant immediate food")
	var applications:=e._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply")
	test.expect(applications.size()==2 and applications[1].result.accepted and applications[1].envelope.command.minute==4320,"Actual vacancy wakes one new application at the same boundary")
	test.equal(applications[1].result.job_observation.vacancies,1,"New application records on-site known vacancy")
	var taken:=e.snapshot()
	test.equal(e.submit_internal(npc,applications[1].envelope.command),applications[1].result,"Accepted NPC application replay returns its original result")
	test.equal(e.snapshot(),taken,"Replay does not create another employment")
	test.equal(LivelihoodAction.execute_current(c.world,"apply",{"job_id":job}).reason,"NO_VACANCY","Former employee cannot force a second contract")
	c=_resident_restore(c)
	var personal:=c.world.personal_economy_state
	var quote:=personal.purchase_quote(PERSON,site,"native:bread",1)
	test.expect(personal.purchase(PERSON,site,"native:bread",1,2,quote).success,"Player and NPC use the same real retail stock")
	test.expect(personal.consume(PERSON,"native:bread",1).success,"Original player consumption survives legal exit")
	for date: int in range(4,8):
		c.simulation_step.advance_minutes(1440)
		e=c.world.economy_r1
		test.equal(e._contracts.size(),1,"Circulation preserves one-person capacity")
		test.equal(e._totals[npc].work_hours,2*(date-3),"Reemployed resident performs actual later work")
		if date==4:
			test.equal(e._wages["work:3:"+PERSON].remaining,0,"Old employer pays the former employee after exit")
			test.equal(e._totals[npc].income,0,"First NPC work still observes the wage delay")
		if date==5:
			test.expect(e._totals[npc].income==6 and e.personal_used(npc,"bread")==1,"Only actual paid income enables NPC acquisition and consumption")
			c=_resident_restore(c)
	c=_resident_restore(c)
	e=c.world.economy_r1
	test.equal(e._totals[npc].work_hours,8,"C completes four resident work periods")
	test.equal(e._totals[npc].income,18,"C pays three matured resident wage claims")
	test.equal(c.world.ledger_state.balance(e._account(npc)),10,"C resident cash equals 18 wage income minus 8 purchases")
	test.equal(e.personal_inventory(npc).bread,1,"C resident owns one acquired loaf")
	test.equal(e.personal_used(npc,"bread"),3,"C uses three actual loaves")
	test.equal(e._totals[npc].categories.food,{"required":7,"satisfied":3,"unmet":4,"used_items":{"beans":0,"bread":3,"grain":0}},"C retains unemployment food consequences")
	var physical:=e._physical_totals[site] as Dictionary
	test.equal(int(e._stocks[site].grain)+int(physical.used.grain),60,"Actual recipes consume only original finite grain")
	test.equal(physical.produced.bread,2*int(physical.used.grain),"Actual bread output follows original material recipe")
	test.equal(int(e._stocks[site].bread)+int(e.personal_inventory(npc).bread)+int(e.personal_used(npc,"bread"))+int(e.personal_used(PERSON,"bread")),12+int(physical.produced.bread),"Produced, bought, held and consumed bread balance without forcing production plans")
	test.equal(c.world.ledger_state.balance("account:opening_paris_workshop"),1180,"Employer pays both workers and receives actual purchase cash")
	test.equal(c.world.ledger_state.balance(e._account(PERSON)),2510,"Former employee retains earned wages and own consumer spending")
	print("EMPLOYMENT_C minute=",c.world.game_clock.total_minutes()," npc_hours=",e._totals[npc].work_hours," npc_income=",e._totals[npc].income," npc_cash=",c.world.ledger_state.balance(e._account(npc))," stock=",e._stocks[site]," physical=",physical," food=",e._totals[npc].categories.food)
	# Read the real prior-generation isolated slot; never overwrite or reinitialize it.
	var old_path:=OS.get_environment("APPDATA").path_join("WWO_R57_Visual_Residents_20261023_idle/formal_world_1900_manual_4.json")
	if FileAccess.file_exists(old_path):
		var loaded:=c.persistence._read_snapshot_file(old_path)
		test.expect(loaded.success,"Read generation17 resident slot without modifying it")
		if loaded.success:
			var old:=c.persistence.restore_candidate(loaded.snapshot)
			test.expect(old.success,"Generation17 retains identities, job capacity and resources: "+old.error)
			if old.success: test.equal(old.persistence.snapshot(),loaded.snapshot,"Old generation17 snapshot restores exactly")
	var early:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,FormalEconomicOpening.single_employer(FRA))
	test.expect(early.success and early.world.economy_r1 != null,"Same-boundary refusal and reopening use a separate ordinary fixture")
	if early.success and early.world.economy_r1 != null:
		test.expect(LivelihoodAction.execute_current(early.world,"apply",{"job_id":job}).accepted,"Early fixture lawfully occupies the single job")
		test.expect(LivelihoodAction.execute_current(early.world,"leave_job",{}).accepted,"Early fixture uses original notice boundary")
		early.simulation_step.advance_minutes(1440)
		var actions:=early.world.economy_r1._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply")
		test.expect(actions.size()==2 and not actions[0].result.accepted and actions[1].result.accepted,"Real boundary change can reconsider the same-day refusal")
		test.expect(actions[0].envelope.command.action_id!=actions[1].envelope.command.action_id,"Changed opportunity is a distinct decision, not replay of refusal")
		test.equal(early.world.economy_r1._contracts.size(),1,"Same-boundary reconsideration cannot double hire")
		early=_resident_restore(early)

func _test_native_residents() -> void:
	var npc := "person:formal_generated_country_fra_0002"
	var site := "site:opening_paris_workshop:paris"
	var settings := FormalEconomicOpening.single_employer(FRA)
	var a := WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
	var b := WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
	var ready: bool = a.success and b.success and a.world.economy_r1 != null and b.world.economy_r1 != null
	test.expect(ready,"Same ordinary Opening creates two isolated worlds: "+a.error+" "+b.error+(a.world.native_economy_error if a.world != null else ""))
	if not ready: return
	test.equal(a.world.person_overlay.person_ids(),[PERSON,npc],"Only two stable Formal people; aggregate population is separate")
	test.equal(a.world.personal_economy_state.person_economy(npc).cash,0,"Resident has recorded zero-cash Opening")
	test.equal(a.world.ledger_state.snapshot(),b.world.ledger_state.snapshot(),"A/B have identical finite money sources")
	test.equal(a.world.economy_r1.snapshot(),b.world.economy_r1.snapshot(),"A/B have identical configuration and economic Opening")
	a=_resident_restore(a)
	test.expect(LivelihoodAction.execute_current(b.world,"apply",{"job_id":"job:opening_paris_workshop"}).accepted,"Player may take the one real vacancy at Opening")
	test.expect(LivelihoodAction.execute_current(b.world,"work",{"hours":2}).accepted,"Player books actual work without controlling resident")
	for date: int in range(1,8):
		a.simulation_step.advance_minutes(1440)
		b.simulation_step.advance_minutes(1440)
		var e:=a.world.economy_r1
		test.equal(e._work_records.size(),maxi(0,date-1),"At most one completed resident work period per day")
		test.equal(e._totals[npc]["work_hours"],2*maxi(0,date-1),"Contract hours are adopted once per completed period")
		test.equal(e._totals[npc]["income"],6*maxi(0,date-2),"Only due periods pay actual wages")
		var total_cash: int = 0
		for account: String in a.world.ledger_state.account_ids(): total_cash+=a.world.ledger_state.balance(account)
		test.equal(total_cash,3700,"Money conservation on day %d" % date)
		var bread: int=0
		for owner: String in e._stocks: bread+=int(e._stocks[owner]["bread"])
		var eaten: int=0
		for person: String in e.personal_accounts():
			eaten+=int(e._physical_totals[person]["used"]["bread"])
			var need:=e._totals[person]["categories"]["food"] as Dictionary
			test.equal(int(need["required"]),date,"Needs accrue once per actual day for "+person)
			test.equal(int(need["satisfied"])+int(need["unmet"]),date,"Satisfied and unmet needs balance")
		test.equal(bread,12+int(e._physical_totals[site]["produced"]["bread"])-eaten,"Bread is produced, held or consumed once")
		test.equal(int(e._stocks[site]["grain"]),60-int(e._physical_totals[site]["used"]["grain"]),"Production uses actual grain lots")
		if date==1:
			test.expect(e._contracts.has(npc) and e._work_queue.has(npc),"Resident autonomously accepts and books work")
			var work_id: String = e._work_queue[npc]["action_id"]
			var booked := e.snapshot()
			test.expect(e.submit_internal(npc,e._commands[work_id]["envelope"]["command"]).accepted,"Replayed automatic work returns its existing result")
			test.equal(e.snapshot(),booked,"Replayed automatic work does not book or settle twice")
			test.equal(e._orders.size(),0,"Zero cash and no completed shop staffing create no purchase")
		if date==2:
			test.equal(e._work_records.size(),1,"One actual resident work period completed")
			test.equal(e._wages.values()[0]["remaining"],6,"Completed work forms unpaid wage responsibility")
			test.equal(e._orders.size(),0,"Resident cannot buy before wages become available")
		if date==3:
			test.expect(e._totals[npc]["income"]>0 and e.personal_used(npc,"bread")>0,"Paid income, native purchase, handover and consumption occur without player requests")
			test.expect(e._orders.values().all(func(order:Dictionary)->bool:return order.buyer==npc and order.delivered==order.quantity and order.route_legs.is_empty()),"Onsite orders have original buyer and real immediate receipts")
		if date in [1,2,3,7]: a=_resident_restore(a)
		if date==2: test.expect(LivelihoodAction.execute_current(b.world,"work",{"hours":2}).accepted,"Player's second work period is explicit")
		if date==3:
			var p:=b.world.personal_economy_state
			var q:=p.purchase_quote(PERSON,site,"native:bread",1)
			test.expect(p.purchase(PERSON,site,"native:bread",1,2,q).success and p.consume(PERSON,"native:bread",1).success,"Original player purchase and food adoption survive resident competition")
	var e:=a.world.economy_r1
	test.equal(a.world.player_state.player_id(),PERSON,"Autonomy does not transfer player control")
	test.equal(a.world.personal_economy_state.person_economy(PERSON).cash,2500,"Idle player receives no resident wages or charges")
	test.expect(e._totals[npc]["work_hours"]>0 and e._totals[npc]["income"]>0,"Autonomous resident has independent labor and income")
	test.equal(b.world.economy_r1._totals[npc]["work_hours"],0,"Resident cannot occupy player's full one-person job")
	test.expect(b.world.economy_r1._commands.values().any(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply" and x.result.reason=="NO_VACANCY"),"Resident still seeks work and receives real vacancy refusal")
	test.equal(b.world.personal_economy_state.person_economy(PERSON).cash,2510,"Player labor-consumption flow remains 2500+12-2")
	test.equal(LivelihoodAction.query(a.world,PERSON).known_jobs[0].vacancies,0,"Player sees occupied local vacancy without worker's private state")
	test.equal(LivelihoodAction.query(a.world,npc),{},"Player-facing query cannot expose automatic resident's private economy")
	var cash:=a.world.ledger_state.snapshot()
	test.equal(LivelihoodAction.execute_current(a.world,"apply",{"job_id":"job:opening_paris_workshop"}).reason,"NO_VACANCY","Player cannot take the resident's occupied job")
	var command:={"action_id":"test:npc_control","minute":a.world.game_clock.total_minutes(),"kind":"work","payload":{"hours":2}}
	test.expect(not LivelihoodAction.execute(a.world,npc,command).accepted,"External player command cannot control automatic resident")
	test.equal(a.world.ledger_state.snapshot(),cash,"Rejected control changes no cash")
	command={"action_id":"auto:"+npc+":test:foreign_cash","minute":a.world.game_clock.total_minutes(),"kind":"buy","payload":{"quote_id":"test","seller":"firm:opening_paris_workshop","seller_site":site,"good":"bread","quantity":1,"buyer_account":e._account(PERSON)}}
	test.expect(not e.submit_internal(npc,command).accepted,"Autonomous purchase cannot nominate another person's account")
	test.equal(a.world.ledger_state.snapshot(),cash,"Invalid account nomination performs no payment")
	print("RESIDENT_A minute=",a.world.game_clock.total_minutes()," hours=",e._totals[npc]["work_hours"]," income=",e._totals[npc]["income"]," cash=",a.world.ledger_state.balance(e._account(npc))," used_bread=",e.personal_used(npc,"bread")," needs=",e._totals[npc]["categories"]["food"])
	var previous_path := OS.get_environment("APPDATA").path_join("WWO_R57_Visual_Ordinary_Consumption_20261023/formal_world_1900_manual_4.json")
	if FileAccess.file_exists(previous_path):
		var loaded := a.persistence._read_snapshot_file(previous_path)
		test.expect(loaded.success,"Read existing generation16 test save without writing it")
		if loaded.success:
			var previous := a.persistence.restore_candidate(loaded.snapshot)
			test.expect(previous.success,"Existing generation16 ordinary save remains readable: "+previous.error)
			if previous.success:
				test.equal(previous.world.person_overlay.person_ids(),[PERSON],"Old save does not regenerate the new Opening resident")
				test.equal(previous.persistence.snapshot(),loaded.snapshot,"Old wages, purchase and consumption remain exact")
	# These are separate legal Opening variants, never live-world edits.
	settings=FormalEconomicOpening.single_employer(FRA)
	for info: Dictionary in settings["information"]:
		if info["actor"]==npc and info["kind"]=="supplier": info["delivery_day"]=5
	var delayed:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
	test.expect(delayed.success,"Delayed supplier knowledge is an explicit initial fact")
	if delayed.success:
		delayed.simulation_step.advance_minutes(5760)
		test.expect(delayed.world.economy_r1._totals[npc]["income"]>0 and delayed.world.economy_r1._orders.is_empty(),"Income cannot reveal an undelivered supplier notice")
		delayed.simulation_step.advance_minutes(1440)
		test.expect(delayed.world.economy_r1.personal_used(npc,"bread")>0,"Delivered notice wakes original known-supplier buying")
	settings=FormalEconomicOpening.single_employer(FRA)
	settings["firms"][0]["cash"]=0
	var unpaid:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
	test.expect(unpaid.success,"Insolvent-employer test uses finite zero-cash Opening")
	if unpaid.success:
		unpaid.simulation_step.advance_minutes(WEEK)
		e=unpaid.world.economy_r1
		test.equal(e._totals[npc]["income"],0,"No source cash means no invented wage payment")
		test.expect(e._wages.values().any(func(w:Dictionary)->bool:return w.remaining>0),"Actual unpaid claims are retained")
		test.expect(not e._contracts.has(npc) and not e._work_queue.has(npc),"Existing arrears response stops further work and preserves debt")
		unpaid=_resident_restore(unpaid)
	# Exercise the existing passenger domain only in an isolated test Opening.
	# The ordinary Opening gains no route or remote action permission.
	settings=FormalEconomicOpening.single_employer(FRA)
	settings["person_travel"]["passages"]=[{"id":"passenger:test_resident:paris_lyon","source_link_id":"rail_paris_lyon","from_place_id":"place:paris","to_place_id":"place:lyon","minutes":720,"fee":0,"payee_account_id":"account:opening_paris_workshop","known_to":[PERSON],"basis":"EXPLICIT_DEVELOPMENT_PERSON_PASSAGE"}]
	var away:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
	test.expect(away.success,"Isolated passenger test reuses existing host Paris-Lyon link: "+away.error)
	if away.success:
		test.expect(LivelihoodAction.execute_current(away.world,"travel",{"destination_place_id":"place:lyon"}).accepted,"Player departs through original travel action")
		away.simulation_step.advance_minutes(WEEK)
		test.equal(away.world.person_overlay.current_place(PERSON),"place:lyon","Player is actually away from resident's workplace")
		test.equal(away.world.economy_r1._totals[npc],a.world.economy_r1._totals[npc],"Resident work, wages and food persist while player is elsewhere")
		away=_resident_restore(away)


func _multi_conservation(built: WorldBuildResult, initial_cash: int) -> void:
	var e := built.world.economy_r1
	var cash: int = 0
	for actor: String in e._actors: cash += built.world.ledger_state.balance(e._account(actor))
	for firm: String in e._spec["firms"]: cash += built.world.ledger_state.balance(e._account(firm))
	test.equal(cash,initial_cash,"Two employers transfer finite Opening cash without creation")
	var bread: int = 0
	var produced: int = 0
	for site: String in e._spec.sites:
		bread += int(e._stocks[site].bread)
		produced += int(e._physical_totals[site].produced.bread)
		var grain: int = 60 if site=="site:opening_paris_workshop:paris" else 24
		test.equal(int(e._stocks[site].grain)+int(e._physical_totals[site].used.grain),grain,"Independent firms consume their own finite grain")
	for actor: String in e._actors: bread += int(e.personal_inventory(actor).bread)+int(e.personal_used(actor,"bread"))
	test.equal(bread,12+produced,"All bread is original stock or native production, held or used once")
	var hours: Dictionary = {}
	for work: Dictionary in e._work_records.values():
		var key: String = str(work.actor)+":"+str(work.day)
		hours[key] = int(hours.get(key,0))+int(work.hours)
	for count: int in hours.values(): test.expect(count<=2,"One person cannot count the same period twice across employers")
	for job: String in e._spec.jobs: test.expect(e._labor_market.occupied(job)<=1,"Each real job keeps its independent one-person capacity")
	for wage: Dictionary in e._wages.values():
		test.equal(int(wage.paid)+int(wage.remaining),int(wage.amount),"Wage payment preserves the original claim amount")
		test.equal(wage.employer,e._spec.jobs[e._work_records[wage.id].job].employer,"Only the actual employer bears each work claim")


func _test_native_multi_employer() -> void:
	var npc := "person:formal_generated_country_fra_0002"
	var low := "job:opening_paris_workshop"
	var high := "job:opening_paris_bakery"
	for mode: String in ["idle","occupied","opportunity","arrears"]:
		var settings := FormalEconomicOpening.for_source(FRA)
		if mode=="opportunity":
			for notice: Dictionary in settings.information:
				if notice.actor==npc and notice.kind=="job" and notice.candidate==high: notice.delivery_day=4
		if mode=="arrears":
			settings.firms[1].cash=16
			settings.opening_organizations[1].notice=str(settings.opening_organizations[1].notice).replace("初始现金600", "初始现金16（隔离欠薪对照）")
		var built:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
		var ready: bool = built.success and built.world.economy_r1 != null
		test.expect(ready,"Two-employer Opening binds original authority: "+mode+" "+(built.world.native_economy_error if built.world != null else built.error))
		if not ready: continue
		var e := built.world.economy_r1
		test.equal(e._spec.firms.size(),2,"Opening has two independent employers")
		test.equal(e._spec.jobs.size(),2,"Opening has two real executable jobs")
		test.equal(e._stocks["site:opening_paris_bakery:paris"].bread,0,"New employer starts with no second batch of bread")
		test.equal(e._labor_market.ordered_jobs(npc,e._actors[npc].known_jobs)[0],low if mode=="opportunity" else high,"Choice uses only delivered local notices, ordered by same-currency hourly wage")
		test.equal(e._actors[npc].known_jobs.size(),1 if mode=="opportunity" else 2,"Undelivered vacancy is not available knowledge")
		var selected: String = low if mode=="opportunity" else high
		if mode in ["occupied","opportunity"]:
			test.expect(LivelihoodAction.execute_current(built.world,"apply",{"job_id":selected}).accepted,"Player chooses the actual selected employer")
			test.equal(LivelihoodAction.execute_current(built.world,"apply",{"job_id":high if selected==low else low}).reason,"ALREADY_EMPLOYED","Fixed one-person contracts reject a second job")
			test.expect(LivelihoodAction.execute_current(built.world,"work",{"hours":2}).accepted,"Player books actual work at their chosen firm")
		built=_resident_restore(built)
		if mode=="opportunity":
			built.simulation_step.advance_minutes(60)
			var leave:=LivelihoodAction.execute_current(built.world,"leave_job",{})
			test.expect(leave.accepted,"Player voluntarily leaves via native contract action")
			test.equal(built.world.economy_r1._known_job(npc,low).vacancies,0,"Pending exit does not release capacity")
			test.expect(not LivelihoodAction.execute_current(built.world,"work",{"hours":2}).accepted,"Pending exit blocks future work")
			built=_resident_restore(built)
		var days: int = 14 if mode=="arrears" else 7
		for date: int in range(1,days+1):
			built.simulation_step.advance_minutes(date*1440-built.world.game_clock.total_minutes())
			e=built.world.economy_r1
			if date==1:
				test.equal(e._contracts.get(npc,{}).get("job"),low if mode in ["occupied","opportunity"] else high,"NPC makes a legal application to an available known job")
				if mode=="opportunity":
					test.expect(not e._contracts.has(PERSON),"Old player contract actually ended")
					test.equal(e._wages["work:1:"+PERSON].remaining,6,"Old employer still owes completed work")
					test.expect(LivelihoodAction.execute_current(built.world,"apply",{"job_id":high}).accepted,"Player legally switches to the independent second employer")
					test.expect(LivelihoodAction.execute_current(built.world,"work",{"hours":2}).accepted,"New job books its own real work")
			if date==2 and mode in ["occupied","opportunity"]: test.expect(LivelihoodAction.execute_current(built.world,"work",{"hours":2}).accepted,"Player second work period uses actual employer")
			if date==2 and mode=="opportunity": test.equal(e._wages["work:1:"+PERSON].paid,6,"Only old employer pays the old wage after exit")
			if date==3 and mode=="opportunity": test.equal(e._totals[PERSON].income,6,"Delayed new salary is not paid early")
			if date==4 and mode=="opportunity":
				var job_notice:=e._receipts.values().filter(func(x:Dictionary)->bool:return x.get("actor")==npc and x.get("kind")=="job" and x.get("candidate")==high)
				test.expect(job_notice.size()==1 and job_notice[0].delivery_day==4,"Later opportunity arrives through the original message boundary")
				test.equal(e._contracts[npc].job,low,"Fixed contract policy retains present job despite higher known wage")
				test.equal(e._totals[PERSON].income,14,"Distinct employers pay 6 plus 8 on their actual delays")
				var p:=built.world.personal_economy_state
				var site:="site:opening_paris_workshop:paris"
				test.expect(p.purchase(PERSON,site,"native:bread",1,2,p.purchase_quote(PERSON,site,"native:bread",1)).success and p.consume(PERSON,"native:bread",1).success,"Player switching employers retains original personal purchase and consumption")
				built.simulation_step.advance_minutes(60)
				test.expect(LivelihoodAction.execute_current(built.world,"leave_job",{}).accepted,"Player can end the second contract by the same formal rule")
				built=_resident_restore(built)
			if date==5 and mode=="opportunity":
				test.equal(e._known_job(npc,high).vacancies,1,"Second job really reopens after the player leaves")
				test.equal(e._contracts[npc].job,low,"NPC keeps the existing fixed contract after observing a real higher-pay vacancy")

			if date in [1,2,4,7] or (mode=="arrears" and date in [9,11,14]): built=_resident_restore(built)
			e=built.world.economy_r1
			_multi_conservation(built,3716 if mode=="arrears" else 4300)
			print("MULTI_DAY ",mode," day=",date," contract=",e._contracts.get(npc,{})," npc=",e._totals[npc]," cash=",built.world.ledger_state.balance(e._account(npc)))
		e=built.world.economy_r1
		test.expect(e._totals[npc].work_hours>0 and e._totals[npc].income>0 and e.personal_used(npc,"bread")>0,"Autonomous employment produces real income, purchase and food use")
		test.equal(LivelihoodAction.query(built.world,npc),{},"Public consumer view cannot read NPC private cash or inventory")
		if mode=="arrears":
			test.equal(e._contracts[npc].job,low,"Native arrears response legally moves to another payable known employer")
			var unpaid:=e._wages.values().filter(func(w:Dictionary)->bool:return w.worker==npc and w.remaining>0 and e._work_records[w.id].job==high)
			test.expect(not unpaid.is_empty(),"Old employer debt survives legal switch; new employer does not assume it")
			print("MULTI_ARREARS ",unpaid)
		var apps:=e._commands.values().filter(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply")
		test.expect(apps.size()<=4,"Unchanged known refusal does not cause daily repeated applications")
		var accepted:=apps.filter(func(x:Dictionary)->bool:return x.result.accepted)
		if not accepted.is_empty():
			var prior:=e.snapshot()
			test.equal(e.submit_internal(npc,accepted[0].envelope.command),accepted[0].result,"Replaying accepted application returns original result")
			test.equal(e.snapshot(),prior,"Replay does not hire or pay twice")
		print("MULTI_FINAL ",mode," minute=",built.world.game_clock.total_minutes()," contracts=",e._contracts," wages=",e._wages," stocks=",e._stocks," physical=",e._physical_totals)

	# Qualification is public job information, not hidden firm finance.
	var qualified_settings := FormalEconomicOpening.for_source(FRA)
	qualified_settings.jobs[1].skill=2
	var qualified:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,qualified_settings)
	test.expect(qualified.success and qualified.world.economy_r1 != null,"Qualification comparison uses a legal initial job requirement")
	if qualified.success and qualified.world.economy_r1 != null:
		qualified.simulation_step.advance_minutes(1440)
		var e := qualified.world.economy_r1
		test.equal(e._contracts[npc].job,low,"Known higher-pay work is skipped when skill is insufficient")
		test.expect(not e._commands.values().any(func(x:Dictionary)->bool:return x.envelope.actor==npc and x.envelope.command.kind=="apply" and x.envelope.command.payload.job_id==high),"Known qualification failure creates no repeated impossible application")
		test.equal(LivelihoodAction.execute_current(qualified.world,"apply",{"job_id":high}).reason,"UNQUALIFIED","Original domain still rejects an explicit ineligible player application")
		qualified=_resident_restore(qualified)

	var old_path:=OS.get_environment("APPDATA").path_join("WWO_R57_Visual_Employment_20261023_released/formal_world_1900_manual_4.json")
	if FileAccess.file_exists(old_path):
		var old_reader:=qualified.persistence._read_snapshot_file(old_path)
		test.expect(old_reader.success,"Read previous generation18 isolated save without writing")
		if old_reader.success:
			var old:=qualified.persistence.restore_candidate(old_reader.snapshot)
			test.expect(old.success,"Generation18 restores without new Opening genesis: "+old.error)
			if old.success:
				test.equal(old.persistence.snapshot(),old_reader.snapshot,"Old single-employer cash, claims, identities and goods remain exact")
				test.equal(old.world.economy_r1._spec.firms.size(),1,"Restoring generation18 does not add a second employer")
