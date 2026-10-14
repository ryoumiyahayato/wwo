extends SceneTree
const Session = preload("res://experiments/war_resolver/interactive_observer/session.gd")
var session: Session = Session.new()

func _initialize() -> void:
	var options: Dictionary = {"scene": "S1", "seed": "71", "actor": "squad", "session": "local", "quota": "31", "diagnostic": "", "measure": "false", "sleeping": "0", "bridge_clear": "false", "second_vessel_role": "opponent", "supply_responses": "{}", "autonomy_mode": "events", "battlefield_actions": "{}"}
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2 or not options.has(parts[0]):
			quit(2)
			return
		options[parts[0]] = parts[1]
	if not str(options.seed).is_valid_int() or not str(options.quota).is_valid_int() or not str(options.sleeping).is_valid_int() or int(options.sleeping) < 0 or int(options.sleeping) > 10000:
		quit(2)
		return
	var supply_responses: Variant = JSON.parse_string(str(options.supply_responses))
	var battlefield: Variant = JSON.parse_string(str(options.battlefield_actions))
	if not battlefield is Dictionary:
		quit(2)
		return
	for key: String in battlefield:
		if key not in ["weapon_profiles", "gun_crews", "position_sites", "engineers", "engineering_edges", "engineering_facts", "action_orders", "infantry_actions"]:
			quit(2)
			return
	if options.second_vessel_role not in ["opponent", "escort"] or options.autonomy_mode not in ["events", "prototype"] or not supply_responses is Dictionary:
		quit(2)
		return
	var initial: Dictionary = {"diagnostic": false, "measure": options.measure == "true", "sleeping_areas": int(options.sleeping), "bridge_clear": options.bridge_clear == "true", "second_vessel_role": options.second_vessel_role, "supply_responses": supply_responses, "autonomy_mode": options.autonomy_mode}
	initial.merge(battlefield)
	if not session.configure(options.scene, int(options.seed), options.actor, options.session, int(options.quota), initial):
		push_error("Session admission failed")
		quit(2)
		return
	print("PERSON_BOUND=" + JSON.stringify({"ok": true, "started": true, "session": session.sid, "person": session.cache, "program": session._program()}))
	while not session.closed:
		var frame: PackedByteArray = OS.read_buffer_from_stdin(Session.FRAME)
		if frame.is_empty():
			break
		var response: Dictionary = {"ok": false, "layer": "PROGRAM_STATUS", "error": "incomplete_frame"}
		if frame.size() == Session.FRAME:
			var parser: JSON = JSON.new()
			var value: Variant = parser.data if parser.parse(frame.get_string_from_utf8().strip_edges()) == OK else null
			response = session.handle(value) if value is Dictionary else {"ok": false, "layer": "PROGRAM_STATUS", "error": "invalid_json_frame"}
		print("PERSON_BOUND=" + JSON.stringify(response))
	if not str(options.diagnostic).is_empty():
		var manual_audit: Script = load("res://experiments/war_resolver/interactive_observer/audit.gd")
		manual_audit.save(session, str(options.diagnostic))
	var world_handle: WeakRef = weakref(session.world.env.state)
	session.dispose()
	print("PERSON_BOUND_CLOSED=" + JSON.stringify({"session": session.sid, "released": world_handle.get_ref() == null, "costs": session.costs, "calls": session.calls, "reader_work": session.reader.work}))
	quit(0)

