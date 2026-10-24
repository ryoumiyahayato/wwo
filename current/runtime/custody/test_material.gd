extends SceneTree
const Scenario = preload("res://custody/scenario.gd")
const MaterialLedger = preload("res://scripts/vnext/military/military_material_state.gd")
const Service = preload("res://scripts/vnext/military/military_material_service.gd")
const NativeUse = preload("res://custody/native_use.gd")
const Authority = preload("res://formal_link/authority.gd")
var rows: Array=[]
var failures: Array=[]
var observations: Dictionary={}
var built: WorldBuildResult
var service: RefCounted

func _initialize() -> void:call_deferred("run")
func check(ok: bool,name: String) -> void:
	rows.append({"case":name,"passed":ok})
	if not ok:failures.append(name);push_error(name)
func ctx(kind: String) -> Dictionary:return Scenario.context(built.world,kind)
func cmd(kind: String,payload: Dictionary) -> Dictionary:return service.command(kind,ctx(kind),payload)
func active() -> String:return service.view().asset.lease_id
func unchanged_rejection(result: Dictionary,before: Dictionary,name: String) -> void:
	check(not result.get("ok",false) and built.world.military_state.material_registry==before,name)

func run() -> void:
	if "--material-crash" in OS.get_cmdline_user_args():await crash_writer();return
	if "--material-resume" in OS.get_cmdline_user_args():resume_crash();return
	if "--material-read-final" in OS.get_cmdline_user_args():read_final();return
	var original:=WorldBootstrap.new().build()
	check(original.success and original.world.military_state.material_registry.is_empty(),"old_world_does_not_mint_a_registry")
	check(original.world.military_state.snapshot().schema_id=="vnext_military_state_v3" and original.world.military_state.snapshot().size()==13,"unused_v3_shape_is_exact")
	built=Scenario.create_new();check(built.success,"explicit_fresh_scenario_creates_sources_and_roles")
	if not built.success:observations.error=built.error;finish();return
	service=Service.new();check(service.bind(built.world,built.persistence),"material_service_binds_real_world_owners")
	var w:=built.world;var c:=MaterialLedger.config()
	var economy_before: Dictionary=w.economy_state.get_persistent_state();var ledger_before:=w.ledger_state.snapshot();var minute_before:=w.game_clock.total_minutes()
	check(w.military_state.snapshot().schema_id=="vnext_military_state_v6_material","explicit_v6_version_when_materials_exist")
	check(service.view().asset.asset_id==c.asset_id and service.view().lot.registered==20,"one_serialized_rifle_and_twenty_scenario_rounds")
	check(MaterialLedger.references_error(w).is_empty(),"source_owner_place_and_authority_references_resolve")
	var before: Dictionary=w.military_state.material_registry.duplicate(true)
	unchanged_rejection(MaterialLedger.append(before,before.events[0]),before,"duplicate_source_event_rejected")
	var unknown:=before.duplicate(true);unknown.events[0].payload.source_kind="historical_inventory"
	check(not MaterialLedger.error(unknown).is_empty(),"unbacked_source_import_rejected")
	unknown=before.duplicate(true);unknown.view.lot.available=21
	check(not MaterialLedger.error(unknown).is_empty(),"stored_inventory_roll_forward_rejected")
	unknown=before.duplicate(true);unknown.events[0].payload.model_id="user_heavy_mbt"
	check(not MaterialLedger.error(unknown).is_empty(),"modern_tank_cannot_rename_into_1900_source")
	var denied:=ctx("reserve");denied.appointment_id=""
	unchanged_rejection(service.command("reserve",denied,{"quantity":6}),before,"known_player_without_post_cannot_reserve")
	unchanged_rejection(cmd("reserve",{"quantity":21}),before,"insufficient_stock_rejected_without_mutation")
	unchanged_rejection(cmd("reserve",{"quantity":-1}),before,"negative_quantity_rejected_without_mutation")
	check(cmd("reserve",{"quantity":6}).ok,"authorized_quartermaster_reserves_exact_stock")
	check(service.view().lot.available==14 and service.view().lot.reserved==6,"reservation_is_not_a_second_inventory")
	before=w.military_state.material_registry.duplicate(true)
	unchanged_rejection(cmd("reserve",{"quantity":1}),before,"competing_request_cannot_hold_same_serialized_object")
	var training:=FormalLocalSession.new();training.bind(w,built.simulation_step,built.persistence)
	check(not training.issue(w.player_state.player_id()).ok,"training_cannot_start_over_active_formal_custody")
	check(cmd("issue",{"lease_id":active()}).ok,"reserved_stock_issued_to_single_person")
	var requested: Dictionary=service.request_use(ctx("use"),active())
	check(requested.ok,"existing_authorization_owner_allows_material_use")
	var used: Dictionary=NativeUse.consume_once(requested.request)
	check(used.ok,"original_native_ammo_owner_commits_one_round")
	check(service.adopt_use(ctx("use"),used.receipt).ok,"military_owner_adopts_consumption_once")
	check(service.view().lot.issued==5 and service.view().lot.consumed==1 and service.view().lot.available==14,"consumed_round_leaves_custodian_and_stays_consumed")
	before=w.military_state.material_registry.duplicate(true)
	var again: Dictionary=service.adopt_use(ctx("use"),used.receipt)
	check(again.get("duplicate",false) and w.military_state.material_registry==before,"identical_receipt_is_idempotent")
	var forged: Dictionary=used.receipt.duplicate(true);forged.after.sequence=99
	unchanged_rejection(service.adopt_use(ctx("use"),forged),before,"conflicting_duplicate_receipt_rejected")
	var saved: SaveOperationResult=await built.persistence.save_to_user_async(4)
	observations.save_result={"success":saved.success,"message":saved.message}
	print("MATERIAL_SAVE_RESULT "+JSON.stringify(observations.save_result))
	check(saved.success,"issued_native_state_saved_by_original_atomic_persistence")
	var loaded:=FormalPersistence.new().load_from_user(4)
	check(loaded.success and loaded.world.military_state.material_registry==before,"cold_restore_preserves_source_custody_and_partial_consumption")
	if loaded.success:
		var fresh:=Service.new();fresh.bind(loaded.world,loaded.persistence)
		check(not fresh.request_use(Scenario.context(loaded.world,"use"),active()).ok,"new_runtime_must_explicitly_recover_an_issued_lease")
		var recovered: Dictionary=fresh.command("recover",Scenario.context(loaded.world,"recover"),{"lease_id":active()})
		check(recovered.ok and fresh.view().lot==service.view().lot,"recovery_changes_executor_without_refill_or_consumption")
		unchanged_rejection(service.adopt_use(ctx("use"),forged),before,"old_conflicting_receipt_still_rejected_after_other_copy_recovers")
	check(cmd("cancel",{"lease_id":active(),"reason":"controlled_cancel_after_use"}).ok,"cancel_after_use_returns_only_unspent_rounds")
	check(service.view().lot.available==19 and service.view().lot.consumed==1 and service.view().lot.cumulative_returned==5,"cancel_never_rewinds_a_consumed_round")
	check(cmd("reserve",{"quantity":2}).ok and cmd("cancel",{"lease_id":active(),"reason":"cancel_before_issue"}).ok,"cancel_reserved_only_restores_reserved_quantity")
	check(service.view().lot.available==19 and service.view().lot.cumulative_issued==6,"cancel_before_issue_does_not_invent_issued_flow")
	check(cmd("reserve",{"quantity":3}).ok and cmd("issue",{"lease_id":active()}).ok,"second_legitimate_issue_uses_remaining_source")
	before=w.military_state.material_registry.duplicate(true)
	unchanged_rejection(cmd("transfer",{"owner_id":c.receiver_id,"place_id":c.place_id,"reason":"attempt_while_issued"}),before,"cannot_transfer_owned_asset_under_an_active_lease")
	check(cmd("return",{"lease_id":active(),"reason":"normal_depot_return"}).ok,"return_closes_lease_and_restores_source_stock")
	check(cmd("transfer",{"owner_id":c.receiver_id,"place_id":c.place_id,"reason":"documented_kit_transfer"}).ok,"available_kit_transfers_to_one_registered_owner")
	check(service.view().asset.owner_id==c.receiver_id and service.view().lot.owner_id==c.receiver_id,"rifle_and_source_lot_share_exactly_one_new_owner")
	before=w.military_state.material_registry.duplicate(true)
	var wrong:=Scenario.context(w,"reserve",c.owner_id)
	unchanged_rejection(service.command("reserve",wrong,{"quantity":1}),before,"prior_owner_grant_cannot_spend_transferred_assets")
	check(cmd("reserve",{"quantity":3}).ok and cmd("issue",{"lease_id":active()}).ok,"new_owner_scoped_grant_can_issue")
	check(cmd("inspect",{"lease_id":active(),"condition":80,"reason":"controlled_inspection"}).ok,"documented_damage_is_preserved_without_hit_solver")
	before=w.military_state.material_registry.duplicate(true)
	unchanged_rejection(cmd("inspect",{"lease_id":active(),"condition":100,"reason":"unbacked_repair"}),before,"unsourced_repair_cannot_reset_condition")
	check(cmd("loss",{"lease_id":active(),"reason":"controlled_loss_fixture"}).ok,"loss_closes_lease_and_preserves_owner_responsibility")
	check(service.view().asset.status=="lost" and service.view().asset.condition==0 and service.view().lot.available==16 and service.view().lot.lost==3 and service.view().lot.consumed==1,"registered_twenty_equals_sixteen_available_one_spent_three_lost")
	check(service.view().asset.owner_id==c.receiver_id and service.view().asset.holder_id=="" and service.view().asset.location_basis=="last_known_at_loss","lost_asset_retains_owner_responsibility_without_false_current_holder")
	before=w.military_state.material_registry.duplicate(true)
	unchanged_rejection(cmd("reserve",{"quantity":1}),before,"lost_serialized_asset_cannot_be_reissued")
	var assessment:=Authority.assess(w,w.player_state.player_id())
	check(assessment.material_registry_present and not assessment.formal_combat_ready,"registry_ready_does_not_open_formal_combat")
	check(MaterialLedger.error(before).is_empty(),"whole_resource_journal_replays_to_exact_projection")
	var snapshot:=built.persistence.snapshot();var damaged:=snapshot.duplicate(true);damaged.military_state.material_registry.view.lot.consumed=0
	check(not built.persistence.restore_candidate(damaged).success and built.persistence.snapshot()==snapshot,"corrupt_material_restore_is_atomic_and_does_not_touch_live_world")
	damaged=snapshot.duplicate(true);damaged.military_state.schema_id="vnext_military_state_v999"
	check(not built.persistence.restore_candidate(damaged).success,"unknown_future_military_version_rejected")
	damaged=snapshot.duplicate(true);damaged.military_state.material_registry.events[-1].minute=w.game_clock.total_minutes()+1
	check(not built.persistence.restore_candidate(damaged).success and built.persistence.snapshot()==snapshot,"material_event_cannot_exceed_formal_clock")
	check(w.organization_state.revoke_authority(Scenario.authority_id(c.receiver_id,"reserve"),w.game_clock.current_hour()),"material_charter_is_revocable_by_existing_owner")
	before=w.military_state.material_registry.duplicate(true)
	var revoked:=cmd("reserve",{"quantity":1})
	check(not revoked.ok and revoked.reason=="MATERIAL_PERMISSION_DENIED" and w.military_state.material_registry==before,"revoked_grant_cannot_reserve_even_for_known_player")
	var before_material:=w.military_state.material_registry.duplicate(true)
	var request:=training.issue(w.player_state.player_id())
	check(request.ok and request.request.native_ammo.vehicles.player_vehicle.primary.capacity==40,"same_world_retains_separate_forty_round_training_vehicle")
	check(w.military_state.material_registry==before_material,"training_allocation_does_not_mint_or_use_formal_stock")
	training.interrupt(request.request.lease_id)
	check(w.military_state.material_registry==before_material,"training_interruption_does_not_restore_formal_losses")
	check(w.economy_state.get_persistent_state()==economy_before and w.ledger_state.snapshot()==ledger_before and w.game_clock.total_minutes()==minute_before,"custody_commands_do_not_modify_economy_ledger_or_formal_time")
	observations.final_view=service.view();observations.save_costs=built.persistence.last_save_costs
	finish()

