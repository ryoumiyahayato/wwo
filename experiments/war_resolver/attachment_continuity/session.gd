extends "res://experiments/war_resolver/interactive_observer/session.gd"
const AttachedWorld = preload("res://experiments/war_resolver/attachment_continuity/scenario.gd")
const AttachedReader = preload("res://experiments/war_resolver/attachment_continuity/reader.gd")
const PassiveProvider = preload("res://experiments/war_resolver/gameplay/policy.gd")
const EventProvider = preload("res://experiments/war_resolver/gameplay/autonomous_policy.gd")
var _saved_providers: Dictionary = {}

const SESSION_RUNTIME_FIELDS: Array[String] = ["sid", "actor", "quota", "mode", "target", "auto_end", "auto_step", "pause_requested", "calls", "focus", "receipts", "receipt_ids", "unresolved", "last_seq", "last_packet", "last_response", "closed", "measure", "projection", "costs"]

func runtime_checkpoint() -> Dictionary:
	var image: Dictionary = world.runtime_checkpoint()
	if not image.get("ok", false):
		return image
	var saved: Dictionary = {}
	for person: String in _saved_providers:
		saved[person] = world.env.decisions.provider_state(_saved_providers[person])
		if saved[person].is_empty():
			return _error("unsupported_saved_control_provider")
	return {"ok": true, "version": "attachment-session-runtime-v1", "world": image,
		"session": _session_runtime_state(), "saved_providers": saved}

func _session_runtime_state() -> Dictionary:
	return preload("res://experiments/war_resolver/battle_state.gd").capture_runtime_fields(self, SESSION_RUNTIME_FIELDS)

func restore_runtime(image: Dictionary) -> Dictionary:
	if not world.env.is_empty() and world.env.state.settlement_pending:
		return _error("restore_requires_committed_boundary")
	if not image.get("ok", false) or image.get("version", "") != "attachment-session-runtime-v1" or not image.get("world") is Dictionary or not image.get("session") is Dictionary or not image.get("saved_providers") is Dictionary:
		return _error("unsupported_session_checkpoint")
	var restored: Dictionary = world.restore_candidate(image.world)
	if not restored.ok:
		return restored
	var candidate: RefCounted = get_script().new()
	if not preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(candidate, image.session, SESSION_RUNTIME_FIELDS):
		return _error("invalid_session_continuation")
	if candidate.actor != restored.world.env.gameplay.focused_person or candidate.actor != restored.world.bound_actor or not candidate.valid_id(candidate.sid):
		return _error("session_control_identity_mismatch")
	for person: String in image.saved_providers:
		var saved: RefCounted = restored.world.env.decisions.restore_provider(image.saved_providers[person])
		if saved == null:
			return _error("invalid_saved_control_provider")
		candidate._saved_providers[person] = saved
	# Installation starts only after all candidate state has been accepted.
	if not world.env.is_empty():
		dispose()
	world = restored.world
	preload("res://experiments/war_resolver/battle_state.gd").restore_runtime_fields(self, image.session, SESSION_RUNTIME_FIELDS)
	_saved_providers = candidate._saved_providers
	reader = AttachedReader.new()
	if projection:
		reader.configure(world.env, actor)
	world.env.information.message_transition.connect(_message)
	world.env.gameplay.transition.connect(_personal)
	world.env.structure.transition.connect(_structure)
	_refresh()
	return {"ok": true, "status": "RESTORED", "time": world.env.state.time, "actor": actor}

func save_runtime(path: String) -> Dictionary:
	var image: Dictionary = runtime_checkpoint()
	if not image.get("ok", false):
		return image
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _error("checkpoint_file_unavailable")
	file.store_var(image, false)
	file.flush()
	if file.get_error() != OK:
		return _error("checkpoint_write_failed")
	return {"ok": true, "status": "SAVED", "time": world.env.state.time}

