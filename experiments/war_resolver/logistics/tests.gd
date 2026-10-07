extends SceneTree
const F = preload("res://experiments/war_resolver/logistics/fixtures.gd")
const Base = preload("res://experiments/war_resolver/structure/fixtures.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func _init() -> void:
	_inventory_boundary()
	_shortages()
	_readiness()
	_lod_structure()
	_attachment()
	_scaling()
	_exploits()
	_admission_and_authority()
	print("TASK6_EVIDENCE_JSON=" + JSON.stringify(evidence))
	print("Task6 logistics: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)

func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) <= 0.000001 * maxf(1.0, absf(b)), label)

func conserve(env: Dictionary) -> void:
	var audit: Dictionary = env.logistics.audit()
	for key: String in audit.initial:
		near(float(audit.current_plus_spent_and_transit[key]), float(audit.initial[key]), "mass " + key)
	for id: String in env.state.area_units.cell_037:
		var u: Dictionary = env.state.units[id]
		near(float(u.serviceable_equipment) + float(u.damaged_equipment), float(u.equipment), "equipment partition " + id)
		for key: String in env.lod.stock_keys():
			check(float(u[key]) >= -0.0000001, "nonnegative " + id + " " + key)

func _inventory_boundary() -> void:
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup()
	F.idle(a)
	F.idle(b)
	var initial: float = float(F.stocks(a).ammunition)
	check(F.delivery(a).ok and F.delivery(b).ok, "A allocation")
	near(float(a.logistics._depots.source.stock.AMMUNITION), 999900.0, "A source debit")
	near(float(F.stocks(a).ammunition), initial, "A allocation not receipt")
	conserve(a)
	check(a.lod.advance(30.0).ok and a.lod.advance(59.0).ok, "B before boundary")
	near(float(F.stocks(a).ammunition), initial, "B ETA not yet usable")
	check(a.lod.advance(60.0).ok, "B exact boundary")
	near(float(F.stocks(a).ammunition), initial + 100.0, "B received exactly")
	check(a.lod.advance(120.0).ok and b.lod.advance(120.0).ok, "B one-shot segmented")
	check(a.lod.snapshot().current.units == b.lod.snapshot().current.units, "B state equality")
	check(a.logistics.snapshot() == b.logistics.snapshot(), "B logistics equality")
	var before: Dictionary = F.stocks(a)
	check(not F.delivery(a).ok, "C duplicate command")
	var repeated: Dictionary = a.logistics.process_event({"id": "logistics_delivery_delivery", "time": 120.0, "payload": {"delivery_id": "delivery"}})
	check(not repeated.record.ok and before == F.stocks(a), "C duplicate processing no receipt")
	check(not a.state.schedule_event("forged", 120.0, "logistics", {"delivery_id": "delivery"}), "C ticket smuggling rejected")
	conserve(a)
	evidence.A_B_C = {"stock_before": initial, "stock_after": F.stocks(a).ammunition, "status": a.logistics._deliveries.delivery.status, "exact_boundary": 60.0, "segmented_equal": true, "source_free": a.logistics._depots.source.stock.AMMUNITION}
	# Combat after an off-grid ETA remains identical for aligned caller boundaries.
	a = F.setup()
	b = F.setup()
	check(F.delivery(a, "combat_eta", "formation", "blue_company", "AMMUNITION", 100.0, 47.0).ok and F.delivery(b, "combat_eta", "formation", "blue_company", "AMMUNITION", 100.0, 47.0).ok, "B off-grid ETA")
	check(a.lod.advance(30.0).ok and a.lod.advance(47.0).ok and a.lod.advance(120.0).ok and b.lod.advance(120.0).ok, "B combat segmented resolve")
	check(causal(a) == causal(b), "B combat snapshot equality")

