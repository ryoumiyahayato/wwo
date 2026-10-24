extends "res://practice/replay.gd"
## Clicks the actual GUI. Physics, authority, visibility, report and adoption stay in their owners.
func wait_for(kind: String) -> bool:
	for i: int in 9000:
		var d: Dictionary=host.world.military_state.duty_operations
		var o: Dictionary=d.orders.values().back() if not d.orders.is_empty() else {}
		if not host.busy and not host.unsaved:
			if kind=="checkpoint" and host.checkpoint_pause:return true
			if o.get("phase")==kind:return true
		await frames(1)
	return check(false,"duty_timeout_"+kind)
func run() -> void:
	Input.use_accumulated_input=false;get_viewport().notify_mouse_entered()
	await frames(45);await host.capture("entry")
	var d: Dictionary=host.world.military_state.duty_operations
	var f: VNextMilitaryFormation=host.world.military_state.get_formation(d.unit)
	if not check(host.world.person_overlay.person_count()==2 and f.personnel==0 and f.named_personnel.members.size()==2 and not f.can_receive_orders() and f.apply_losses(1)==0,"named_people_disjoint_from_aggregate_combat"):return
	var denied: Dictionary=host.service.authorize("issue",load("res://custody/scenario.gd").context(host.world,"inspect"))
	if not check(not denied.ok,"quartermaster_is_not_duty_commander"):return
	if host.tour in ["outbound","complete","repeat"]:
		var target: Vector3=d.mapping.plans.values()[0].target_position
		var blocked: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(host.leader.position+Vector3(0,1.5,0),target,9))
		if not check(not blocked.is_empty() and blocked.collider.get_meta("duty_target_id","")=="","initial_road_target_hidden_by_actual_wall"):return
		host.last_result={"initial_direct_ray_obstructed":true,"distance":(host.leader.position+Vector3(0,1.5,0)).distance_to(blocked.position)};host.record("actual_wall_occlusion")
		await click("issue")
		if not check(not host.simulation.advance_minutes(1).get("success",true),"unowned_world_time_refused_during_duty"):return
		if host.tour in ["complete","repeat"]:
			if not await wait_for("REPORTED"):return
			var completed: Dictionary=d.orders.values().back()
			if not check(completed.elapsed_usec>=60000000 and not completed.report.is_empty(),"repeatable_cross_minute_duty"):return
			await click("duplicate")
			if not check(host.last_result.get("duplicate",false) and host.last_result.state_exact,"repeated_task_receipt_exact"):return
			host.record("sustained_duty_complete");await host.capture("sustained_complete");await click("leave");return
		if not await wait_for("checkpoint"):return
		var o: Dictionary=host.service.current()
		if not check(o.phase=="OUTBOUND" and o.physics_steps>=600 and o.observation.is_empty() and o.report.is_empty() and o.elapsed_usec>=20000000,"outbound_real_physics_checkpoint"):return
		host.record("outbound_checkpoint_before_exit");await host.capture("midroute_no_report");await click("leave");return
	if host.tour=="resume":
		var o: Dictionary=host.service.current()
		if not check(host.paused and o.phase=="OUTBOUND" and o.elapsed_usec>=20000000 and o.observation.is_empty(),"cold_route_restored_without_teleport_or_report"):return
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false) and host.last_result.state_exact,"cold_midroute_duplicate_no_time"):return
		await click("resume")
		if not await wait_for("REPORTED"):return
		var result: Dictionary=d.orders.values().back()
		if not check(host.world.game_clock.total_minutes()>=1 and result.elapsed_usec>=60000000 and not result.report.is_empty() and d.active.is_empty(),"real_cross_minute_report_and_adoption"):return
		await host.capture("real_report_world_minute")
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false) and host.last_result.state_exact,"duplicate_no_economy_or_time"):return
		host.record("completed_once");await click("leave");return
	if host.tour in ["failure","failure-cold"]:
		if host.tour=="failure":
			await click("revoke");await click("resume")
			if not await wait_for("BLOCKED"):return
		var o: Dictionary=host.service.current()
		if not check(o.phase=="BLOCKED" and o.report.is_empty() and o.failure.reason=="DUTY_PERMISSION_DENIED" and not d.active.is_empty(),"revoked_duty_stays_incomplete"):return
		host.record("revoked_failure_preserved");await host.capture("revoked_not_completed");await click("leave");return
	# Completed cold entry and repeated local/global handoffs.
	var o: Dictionary=d.orders.values().back()
	if not check(o.phase=="REPORTED" and not o.report.is_empty() and d.active.is_empty() and host.world.game_clock.total_minutes()>=1,"complete_cold_identity_report_time"):return
	await click("duplicate")
	if not check(host.last_result.get("duplicate",false) and host.last_result.state_exact,"completed_cold_duplicate_exact"):return
	host.record("completed_cold_preserved");await host.capture("completed_cold");await click("leave")
