extends SceneTree

const PERSON: String = WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
const FRA: String = "country_fra"
const WEEK: int = 7 * 24 * 60
var test := FormalTestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--material-renewal-trade" in OS.get_cmdline_user_args():
		_test_material_renewal()
		test.finish(self, "Formal Paris finite material renewal")
		return
	if "--second-worker-material-trade" in OS.get_cmdline_user_args():
		_test_second_worker_material_trade()
		test.finish(self, "Formal second Paris worker supply")
		return
	if "--unattended-material-trade" in OS.get_cmdline_user_args():
		_test_unattended_material_trade()
		test.finish(self, "Formal unattended Paris supply")
		return
	if "--native-material-trade" in OS.get_cmdline_user_args():
		_test_material_renewal()
		_test_second_worker_material_trade()
		_test_unattended_material_trade()
		_test_native_material_trade()
		_test_native_consumption()
		test.finish(self,"Formal Paris finite material trade")
		return
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

func _material_facts(b: WorldBuildResult) -> Dictionary:
	return {"ledger":b.world.ledger_state.snapshot(),"lots":b.world.economy_r1._lots.snapshot(),"orders":b.world.economy_r1._orders.duplicate(true),"organizations":b.world.organization_state.snapshot(),"wages":b.world.economy_r1._wages.duplicate(true),"deliveries":b.world.economy_r1._delivery_receipts.duplicate(true)}

func _material_disk_restore(b: WorldBuildResult) -> WorldBuildResult:
	var before:=b.persistence.snapshot()
	var saved:=b.persistence.save_to_user(4)
	test.expect(saved.success,"Material trade real disk save")
	if not saved.success: return b
	var loaded:=FormalPersistence.new().load_from_user(4)
	test.expect(loaded.success,"Material trade real disk load: "+loaded.error)
	if loaded.success:
		test.expect(loaded.persistence.snapshot()==before,"Disk restore retains exact authority and lots")
		loaded.simulation_step.advance_minutes(0)
		test.expect(loaded.persistence.snapshot()==before,"Zero-time resume repeats no procurement, payment or production")
		return loaded
	return b

# Single-NPC control and quota extension reused from unmerged PR #118, commit 9ca5dab3.
func _test_unattended_material_trade() -> void:
	var npc := "person:formal_generated_country_fra_0002"
	var seller := "firm:opening_paris_workshop"
	var buyer := "firm:opening_paris_bakery"
	var site := "site:opening_paris_workshop:paris"
	var destination := "site:opening_paris_bakery:paris"
	var b := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, FormalEconomicOpening.for_source(FRA))
	test.expect(b.success and b.world.economy_r1 != null, "Unattended ordinary Paris Opening builds")
	if not b.success or b.world.economy_r1 == null: return
	var first_need := -1
	for date: int in range(1, 46):
		b.simulation_step.advance_minutes(1440)
		var e := b.world.economy_r1
		var need := e._input_need(destination, "grain")
		var offers := e._input_offers(destination, "grain", int(need.need_by_day), int(need.quantity))
		var player_requests := e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == PERSON)
		test.equal(player_requests.size(), 0, "Unattended player command count remains zero")
		test.equal(e._contracts.size(), 1, "One autonomous person has one fixed contract")
		test.equal(e._contracts[npc].job, "job:opening_paris_bakery", "NPC retains actual bakery job without forced reassignment")
		test.equal(e._labor_market.occupied("job:opening_paris_workshop"), 0, "Workshop vacancy is not fictional staffing")
		test.equal(e._retail.allocated_hours(site), 0, "Unstaffed workshop receives no sales labor")
		test.equal(e._physical_totals[site].produced.bread, 0, "Unstaffed workshop cannot produce")
		test.equal(e._totals[npc].work_hours, 2 * maxi(0, date - 1), "NPC completed labor is adopted once per actual period")
		test.equal(e._material_remaining(seller, "SELL"), 8, "Unexecuted sales preserve cumulative mandate")
		test.equal(e._material_remaining(buyer, "PROCURE"), 8, "Unexecuted procurement preserves separate mandate")
		test.equal(e._material_sale_available(site, "grain"), 8, "Finite surplus is available but does not substitute for labor")
		test.equal(e._committed(site, "grain"), 0, "No accepted grain sale means no fictional reservation")
		test.expect(e._service_market._offers.is_empty() and e._service_market.contracts.is_empty(), "Ordinary Opening has no independent service labor provider")
		var purchases := e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == buyer and x.envelope.command.kind == "buy")
		test.equal(purchases.size(), maxi(0, date - 41), "Original procurement submits one real request per shortage day")
		for entry: Dictionary in purchases:
			test.equal(entry.source, "firm", "Procurement is issued by the original enterprise executor")
			test.equal(entry.result, {"accepted": false, "reason": "STORE_NO_ACTUAL_STAFFING"}, "Actual enterprise request preserves the staffing refusal")
		if not purchases.is_empty():
			var before := b.persistence.snapshot()
			var entry: Dictionary = purchases.back()
			test.equal(e.submit_internal(buyer, entry.envelope.command), entry.result, "Failed procurement replay returns the same refusal")
			test.equal(b.persistence.snapshot(), before, "Failed replay changes no money, lots, wages, orders or responsibilities")
		test.expect(e._orders.values().all(func(x: Dictionary) -> bool: return x.good != "grain"), "No grain order or delivery is fabricated")
		if int(need.quantity) > 0:
			if first_need < 0: first_need = date
			test.equal(offers.size(), 1, "Delivered supplier knowledge supplies the real grain offer")
			if not offers.is_empty():
				test.equal(offers[0].reason, "STORE_NO_ACTUAL_STAFFING", "Real procurement candidate fails actual seller staffing")
				test.equal(offers[0].quantity, 0, "Unstaffed offer is not executable")
				test.equal(offers[0].transport_quantity, 0, "No handover capacity without actual labor")
			if date > first_need:
				test.equal(e._physical_totals[destination].produced.bread, 48, "Exhausted initial grain cannot produce further bread")
		if date in [1, 2, 30, 41, 42, 43, 45] or date == first_need:
			_multi_conservation(b, 4300)
			print("UNATTENDED_PARIS ", JSON.stringify({"day": date, "first_need": first_need, "contract": e._contracts[npc], "jobs": [e._known_job(npc, "job:opening_paris_workshop"), e._known_job(npc, "job:opening_paris_bakery")], "completed_hours": e._totals[npc].work_hours, "retail_hours": [e._retail.allocated_hours(site), e._retail.allocated_hours(destination)], "production_labor": e._labor, "need": need, "offers": offers, "stocks": e._stocks, "cash": [b.world.ledger_state.balance(e._account(seller)), b.world.ledger_state.balance(e._account(buyer)), b.world.ledger_state.balance(e._account(npc))], "player_requests": player_requests.size(), "buyer_commands": purchases, "wage_claims": e._wages.size()}))
		if date in [42, 45]: b = _material_disk_restore(b)
	test.equal(first_need, 42, "Ordinary autonomous bakery first needs grain on day42")
	test.equal(b.world.game_clock.total_minutes(), 45 * 1440, "Unattended observation continues through day45")