func _shortages() -> void:
	var low: Dictionary = F.setup(40, 0, true, true, 8.0, 0.75, 0.0)
	var high: Dictionary = F.setup()
	check(low.lod.advance(30.0).ok and high.lod.advance(30.0).ok, "D ammo resolve")
	var ls: Dictionary = F.stocks(low)
	var hs: Dictionary = F.stocks(high)
	check(float(ls.ammo_spent) == 0.0 and float(hs.ammo_spent) > 0.0 and float(hs.casualties) > float(ls.casualties), "D ammo drives spent and casualties")
	var pressure: float = 0.0
	var fire: float = 0.0
	for contact: Dictionary in high.state.contacts.cell_037:
		pressure += float(contact.suppression)
		fire += float(contact.usable_fire_per_minute)
	check(pressure > 0.0 and fire > 0.0, "D actual suppression and usable fire")
	var dry: Dictionary = F.setup(40, 0, true, true, 0.0, 0.75, 0.0)
	var wet: Dictionary = F.setup(40, 0, true, true, 0.01, 0.75, 0.0)
	var foot: Dictionary = F.setup(40, 0, true, false, 0.0, 0.75, 0.0)
	check(dry.lod.advance(120.0).ok and wet.lod.advance(120.0).ok and foot.lod.advance(120.0).ok, "E movement resolve")
	near(float(dry.lod.preview_leaf("unit_000").distance_moved), 0.0, "E motor dry stalls")
	check(float(wet.lod.preview_leaf("unit_000").distance_moved) > 0.0 and float(foot.lod.preview_leaf("unit_000").distance_moved) > float(wet.lod.preview_leaf("unit_000").distance_moved), "E fuel exhaustion vs walking")
	near(float(wet.lod.preview_leaf("unit_000").fuel), 0.0, "E exact fuel exhaustion")
	var distance: float = float(wet.lod.preview_leaf("unit_000").distance_moved)
	check(wet.lod.advance(240.0).ok, "E exhausted subsequent advance")
	near(float(wet.lod.preview_leaf("unit_000").distance_moved), distance, "E no continued motor movement")
	check(F.delivery(wet, "refuel", "formation", "blue_company", "FUEL", 1.0, 240.0).ok and wet.lod.advance(270.0).ok, "E explicit refuel")
	check(float(wet.lod.preview_leaf("unit_000").distance_moved) > distance, "E refuel resumes")
	conserve(low)
	conserve(high)
	conserve(wet)
	evidence.D_E = {"dry_ammo_spent": ls.ammo_spent, "supplied_ammo_spent": hs.ammo_spent, "dry_casualties": ls.casualties, "supplied_casualties": hs.casualties, "usable_fire": fire, "pressure": pressure, "fuel_exhaustion_distance": distance, "walking_distance": foot.lod.preview_leaf("unit_000").distance_moved}

func _readiness() -> void:
	var damaged: Dictionary = F.setup(40, 0, true, true, 8.0, 0.0)
	var operational: Dictionary = F.setup(40, 0, true, true, 8.0, 1.0)
	var assigned: float = float(F.stocks(damaged).equipment)
	near(assigned, float(F.stocks(operational).equipment), "F same assigned equipment")
	check(damaged.lod.advance(30.0).ok and operational.lod.advance(30.0).ok, "F readiness resolve")
	check(float(F.stocks(damaged).ammo_spent) == 0.0 and float(F.stocks(operational).ammo_spent) > 0.0, "F operational controls fire")
	check(float(damaged.lod.preview_leaf("unit_000").distance_moved) == 0.0 and float(operational.lod.preview_leaf("unit_000").distance_moved) > 0.0, "F motor availability")
	F.idle(damaged)
	check(damaged.lod.advance(7200.0).ok, "G no repair over time")
	near(float(F.stocks(damaged).serviceable_equipment), 0.0, "G no magical repair")
	check(F.repair(damaged, "oversized", "formation", "blue_company", assigned + 1.0, 7200.0).ok, "G oversized scheduled only")
	var before: Dictionary = F.stocks(damaged)
	check(damaged.lod.advance(7200.0).ok and damaged.logistics._maintenance.oversized.status == "REJECTED", "G oversized repair atomic reject")
	check(before == F.stocks(damaged), "G reject unchanged inventory")
	check(F.repair(damaged, "bounded", "formation", "blue_company", 2.0, 7200.0).ok and damaged.lod.advance(7200.0).ok, "G explicit repair")
	near(float(F.stocks(damaged).serviceable_equipment), 2.0, "G bounded restored")
	near(float(F.stocks(damaged).spares_spent), 2.0, "G spares consumed")
	near(float(damaged.logistics._capacities.workshop.remaining), 998.0, "G capacity consumed")
	conserve(damaged)
	evidence.F_G = {"assigned_before": assigned, "damaged_fire_spent": before.ammo_spent, "operational_fire_spent": F.stocks(operational).ammo_spent, "explicit_restored": F.stocks(damaged).serviceable_equipment, "spares_spent": F.stocks(damaged).spares_spent, "logistics_materialized": damaged.logistics.work.leaves_materialized_for_logistics}