func load_runtime(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("checkpoint_file_unavailable")
	var image: Variant = file.get_var(false)
	return restore_runtime(image) if image is Dictionary else _error("invalid_checkpoint_file")

func _init() -> void:
	world = AttachedWorld.new()
	reader = AttachedReader.new()

func configure(scene: String, seed_value: int, person: String, session_id: String, work_quota: int, options: Dictionary = {}) -> bool:
	if not super.configure(scene, seed_value, person, session_id, work_quota, options):
		return false
	world.env.structure.transition.connect(_structure)
	_saved_providers[actor] = PassiveProvider.new() if world._prototype_policy else EventProvider.new()
	return true

func request(op: String, args: Dictionary) -> Dictionary:
	if op in ["save_runtime", "load_runtime"]:
		if args.size() != 1 or not args.get("path") is String or str(args.path).is_empty():
			return _error("checkpoint_path_required")
		if world.env.state.settlement_pending:
			return _error("checkpoint_requires_committed_boundary")
		return save_runtime(str(args.path)) if op == "save_runtime" else load_runtime(str(args.path))
	if op == "body":
		if closed or args.size() != 2 or not args.get("id") is String or not valid_id(args.id) or not args.get("parameters") is Dictionary:
			return _error("body_requires_id_and_explicit_action_parameters")
		return _submit_choice(op, args, {"kind": "local_action", "values": args.parameters.duplicate(true)})
	if op == "person_report":
		if closed or world.env.state.public_pending() or args.size() != 3 or not args.get("id") is String or not valid_id(args.id) or not args.get("person") is String or not args.get("recipient") is String:
			return _error("person_report_requires_current_local_observation")
		var observed: Dictionary = world.env.information.observe(actor, {"id": args.id, "source_ref": actor + "_body", "subject_kind": "person", "subject_ref": args.person, "fact_kind": "person_status"})
		if not observed.ok:
			return _error(str(observed.error))
		return world.env.information.send_report(actor, {"id": "report_" + str(args.id), "recipient_ref": args.recipient, "channel_ref": "report", "observation_ids": [args.id]})
	if op == "combat_report":
		if closed or args.size() != 3 or not args.get("id") is String or not valid_id(args.id) or not args.get("observation") is String or not args.get("recipient") is String:
			return _error("combat_report_requires_existing_own_observation")
		return world.env.information.send_report(actor, {"id": args.id, "recipient_ref": args.recipient, "channel_ref": "report", "observation_ids": [args.observation]})
	if op == "continue_as":
		if closed or args.size() != 1 or not args.get("person") is String:
			return _error("existing_focus_person_required")
		var scheduled: Dictionary = world.env.gameplay.focus_continuity.request(actor, str(args.person))
		if not scheduled.ok:
			return _error(str(scheduled.error))
		target = world.env.state.time
		_advance(64)
		return {"ok": true, "status": "FOCUS_PENDING" if world.env.state.public_pending() else ("FOCUS_CHANGED" if actor == args.person else "FOCUS_NOT_CHANGED"), "person": cache.duplicate(true)}
	if op == "forward":
		if closed or args.size() != 3 or not args.get("id") is String or not valid_id(args.id) or not args.get("message") is String or not args.get("recipient") is String:
			return _error("received_report_forward_requires_id_message_and_recipient")
		return _submit_choice(op, args, {"kind": "report_forward", "message_ref": args.message, "recipient_ref": args.recipient})
	if op in ["task", "reserve", "air", "naval", "land", "operation", "tactics"]:
		if closed or args.size() != 3 or not args.get("id") is String or not valid_id(args.id) or not args.get("target") is String or not args.get("parameters") is Dictionary:
			return _error("explicit_task_input_required")
		var kind: String = {"air": "air_intent", "naval": "naval_intent", "land": "land_intent", "reserve": "reserve_intent", "task": "goal_intent", "operation": "operation_intent", "tactics": "tactical_intent"}[op]
		var channel: String = "red_command" if world.env.structure._nodes[world.env.structure.command_person(actor).formation_id].side == "red" else "command"
		return _submit_choice(op, args, {"kind": "command", "command_kind": kind, "target": args.target, "channel_ref": channel, "values": args.parameters.duplicate(true)})
	if op in ["transfer", "split_members", "merge_members", "detach_children", "coarsen", "propose_move", "propose_transport", "approve_move", "cancel_move", "accept_move", "redirect_move", "vacate_position", "appoint"]:
		if closed:
			return _error("session_closed")
		if args.size() != 3 or not args.get("id") is String or not valid_id(args.id) or not number(args.get("delay")) or float(args.delay) < 1.0 or world.env.state.time + float(args.delay) > 86400.0 or not args.get("parameters") is Dictionary:
			return _error("invalid_member_adjustment_shape")
		var operation: String = "transfer_person" if op == "transfer" else op
		return _submit_choice(op, args, {"kind": "structure_request", "values": {"operation": operation, "delay": float(args.delay), "parameters": args.parameters.duplicate(true)}})
	if op not in ["attach", "revoke"]:
		var result: Dictionary = super.request(op, args)
		if op == "help" and result.ok:
			result.commands.append("continue_as existing_related_person")
			result.commands.append("save_runtime path / load_runtime path (committed research world)")
			result.commands.append("body id JSON_aid_relocate_collect_remains_or_place_remains")
			result.commands.append("body id JSON_relocate_local_path_destination_ref_or_local_action_stop_return_enter")
			result.commands.append("body id JSON_ammunition_take_handover_recover_or_rescue_approach_pickup_carry_return_stop_put_down_road (interface; not trial-run)")
			result.commands.append("body id JSON_observe_watch_fire_cease_fire_reload_release_weapon_claim_weapon_wait_or_take_cover")
			result.commands.append("tactics id current_scope JSON_fire_mode_or_gun_action")
			result.commands.append("tactics id current_squad JSON_manoeuvre_action_parts_local_path_destination_ref")
			result.commands.append("tactics id current_squad JSON_ammo_action_move_handover_or_carrier_ref_rescue_order (interface; not trial-run)")
			result.commands.append("combat_report id own_observation_id recipient")
			result.commands.append("person_report id nearby_person recipient")
			result.commands.append("task id target_node JSON_goal_with_dependencies_or_resume")
			result.commands.append("reserve id current_office JSON_retain_units_or_release_tasks")
			result.commands.append("air id current_office JSON_sortie_service_recover_recover_land_or_cancel_recovery")
			result.commands.append("naval id current_office JSON_navigation_rendezvous_reassign_cargo_supply_continue_transport_transship_cargo_cancel_transshipment_or_aircraft_recovery")
			result.commands.append("land id current_office JSON_transport_continue_transport_resume_redirect_unload_stop_or_recover_cargo")
			result.commands.append("operation id current_office JSON_begin_with_ground_relay_deployment_engineering_or_existing_transport_ref_cancel_priority_reassign_transfer_observer_request_report_or_reduce_supply_request")
			result.commands.append("forward id received_message_id subordinate_person")
			result.commands.append("attach id target parent delay duration")
			result.commands.append("revoke id target delay")
			result.commands.append("transfer id person source_unit destination_unit delay")
			result.commands.append("split_members|merge_members|detach_children|coarsen|propose_move|propose_transport|approve_move|cancel_move|accept_move|redirect_move|vacate_position|appoint id delay JSON_parameters")
		return result
	if closed:
		return _error("session_closed")
	if not args.get("id") is String or not valid_id(args.id) or not args.get("target") is String or args.target.length() > 48 or not number(args.get("delay")) or float(args.delay) < 1.0:
		return _error("invalid_structure_shape")
	var values: Dictionary
	if op == "attach":
		if args.size() != 5 or not args.get("parent") is String or args.parent.length() > 48 or not number(args.get("duration")) or float(args.duration) <= 0.0 or world.env.state.time + float(args.delay) + float(args.duration) > 86400.0:
			return _error("invalid_attachment_interval")
		values = {"target": args.target, "parent": args.parent, "delay": float(args.delay), "duration": float(args.duration)}
	else:
		if args.size() != 3 or world.env.state.time + float(args.delay) > 86400.0:
			return _error("invalid_revoke_shape")
		values = {"operation": "revoke", "target": args.target, "delay": float(args.delay)}
	return _submit_choice(op, args, {"kind": "structure_request", "values": values})

func _refresh() -> void:
	var next: String = str(world.env.gameplay.focused_person)
	if not next.is_empty() and next != actor:
		# The event is committed. Only the input/reading focus changes here.
		world.env.decisions._persons[actor].provider = _saved_providers[actor]
		world.env.decisions.suspend_autonomy(actor, false)
		if projection:
			reader.dispose()
		actor = next
		world.bound_actor = next
		world.provider.proposal.clear()
		focus = ""
		if not world.env.decisions._persons.has(next):
			var position: Dictionary = world.env.structure.command_person(next)
			var targets: Array[String] = [str(position.formation_id)]
			for child: String in world.env.structure.children(str(position.formation_id)):
				targets.append(child)
			var cadence: float = float(world.env.structure.Roles.INPUT_SECONDS[world.env.structure.Roles.ROLES.find(str(position.role))])
			world.env.decisions.enroll(next, {"cadence": cadence, "targets": targets, "urgent": false, "command_kind": "goal_intent", "standing_orders": {}}, PassiveProvider.new())
		_saved_providers[next] = world.env.decisions._persons[next].provider
		world.env.decisions.suspend_autonomy(next, true)
		world.env.decisions._persons[next].provider = world.provider
		if projection:
			reader = AttachedReader.new()
			reader.configure(world.env, next)
	super._refresh()

func _program() -> Dictionary:
	var result: Dictionary = super._program()
	result.controlled_person_id = actor
	return result

func _harvest() -> void:
	var owned: Array[String] = unresolved.duplicate()
	super._harvest()
	for id: String in owned:
		var decision: Dictionary = world.env.decisions.result(receipts[id].event_id)
		var issued: Dictionary = decision.get("issued_input", {})
		if issued.get("domain", "") == "STRUCTURE" and issued.result.get("ok", false):
			receipts[id].status = "STRUCTURE_SCHEDULED"
			receipts[id].effective_time = issued.result.effective_time
		elif receipts[id].intent.get("values", {}).get("operation", "") in world.env.structure.Members.KINDS + world.env.structure.Movements.KINDS + world.env.structure.OFFICE_KINDS:
			receipts[id].reason = decision.get("creation_validation", {}).get("error", issued.get("result", {}).get("error", "intent_not_admitted"))
		elif receipts[id].identity.op in ["task", "reserve", "air", "naval", "land", "operation", "forward", "body"] and not decision.get("creation_validation", {}).get("ok", false):
			receipts[id].reason = decision.get("creation_validation", {}).get("error", "task_not_admitted")

func _structure(record: Dictionary) -> void:
	if record.actor != actor:
		return
	var request_id: String = str(record.id).trim_prefix("structure_expiry_") if str(record.id).begins_with("structure_expiry_") else str(record.id).trim_prefix("structure_")
	var member_request: bool = world.env.structure._requests.get(request_id, {}).get("kind", "") in world.env.structure.Members.KINDS + world.env.structure.Movements.KINDS + world.env.structure.OFFICE_KINDS
	for id: String in receipt_ids:
		if receipts[id].domain_id == request_id:
			receipts[id].processed_at = record.time
			var kind: String = str(record.outcome.get("kind", ""))
			receipts[id].status = "STRUCTURE_APPLIED" if kind in world.env.structure.Members.KINDS + world.env.structure.Movements.KINDS + world.env.structure.OFFICE_KINDS else {"attach": "STRUCTURE_APPLIED", "revoke": "STRUCTURE_REVOKED", "attachment_expired": "STRUCTURE_EXPIRED", "stale_expiry_noop": "STALE_EXPIRY_NOOP"}.get(kind, "STRUCTURE_REJECTED")
			var reason: String = str(record.outcome.get("error", ""))
			receipts[id].reason = reason if member_request or reason in ["", "stale_attachment_revoke"] else "structure_request_not_admitted"
			if record.outcome.has("movement"):
				receipts[id].movement_ref = record.outcome.movement
				receipts[id].movement_status = record.outcome.movement_status
				receipts[id].reason = record.outcome.reason
			break

func dispose() -> void:
	world.env.structure.transition.disconnect(_structure)
	super.dispose()