func crash_writer() -> void:
	built=Scenario.create_new();service=Service.new();service.bind(built.world,built.persistence)
	cmd("reserve",{"quantity":6});cmd("issue",{"lease_id":active()})
	var requested: Dictionary=service.request_use(ctx("use"),active());var used: Dictionary=NativeUse.consume_once(requested.request)
	service.adopt_use(ctx("use"),used.receipt)
	var saved:=built.persistence.save_to_user(3)
	if not saved.success:push_error(saved.message);quit(1);return
	cmd("cancel",{"lease_id":active(),"reason":"uncommitted_cancel"})
	var doc:=FormalWorldPersistenceDocument.encode(built.persistence.snapshot(),built.persistence._save_metadata)
	var thread:=Thread.new();thread.start(func() -> String:return AtomicJsonFileStore.write_verified(FormalPersistence.slot_path(3),doc,Callable(self,"hold"),true))
	while thread.is_alive():await process_frame
	thread.wait_to_finish();quit(2)

func hold(path: String) -> String:
	print("MATERIAL_TEMP_BEFORE_COMMIT pid=%d path=%s"%[OS.get_process_id(),path]);OS.delay_msec(30000);return "INTERRUPTION_NOT_COMMITTED"

func resume_crash() -> void:
	built=FormalPersistence.new().load_from_user(3);check(built.success,"interrupted_material_save_keeps_valid_prior_primary")
	if built.success:
		service=Service.new();service.bind(built.world,built.persistence);var v: Dictionary=service.view()
		check(v.lot.available==14 and v.lot.issued==5 and v.lot.consumed==1,"uncommitted_cancel_cannot_erase_custody_or_spent_round")
		check(not service.request_use(ctx("use"),active()).ok,"crash_keeps_explicit_executor_recovery_requirement")
		check(cmd("recover",{"lease_id":active()}).ok,"authorized_recovery_preserves_partial_native_state")
		observations.recovered_view=service.view()
	finish()