func _lod_structure() -> void:
	var env: Dictionary = F.setup(100)
	check(F.delivery(env).ok and env.lod.advance(120.0).ok, "H macro delivery combat")
	var total: Dictionary = F.stocks(env)
	check(env.lod.materialize_leaf("unit_000").materialized == 1, "H one causal extract")
	for key: String in total:
		near(float(F.stocks(env)[key]), float(total[key]), "H extract conserved " + key)
	conserve(env)
	# No elapsed combat between split and merge: check every extensive ledger.
	F.idle(env)
	for round_index: int in range(12):
		var id: String = "round_%d" % round_index
		var fresh: String = "child_%d" % round_index
		var before: Dictionary = F.stocks(env)
		check(env.commands.company.apply(F.split(env, id, "unit_000", fresh)).ok and env.lod.advance(float(env.state.time)).ok, "I split " + id)
		check(env.commands.company.apply(Base.request("merge_" + id, "merge", float(env.state.time), {"survivor": "unit_000", "donor": fresh})).ok and env.lod.advance(float(env.state.time)).ok, "I merge " + id)
		for key: String in before:
			near(float(F.stocks(env)[key]), float(before[key]), "I round conservation " + key)
	conserve(env)
	for count: int in [40, 100]:
		var macro: Dictionary = F.setup(count)
		F.idle(macro)
		check(F.delivery(macro).ok and macro.lod.advance(60.0).ok, "M formation receipt")
		check(macro.logistics.work.leaves_materialized_for_logistics == 0 and macro.lod.work.leaf_records_materialized == 0, "M no full materialization")
		check(int(macro.logistics.work.proxy_edits) == count / 20, "M direct proxy edits")
		var old: Dictionary = F.stocks(macro)
		check(F.delivery(macro, "leaf", "unit", "unit_000", "AMMUNITION", 7.0, 61.0).ok and macro.lod.advance(61.0).ok, "N leaf receipt")
		check(macro.logistics.work.leaves_materialized_for_logistics == 1 and macro.lod.work.leaf_records_materialized == 1, "N exactly one leaf")
		near(float(F.stocks(macro).ammunition), float(old.ammunition) + 7.0, "N recipient plus residual")
		conserve(macro)
		evidence["M_N_%d" % count] = macro.logistics.work.duplicate()
	# A fixed unit recipient is not copied to its split child.
	env = F.setup(40, 0, false)
	F.idle(env)
	check(F.delivery(env, "split_pending", "unit", "unit_000").ok, "I schedule before split")
	check(env.commands.company.apply(F.split(env)).ok and env.lod.advance(0.0).ok, "I split before receipt")
	var child_ammo: float = float(env.state.units.detachment.ammunition)
	check(env.lod.advance(60.0).ok, "I split pending receipt")
	near(float(env.state.units.detachment.ammunition), child_ammo, "I child no duplicated shipment")
	conserve(env)
	# Merged donor is retired: return reserved source stock with explicit history.
	env = F.setup(40, 0, false)
	F.idle(env)
	check(F.delivery(env, "retired", "unit", "unit_001").ok, "L allocate retired candidate")
	check(env.commands.company.apply(Base.request("merge", "merge", 0.0, {"survivor": "unit_000", "donor": "unit_001"})).ok and env.lod.advance(0.0).ok and env.lod.advance(60.0).ok, "L merge then due")
	check(env.logistics._deliveries.retired.status == "REJECTED_RETURNED" and not env.state.units.has("unit_001"), "L return retired delivery")
	near(float(env.logistics._depots.source.stock.AMMUNITION), 1000000.0, "L source restored")
	conserve(env)
	evidence.H_I_L = {"split_merge_cycles": 12, "retired_policy": env.logistics._deliveries.retired.status}

