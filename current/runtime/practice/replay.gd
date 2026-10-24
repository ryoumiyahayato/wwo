extends Node
## Real engine input events. No direct equipment/shot/state commands in the replay.
var host: Node3D

func frames(count: int) -> void:
	for i: int in count:
		if not is_inside_tree():return
		await get_tree().process_frame

func key(code: int, duration: int=1) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=pressed;Input.parse_input_event(event)
		await frames(duration if pressed else 2)
	while is_instance_valid(host) and host.busy:await get_tree().process_frame
	await frames(3)

func click(name_value: String) -> void:
	var before_rows: int=host.rows.size()
	var position_value: Vector2=(host.buttons[name_value] as Button).get_global_rect().get_center()
	var move:=InputEventMouseMotion.new();move.position=position_value;move.global_position=position_value;get_viewport().push_input(move,true);await frames(2)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=position_value;event.global_position=position_value;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;get_viewport().push_input(event,true)
		if not pressed and name_value in ["leave","safeexit"]:return
		await frames(2)
	while is_instance_valid(host) and host.busy:await get_tree().process_frame
	await frames(4)
	# Desktop pointer motion can cancel a synthetic press/release across frames.
	# Retry through the actual focused GUI keyboard path, never the domain action.
	if is_instance_valid(host) and host.rows.size()==before_rows:
		(host.buttons[name_value] as Button).grab_focus()
		await key(KEY_ENTER)

func check(value: bool, reason: String) -> bool:
	if value:return true
	push_error("PRACTICE_REPLAY_FAILED "+reason);host.record("replay_failed_"+reason);host.write_rows();get_tree().quit(1);return false

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	Input.use_accumulated_input=false;get_viewport().notify_mouse_entered()
	await frames(45);await host.capture("entry")
	if host.tour_mode=="pending":
		if not check(host.pending_native_blocked and host.service.view().lot.consumed==0 and host.service.view().lot.issued==6,"pending_native_not_replayed_or_refilled"):return
		await key(KEY_F)
		if not check(host.service.view().lot.consumed==0 and host.pending_native_blocked,"pending_native_blocks_new_fire"):return
		host.record("pending_native_cold_fail_closed");host.write_rows();print("PRACTICE_PENDING_NATIVE_BOUNDARY_FINISHED");get_tree().quit();return
	if host.tour_mode=="new":
		await key(KEY_E)
		if not check(host.service.view().lot.issued==6,"issued_six"):return
		await host.capture("formal_person_sourced_rifle")
		await key(KEY_B);await frames(8);await key(KEY_F)
		if not check(host.last_result.get("reason")=="barrel_obstructed" and host.service.view().lot.consumed==0 and host.actor.shot_sequence==0,"blocked_muzzle_no_consumption"):return
		host.record("blocked_muzzle_no_consumption");await host.capture("muzzle_blocked")
		await key(KEY_B);await key(KEY_W,20);await key(KEY_A,9);await key(KEY_RIGHT,8);await key(KEY_LEFT,8);await frames(20)
		await key(KEY_F)
		if "--practice-hold-after-native" in OS.get_cmdline_user_args():return
		if not check(host.service.view().lot.consumed==1 and host.service.view().lot.issued==5 and host.actor.shot_sequence==1,"one_native_physical_shot"):return
		await host.capture("physical_shot_and_single_adoption")
		await key(KEY_F)
		if not check(host.last_result.get("equipment_reason")=="loading" and host.service.view().lot.consumed==1 and host.actor.shot_sequence==1,"unloaded_chamber_no_second_consumption"):return
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false) and host.service.view().lot.consumed==1,"duplicate_no_consumption"):return
		await host.capture("duplicate_receipt_unchanged")
		await click("return")
		if not check(host.service.view().lot.available==19 and host.service.view().lot.issued==0,"remaining_five_returned"):return
		# A fresh loaded budget proves revocation blocks an otherwise loaded weapon.
		await key(KEY_E);await click("revoke");await key(KEY_F)
		if not check(host.last_result.get("reason")=="PRACTICE_FIRE_PERMISSION_DENIED" and host.service.view().lot.consumed==1 and host.service.view().lot.issued==6 and host.actor.shot_sequence==1,"revoked_loaded_weapon_denied"):return
		host.record("revoked_loaded_weapon_no_consumption");await host.capture("revoked_loaded_weapon")
		await click("return")
	else:
		if not check(host.service.view().lot.available==19 and host.service.view().lot.consumed==1 and host.service.view().lot.issued==0 and host.actor.shot_sequence==1,"cold_counts_restored"):return
		host.record("cold_registry_restored");await host.capture("cold_restored")
		await click("duplicate")
		if not check(host.last_result.get("duplicate",false) and host.service.view().lot.consumed==1,"cold_old_receipt_duplicate"):return
		await key(KEY_F)
		if not check(host.last_result.get("reason")=="PRACTICE_FIRE_PERMISSION_DENIED" and host.service.view().lot.consumed==1,"cold_revocation_preserved"):return
		host.record("cold_duplicate_and_revocation_preserved")
	await host.capture("final_returned_stock")
	host.record("practice_replay_finished");host.write_rows()
	await click("leave")
