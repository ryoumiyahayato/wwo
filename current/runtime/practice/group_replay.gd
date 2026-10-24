extends "res://practice/replay.gd"
const State = preload("res://scripts/vnext/military/military_training_state.gd")
## Native GUI/key events. Completion requires the real body's collision movement, visibility ray and face to face report.
func wait_status(status: String) -> bool:
	for i: int in 2400:
		if host.world.military_state.training_group.order.get("status")==status and not host.busy and not host.unsaved:return true
		await frames(1)
	return check(false,"group_execution_timeout_"+status)

func run() -> void:
	Input.use_accumulated_input=false;get_viewport().notify_mouse_entered()
	await frames(45);await host.capture("group_entry")
	if not check(host.group_view!=null and host.world.person_overlay.person_count()==2,"two_legitimate_formal_persons"):return
	var d: Dictionary=host.world.military_state.training_group
	var qm_only: Dictionary=host.group_view.service.authorize("issue",host.custody_context("inspect"))
	if not check(not qm_only.ok,"quartermaster_not_training_leader"):return
	host.record("quartermaster_training_order_denied")
	if host.tour_mode=="group-inspect":
		if not check(d.order.status=="REPORTED" and host.service.view().lot.available==18 and host.service.view().lot.issued==0 and host.service.view().lot.consumed==2,"recovered_source_report_and_final_budget"):return
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false) and host.actor.shot_sequence==2,"source_restore_no_second_adoption"):return
		host.record("group_recoverable_source_cold_verified");host.write_rows();await host.capture("source_restored_group")
		await click("save");await click("safeexit");return
	if host.tour_mode=="group":
		if not check(d.order.is_empty() and d.position==State.HOME,"fresh_unarmed_observer"):return
		await key(KEY_E)
		# Actual aim/movement input points the existing muzzle at the formal NPC.
		# This must be rejected before ammo commit; a person cannot become a synthetic target.
		var rate: int=30 if OS.get_cmdline_user_args().has("--practice-movie") else 60
		await key(KEY_A,rate);await key(KEY_S,int(rate*2.5));await key(KEY_LEFT,rate);await key(KEY_F)
		if not check(host.last_result.get("equipment_reason")=="FORMAL_PERSON_NOT_A_TRAINING_TARGET" and host.actor.shot_sequence==0 and host.service.view().lot.issued==6 and host.service.view().lot.consumed==0,"formal_npc_not_a_synthetic_target"):return
		host.record("formal_npc_target_refused_before_ammo_commit");await host.capture("formal_npc_not_a_target")
		await key(KEY_D,rate);await key(KEY_W,int(rate*2.5));await key(KEY_RIGHT,rate)
		await click("order")
		if not check(await wait_status("RETURNING"),"physical_observation"):return
		d=host.world.military_state.training_group
		if not check(d.order.report.is_empty() and host.group_view.paused_for_resume and d.physics_steps>200,"not_omniscient_before_report"):return
		host.record("group_checkpoint_private_observation");host.write_rows()
		await host.capture("observer_at_point_no_report")
		await click("export");await click("safeexit");return
	if host.tour_mode=="group-resume":
		if not check(d.order.status=="RETURNING" and d.order.report.is_empty() and host.group_view.paused_for_resume,"cold_mid_order_restored"):return
		host.record("group_cold_mid_order_exact")
		await click("recover");await click("group_resume")
		if not check(await wait_status("REPORTED"),"physical_return_and_face_to_face_report"):return
		await host.capture("report_received")
		if not check(host.world.military_state.training_group.order.report.channel=="FACE_TO_FACE_LOS_5M","limited_report_channel"):return
		await key(KEY_F)
		if not check(host.service.view().lot.consumed==1,"group_same_world_first_native_shot"):return
		await key(KEY_F)
		if not check(host.service.view().lot.consumed==1,"group_empty_chamber_refused"):return
		await key(KEY_R);await key(KEY_RIGHT,30);await key(KEY_F)
		if not check(host.service.view().lot.consumed==2 and host.actor.shot_sequence==2,"group_same_world_second_native_shot"):return
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false),"group_duplicate_does_not_spend"):return
		host.record("group_report_and_finite_4_plus_2");host.write_rows()
		await host.capture("group_report_two_shots")
		await click("export");await click("safeexit");return
	if not check(d.order.status=="REPORTED" and d.order.report.id==State.ORDER+":report:1" and host.service.view().lot.issued==4 and host.service.view().lot.consumed==2,"group_report_and_resources_cold_exact"):return
	host.record("group_final_cold_exact");await host.capture("group_final_cold")
	await click("recover");await click("duplicate")
	if not check(host.last_result.get("duplicate",false) and host.actor.shot_sequence==2,"group_cold_duplicate_no_replay"):return
	await click("return")
	if not check(host.service.view().lot.available==18 and host.service.view().lot.issued==0 and host.service.view().lot.consumed==2,"group_final_18_plus_2"):return
	await host.capture("group_legal_return");await click("export");await click("safeexit")