func _attachment() -> void:
	var a: Dictionary = F.setup()
	var b: Dictionary = F.setup()
	F.idle(a)
	F.idle(b)
	for env: Dictionary in [a, b]:
		check(F.delivery(env, "stable_unit", "unit", "unit_000", "AMMUNITION", 10.0, 30.0).ok, "J unit fixed shipment")
		check(F.delivery(env, "old_company", "formation", "blue_company", "AMMUNITION", 20.0, 30.0).ok, "J formation fixed shipment")
		check(env.commands.regiment.apply(Base.request("attach", "attach", 30.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0})).ok, "J schedule attachment")
	var original: Dictionary = F.stocks(a)
	check(a.lod.advance(29.0).ok, "J before attach")
	check(original == F.stocks(a), "J no moving owned stocks")
	check(a.lod.advance(30.0).ok and b.lod.advance(30.0).ok, "K same exact boundary")
	var relation: Dictionary = a.logistics.responsibility("unit_000")
	check(relation.permanent_parent == "platoon_000" and relation.effective_parent == "blue_destination", "J responsibility follows effective relation")
	var query: Dictionary = {"id": "new_scope", "kind": "request", "target_kind": "unit", "target": "unit_000", "resource_class": "AMMUNITION", "quantity": 1.0}
	check(not a.supply_commands.company.submit(query).ok and a.supply_commands.recipient.submit(query).ok, "J request scope updated")
	check(a.logistics._deliveries.stable_unit.status == "RECEIVED" and a.logistics._deliveries.old_company.status == "RECEIVED", "J delivery single receipt")
	near(float(a.state.units.unit_000.ammunition), 1210.0, "J attached leaf gets own shipment only")
	check(causal(a) == causal(b), "K deterministic attach delivery order")
	check(a.lod.advance(90.0).ok, "J expiry")
	check(a.logistics.responsibility("unit_000").effective_parent == "platoon_000", "J responsibility restored")
	conserve(a)
	evidence.J_K = {"relation_during": relation, "relation_after": a.logistics.responsibility("unit_000"), "unit_receipt": 10.0, "former_parent_receipt": 20.0, "unit_ammo": a.state.units.unit_000.ammunition}
	# Combat scheduled to the same boundary settles the old interval first.
	a = F.setup()
	b = F.setup()
	for env: Dictionary in [a, b]:
		check(F.delivery(env, "combat_attach", "unit", "unit_000", "AMMUNITION", 10.0, 30.0).ok, "K combat delivery")
		check(env.commands.regiment.apply(Base.request("combat_attach", "attach", 30.0, {"target": "node_unit_000", "parent": "blue_destination", "until": 90.0})).ok, "K combat attach")
	check(a.lod.advance(30.0).ok and a.lod.advance(120.0).ok and b.lod.advance(120.0).ok, "K combat advance")
	check(causal(a) == causal(b) and a.logistics.snapshot() == b.logistics.snapshot(), "K combat deterministic ordering")
	conserve(a)

func _scaling() -> void:
	var local: Dictionary = F.setup()
	var world: Dictionary = F.setup(40, 10000)
	for env: Dictionary in [local, world]:
		check(F.delivery(env, "sleep_test", "unit", "unit_000").ok and env.lod.advance(120.0).ok, "O local due delivery")
	check(local.logistics.work == world.logistics.work and local.state.counters == world.state.counters and local.lod.counters() == world.lod.counters(), "O exact active work independence")
	check(local.lod.macro_summary().sides == world.lod.macro_summary().sides, "O same active result")
	evidence.O = {"local_work": local.logistics.work.duplicate(), "world_work": world.logistics.work.duplicate(), "combat": local.state.counters.duplicate()}
	var many: Dictionary = F.setup()
	F.idle(many)
	for index: int in range(1000):
		check(F.delivery(many, "future_%04d" % index, "formation", "blue_company", "AMMUNITION", 1.0, 60.0 if index < 3 else 100000.0 + float(index)).ok, "P future schedule")
	check(many.lod.advance(120.0).ok, "P few due")
	check(many.logistics.work.deliveries_processed == 3 and many.logistics.work.future_deliveries_examined == 0 and many.state.events.size() == 997, "P only due work")
	conserve(many)
	evidence.P = {"due": many.logistics.work.deliveries_processed, "future_examined": many.logistics.work.future_deliveries_examined, "pending": many.state.events.size()}