func _test_material_renewal() -> void:
	var settings := FormalEconomicOpening.material_renewal(FRA)
	var ordinary := FormalEconomicOpening.second_worker(FRA)
	var seller := "firm:opening_paris_workshop"
	var buyer := "firm:opening_paris_bakery"
	var site := "site:opening_paris_workshop:paris"
	var destination := "site:opening_paris_bakery:paris"
	if "--formal-material-renewal-opening" in OS.get_cmdline_user_args():
		test.equal(FormalEconomicOpening.for_source(FRA), settings, "Formal selector explicitly selects finite renewal candidate")
	test.expect(EconomySliceConfig.valid(settings), "Finite renewal requires the complete candidate and both organization resolutions")
	for field: String in ["firms", "jobs", "actors", "opening_residents", "labor_response_policies", "information", "retail_sites", "firm_operations"]:
		test.equal(settings[field], ordinary[field], "Renewal changes no resources or operating parameter: " + field)
	for i: int in range(2): test.equal(settings.opening_organizations[i].material_trade, ordinary.opening_organizations[i].material_trade, "Original eight-grain genesis grant is unchanged")
	for variant: String in ["old_case", "issuer", "limit", "expiry", "floor", "duplicate", "missing"]:
		var bad := settings.duplicate(true)
		match variant:
			"old_case": bad.case_id = ordinary.case_id
			"issuer": bad.material_renewals[0].issuer = bad.opening_organizations[1].organization_id
			"limit": bad.material_renewals[0].quantity_limit = 5
			"expiry": bad.material_renewals[0].valid_until = 100 * 1440
			"floor": bad.material_renewals[0].stock_floor = 0
			"duplicate": bad.material_renewals[1] = bad.material_renewals[0].duplicate(true)
			"missing": bad.material_renewals.pop_back()
		test.expect(not EconomySliceConfig.valid_material_renewals(bad), "Finite organization resolution rejects " + variant)
	var b := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, settings)
	test.expect(b.success and b.world.economy_r1 != null, "Renewal candidate builds through formal bootstrap: " + b.error + (b.world.native_economy_error if b.world != null else ""))
	if not b.success or b.world.economy_r1 == null: return
	var last_purchase: Dictionary = {}
	for date: int in range(1, 37):
		b.simulation_step.advance_minutes(1440)
		var e := b.world.economy_r1
		test.equal(e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == PERSON).size(), 0, "Autonomous renewal run has zero player requests")
		var grain_orders := e._orders.values().filter(func(o: Dictionary) -> bool: return o.good == "grain")
		var delivered := 0
		var receipts: Array[String] = []
		for order: Dictionary in grain_orders:
			delivered += int(order.delivered)
			test.equal(e._commands[order.action_id].source, "firm", "Only original enterprise procurement creates renewal purchases")
			test.equal(order.pending + order.transit, 0, "Renewed onsite order has actual completed handover")
			test.expect(e._material_order_valid(order, e._orders, e._commands), "Each order retains both original admission authorizations")
			for receipt: Dictionary in e._delivery_receipts.values():
				if receipt.order_id == order.id: receipts.append(receipt.id)
		var adopted := 0
		for portion: Dictionary in e._lots.portions.values():
			if portion.owner == buyer and portion.good == "grain" and portion.acquisition_id in receipts: adopted += int(portion.consumed)
		for row: Dictionary in settings.material_renewals:
			var issue_id := e._material_resolution_id(row)
			test.equal(e._commands.has(issue_id), date >= 32, "One predeclared resolution executes only after first quota exhaustion and effective date")
			var original := e._material_genesis_id(row.firm, row.operation)
			test.equal(e._material_used(row.firm, row.operation, original), mini(8, delivered), "Old orders remain allocated to the original eight-grain grant")
			test.equal(e._material_used(row.firm, row.operation, row.id), maxi(0, delivered - 8), "New orders alone debit the independent four-grain grant")
			if date >= 32:
				test.equal(e._commands[issue_id].source, "firm", "Organization decision executes through original enterprise command source")
				test.equal(e._commands[issue_id].envelope.command.minute, 32 * 1440, "Resolution retains its actual issue time")
		if date == 30 or date == 31: test.equal(delivered, 8, "First exhausted batch is not enlarged by procurement authority")
		if date == 32: test.expect(delivered > 8, "Effective independent SELL and PROCURE grants permit real continued procurement")
		if 32 <= date and date <= 34:
			test.expect(int(e._stocks[site].grain) >= maxi(4, int(e._input_need(site, "grain").target)), "Renewed sales preserve actual stock floor and production protection")
		if date >= 34: test.equal(delivered, 12, "Both independent second batches stop after exactly four grain")
		var purchases := e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == buyer and x.envelope.command.kind == "buy" and x.envelope.command.minute == date * 1440)
		if not purchases.is_empty(): last_purchase = purchases.back()
		if date == 31 or date >= 35:
			test.expect(not purchases.is_empty(), "Original executor still submits the actual input shortage")
			for entry: Dictionary in purchases: test.equal(entry.result.reason, "INSUFFICIENT_MATERIAL_SALE_SURPLUS_OR_MANDATE", "Exhaustion or expiry preserves original procurement refusal")
		if date in [30, 31, 32, 34, 35, 36]:
			_multi_conservation(b, 4300)
			print("FINITE_RENEWAL_PARIS ", JSON.stringify({"day": date, "delivered": delivered, "adopted": adopted, "remaining": [e._material_remaining(seller, "SELL"), e._material_remaining(buyer, "PROCURE")], "purchases": purchases, "stocks": e._stocks, "wages": e._open_wages.size(), "cash": [b.world.ledger_state.balance(e._account(seller)), b.world.ledger_state.balance(e._account(buyer))]}))
		if date in [30, 32, 35, 36]:
			b = _material_disk_restore(b)
			e = b.world.economy_r1
			if not last_purchase.is_empty():
				var before := b.persistence.snapshot()
				test.equal(e.submit_internal(buyer, last_purchase.envelope.command), last_purchase.result, "Restored original procurement command replays its receipt or refusal")
				test.equal(b.persistence.snapshot(), before, "Restored procurement replay duplicates no goods, cash or liability")
		if date >= 32 and date in [32, 36]:
			for row: Dictionary in settings.material_renewals:
				var issued: Dictionary = e._commands[e._material_resolution_id(row)]
				var before := b.persistence.snapshot()
				test.equal(e.submit_internal(row.firm, issued.envelope.command), issued.result, "Identical issue replays even after expiry")
				test.equal(b.persistence.snapshot(), before, "Repeated issue creates no second allowance")
				var retry: Dictionary = issued.envelope.command.duplicate(true)
				retry.action_id += ":second_attempt:" + str(date)
				retry.minute = date * 1440
				test.equal(e.submit_internal(row.firm, retry).reason, "MATERIAL_RESOLUTION_ALREADY_EXECUTED", "New command identity cannot issue a second grant")
		if date == 32:
			# Separate manual authority/revocation checks on detached worlds. These
			# commands are not evidence for the autonomous continued transaction.
			var saved := b.persistence.snapshot()
			for row: Dictionary in settings.material_renewals:
				var fork := b.persistence.restore_candidate(saved)
				test.expect(fork.success, "Detached renewal state restores for manual revocation control")
				if not fork.success: continue
				var f := fork.world.economy_r1
				var facts := _material_facts(fork)
				var command := {"action_id": f._material_resolution_id(row, true), "minute": 32 * 1440, "kind": "revoke_material_mandate", "payload": {"mandate_id": row.id}}
				test.expect(f.submit_internal(row.firm, command).accepted, "Original organization executor can revoke its own fixed mandate")
				test.equal(f._material_remaining(row.firm, row.operation), 0, "Revocation removes the still-unused second-batch capacity")
				test.equal(_material_facts(fork), facts, "Revocation preserves accepted cash, lots, orders and wages")
				fork = _material_disk_restore(fork)
				fork.simulation_step.advance_minutes(1440)
				f = fork.world.economy_r1
				test.equal(f._orders.values().filter(func(o: Dictionary) -> bool: return o.good == "grain").reduce(func(total: int, o: Dictionary) -> int: return total + int(o.delivered), 0), 10, "Either side's revocation independently blocks further purchases")
				var npc := "person:formal_generated_country_fra_0003"
				command = {"action_id": "auto:" + npc + ":invalid_renewal", "minute": 33 * 1440, "kind": "issue_material_mandate", "payload": {"mandate_id": row.id}}
				test.equal(f.submit_internal(npc, command).reason, "NO_MATERIAL_ISSUING_AUTHORITY", "Ordinary employee has no organization issuing authority")
				var other: Dictionary = settings.material_renewals[1] if row.operation == "SELL" else settings.material_renewals[0]
				test.equal(f._material_remaining(other.firm, other.operation), 2, "Unrevoked counterparty retains its own unused two-grain balance")
				fork.simulation_step.advance_minutes(3 * 1440)
				f = fork.world.economy_r1
				test.equal(f._material_remaining(other.firm, other.operation), 0, "Deadline expires unused capacity without spending it")
				test.equal(f._material_used(other.firm, other.operation, other.id), 2, "Expiry preserves the actual partial use of the grant")
				fork = _material_disk_restore(fork)
			var invalid := saved.duplicate(true)
			var native: Dictionary = invalid.economy_native
			native.commands.erase(e._material_resolution_id(settings.material_renewals[0]))
			test.expect(not b.persistence.restore_candidate(invalid).success, "Saved renewed orders cannot lose their issuing command")
			invalid = saved.duplicate(true)
			invalid.economy_native.commands[e._material_resolution_id(settings.material_renewals[0])].envelope.command.kind = "buy"
			test.expect(not b.persistence.restore_candidate(invalid).success, "Another accepted command cannot impersonate the issuance record")
			invalid = saved.duplicate(true)
			for order: Dictionary in invalid.economy_native.orders.values():
				if order.good == "grain" and order.accepted_minute < 32 * 1440:
					order.material_authorizations.SELL = settings.material_renewals[0].id
					break
			test.expect(not b.persistence.restore_candidate(invalid).success, "Old order cannot be reassigned to a later issuing authority")
			var excess := e._orders.duplicate(true)
			for order: Dictionary in excess.values():
				if order.good == "grain" and order.accepted_minute == 32 * 1440:
					order.quantity += 4
					test.expect(not e._material_order_valid(order, excess, e._commands), "Restore quota check counts saved orders against each separate grant")
					break
	var e := b.world.economy_r1
	var paid := 0
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.kind == "goods" and e._orders[tx.reference_id].good == "grain": paid += int(tx.amount)
	test.equal(paid, 12, "Twelve actually delivered grain have twelve original cash payments")
	for wage: Dictionary in e._wages.values():
		if wage.due_day <= e.day: test.equal(wage.remaining, 0, "Finite renewal interval has no unpaid matured wages")
	test.equal(b.world.game_clock.total_minutes(), 36 * 1440, "Finite observation stops after second exhaustion and expiry")


