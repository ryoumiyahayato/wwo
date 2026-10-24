extends "res://practice/replay.gd"
## Native input replay. No direct calls to material commands or shot emission.
func run() -> void:
	Input.use_accumulated_input=false
	await frames(45);await host.capture("entry")
	if host.tour_mode=="frozen":
		if not check(host.pending_native_blocked,"frozen_boundary_detected"):return
		await click("recover")
		if not check(host.pending_native_blocked,"uncertain_boundary_stays_frozen"):return
		await click("diagnostic");await host.capture("frozen_diagnosis")
		await click("safeexit");return
	if host.tour_mode=="recover":
		if OS.get_cmdline_user_args().has("--revoke-before-recovery"):await click("revoke")
		await click("recover")
		if not check(not host.pending_native_blocked and host.service.view().lot.consumed==1,"same_event_recovered"):return
		if not check(host.actor.shot_sequence==1,"no_native_replay"):return
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false),"recovered_event_duplicate"):return
		await host.capture("recovered_once")
		await click("return");await click("export");await click("safeexit");return
	if host.tour_mode=="before":
		await click("recover")
		if not check(host.service.view().lot.consumed==0 and host.service.view().lot.issued==6 and host.actor.shot_sequence==0,"not_emitted_no_spend"):return
		await click("return");await click("safeexit");return
	if host.tour_mode=="continue":
		if not check(host.service.view().lot.issued==4 and host.service.view().lot.consumed==2,"cold_finite_budget"):return
		await click("recover")
		if not check(host.service.view().lot.issued==4 and host.actor.shot_sequence==2,"cold_no_refill_or_replay"):return
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false),"cold_duplicate"):return
		await click("return")
		if not check(host.service.view().lot.available==18 and host.service.view().lot.issued==0 and host.service.view().lot.consumed==2,"four_returned_18_plus_2"):return
		await host.capture("cold_legal_return");await click("export");await click("safeexit");return
	await key(KEY_E)
	if host.busy:return # A real kill boundary deliberately holds this process.
	if not check(host.service.view().lot.issued==6,"finite_six_issued"):return
	await key(KEY_B);await frames(8);await key(KEY_F)
	if not check(host.service.view().lot.consumed==0 and host.actor.shot_sequence==0,"blocked_muzzle"):return
	await key(KEY_B);await key(KEY_W,20);await key(KEY_F)
	if host.busy or OS.get_cmdline_user_args().has("--practice-hold-after-native"):return
	if not check(host.service.view().lot.consumed==1,"first_real_shot"):return
	await key(KEY_F)
	if not check(host.service.view().lot.consumed==1,"empty_chamber_refused"):return
	await key(KEY_R);await key(KEY_RIGHT,30);await frames(20);await key(KEY_F)
	if not check(host.service.view().lot.consumed==2 and host.service.view().lot.issued==4 and host.actor.shot_sequence==2,"second_real_shot"):return
	var last: Dictionary=host.last_receipt.physical
	if not check(last.hit_id in ["practice_target:backstop",""],"second_shot_backstop_or_legal_miss"):return
	await click("duplicate")
	if not check(host.last_result.get("duplicate",false) and host.service.view().lot.consumed==2,"duplicate_does_not_spend"):return
	await host.capture("two_shots_four_remaining");await click("export");await click("safeexit")