func _exploits() -> void:
	var env: Dictionary = F.setup()
	F.idle(env)
	var before: Dictionary = F.stocks(env)
	for quantity: Variant in [-1.0, NAN, true, "1", 0.0, INF]:
		check(not env.supply_commands.company.submit({"id": "invalid", "kind": "request", "target_kind": "formation", "target": "blue_company", "resource_class": "AMMUNITION", "quantity": quantity}).ok, "R invalid quantity")
	check(not env.supply_commands.soldier.submit({"id": "soldier", "kind": "request", "target_kind": "formation", "target": "blue_company", "resource_class": "AMMUNITION", "quantity": 1.0}).ok, "R soldier cannot allocate company")
	check(not F.delivery(env, "overstock", "formation", "blue_company", "AMMUNITION", 1000001.0).ok, "R overstock reject")
	env.logistics._depots.source.stock.AMMUNITION = 0.0
	check(not F.delivery(env, "zero_source").ok, "R zero source reject")
	env.logistics._depots.source.stock.AMMUNITION = 1000000.0
	check(before == F.stocks(env), "R rejected inputs atomic")
	var foot: Dictionary = F.setup(40, 0, true, false)
	check(not F.delivery(foot, "wrong_fuel", "formation", "blue_company", "FUEL").ok, "R fuel invalid for foot capability")
	var repair_before: Dictionary = F.stocks(env)
	check(F.repair(env, "overspares", "unit", "unit_000", 5.0, 0.0).ok and env.lod.advance(0.0).ok, "R overspares due reject")
	check(env.logistics._maintenance.overspares.status == "REJECTED" and repair_before == F.stocks(env), "R repair bounded spares atomic")
	env.logistics._capacities.workshop.remaining = 0.0
	check(F.repair(env, "no_capacity", "formation", "blue_company", 1.0, 0.0).ok and env.lod.advance(0.0).ok, "R missing external capacity")
	check(env.logistics._maintenance.no_capacity.status == "REJECTED" and repair_before == F.stocks(env), "R capacity atomic")
	for cycle: int in range(4):
		check(env.commands.regiment.apply(Base.request("attach_%d" % cycle, "attach", float(cycle * 20), {"target": "node_unit_000", "parent": "blue_destination", "until": float(cycle * 20 + 10)})).ok, "R repeated nonoverlap attach")
		check(env.lod.advance(float(cycle * 20 + 10)).ok, "R repeated expiry")
		check(repair_before == F.stocks(env), "R attach stocks unchanged")
	for index: int in range(100):
		check(F.delivery(env, "bulk_%03d" % index, "formation", "blue_company", "SPARES", 1.0, 100.0).ok, "R bulk reserve")
	check(env.lod.advance(100.0).ok, "R bulk simultaneous receipt")
	near(float(F.stocks(env).spares), float(repair_before.spares) + 100.0, "R bulk once only")
	conserve(env)
	evidence.R = {"invalid_quantities": 6, "bulk_due": 100, "attachment_cycles": 4, "bulk_spares": F.stocks(env).spares}

func causal(env: Dictionary) -> Dictionary:
	var snapshot: Dictionary = env.lod.snapshot()
	# Diagnostic spatial fold reads depend on explicit caller observation count.
	snapshot.current.erase("counters")
	return snapshot