func read_final() -> void:
	built=FormalPersistence.new().load_from_user(2);check(built.success,"new_process_reads_final_v6_formal_save")
	if built.success:
		var v: Dictionary=built.world.military_state.material_registry.view
		check(v.asset.status=="lost" and v.lot.available==13 and v.lot.consumed==1 and v.lot.lost==6,"cold_final_owner_and_conservation_preserved")
		check(v.asset.owner_id==MaterialLedger.config().receiver_id and MaterialLedger.references_error(built.world).is_empty(),"cold_owner_and_event_references_resolve")
		observations.final_view=v
		observations.material_payload_bytes=var_to_bytes(built.world.military_state.material_registry).size()
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--before-custody-save="):
				var old_doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--before-custody-save=")))
				var old: Dictionary=FormalWorldPersistenceDocument.decode(old_doc)
				check(old.get("success",false) and old.snapshot.military_state.material_registry==built.world.military_state.material_registry,"actual_native_training_keeps_entire_formal_material_registry_exact")
		var id:=built.world.player_state.player_id()
		var participant: Dictionary=built.world.military_state.local_operations.get("participants",{}).get(id,{})
		if not participant.is_empty():
			var pool: Dictionary=participant.local.native_ammo.vehicles.player_vehicle.primary
			observations.training={"remaining":int(pool.capacity)-int(pool.spent),"shots":participant.local.shot_sequence,"adoptions":participant.adoption_count,"pending_usec":participant.pending_usec,"world_minute":built.world.game_clock.total_minutes()}
			check(observations.training.remaining==39 and observations.training.shots==1,"same_world_native_training_uses_its_own_forty_round_source")
	finish()

func finish() -> void:
	FileAccess.open("user://material_contract_results.json",FileAccess.WRITE).store_string(JSON.stringify({"source":"CONTROLLED_NEW_SCENARIO_CONTRACT_TESTS_NOT_HISTORICAL_STOCK_OR_BALLISTICS","rows":rows,"failures":failures,"observations":observations},"\t"))
	print("MATERIAL_CONTRACT_FINISHED "+JSON.stringify({"cases":rows.size(),"failures":failures}));quit(0 if failures.is_empty() else 1)