func _test_second_worker_material_trade() -> void:
	var npc := "person:formal_generated_country_fra_0002"
	var added := "person:formal_generated_country_fra_0003"
	var seller := "firm:opening_paris_workshop"
	var buyer := "firm:opening_paris_bakery"
	var site := "site:opening_paris_workshop:paris"
	var destination := "site:opening_paris_bakery:paris"
	var ordinary := FormalEconomicOpening._load(FormalEconomicOpening.PATH)
	var settings := FormalEconomicOpening.second_worker(FRA)
	test.equal(FormalEconomicOpening.for_source(FRA), settings if "--formal-second-worker-opening" in OS.get_cmdline_user_args() else ordinary, "Candidate selection is explicit; default stays single-NPC")
	test.expect(EconomySliceConfig.valid(settings), "Explicit second-worker candidate passes original configuration validation")
	test.equal(FormalEconomicOpening.second_worker("country_gbr"), {}, "Candidate remains scoped to France")
	for field: String in ["firms", "jobs", "opening_organizations", "firm_operations", "retail_sites", "route"]:
		test.equal(settings[field], ordinary[field], "Second worker preserves enterprise opening: " + field)
	for variant: String in ["missing", "duplicate", "claim", "identity", "account", "cash", "stock", "need", "control", "place", "basis", "case", "cohort"]:
		var bad := settings.duplicate(true)
		match variant:
			"missing": bad.opening_residents.pop_back()
			"duplicate": bad.opening_residents[1] = bad.opening_residents[0].duplicate(true)
			"claim": bad.opening_residents[1].claim_id = bad.opening_residents[0].claim_id
			"identity": bad.opening_residents[1].person_id = PERSON
			"account": bad.actors[2].account_id = bad.actors[1].account_id
			"cash": bad.actors[2].cash = 1
			"stock": bad.actors[2].stock.bread = 1
			"need": bad.actors[2].daily_need = 0
			"control": bad.actors[0].control = "automatic"
			"place": bad.opening_residents[1].place_id = "place:lyon"
			"basis": bad.opening_residents[1].basis = "DEVELOPMENT_CONFIGURATION"
			"case": bad.case_id = ordinary.case_id
			"cohort": bad.actors.append({"id": "cohort:duplicate_resident", "kind": "cohort"})
		test.expect(not EconomySliceConfig.valid_opening_residents(bad), "Resident boundary rejects " + variant)
	var bad_response := settings.duplicate(true)
	bad_response.labor_response_policies[1].actor = PERSON
	test.expect(not EconomyLiquidityRules.valid(bad_response), "Generated arrears response cannot target the player")
	var wrong_origin := {"person_id": added, "basic_demographic_identity": {"opening_cash_policy": "ZERO_CASH_GENERATED_RESIDENT", "opening_configuration_id": ordinary.case_id}}
	test.expect(not FormalPersonalEconomyState._zero_cash_opening(wrong_origin), "Second resident zero cash requires its specific opening origin")
	var baseline := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, ordinary)
	var b := WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, settings)
	test.expect(baseline.success and b.success and b.world.economy_r1 != null, "Both formal opening variants build: " + b.error + (b.world.native_economy_error if b.world != null else ""))
	if not baseline.success or not b.success or b.world.economy_r1 == null: return
	var initial_population := baseline.world.population_state.unit(FRA)
	var population := b.world.population_state.unit(FRA)
	test.equal(population.population_total, initial_population.population_total, "Materialization preserves statistical population")
	test.equal(population.named_person_count, initial_population.named_person_count + 1, "Exactly one new named resident")
	test.equal(population.remaining_background_population, initial_population.remaining_background_population - 1, "Exactly one anonymous share is claimed")
	test.equal(b.world.person_overlay.person_ids(), [PERSON, npc, added], "Stable distinct person identities")
	test.equal(b.world.person_overlay.person(added).claim_id, "formal_population_claim:country_fra:0003", "New resident has its own claim")
	test.equal(b.world.personal_economy_state.managed_population(FRA), 3, "All three named people own personal needs")
	test.equal(b.world.economy_state.consumption_population(FRA), int(population.population_total) - 3, "Personal needs are excluded from macro demand")
	test.equal(b.world.economy_r1.managed_background_population(FRA), 0, "No cohort duplicates the new resident")
	for person: String in [npc, added]:
		test.equal(b.world.personal_economy_state.person_economy(person).cash, 0, "Resident starts with zero cash")
		test.equal(b.world.economy_r1.personal_inventory(person), EconomySliceConfig.ZERO, "Resident starts with zero goods")
		test.equal(b.world.ledger_state.account(b.world.economy_r1._account(person)).owner_id, person, "Resident owns a distinct personal account")
	test.expect(b.world.economy_r1._contracts.is_empty(), "Opening contains no prefilled employment")
	_multi_conservation(b, 4300)
	# Old single-NPC worlds restore their saved configuration even with candidate code installed.
	baseline.simulation_step.advance_minutes(2 * 1440)
	var saved_config := baseline.world.economy_r1.config.duplicate(true)
	baseline = _material_disk_restore(baseline)
	test.equal(baseline.world.person_overlay.person_ids(), [PERSON, npc], "Old single-NPC disk save gains no resident")
	test.equal(baseline.world.economy_r1.config, saved_config, "Old save retains its original opening and mandates")
	var first_purchase := -1
	var first_adoption := -1
	var first_refusal := -1
	var previous_delivered := 0
	for date: int in range(1, 61):
		b.simulation_step.advance_minutes(1440)
		var e := b.world.economy_r1
		test.equal(e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == PERSON).size(), 0, "Candidate player requests remain zero")
		test.equal(b.world.player_state.player_id(), PERSON, "Player remains independently controlled")
		test.equal(e._contracts.size(), 2, "Two independent employment contracts")
		for person: String in [npc, added]:
			var job: String = "job:opening_paris_bakery" if person == npc else "job:opening_paris_workshop"
			test.equal(e._contracts.get(person, {}).get("job"), job, "Resident retains its actual employer")
			test.equal(e._totals[person].work_hours, 2 * (date - 1), "Each resident completes its own two-hour period")
			var need: Dictionary = e._totals[person].categories.food
			test.equal(need.required, date, "Resident daily food requirement accrues once")
			test.equal(need.satisfied + need.unmet, date, "Resident cannot escape unmet consumption responsibility")
			if date == 1:
				var applications := e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == person and x.envelope.command.kind == "apply" and x.result.accepted)
				test.equal(applications.size(), 1, "Original automatic apply command creates one actual job")
				if not applications.is_empty():
					test.equal(applications[0].envelope.command.payload.job_id, job, "Application uses the known local vacancy")
					test.expect(e._actors[person].known_jobs.has(job), "Job notice was actually received")
				var work: Dictionary = e._commands[e._work_queue[person].action_id]
				var before := b.persistence.snapshot()
				test.equal(e.submit_internal(person, work.envelope.command), work.result, "Automatic work replay keeps its result")
				test.equal(b.persistence.snapshot(), before, "Repeated work creates no extra labor or wages")
		var purchases := e._commands.values().filter(func(x: Dictionary) -> bool: return x.envelope.actor == buyer and x.envelope.command.kind == "buy" and x.envelope.command.minute == date * 1440)
		for entry: Dictionary in purchases:
			if first_purchase < 0: first_purchase = date
			test.equal(entry.source, "firm", "Only original firm executor submits material procurement")
			if not entry.result.accepted and first_refusal < 0: first_refusal = date
			if entry.result.accepted:
				test.equal(entry.result.reason, "ONSITE_DELIVERED", "Real staffed procurement completes the original handover")
			else:
				test.equal(entry.result.reason, "INSUFFICIENT_MATERIAL_SALE_SURPLUS_OR_MANDATE", "Exhausted mandate preserves original refusal")
		var delivered := 0
		var acquired_receipts: Array[String] = []
		for order: Dictionary in e._orders.values():
			if order.good != "grain": continue
			delivered += int(order.delivered)
			test.equal(order.buyer_site, destination, "Grain arrives at the actual buyer site")
			test.equal(order.pending + order.transit, 0, "Onsite handover completes its real order")
			for receipt: Dictionary in e._delivery_receipts.values():
				if receipt.order_id == order.id: acquired_receipts.append(receipt.id)
		var adopted := 0
		for portion: Dictionary in e._lots.portions.values():
			if portion.acquisition_id in acquired_receipts and portion.owner == buyer and portion.good == "grain": adopted += int(portion.consumed)
		if adopted > 0 and first_adoption < 0: first_adoption = date
		test.equal(e._material_remaining(seller, "SELL"), 8 - delivered, "Actual sales debit original cumulative eight-grain authorization")
		test.equal(e._material_remaining(buyer, "PROCURE"), 8 - delivered, "Buyer independently debits procurement authorization")
		if delivered > previous_delivered:
			test.expect(int(e._stocks[site].grain) >= maxi(4, int(e._input_need(site, "grain").target)), "Real grain sales preserve floor and production protection")
		previous_delivered = delivered
		test.equal(delivered, clampi(date - 22, 0, 8), "Observed original procurement delivers one grain daily on days23 through30")
		test.equal(adopted, clampi(date - 25, 0, 8), "Original FIFO adopts acquired grain on days26 through33")
		for workplace: String in [site, destination]:
			test.equal(e._retail.allocated_hours(workplace, date), 0 if date == 1 else 1, "Sales ability uses each employer's actual settled labor")
		if date >= 33:
			test.equal(e._stocks[destination].grain, 0, "Bakery exhausts its actual grain on day33")
			test.equal(e._physical_totals[destination].produced.bread, 64, "No further bakery production after actual grain exhaustion")
		if date in [1, 2, 3, 22, 23, 25, 26, 30, 31, 33, 34, 45, 60]:
			_multi_conservation(b, 4300)
			print("SECOND_WORKER_PARIS ", JSON.stringify({"day": date, "first_purchase": first_purchase, "first_adoption": first_adoption, "first_refusal": first_refusal, "delivered": delivered, "adopted": adopted, "need": e._input_need(destination, "grain"), "purchases": purchases, "stocks": e._stocks, "production": [e._physical_totals[site], e._physical_totals[destination]], "cash": [b.world.ledger_state.balance(e._account(seller)), b.world.ledger_state.balance(e._account(buyer)), b.world.ledger_state.balance(e._account(npc)), b.world.ledger_state.balance(e._account(added))], "food": [e._totals[npc].categories.food, e._totals[added].categories.food], "open_wages": e._open_wages.size(), "retail_hours": [e._retail.allocated_hours(site, date), e._retail.allocated_hours(destination, date)]}))
		if date in [2, 60] or date == first_purchase or date == first_adoption or date == first_refusal:
			b = _material_disk_restore(b)
			e = b.world.economy_r1
			for entry: Dictionary in purchases:
				var before := b.persistence.snapshot()
				test.equal(e.submit_internal(buyer, entry.envelope.command), entry.result, "Restored accepted or refused procurement replays identically")
				test.equal(b.persistence.snapshot(), before, "Restored replay changes no cash, lots, wages or responsibility")
			if date == 2:
				test.equal(e._open_wages.size(), 2, "First two completed work periods retain unpaid wage responsibilities")
	var e := b.world.economy_r1
	var grain_payment := 0
	for transaction: Dictionary in b.world.ledger_state.transactions():
		if transaction.kind == "goods" and e._orders[transaction.reference_id].good == "grain":
			grain_payment += int(transaction.amount)
			test.equal(transaction.from_account_id, e._account(buyer), "Actual grain payment belongs to the bakery")
			test.equal(transaction.to_account_id, e._account(seller), "Actual grain payment reaches the workshop")
	test.equal(grain_payment, 8, "Eight grain transfers have exactly eight original cash payments")
	for wage: Dictionary in e._wages.values():
		test.equal(wage.worker, e._work_records[wage.id].actor, "Wage claim belongs to the person who actually worked")
		if wage.due_day <= e.day: test.equal(wage.remaining, 0, "No overdue wages occurred within60 days")
	for work: Dictionary in e._work_records.values():
		test.equal(work.job, "job:opening_paris_bakery" if work.actor == npc else "job:opening_paris_workshop", "Actual work stays with its own employer")
	for transaction: Dictionary in b.world.ledger_state.transactions():
		if transaction.kind != "wage": continue
		var wage: Dictionary = e._wages[transaction.reference_id]
		test.equal(transaction.from_account_id, e._account(wage.employer), "Wage payment debits its actual employer")
		test.equal(transaction.to_account_id, e._account(wage.worker), "Wage payment credits its actual worker")
	for person: String in [npc, added]:
		test.expect(e.personal_used(person, "bread") > 0, "Both autonomous workers actually buy and consume food")
	test.equal(first_purchase, 23, "First real input procurement follows the candidate's actual shortage on day23")
	test.equal(first_adoption, 26, "First acquired grain is adopted on day26")
	test.equal(first_refusal, 31, "First quota refusal follows actual exhaustion on day31")
	test.equal(e._stocks[site], {"beans": 0, "bread": 15, "grain": 24}, "Workshop keeps finite stock after its own production and sales")
	test.equal(e._stocks[destination], EconomySliceConfig.ZERO, "Bakery remains out of grain and bread at day60")
	var final_cash: Array[int] = []
	for actor: String in [seller, buyer, npc, added, PERSON]: final_cash.append(b.world.ledger_state.balance(e._account(actor)))
	test.equal(final_cash, [966, 264, 340, 230, 2500], "Actual day60 balances conserve4300 without granting new cash")
	test.equal(b.world.game_clock.total_minutes(), 60 * 1440, "Observation ends at exactly60 days")