func _admission_and_authority() -> void:
	var env: Dictionary = F.setup(40, 0, false)
	F.idle(env)
	var request: Dictionary = {"id": "platoon_request", "kind": "request", "target_kind": "unit", "target": "unit_000", "resource_class": "AMMUNITION", "quantity": 9.0}
	check(env.supply_commands.platoon.submit(request).ok, "R platoon legitimate request")
	check(not env.supply_commands.platoon.submit(request).ok, "R duplicate request")
	var allocation: Dictionary = {"id": "authority_delivery", "kind": "allocate", "request_id": request.id, "source_ref": "source", "delivery_time": 20.0}
	check(not env.supply_commands.soldier.submit(allocation).ok and not env.supply_commands.platoon.submit(allocation).ok, "R soldier and platoon cannot allocate warehouse")
	check(not env.supply_commands.recipient.submit(allocation).ok, "R allocation outside effective scope")
	var spoofed: Dictionary = allocation.duplicate(true)
	spoofed.person_id = "division"
	check(not env.supply_commands.soldier.submit(spoofed).ok, "R payload cannot impersonate")
	check(env.supply_commands.company.submit(allocation).ok, "R allocation legitimate officer")
	check(not env.supply_commands.company.submit(allocation).ok, "R duplicate delivery id")
	var second: Dictionary = allocation.duplicate(true)
	second.id = "second_id"
	check(not env.supply_commands.company.submit(second).ok, "R request cannot be allocated twice")
	check(not env.state.schedule_event("logistics_delivery_authority_delivery", 19.0, "logistics", {"delivery_id": "authority_delivery"}), "R forged ETA ticket")
	check(env.lod.advance(20.0).ok, "R authority receipt")
	var before: Dictionary = F.stocks(env)
	var repeat: Dictionary = env.logistics.process_event({"id": "logistics_delivery_authority_delivery", "time": 20.0, "payload": {"delivery_id": "authority_delivery"}})
	check(not repeat.record.ok and before == F.stocks(env), "R exact-time duplicate processing")
	# Supply-node stock stays in that source fact, never auto-distributed to troops.
	var source_before: float = float(env.logistics._depots.recipient_source.stock.AMMUNITION)
	check(F.delivery(env, "warehouse", "depot", "recipient_source", "AMMUNITION", 50.0, 30.0, "regiment").ok and env.lod.advance(30.0).ok, "J explicit depot receipt")
	near(float(env.logistics._depots.recipient_source.stock.AMMUNITION), source_before + 50.0, "J depot remains separate from recipients")
	check(before == F.stocks(env), "J depot receipt not battlefield receipt")
	check(env.logistics._depots.source.owner_ref == "external_warehouse_owner", "J source ownership unchanged")
	conserve(env)
	# Admission and LOD compatibility reject unrepresentable stock profiles.
	env = F.setup(40, 0, false)
	env.state.units.unit_000.fuel = 0.0
	var cohort: Array[String] = ["unit_000", "unit_001"]
	check(not env.lod.coalesce("platoon_000", cohort).ok, "H heterogeneous exhaustion cannot average")
	env.state.units.unit_000.fuel = 8.0
	var facts: Dictionary = {"unit_000": {"fuel": 8.0, "fuel_spent": 0.0, "spares": 4.0, "spares_spent": 0.0, "serviceable_equipment": 13.0, "damaged_equipment": 0.0, "wear_damage": 0.0, "repair_restored": 0.0, "capability": env.state.units.unit_000.supply_capability.duplicate(true)}}
	check(not F.Service._valid_fact(facts.unit_000, env.state.units.unit_000), "R invalid assigned serviceability admission")
	# Split company inventory: new formation has its own indexed live recipients.
	F.idle(env)
	var total: Dictionary = F.stocks(env)
	var allocation_stocks: Dictionary = {}
	for key: String in env.service.stock_keys():
		allocation_stocks[key] = 0.0
	for leaf: String in env.service.leaves("blue_company"):
		var unit: Dictionary = env.lod.preview_leaf(str(env.service.node(leaf).unit_id))
		for key: String in allocation_stocks:
			allocation_stocks[key] += float(unit[key]) * 0.25
	check(env.commands.battalion.apply(Base.request("company_split", "split", 0.0, {"source": "blue_company", "new_id": "new_company", "new_node": "new_company", "allocation": allocation_stocks})).ok and env.lod.advance(0.0).ok, "I company split extended stocks")
	for key: String in total:
		near(float(F.stocks(env)[key]), float(total[key]), "I company split conservation " + key)
	check(F.delivery(env, "new_formation", "formation", "new_company", "AMMUNITION", 50.0, 60.0, "battalion").ok and env.lod.advance(60.0).ok, "I delivery to new formation")
	near(float(F.stocks(env).ammunition), float(total.ammunition) + 50.0, "I new formation receives once")
	conserve(env)
	evidence.authority_admission = {"platoon_request_only": true, "bound_person_scope": true, "depot_receipt_is_not_unit_receipt": true, "company_split_extended_stocks": true}
