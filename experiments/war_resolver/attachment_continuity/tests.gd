extends SceneTree
const Session = preload("res://experiments/war_resolver/attachment_continuity/session.gd")
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")
const Audit = preload("res://experiments/war_resolver/interactive_observer/audit.gd")
var checks: int = 0
var failures: int = 0
var evidence: Array[Dictionary] = []
var env: Dictionary = {}
var before: Dictionary = {}
var boundary_rows: Array[Dictionary] = []
var boundary_started: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)

func _initialize() -> void:
	if "--tactical-continuity" in OS.get_cmdline_user_args():
		_tactical_transfers()
		_tactical_carried_location()
		_tactical_split_merge()
		_tactical_interruptions()
		_tactical_shared_fire()
		_tactical_runtime()
		_tactical_action_recovery()
		_tactical_medical_recovery()
		_tactical_inventory_recovery()
		_versioned_revoke()
		_negative()
		_incapped()
		_pending()
		print("Tactical continuity local: %d checks, %d failures" % [checks, failures])
		quit(0 if failures == 0 else 1)
		return
	var all: bool = "--all" in OS.get_cmdline_user_args()
	var long_run: bool = "--long" in OS.get_cmdline_user_args()
	var seeds: Array[int] = [71]
	if all:
		seeds.assign([71, 109, 347, 2027])
	for seed_value: int in seeds:
		var reference: Dictionary = {}
		for quota: int in [0, 1, 7, 31]:
			_personal(seed_value, quota)
			var result: Dictionary = _crossing(seed_value, quota)
			if quota == 0:
				reference = result
			else:
				check(result == reference, "crossing normal/quota exact formal " + str(quota))
			_cycles(seed_value, quota, 3600.0)
	_incapped()
	_negative()
	_versioned_revoke()
	_pending()
	if long_run:
		for seed_value: int in [71, 109]:
			var reference: Dictionary = {}
			for quota: int in [0, 1, 7, 31]:
				var result: Dictionary = _cycles(seed_value, quota, 86400.0)
				if quota == 0:
					reference = result
				else:
					check(result == reference, "24h exact formal " + str(seed_value) + "/" + str(quota))
	var output: Dictionary = {"view": "DEBUG_TRUTH", "checks": checks, "failures": failures,
		"regression_seeds": seeds, "boundary_rows": boundary_rows, "scenarios": evidence}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--output="), FileAccess.WRITE)
			file.store_string(JSON.stringify(output) + "\n")
	print("Attachment continuity: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _tactical_env() -> Dictionary:
	var result: Dictionary = F.setup(71, {"personal": true, "red_ammunition": 0.0})
	result.structure.member_adjustments = true
	for mission: Dictionary in result.state.missions.values():
		mission.posture = "idle"
	check(result.gameplay.tactics.admit_weapon("soldier"), "existing equipment share admitted")
	return result

func _stocks(world: Dictionary) -> Dictionary:
	var result: Dictionary = {"ammunition": 0.0, "equipment": 0.0, "spent": 0.0, "lost": 0.0, "casualties": 0.0}
	for unit: Dictionary in world.state.units.values():
		result.ammunition += float(unit.ammunition)
		result.equipment += float(unit.equipment)
		result.spent += float(unit.ammo_spent)
		result.lost += float(unit.equipment_lost)
		result.casualties += float(unit.casualties)
	return result

func _transfer(world: Dictionary, id: String, source: String, destination: String, at: float, disposition: String = "carry") -> Dictionary:
	return world.structure.submit("company", {"id": id, "kind": "transfer_person", "effective_time": at,
		"values": {"person": "soldier", "source": source, "destination": destination, "weapon_disposition": disposition}})

func _tactical_transfers() -> void:
	var world: Dictionary = _tactical_env()
	var tactics: RefCounted = world.gameplay.tactics
	check(tactics.personal("soldier", "load", {"action": "reload"}).ok and F.advance(world, 10.0).ok, "timed preparation completed")
	var stock: Dictionary = _stocks(world)
	var body: Dictionary = world.gameplay.participants._member("soldier")
	var ready: float = float(tactics.weapons.soldier.ready)
	var target_ammo: float = float(world.state.units.unit_001.ammunition)
	var target_equipment: float = float(world.state.units.unit_001.equipment)
	check(ready > 0.0 and _transfer(world, "carry", "unit_000", "unit_001", 11.0).ok and F.advance(world, 11.0).ok, "prepared member actual handover")
	check(tactics.weapons.soldier.unit_ref == "unit_001" and is_equal_approx(float(tactics.weapons.soldier.ready), ready), "same weapon prepared claim follows actual holder")
	check(is_equal_approx(float(world.state.units.unit_001.ammunition), target_ammo + ready) and is_equal_approx(float(world.state.units.unit_001.equipment), target_equipment + 1.0) and _stocks(world) == stock, "single ammo and equipment debit/credit")
	check(is_same(body, world.gameplay.participants._member("soldier")), "same body object retained")
	check(_transfer(world, "leave", "unit_001", "unit_000", 12.0, "leave").ok and F.advance(world, 12.0).ok, "explicit weapon left at original place")
	check(tactics.weapons.soldier.custody == "LEFT" and tactics.weapons.soldier.unit_ref == "unit_001" and float(tactics.weapons.soldier.ready) == ready and _stocks(world) == stock, "left preparation remains inside source inventory")
	check(not tactics.validate_person("soldier", {"action": "reload"}).ok, "membership alone does not acquire left equipment")
	check(_transfer(world, "return", "unit_000", "unit_001", 13.0).ok and F.advance(world, 13.0).ok and tactics.personal("soldier", "claim", {"action": "claim_weapon"}).ok, "actual contact can claim original left weapon")
	check(_stocks(world) == stock and float(tactics.weapons.soldier.ready) == ready, "claim neither creates stock nor repeats transfer")
	var failed: Dictionary = _tactical_env()
	check(failed.gameplay.tactics.personal("soldier", "loading", {"action": "reload"}).ok and F.advance(failed, 10.0).ok, "failed handover fixture prepared")
	check(_transfer(failed, "late_handover", "unit_000", "unit_001", 15.0).ok, "handover scheduled before situation change")
	var moving: Dictionary = F.command(failed, "platoon", "destination_moves", F.intent("advance", "B", ["AB"]), "node_unit_001", "instant")
	if not moving.ok:
		print("receiver command: ", moving)
	check(moving.ok and F.advance(failed, 15.0).ok, "receiver actually starts movement")
	check(not failed.structure.history.is_empty() and failed.structure.history[-1].outcome.ok == false and failed.gameplay.tactics.weapons.soldier.unit_ref == "unit_000" and float(failed.gameplay.tactics.weapons.soldier.ready) > 0.0, "failed physical handover preserves source weapon and claim")

func _tactical_interruptions() -> void:
	var world: Dictionary = _tactical_env()
	var tactics: RefCounted = world.gameplay.tactics
	check(F.report(world, "soldier", "soldier_local", "cover", "cover_before_reload", "soldier") and F.advance(world, 0.0).ok, "body knows actual nearby cover")
	check(tactics.personal("soldier", "reload_before_move", {"action": "reload"}).ok and F.advance(world, 2.0).ok, "reload interval begun")
	check(world.gameplay.participants.apply_action("soldier", "move_during_reload", "take_cover").ok and F.advance(world, 10.0).ok, "real body movement interrupts preparation")
	check(float(tactics.weapons.soldier.ready) == 0.0 and tactics.weapons.soldier.last_interruption.elapsed == 2.0, "stale reload cannot complete or refund elapsed time")
	check(tactics.personal("soldier", "replacement_reload", {"action": "reload"}).ok and _transfer(world, "during_reload", "unit_000", "unit_001", 11.0).ok and F.advance(world, 20.0).ok, "unfinished reload interrupted by actual member handover")
	check(tactics.weapons.soldier.unit_ref == "unit_001" and float(tactics.weapons.soldier.ready) == 0.0, "old source event cannot prepare destination stock")
	check(tactics.personal("soldier", "new_reload", {"action": "reload"}).ok and F.advance(world, 30.0).ok, "new owner explicitly reloads")
	check(tactics.personal("soldier", "aim_before_hurt", {"action": "fire", "target_ref": "unit_002", "seconds": 30.0}).ok and F.advance(world, 31.0).ok, "actual aim pending")
	world.gameplay.participants.external_damage("soldier", 3.0, "local_incap", "ground_fire")
	var casualties: float = float(world.state.totals.casualties)
	var ammunition: float = float(world.state.units.unit_001.ammunition)
	check(F.advance(world, 62.0).ok and not world.gameplay.participants._member("soldier").actionable, "incapacity interrupts future weapon work")
	check(world.state.totals.casualties == casualties and world.state.units.unit_001.ammunition == ammunition, "stale aim/cease adds no casualty or firing")
	var observer: Dictionary = _tactical_env()
	check(observer.gameplay.tactics.personal("soldier", "old_observe", {"action": "observe", "node_ref": "A"}).ok and _transfer(observer, "observer_moved", "unit_000", "unit_001", 2.0).ok and F.advance(observer, 6.0).ok, "actual membership change interrupts unfinished observation")
	check(observer.information._observations.is_empty(), "stale old-unit observation ticket creates no new knowledge")

func _tactical_split_merge() -> void:
	var world: Dictionary = _tactical_env()
	check(world.gameplay.tactics.personal("soldier", "split_reload", {"action": "reload"}).ok and F.advance(world, 10.0).ok, "split fixture prepared")
	var stock: Dictionary = _stocks(world)
	var request: Dictionary = {"id": "split_with_weapon", "kind": "split_members", "effective_time": 11.0,
		"values": {"source": "unit_000", "new_id": "weapon_detachment", "new_node": "node_weapon_detachment", "members": ["soldier"], "anonymous": 0.0,
			"allocation": {"equipment": 1.0, "ammunition": 4.0, "fuel": 0.0, "spares": 0.0}, "keep_goal": "source", "other_task": "idle"}}
	var insufficient: Dictionary = request.duplicate(true)
	insufficient.id = "insufficient_split"
	insufficient.values.allocation.ammunition = 0.0
	check(not world.structure.submit("company", insufficient).ok and _stocks(world) == stock, "split cannot detach ready claim without allocated ammunition")
	check(world.structure.submit("company", request).ok and F.advance(world, 11.0).ok, "explicit pooled split admitted")
	check(world.gameplay.tactics.weapons.soldier.unit_ref == "weapon_detachment" and float(world.gameplay.tactics.weapons.soldier.ready) == 4.0 and _stocks(world) == stock, "split equipment and preparation transferred exactly once inside allocation")
	check(world.structure.submit("company", {"id": "merge_with_weapon", "kind": "merge_members", "effective_time": 12.0,
		"values": {"survivor": "unit_000", "donor": "weapon_detachment", "keep_goal": "survivor", "discard_other": true}}).ok and F.advance(world, 12.0).ok, "pooled merge with named weapon")
	check(world.gameplay.tactics.weapons.soldier.unit_ref == "unit_000" and float(world.gameplay.tactics.weapons.soldier.ready) == 4.0 and _stocks(world) == stock and not world.state.units.has("weapon_detachment"), "merge does not debit or credit pooled inventory twice")

func _tactical_carried_location() -> void:
	var world: Dictionary = _tactical_env()
	check(world.gameplay.tactics.personal("soldier", "carry_prepare", {"action": "reload"}).ok and F.advance(world, 10.0).ok, "carried location fixture prepared")
	var stock: Dictionary = _stocks(world)
	check(world.gameplay.participants.apply_extended("soldier", "carry_walk", {"action": "relocate", "destination_node": "B", "path": ["AB"]}).ok and F.advance(world, 72.0).ok, "original body actually travels with its claimed weapon")
	check(not world.gameplay.tactics.personal("soldier", "remote_release", {"action": "release_weapon"}).ok and world.gameplay.tactics.weapons.soldier.ready == 4.0 and _stocks(world) == stock, "carried preparation cannot be remotely released into source free stock")
	check(world.gameplay.participants.apply_extended("soldier", "carry_return", {"action": "relocate", "destination_node": "A", "path": ["AB"]}).ok and F.advance(world, 134.0).ok, "real return to stock location")
	check(world.gameplay.tactics.personal("soldier", "contact_release", {"action": "release_weapon"}).ok and world.gameplay.tactics.weapons.soldier.ready == 0.0 and _stocks(world) == stock, "release only changes preparation allocation after actual contact")

func _gun_profile() -> Dictionary:
	return {"crew": 2.0, "equipment_share": 2.0, "range_km": 0.2, "deploy_seconds": 5.0, "reload_seconds": 5.0,
		"cycle_seconds": 5.0, "rounds_per_mission": 1.0, "lethality": 0.001, "radius_km": 0.02}

func _tactical_shared_fire() -> void:
	var world: Dictionary = _tactical_env()
	var tactics: RefCounted = world.gameplay.tactics
	check(tactics.personal("soldier", "load_for_fire", {"action": "reload"}).ok and F.advance(world, 10.0).ok, "shared fire preparation")
	check(tactics.personal("soldier", "partial_fire", {"action": "fire", "target_ref": "unit_002", "seconds": 40.0}).ok and F.advance(world, 17.0).ok, "partial fire through original segment")
	var spent: float = float(tactics.weapons.soldier.spent)
	var ready: float = float(tactics.weapons.soldier.ready)
	check(spent > 0.0 and ready > 0.0 and is_equal_approx(float(world.state.totals.ammo_spent), spent), "personal fire is original single stock spend")
	var prior: Dictionary = _stocks(world)
	check(_transfer(world, "after_shots", "unit_000", "unit_001", 18.0).ok, "transfer accepted after partial personal fire")
	var firing_copy: Dictionary = F.restore_runtime(bytes_to_var(var_to_bytes(F.runtime_state(world))))
	check(firing_copy.ok, "active personal fire and pending structural handover restored")
	check(F.advance(world, 18.0).ok, "elapsed fire settled before transfer")
	check(float(tactics.weapons.soldier.spent) >= spent and float(tactics.weapons.soldier.ready) <= ready and is_equal_approx(float(_stocks(world).ammunition) + float(_stocks(world).spent), float(prior.ammunition) + float(prior.spent)), "remaining preparation carried without resupplying spent rounds")
	check(F.advance(world, 51.0).ok and tactics.weapons.soldier.unit_ref == "unit_001" and tactics.weapons.soldier.mode == "CEASE", "old fire expiry cannot reactivate source or destination")
	if firing_copy.ok:
		check(F.advance(firing_copy.env, 18.0, 7).ok and F.advance(firing_copy.env, 51.0, 7).ok and firing_copy.env.state.units == world.state.units and firing_copy.env.state.totals == world.state.totals and firing_copy.env.gameplay.tactics.weapons == tactics.weapons, "restored personal fire/handover adopts identical stock spend and casualties")
	var competition: Dictionary = _tactical_env()
	var t: RefCounted = competition.gameplay.tactics
	check(t.admit_gun("gun", "unit_000", _gun_profile()), "gun claims existing crew and equipment")
	check(t.personal("soldier", "rifle_ready", {"action": "reload"}).ok and t.gun_action("squad", "gun_deploy", {"gun_ref": "gun", "gun_action": "deploy"}).ok and F.advance(competition, 10.0).ok, "personal and gun preparations share finite stock")
	var plan: Dictionary = {"commitment": 12.0, "posture": "hold", "exposure": 1.0}
	competition.gameplay.participants.prepare(competition.state.units.unit_000, plan)
	t.prepare(competition.state.units.unit_000, plan)
	check(float(plan.commitment) <= 9.0 and t.prepared_total("unit_000") <= float(competition.state.units.unit_000.ammunition), "anonymous fire excludes named shooter and real gun crew/equipment")
	check(not t.squad("squad", "unit_000", "bad_cover", {"fire_mode": "cover_move", "node_ref": "A", "movers": ["soldier", "soldier"]}).ok, "same mover cannot occupy two cover roles")
	check(t.gun_action("squad", "direct_gun", {"gun_ref": "gun", "gun_action": "fire", "direct": true, "target_ref": "unit_002", "missions": 1}).ok and F.advance(competition, 15.0).ok, "actual prepared gun fire")
	var actual: Dictionary = _stocks(competition)
	check(is_equal_approx(float(actual.spent), float(competition.state.totals.ammo_spent)) and is_equal_approx(float(actual.casualties), float(competition.state.totals.casualties)), "gun and group adopt original spend and losses once")

func _tactical_runtime() -> void:
	var world: Dictionary = _tactical_env()
	check(world.gameplay.tactics.personal("soldier", "save_reload", {"action": "reload"}).ok and F.advance(world, 4.0).ok, "checkpoint during unfinished reload")
	var image: Dictionary = bytes_to_var(var_to_bytes(F.runtime_state(world)))
	var candidate: Dictionary = F.restore_runtime(image)
	check(candidate.ok, "candidate runtime restored without initial admissions")
	if candidate.ok:
		check(candidate.env.state.time == world.state.time and candidate.env.state.events == world.state.events and candidate.env.gameplay.tactics._tickets == world.gameplay.tactics._tickets, "clock and stable unfinished event IDs preserved")
		check(F.advance(world, 20.0, 7).ok and F.advance(candidate.env, 20.0, 7).ok, "both worlds continue same bounded action")
		check(candidate.env.state.units == world.state.units and candidate.env.state.totals == world.state.totals and candidate.env.gameplay.tactics.weapons == world.gameplay.tactics.weapons, "restoration adds no preparation resources or losses")
	var broken: Dictionary = image.duplicate(true)
	broken.gameplay.modules.tactics.weapons.soldier.ready = 10000.0
	var before_world: Dictionary = F.runtime_state(world)
	check(not F.restore_runtime(broken).ok and F.runtime_state(world) == before_world, "failed candidate leaves current authoritative world untouched")
	var session: Session = Session.new()
	var configured: bool = session.configure("A2", 71, "company", "runtime", 7)
	check(configured, "actual A assembly with professional modules")
	if not configured:
		print("A admission state: ", {"bodies": session.world.env.gameplay.participants._units, "air": session.world.env.gameplay.air.assets.keys(), "sea": session.world.env.gameplay.sea.vessels.keys(), "goals": session.world.env.gameplay._goals, "requests": session.world.env.logistics._requests, "sources": session.world.env.information._platform_sources.keys()})
		return
	advance(session, 4.0)
	var checkpoint: Dictionary = bytes_to_var(var_to_bytes(session.runtime_checkpoint()))
	var twin: Session = Session.new()
	var restored: Dictionary = twin.restore_runtime(checkpoint)
	check(restored.ok, "A session runtime and provider state restored")
	if restored.ok:
		check(twin.world.env.gameplay.air.assets.air_recon_01.stock == twin.world.env.logistics._assets.air_recon_01 and is_same(twin.world.env.gameplay.air.assets.air_recon_01.stock, twin.world.env.logistics._assets.air_recon_01), "Task6 aircraft stock alias restored")
		var path: String = ProjectSettings.globalize_path("res://experiments/war_resolver/attachment_continuity/.runtime-local-%d.bin" % Time.get_ticks_usec())
		check(session.save_runtime(path).ok and twin.load_runtime(path).ok, "native binary checkpoint file saves and restores same session")
		check(DirAccess.remove_absolute(path) == OK, "temporary local checkpoint removed")
		advance(session, 50.0)
		advance(twin, 50.0)
		check(twin.world.env.state.units == session.world.env.state.units and twin.world.env.state.totals == session.world.env.state.totals and twin.world.env.information._messages == session.world.env.information._messages, "ongoing local professional/info/decision events continue identically")
		check(twin.world.env.information._messages.report_old_inflight_report.status == "DELIVERED" and twin.world.env.information._messages.report_old_inflight_report.claims[0].observed_at == 0.0, "restored delayed report retains original observation and delivery identity")
		check(not twin.restore_runtime(broken).ok, "wrong checkpoint scope rejected")
		twin.dispose()
	session.dispose()

func _tactical_action_recovery() -> void:
	var cover_world: Dictionary = _tactical_env()
	check(F.report(cover_world, "soldier", "soldier_local", "cover", "cover_recovery", "soldier") and F.advance(cover_world, 0.0).ok, "cover recovery actual knowledge")
	check(cover_world.gameplay.tactics.squad("squad", "unit_000", "cover_order", {"fire_mode": "cover_move", "node_ref": "A", "movers": ["soldier"], "seconds": 20.0}).ok and F.advance(cover_world, 2.0).ok, "nearby actual cover movement in progress")
	var restored: Dictionary = F.restore_runtime(bytes_to_var(var_to_bytes(F.runtime_state(cover_world))))
	check(restored.ok, "cover action and its occupation restored")
	if restored.ok:
		check(F.advance(cover_world, 6.0).ok and F.advance(restored.env, 6.0).ok and cover_world.gameplay.participants._member("soldier") == restored.env.gameplay.participants._member("soldier"), "same body reaches same cover after recovery")
		check(restored.env.gameplay.tactics.fire_orders.unit_000.moving.soldier.status == "EXECUTED", "cover mover completion linked to original action ID")
	var gun_world: Dictionary = _tactical_env()
	var t: RefCounted = gun_world.gameplay.tactics
	check(t.admit_gun("runtime_gun", "unit_000", _gun_profile()) and t.gun_action("squad", "deploy_saved", {"gun_ref": "runtime_gun", "gun_action": "deploy"}).ok and F.advance(gun_world, 2.0).ok, "gun deployment pending")
	var gun_copy: Dictionary = F.restore_runtime(bytes_to_var(var_to_bytes(F.runtime_state(gun_world))))
	check(gun_copy.ok, "deployed crew preparation and event restored")
	if gun_copy.ok:
		check(F.advance(gun_world, 5.0).ok and F.advance(gun_copy.env, 5.0).ok and gun_copy.env.gameplay.tactics.guns == t.guns, "gun ready reservation created once after restored deployment")
		check(t.gun_action("squad", "shots_saved", {"gun_ref": "runtime_gun", "gun_action": "fire", "direct": true, "target_ref": "unit_002", "missions": 2}).ok and F.advance(gun_world, 12.0).ok, "gun one shot spent and next reload pending")
		var after_shot: Dictionary = F.restore_runtime(bytes_to_var(var_to_bytes(F.runtime_state(gun_world))))
		check(after_shot.ok, "unfinished gun salvo restored after actual partial expenditure")
		if after_shot.ok:
			check(F.advance(gun_world, 20.0).ok and F.advance(after_shot.env, 20.0).ok and gun_world.state.units == after_shot.env.state.units and gun_world.state.totals == after_shot.env.state.totals and t.guns == after_shot.env.gameplay.tactics.guns, "restored salvo does not repeat first shot or losses")
	var partial: Dictionary = _tactical_env()
	check(partial.gameplay.tactics.personal("soldier", "pending_save", {"action": "reload"}).ok, "pending restriction fixture")
	check(partial.lod.advance_bounded(3.0, 1).status == "PENDING" and not F.runtime_state(partial).get("ok", true), "half settlement cannot become a complete checkpoint")
	check(F.advance(partial, 3.0, 7).ok, "original bounded operation can still finish")

func _tactical_medical_recovery() -> void:
	var world: Dictionary = F.setup(71, {"personal": true, "medical_unit_stock": 2.0, "red_ammunition": 0.0})
	for mission: Dictionary in world.state.missions.values():
		mission.posture = "idle"
	check(world.gameplay.participants.admit("scout").ok and world.gameplay.medical.admit_healer("scout") and world.gameplay.tactics.admit_weapon("scout"), "existing helper equipment and medical capability")
	check(world.gameplay.tactics.personal("scout", "helper_reload", {"action": "reload"}).ok and F.advance(world, 2.0).ok, "helper reload started")
	world.gameplay.participants.external_damage("soldier", 0.1, "existing_minor_wound", "ground_fire")
	check(world.gameplay.medical.start("scout", "real_care", {"action": "aid", "patient_ref": "soldier", "mode": "stabilize", "supply_unit": "unit_001"}).ok and F.advance(world, 4.0).ok, "actual care consumes kit and interrupts weapon work")
	var image: Dictionary = bytes_to_var(var_to_bytes(F.runtime_state(world)))
	var candidate: Dictionary = F.restore_runtime(image)
	check(candidate.ok, "unfinished medical occupation and body relationship restored")
	if candidate.ok:
		check(F.advance(world, 33.0).ok and F.advance(candidate.env, 33.0).ok and world.state.units == candidate.env.state.units and world.gameplay.participants._actions == candidate.env.gameplay.participants._actions, "same care completes without repeating kit or body loss")
		check(float(candidate.env.gameplay.tactics.weapons.scout.ready) == 0.0 and candidate.env.state.units.unit_001.medical == 1.0 and candidate.env.gameplay.participants._member("soldier").treatment.status == "STABILIZED", "old reload does not complete during saved medical occupation")

func _tactical_inventory_recovery() -> void:
	var world: Dictionary = F.setup(71, {"personal": true, "motor": true, "red_ammunition": 0.0})
	for mission: Dictionary in world.state.missions.values():
		mission.posture = "idle"
	check(world.gameplay.land.admit("unit_001", 20.0), "existing motor carrier admitted for checkpoint scope")
	check(world.logistics.submit("platoon", {"id": "saved_supply", "kind": "request", "target_kind": "unit", "target": "unit_000", "resource_class": "AMMUNITION", "quantity": 6.0}).ok, "real Task6 request")
	check(world.gameplay.land.apply("company", {"operation": "transport", "unit_ref": "unit_001", "source_ref": "source", "recipient_kind": "unit", "recipient_ref": "unit_000", "target_node": "A", "approach_path": [], "path": [], "cargo": {"AMMUNITION": 6.0}, "request_ref": "saved_supply"}, "saved_land").ok and F.advance(world, 2.0).ok, "physical handling reserves original depot stock")
	var reserved: Dictionary = F.restore_runtime(bytes_to_var(var_to_bytes(F.runtime_state(world))))
	check(reserved.ok and reserved.env.logistics._reserved == world.logistics._reserved and world.logistics._reserved.source.AMMUNITION == 6.0, "Task6 source reservations restored rather than regenerated")
	if not reserved.ok:
		return
	check(F.advance(world, 40.0).ok and F.advance(reserved.env, 40.0).ok and reserved.env.logistics._deliveries == world.logistics._deliveries, "saved loading transfers depot cargo once")
	var loaded: Dictionary = F.restore_runtime(bytes_to_var(var_to_bytes(F.runtime_state(world))))
	check(loaded.ok, "loaded physical cargo continuation restored")
	if loaded.ok:
		check(F.advance(world, 78.0).ok and F.advance(loaded.env, 78.0, 7).ok and world.state.units == loaded.env.state.units and world.logistics._deliveries == loaded.env.logistics._deliveries and world.logistics._requests == loaded.env.logistics._requests, "cargo unload/front receipt not duplicated by restoration")
		check(world.logistics._requests.saved_supply.received_quantity == 6.0 and world.logistics._depots.source.stock.AMMUNITION == 94.0, "exact request receipt and single depot source debit")

func advance(session: Session, to: float) -> void:
	var row: Dictionary = session.request("advance", {"seconds": to - float(session.cache.time)})
	check(row.ok, "advance admitted")
	for index: int in range(1000000):
		if not session.world.env.state.public_pending():
			return
		row = session.request("resume", {"calls": 64})
		if not row.ok:
			break
	check(false, "advance did not complete")

func drain(session: Session) -> void:
	for index: int in range(1000000):
		if not session.world.env.state.public_pending():
			return
		check(session.request("resume", {"calls": 64}).ok, "pending resume")
	check(false, "drain bounded")

func _facts() -> Dictionary:
	var unit: Dictionary = env.state.units.unit_000
	return {"time": env.state.time, "unit": unit.duplicate(true),
		"mission": env.state.missions[unit.mission_id].duplicate(true),
		"actions": env.gameplay.participants._actions.duplicate(true),
		"members": env.gameplay.participants._units.duplicate(), "goals": env.gameplay._goals.duplicate(),
		"knowledge": env.information._knowledge.duplicate(true), "messages": env.information._messages.duplicate(true),
		"rng": env.state.random_state.duplicate(true)}

func _applying(_event: Dictionary) -> void:
	before = _facts()
	boundary_started = Time.get_ticks_usec()

func _applied(record: Dictionary) -> void:
	var neutral: bool = _facts() == before
	check(neutral, "instant structure physical/person/action/goal/knowledge neutral " + str(record.id))
	boundary_rows.append({"event": record.id, "time": record.time, "outcome": record.outcome,
		"immediate_facts_unchanged": neutral, "event_usec_with_test_copy": Time.get_ticks_usec() - boundary_started})

func bind_probe(session: Session) -> void:
	env = session.world.env
	env.structure.applying.connect(_applying)
	env.structure.transition.connect(_applied)

func unbind_probe(session: Session) -> void:
	env.structure.applying.disconnect(_applying)
	env.structure.transition.disconnect(_applied)
	before.clear()
	env = {}
	session.dispose()

func _personal(seed_value: int, quota: int) -> void:
	var session: Session = Session.new()
	check(session.configure("A1", seed_value, "soldier", "personal", quota), "personal existing session")
	bind_probe(session)
	var world_id: int = session.world.get_instance_id()
	var mission: String = str(env.state.units.unit_000.mission_id)
	var deadline: float = float(env.state.missions[mission].goal_v1.deadline)
	advance(session, 10.0)
	check(session.request("personal", {"id": "cover", "action": "take_cover"}).ok, "real personal choice")
	drain(session)
	var action: String = str(env.gameplay.participants._member("soldier").action_ref)
	var due: float = float(env.gameplay.participants._actions[action].due)
	advance(session, 12.0)
	check(env.gameplay.participants._member("soldier").state == "ENTERING", "attachment during entry")
	check(env.structure.parent("node_unit_000") == "blue_destination" and env.structure._nodes.node_unit_000.parent == "blue_platoon", "effective/permanent separated")
	check(env.gameplay.participants._actions[action].due == due, "entry completion not reset")
	check(env.state.units.unit_000.mission_id == mission and env.state.missions[mission].goal_v1.deadline == deadline, "goal identity/deadline preserved")
	check(session.cache.authority.relation.effective_parent == "blue_destination", "own permission metadata at commit")
	check(session.request("personal", {"id": "cover", "action": "take_cover"}).duplicate, "same ID after relationship stays idempotent")
	advance(session, 18.0)
	check(env.gameplay.participants._member("soldier").state == "COVERED", "same action completes")
	check(env.gameplay.participants._actions[action].due == due and env.gameplay.participants._actions[action].status == "EXECUTED", "one original completion")
	check(float(env.gameplay.participants._member("soldier").injury) > 0.0 and session.world.balanced(), "one shared injury ledger")
	advance(session, 40.0)
	check(session.request("personal", {"id": "follow", "action": "wait"}).ok, "same person next legal input")
	drain(session)
	advance(session, 50.0)
	check(env.gameplay.participants._member("soldier").state == "FOLLOWING", "return action completes")
	advance(session, 650.0)
	check(env.structure.parent("node_unit_000") == "blue_platoon", "expiry restores permanent relationship")
	check(session.world.get_instance_id() == world_id and session.actor == "soldier" and session.sid == "personal", "no new world/person/session")
	check(env.lod.work.leaf_records_materialized == 0 and env.lod._groups.size() == 2, "personal stays detailed unrelated proxies live")
	check(env.decisions.work.world_truth_reads_for_decision == 0 and session.reader.work.unit_table_scans == 0, "no truth scan")
	evidence.append({"scene": "A1", "seed": seed_value, "quota": quota, "action_due": due, "mission_id": mission,
		"person": session.cache.personal, "relationship": env.structure.relation("node_unit_000"), "ledger_balanced": session.world.balanced()})
	unbind_probe(session)

func _crossing(seed_value: int, quota: int) -> Dictionary:
	var session: Session = Session.new()
	check(session.configure("A2", seed_value, "recipient", "crossing", quota), "recipient fixed session")
	bind_probe(session)
	var mission: String = str(env.state.units.unit_000.mission_id)
	var report: Dictionary = env.information._messages.report_old_inflight_report.duplicate(true)
	advance(session, 5.0)
	check("node_unit_000" in session.cache.known_targets, "new current scope indexed")
	check(session.cache.reports.entries.is_empty(), "receiving authority does not copy old knowledge")
	check(not env.logistics._allowed("platoon", "unit", "unit_000", 2) and env.logistics._allowed("recipient", "unit", "unit_000", 2), "supply responsibility current scope")
	check(env.roles.platoon.report().get("mode", "") == "information_aware", "stale role adapter still bound")
	check(not F.command(env, "platoon", "stale_adapter", F.intent("hold", "A")).ok, "stale adapter cannot bypass authority")
	check(F.command(env, "squad", "own_squad", F.intent("hold", "A")).ok, "same squad leader keeps own authority")
	advance(session, 15.0)
	check(env.information._messages.old_inflight_command.status == "REJECTED" and env.information._messages.old_inflight_command.outcome.reason == "wrong_owner_or_layer", "issued old order denied at current delivery scope")
	check(env.state.units.unit_000.mission_id == mission, "already accepted task survives old rejection")
	advance(session, 20.0)
	check(env.information._messages.own_squad.status == "EXECUTED", "own squad delayed legal order")
	advance(session, 47.0)
	var delivered: Dictionary = env.information._messages.report_old_inflight_report
	check(delivered.recipient_ref == report.recipient_ref and delivered.created_at == report.created_at and delivered.delivery_time == report.delivery_time, "inflight report keeps concrete recipient and times")
	check(env.information.knowledge("platoon").total_matching > 0 and env.information.knowledge("recipient").total_matching == 0, "old report received without forwarding to new parent")
	advance(session, 170.0)
	check(session.request("intent", {"id": "new_order", "target": "node_unit_000", "intent": "advance", "node": "B", "path": ["AB"]}).ok, "recipient legal runtime intention")
	drain(session)
	var prior: String = str(env.state.units.unit_000.mission_id)
	advance(session, 184.0)
	check(env.state.units.unit_000.mission_id == prior, "new order not executed before delivery")
	advance(session, 185.0)
	check(env.information._messages["input_live_crossing_new_order"].status == "EXECUTED", "new order delivered under new scope")
	check(env.state.missions[env.state.units.unit_000.mission_id].goal_v1.actor == "recipient" and env.state.missions[mission].goal_v1.actor == "squad", "new issuer distinct from unchanged history")
	advance(session, 300.0)
	check(env.logistics._deliveries.finite_allocation.status == "RECEIVED" and env.logistics._deliveries.finite_allocation.receipt_time == 300.0, "stable shipment received once across relation")
	advance(session, 950.0)
	check(env.structure.parent("node_unit_000") == "blue_platoon", "automatic expiry without query")
	check(env.logistics.work.deliveries_processed == 1 and session.world.balanced(), "no duplicate receipt or resources")
	check(env.gameplay.participants._units.soldier == "unit_000", "person stable unit reference")
	var result: Dictionary = Audit.collect(session).formal
	evidence.append({"scene": "A2", "seed": seed_value, "quota": quota,
		"old_command": env.information._messages.old_inflight_command, "new_command": env.information._messages["input_live_crossing_new_order"],
		"shipment": env.logistics._deliveries.finite_allocation, "relation": env.structure.relation("node_unit_000")})
	unbind_probe(session)
	return result

func _cycles(seed_value: int, quota: int, end: float) -> Dictionary:
	var session: Session = Session.new()
	check(session.configure("A3", seed_value, "soldier", "cycles", quota), "no-input bounded cycles")
	bind_probe(session)
	var unit_ref: int = session.world.get_instance_id()
	advance(session, end)
	check(env.structure.history.size() == 12 and env.structure._attachments.is_empty(), "six attach/expiry pairs retained")
	check(env.structure.parent("node_unit_000") == "blue_platoon", "cycle relationship restored")
	check(env.gameplay.participants._units.size() == 1 and env.gameplay._goals.size() == 1 and env.lod._groups.size() == 2, "live people goals representations stay bounded")
	check(session.world.get_instance_id() == unit_ref and session.receipts.is_empty(), "autonomous events need no user reads or reset")
	check(session.world.balanced() and env.lod.work.leaf_records_materialized == 0, "repeated attach cannot restore stocks")
	var result: Dictionary = Audit.collect(session).formal
	evidence.append({"scene": "A3", "seed": seed_value, "quota": quota, "end": end,
		"structure_history": env.structure.history.size(), "live_persons": env.gameplay.participants._units.size(),
		"live_goals": env.gameplay._goals.size(), "pending": env.state.events.size(),
		"continuity_work": env.structure.continuity_work.duplicate(), "reader_work": session.reader.continuity_work.duplicate()})
	unbind_probe(session)
	return result

func _incapped() -> void:
	env = F.setup(71, {"personal": true, "npc": true, "blue_ammunition": 0.0, "red_ammunition": 7.0})
	check(env.structure.enable_attachment_continuity(), "incap continuity admitted")
	# Existing physical overkill fixture; no supplied health or injury outcome.
	for id: String in ["unit_002", "unit_003"]:
		env.state.units[id].weapon.lethality = 3.5
	check(env.gameplay.admit_standing("unit_000", "initial_hold", "squad", F.intent("hold", "A")).ok, "incap initial goal")
	check(F.report(env, "npc", "npc_local", "cover", "npc_cover", "npc") and F.advance(env, 0.0).ok, "npc lawful received cover")
	check(F.local(env, "npc", "npc_action", "take_cover").ok and F.advance(env, 30.0).ok, "same original fire incapacitates exposed person")
	check(env.gameplay.participants._member("soldier").health == 0.0 and env.gameplay.participants._member("npc").actionable, "incapacity actual dose and survivor")
	check(env.structure.submit("company", {"id": "incap_attach", "kind": "attach", "effective_time": 35.0,
		"values": {"target": "node_unit_000", "parent": "blue_destination", "until": 500.0}}).ok, "incap leaf legal attach")
	check(F.advance(env, 35.0).ok and not F.local(env, "soldier", "revive_attempt", "wait").ok, "attach cannot revive")
	check(F.command(env, "squad", "survivor_move", F.intent("withdraw", "C", ["AC"])).ok and F.advance(env, 900.0).ok, "surviving squad moves and expiry restores")
	check(env.state.units.unit_000.spatial.node == "C" and env.gameplay.participants.position("soldier") == [0.0, 0.0], "body cannot borrow moved squad position")
	check(not env.information.observe("soldier", {"id": "borrowed", "source_ref": "soldier_local", "subject_kind": "unit", "subject_ref": "unit_000", "fact_kind": "contact"}).ok, "incap observation uses own body")
	evidence.append({"scene": "incap", "person": env.gameplay.participants.view("soldier"), "group_node": env.state.units.unit_000.spatial.node, "relation": env.structure.relation("node_unit_000")})
	env.clear()

func _negative() -> void:
	env = F.setup(71, {"personal": true})
	check(env.structure.enable_attachment_continuity(), "negative opt in")
	check(env.gameplay.admit_standing("unit_000", "negative_goal", "squad", F.intent("hold", "A")).ok, "negative goal")
	var base: Dictionary = _facts()
	var requests: Array[Dictionary] = [
		{"actor": "squad", "target": "node_unit_000", "parent": "blue_destination", "time": 5.0, "until": 20.0},
		{"actor": "company", "target": "node_unit_000", "parent": "red_platoon", "time": 5.0, "until": 20.0},
		{"actor": "company", "target": "node_unit_000", "parent": "blue_company", "time": 5.0, "until": 20.0},
		{"actor": "company", "target": "node_unit_000", "parent": "node_unit_000", "time": 5.0, "until": 20.0},
		{"actor": "company", "target": "blue_platoon", "parent": "blue_destination", "time": 5.0, "until": 20.0},
		{"actor": "company", "target": "node_unit_000", "parent": "blue_destination", "time": -1.0, "until": 20.0},
		{"actor": "company", "target": "node_unit_000", "parent": "blue_destination", "time": 5.0, "until": 5.0}]
	for index: int in range(requests.size()):
		var request: Dictionary = requests[index]
		check(not env.structure.submit(request.actor, {"id": "bad_%d" % index, "kind": "attach", "effective_time": request.time,
			"values": {"target": request.target, "parent": request.parent, "until": request.until}}).ok, "invalid scope/side/layer/cycle/time rejected")
		check(_facts() == base and env.structure._attachments.is_empty() and env.lod.work.leaf_records_materialized == 0, "rejection leaves no half physical mutation")
	var pair: Array[String] = ["unit_000", "unit_001"]
	check(not env.lod.coalesce("blue_platoon", pair).ok, "personal goal coalesce guard retained")
	var allocation: Dictionary = {}
	for key: String in env.structure.stock_keys():
		allocation[key] = float(env.state.units.unit_000.get(key, 0.0)) * 0.5
	check(not env.structure.submit("company", {"id": "split", "kind": "split", "effective_time": 5.0,
		"values": {"source": "unit_000", "new_id": "fresh", "new_node": "node_fresh", "allocation": allocation}}).ok, "personal goal split guard retained")
	check(not env.structure.submit("company", {"id": "merge", "kind": "merge", "effective_time": 5.0,
		"values": {"survivor": "unit_000", "donor": "unit_001"}}).ok, "personal goal merge guard retained")
	check(env.information.issue_command("platoon", {"id": "dependency", "channel_ref": "instant",
		"command": {"id": "dependency", "kind": "coordination", "target": "node_unit_000", "values": {"posture": "hold", "release_after": 20.0}}}).ok and F.advance(env, 0.0).ok, "actual existing coordinated input")
	check(not env.structure.submit("company", {"id": "dependency_attach", "kind": "attach", "effective_time": 5.0,
		"values": {"target": "node_unit_000", "parent": "blue_destination", "until": 20.0}}).ok, "unsupported dependency explicitly denied")
	env.clear()

func _versioned_revoke() -> void:
	env = F.setup(71, {"personal": true})
	check(env.structure.enable_attachment_continuity(), "version contract enabled")
	var a: Dictionary = {"id": "a", "kind": "attach", "effective_time": 5.0, "values": {"target": "node_unit_000", "parent": "blue_destination", "until": 20.0}}
	check(env.structure.submit("company", a).ok and not env.structure.submit("company", a).ok and F.advance(env, 5.0).ok, "original request ID retained and once")
	check(env.structure.submit("company", {"id": "old_revoke", "kind": "revoke", "effective_time": 25.0, "values": {"target": "node_unit_000"}}).ok, "revoke captures original attachment")
	check(F.advance(env, 20.0).ok, "a expiry")
	check(env.structure.submit("company", {"id": "b", "kind": "attach", "effective_time": 21.0, "values": {"target": "node_unit_000", "parent": "blue_destination", "until": 50.0}}).ok and F.advance(env, 25.0).ok, "new attachment before stale revoke")
	check(env.structure._attachments.node_unit_000.id == "b" and env.structure.history[-1].outcome.error == "stale_attachment_revoke", "old revoke cannot erase b")
	check(env.structure.submit("company", {"id": "real_revoke", "kind": "revoke", "effective_time": 26.0, "values": {"target": "node_unit_000"}}).ok and F.advance(env, 26.0).ok, "real current revoke")
	check(env.structure.submit("company", {"id": "c", "kind": "attach", "effective_time": 27.0, "values": {"target": "node_unit_000", "parent": "blue_destination", "until": 70.0}}).ok and F.advance(env, 50.0).ok, "new attachment crosses old expiry")
	check(env.structure._attachments.node_unit_000.id == "c" and env.structure.history[-1].outcome.kind == "stale_expiry_noop", "stale expiry does not erase c")
	check(not env.structure.submit("company", {"id": "overlap", "kind": "attach", "effective_time": 55.0,
		"values": {"target": "node_unit_000", "parent": "blue_platoon", "until": 80.0}}).ok, "overlap denied")
	evidence.append({"scene": "versions", "history": env.structure.history.duplicate(true), "relation": env.structure.relation("node_unit_000")})
	env.clear()

func _pending() -> void:
	var session: Session = Session.new()
	check(session.configure("A2", 71, "company", "pending", 1), "pending company fixed")
	check(session.request("attach", {"id": "first", "target": "node_unit_000", "parent": "blue_destination", "delay": 5.0, "duration": 100.0}).ok, "runtime attachment accepted")
	drain(session)
	check(session.receipts.first.status == "STRUCTURE_SCHEDULED" and session.world.env.structure.parent("node_unit_000") == "blue_platoon", "scheduled not executed")
	check(session.request("attach", {"id": "first", "target": "node_unit_000", "parent": "blue_destination", "delay": 5.0, "duration": 100.0}).duplicate, "runtime duplicate ID")
	check(not session.request("attach", {"id": "first", "target": "node_unit_000", "parent": "blue_destination", "delay": 6.0, "duration": 100.0}).ok, "conflict ID")
	var previous: Dictionary = session.cache.duplicate(true)
	var checkpoint: Dictionary = session.runtime_checkpoint()
	check(session.request("advance", {"seconds": 6.0}).ok and session.world.env.state.public_pending(), "bounded actual pending")
	check(not session.runtime_checkpoint().get("ok", true) and not session.restore_runtime(checkpoint).ok, "pending session refuses save and candidate installation")
	check(session.request("look", {}).person == previous, "pending returns previous complete view")
	check(not session.request("revoke", {"id": "retry", "target": "node_unit_000", "delay": 1.0}).ok, "pending writes refused")
	drain(session)
	check(session.cache.time == 6.0 and session.receipts.first.status == "STRUCTURE_APPLIED", "ready complete relationship receipt")
	check(session.request("revoke", {"id": "early", "target": "node_unit_000", "delay": 1.0}).ok, "early ID is recorded")
	drain(session)
	check(session.receipts.early.status == "INPUT_REJECTED", "cooldown not reset by attach")
	check(not session.handle({"session": "old", "seq": 1, "op": "look", "args": {}}).ok, "old session denied")
	advance(session, 300.0)
	check(session.request("attach", {"id": "again", "target": "node_unit_000", "parent": "blue_destination", "delay": 5.0, "duration": 500.0}).ok, "later lawful attach")
	drain(session)
	advance(session, 600.0)
	check(session.request("revoke", {"id": "revoke", "target": "node_unit_000", "delay": 5.0}).ok, "same Task8 runtime revoke")
	drain(session)
	advance(session, 605.0)
	check(session.receipts.revoke.status == "STRUCTURE_REVOKED" and session.world.env.structure.parent("node_unit_000") == "blue_platoon", "runtime revoke effective")
	session.dispose()