func _test_native_material_trade() -> void:
	var seller:="firm:opening_paris_workshop";var buyer:="firm:opening_paris_bakery"
	var site:="site:opening_paris_workshop:paris";var destination:="site:opening_paris_bakery:paris"
	for variant: String in ["unknown","sale_permission","sale_missing","procurement_permission","unstaffed","surplus","cash","worker"]:
		var settings:=FormalEconomicOpening.for_source(FRA)
		if variant=="unknown":
			for notice: Dictionary in settings.information:
				if notice.actor==destination: notice.delivery_day=2
		if variant=="sale_permission": settings.opening_organizations[0].material_trade.enabled=false
		if variant=="sale_missing": settings.opening_organizations[0].erase("material_trade")
		if variant=="procurement_permission": settings.opening_organizations[1].material_trade.enabled=false
		if variant=="surplus": settings.opening_organizations[0].material_trade.stock_floor=60
		if variant=="cash": settings.firms[1].cash=0
		var b:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
		var ready: bool=b.success and b.world.economy_r1!=null
		test.expect(ready,"Finite material negative fixture: "+variant+" "+(b.world.native_economy_error if b.world!=null else b.error))
		if not ready: continue
		if variant!="unstaffed":
			test.expect(LivelihoodAction.execute_current(b.world,"apply",{"job_id":"job:opening_paris_workshop"}).accepted,"Negative fixture volunteers through normal employment")
			test.expect(LivelihoodAction.execute_current(b.world,"work",{"hours":2}).accepted,"Negative fixture books actual labor")
		b.simulation_step.advance_minutes(1440)
		var e:=b.world.economy_r1
		var quote: Dictionary=e._offer(buyer,seller,"grain","onsite:"+site,site,destination)
		var payload: Dictionary={"quote_id":quote.quote_id,"seller":seller,"seller_site":site,"buyer_site":destination,"good":"grain","quantity":1,"denomination":quote.denomination,"max_price":1,"path_id":quote.route_id}
		var before:=_material_facts(b)
		var result: Dictionary
		if variant=="worker":
			payload["firm"]=buyer
			result=LivelihoodAction.execute_current(b.world,"buy",payload)
		else: result=e.submit_internal(buyer,{"action_id":"auto:"+buyer+":material_negative:"+variant,"minute":b.world.game_clock.total_minutes(),"kind":"buy","payload":payload})
		var expected: Dictionary={"unknown":"UNKNOWN_SUPPLIER","sale_permission":"NO_MATERIAL_SALE_MANDATE","sale_missing":"NO_MATERIAL_SALE_MANDATE","procurement_permission":"NO_MATERIAL_PROCUREMENT_MANDATE","unstaffed":"STORE_NO_ACTUAL_STAFFING","surplus":"INSUFFICIENT_MATERIAL_SALE_SURPLUS_OR_MANDATE","cash":"INSUFFICIENT_CASH_OR_CAPACITY_OR_NEED","worker":"NOT_PROCUREMENT_MANAGER"}
		test.equal(result.reason,expected[variant],"Material refusal has exact cause: "+variant)
		test.equal(_material_facts(b),before,"Material refusal preserves money, portions, orders and authority: "+variant)
	var settings:=FormalEconomicOpening.for_source(FRA)
	var b:=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,true,settings)
	var ready: bool=b.success and b.world.economy_r1!=null
	test.expect(ready,"Ordinary material trade Opening")
	if not ready: return
	test.expect(LivelihoodAction.execute_current(b.world,"apply",{"job_id":"job:opening_paris_workshop"}).accepted,"Player voluntarily takes workshop job, receives no management")
	var order_id:="";var adopted:=false;var trade_day:=-1
	for date: int in range(1,46):
		test.expect(LivelihoodAction.execute_current(b.world,"work",{"hours":2}).accepted,"Actual workshop labor for material handover day "+str(date))
		b.simulation_step.advance_minutes(1440)
		var e:=b.world.economy_r1
		for order: Dictionary in e._orders.values():
			if order.buyer==buyer and order.seller==seller and order.good=="grain": order_id=order.id;break
		if order_id.is_empty(): continue
		if trade_day<0:
			trade_day=date
			var order: Dictionary=e._orders[order_id]
			test.expect(order.delivered>0 and order.pending==0 and order.transit==0,"Material onsite handover is real and atomic")
			test.equal(order.buyer_site,destination,"Enterprise handover keeps its actual destination")
			test.equal(e._commands[order.action_id].source,"firm","Only native enterprise procurement creates the successful order")
			var before:=_material_facts(b)
			test.expect(e.submit_internal(buyer,e._commands[order.action_id].envelope.command).accepted,"Identical procurement request replays its receipt")
			test.equal(_material_facts(b),before,"Duplicate request changes no money, goods, orders or authority")
			print("MATERIAL_NATIVE_DELIVERED day=",date," order=",order," need=",e._input_need(destination,"grain"))
			b=_material_disk_restore(b);e=b.world.economy_r1
		var receipt_ids: Array=[]
		for receipt: Dictionary in e._delivery_receipts.values():
			if receipt.order_id==order_id: receipt_ids.append(receipt.id)
		for portion: Dictionary in e._lots.portions.values():
			if portion.acquisition_id in receipt_ids and portion.owner==buyer and portion.good=="grain" and portion.consumed>0:
				adopted=true
				print("MATERIAL_NATIVE_INPUT portion=",portion," source=",e._lots.sources[portion.source_id])
		if adopted:
			print("MATERIAL_NATIVE_ADOPTED day=",date," order=",order_id)
			b=_material_disk_restore(b)
			break
	test.expect(trade_day>0,"Production need triggers first purchase within45 days without stock changes")
	test.expect(adopted,"Original FIFO production consumes acquired source portions")
	test.expect(LivelihoodAction.query_firm(b.world,PERSON,buyer).is_empty(),"Worker gains no enterprise observation rights")
	test.expect(not b.world.economy_r1.personal_material_handovers(PERSON).is_empty(),"Worker can see only the material handover backed by own labor")
	var baseline:=FormalPersistence.new()._restore_snapshot_file(OS.get_environment("APPDATA")+"/WWO_R57_Visual_Living_UI_20261023/formal_world_1900_manual_3.json")
	test.expect(baseline.success,"Prior day30 save restores read-only: "+baseline.error)
	if baseline.success:
		test.equal(baseline.world.game_clock.total_minutes(),43200,"Prior day30 clock remains unchanged")
		test.expect(not baseline.world.person_overlay.has_person("person:formal_generated_country_fra_0003"), "Archived day30 world gains no second worker")
		test.expect(baseline.world.economy_r1._material_terms(seller,"SELL").is_empty(),"Loading the old world does not add a new mandate")


	# Separate player-staffed control: consume the original mandate through real daily work/orders.
	var e := b.world.economy_r1
	for unused_day: int in range(24):
		if e._material_remaining(seller, "SELL") == 0: break
		test.expect(LivelihoodAction.execute_current(b.world, "work", {"hours": 2}).accepted, "Quota control registers real player labor")
		b.simulation_step.advance_minutes(1440)
	test.equal(e._material_remaining(seller, "SELL"), 0, "Actual deliveries exhaust original sales mandate8")
	test.equal(e._material_remaining(buyer, "PROCURE"), 0, "Actual purchases exhaust independent procurement mandate8")
	var grain_orders := e._orders.values().filter(func(x: Dictionary) -> bool: return x.good == "grain")
	var delivered := 0
	for order: Dictionary in grain_orders:
		delivered += int(order.delivered)
		test.equal(order.pending + order.transit, 0, "Accepted onsite grain orders have no fictional unfinished handover")
	test.equal(delivered, 8, "Exactly eight real grain units delivered within mandate")
	test.equal(e._material_sale_available(site, "grain"), 0, "Exhausted mandate removes saleable quantity despite physical surplus")
	test.expect(int(e._stocks[site].grain) >= maxi(4, int(e._input_need(site, "grain").target)), "Real sales retain stock floor and production protection")
	var quote: Dictionary = e._offer(buyer, seller, "grain", "onsite:" + site, site, destination)
	var before := _material_facts(b)
	var refused := e.submit_internal(buyer, {"action_id": "auto:" + buyer + ":exhausted_control", "minute": b.world.game_clock.total_minutes(), "kind": "buy", "payload": {"quote_id": quote.quote_id, "seller": seller, "seller_site": site, "buyer_site": destination, "good": "grain", "quantity": 1, "denomination": quote.denomination, "max_price": 1, "path_id": quote.route_id}})
	test.equal(refused.reason, "INSUFFICIENT_MATERIAL_SALE_SURPLUS_OR_MANDATE", "Exhausted mandate rejects another enterprise purchase")
	test.equal(_material_facts(b), before, "Quota refusal preserves cash, lots, wages and accepted responsibility")
	print("STAFFED_QUOTA_CONTROL day=", e.day, " delivered=", delivered, " reason=", refused.reason)
	b = _material_disk_restore(b)


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
		for order: Dictionary in e._orders.values():
			if order.good != "grain": continue
			if order.seller_site == site: grain -= int(order.delivered)
			if order.buyer_site == site: grain += int(order.delivered)
		test.equal(int(e._stocks[site].grain)+int(e._physical_totals[site].used.grain),grain,"Firms conserve initial grain plus actual material handovers")
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
		var before_read:=e.snapshot()
		var wage_rows:=e.personal_wage_rows(PERSON,16)
		var own_claims:=e._wages.values().filter(func(w:Dictionary)->bool:return w.worker==PERSON)
		test.equal(wage_rows.size(),own_claims.size(),"Own wage UI includes each existing claim once, including former employers")
		for row: Dictionary in wage_rows:
			var claim:=e._wages[row.id] as Dictionary
			test.expect(claim.worker==PERSON and row.employer_id==claim.employer and row.amount==claim.amount and row.paid==claim.paid and row.remaining==claim.remaining and row.due_minute==int(claim.due_day)*1440,"UI wages retain actual owner, employer, payment and due time")
		test.equal(e.personal_wage_rows(npc),[],"Wage UI cannot disclose an uncontrolled resident's private claims")
		test.equal(e.snapshot(),before_read,"Reading wage UI creates no command, time, money or claim")
		var view:=PersonView.new()
		var personal:=built.world.personal_economy_state.person_economy(PERSON)
		personal["known_jobs"]=LivelihoodAction.query(built.world,PERSON).known_jobs
		view.refresh(built.world.person_overlay.person(PERSON),built.world.spatial_world.get_place("place:paris"),[],personal,[],{})
		view.selected_job_id=high
		var selected_row:=view.job_row(high)
		personal.known_jobs.reverse()
		view.refresh(built.world.person_overlay.person(PERSON),built.world.spatial_world.get_place("place:paris"),[],personal,[],{})
		test.equal(view.job_row(view.selected_job_id),selected_row,"Job selection is an ID, unaffected by list order and refresh")
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
		var page:=PersonView.new()
		var person_view:=qualified.world.personal_economy_state.person_economy(PERSON)
		person_view["known_jobs"]=LivelihoodAction.query(qualified.world,PERSON).known_jobs
		page.refresh(qualified.world.person_overlay.person(PERSON),qualified.world.spatial_world.get_place("place:paris"),[],person_view,[],{})
		test.expect(not page.can_apply(page.job_row(high)) and "技能" in page.job_reason(page.job_row(high)),"Known qualification failure has a readable disabled application reason")
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
