extends SceneTree
## Same recorded input and time requests, without person projection or pipe I/O.
const Session = preload("res://experiments/war_resolver/interactive_observer/session.gd")
const AttachedSession = preload("res://experiments/war_resolver/attachment_continuity/session.gd")
const Audit = preload("res://experiments/war_resolver/interactive_observer/audit.gd")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not input is Dictionary or input.packets.size() > 4096:
		quit(2)
		return
	var session: Session = Session.new()
	if str(input.scene).begins_with("A"):
		session = AttachedSession.new()
	if not session.configure(input.scene, int(input.seed), input.actor, input.session, int(input.quota),
		{"projection": false, "diagnostic": false, "measure": true, "sleeping_areas": int(input.get("sleeping", 0)), "bridge_clear": input.get("bridge_clear", false)}):
		quit(2)
		return
	for packet: Dictionary in input.packets:
		session.handle(packet)
	Audit.save(session, args[1])
	var handle: WeakRef = weakref(session.world.env.state)
	session.dispose()
	print("REFERENCE=" + JSON.stringify({"released": handle.get_ref() == null, "costs": session.costs, "calls": session.calls}))
	quit(0)
