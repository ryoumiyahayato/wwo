extends SceneTree
const Session = preload("res://experiments/war_resolver/interactive_observer/session.gd")
const Audit = preload("res://experiments/war_resolver/interactive_observer/audit.gd")
const AdmissionFixture = preload("res://experiments/war_resolver/interactive_observer/admission_fixture.gd")
var checks: int = 0
var failures: int = 0
var released_handles: Array[WeakRef] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func make(scene: String = "S1", actor: String = "squad", quota: int = 31) -> Session:
	var s: Session = Session.new()
	check(s.configure(scene, 71, actor, "contract", quota), "fixed person admission")
	check(s.world.selected_script_disabled, "selected pre-script disabled")
	return s

func ready(s: Session, seconds: float) -> void:
	check(s.request("advance", {"seconds": seconds}).ok, "advance request")
	while s.world.env.state.public_pending():
		check(s.request("resume", {"calls": 64}).ok, "same bounded target resumes")

func finish(s: Session) -> void:
	var handle: WeakRef = weakref(s.world.env.state)
	s.dispose()
	released_handles.append(handle)
	check(s.world.env.is_empty(), "owner disposed")

func _initialize() -> void:
	_read_contract()
	_pending()
	_pending_admission()
	_identity_and_capacity()
	_permissions()
	_hidden_bridge()
	_personal()
	_clock()
	# Check after the fixture functions return. A GDScript while receiver can retain
	# its last temporary state reference until that fixture's stack frame returns.
	for handle: WeakRef in released_handles:
		check(handle.get_ref() == null, "world released after caller temporary returns")
	print("Person bound interaction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _read_contract() -> void:
	var s: Session = make("S3", "soldier")
	ready(s, 600.0)
	var before: Dictionary = Audit.collect(s)
	var lod: Dictionary = s.world.env.lod.work.duplicate()
	var state: Dictionary = s.world.env.state.counters.duplicate()
	var keys: Dictionary = s.world.env.state.random_state.duplicate()
	var knowledge: Dictionary = s.world.env.information._knowledge.duplicate(true)
	var sizes: Array = [s.reader.timeline.size(), s.receipts.size(), s.world.env.decisions._events.size()]
	for index: int in range(100):
		var view: Dictionary = s.request("look", {}).person
		check(view.reports.entries.size() <= 20 and view.events.records.size() <= 20, "bounded person pages")
		s.request("help", {})
		s.request("reports", {"before": -1})
		s.request("events", {"before": -1})
		s.request("receipts", {"before": -1})
		s.request("focus", {"subject": "soldier"})
	check(before.formal == Audit.collect(s).formal, "reads preserve all formal outputs")
	check(lod == s.world.env.lod.work and state == s.world.env.state.counters and keys == s.world.env.state.random_state, "reads do not wake materialize consume or RNG")
	check(knowledge == s.world.env.information._knowledge, "pages preserve authoritative knowledge")
	check(sizes == [s.reader.timeline.size(), s.receipts.size(), s.world.env.decisions._events.size()], "refresh has no growing event state")
	check(not s.request("focus", {"subject": "red_secret"}).ok, "focus catalog cannot search hidden truth")
	# Ring bound test feeds only lawful own-input records. It never changes war state.
	for index: int in range(300):
		s.reader.own_input("reader_%d" % index, s.world.env.state.time, {"kind": "test_record"})
	check(s.reader.timeline.size() == 256 and s.reader.events(1).cursor_lost, "ring explicitly declares missing cursor")
	var page: Dictionary = s.reader.events()
	check(page.records.size() == 20 and page.dropped > 0, "latest bounded ring page")
	check(s.reader.events(page.next_before).records[-1].cursor < page.records[0].cursor, "page positions do not duplicate")
	check(before.formal == Audit.collect(s).formal, "reader fixture cannot alter war ledger")
	finish(s)

func _pending() -> void:
	var s: Session = make("S1", "squad", 1)
	var committed: Dictionary = s.cache.duplicate(true)
	check(s.request("advance", {"seconds": 100.0}).status == "PENDING", "small quota produces actual PENDING")
	check(s.request("look", {}).person == committed, "PENDING uses last complete view")
	check(s.request("reports", {"before": -1}).person == committed, "PENDING page uses last complete view")
	check(not s.request("intent", {"id": "late", "target": "node_unit_000", "intent": "advance", "node": "B", "path": ["AB"]}).ok and s.receipts.is_empty(), "PENDING has no hidden write queue")
	check(not s.request("advance", {"seconds": 1.0}).ok, "PENDING cannot replace target")
	check(s.request("pause", {}).status == "PAUSE_AT_COMMIT", "pause waits safe boundary")
	while s.world.env.state.public_pending():
		s.request("resume", {"calls": 64})
	check(s.world.env.state.time == 100.0 and s.mode == "PAUSED", "same original target completes before pause")
	check(s.request("intent", {"id": "late", "target": "node_unit_000", "intent": "hold", "node": "A", "path": []}).receipt.received_at == 100.0, "explicit retry is current committed time")
	while s.world.env.state.public_pending():
		s.request("resume", {"calls": 64})
	finish(s)

func _identity_and_capacity() -> void:
	var s: Session = make()
	var packet: Dictionary = {"session": "contract", "seq": 1, "op": "look", "args": {}}
	var response: Dictionary = s.handle(packet)
	check(s.handle(packet) == response, "transport replay is cached")
	check(not s.handle({"session": "contract", "seq": 1, "op": "help", "args": {}}).ok, "same sequence different content rejects")
	check(not s.handle({"session": "old", "seq": 2, "op": "look", "args": {}}).ok, "cross session rejected")
	check(not s.handle({"session": "contract", "seq": 2.1, "op": "look", "args": {}}).ok, "fractional seq rejected")
	check(not s.handle({"session": "contract", "seq": 2, "op": "look", "args": {}, "actor": "company"}).ok, "actor injection envelope rejected")
	ready(s, 10.0)
	var args: Dictionary = {"id": "one", "target": "node_unit_000", "intent": "advance", "node": "B", "path": ["AB"]}
	check(s.request("intent", args).receipt.status == "ISSUED_WAITING", "real issued delayed command")
	var events: int = s.world.env.decisions._events.size()
	check(s.request("intent", args).duplicate and s.world.env.decisions._events.size() == events, "stable command id executes once")
	args.node = "A"
	check(not s.request("intent", args).ok, "same id different intent rejects")
	for index: int in range(1, Session.MAX_IDS):
		s.request("personal", {"id": "fill_%d" % index, "action": "wait"})
	check(s.receipts.size() == Session.MAX_IDS, "finite identities preserve refusals")
	check(not s.request("personal", {"id": "overflow", "action": "wait"}).ok and s.receipts.has("one"), "identity cap keeps original requests")
	check(not s.request("personal", {"id": "x".repeat(49), "action": "wait"}).ok, "id length bounded")
	check(not s.request("personal", {"id": "spoof", "action": "wait", "actor": "soldier"}).ok, "personal identity cannot be overwritten")
	check(not s.request("advance", {"seconds": NAN}).ok and not s.request("advance", {"seconds": -1.0}).ok, "nonfinite negative times denied")
	check(not s.request("reports", {"before": 999999}).ok, "invalid page has program refusal")
	finish(s)

func _pending_admission() -> void:
	var exercised: bool = false
	for cut: int in range(1, 64):
		var s: AdmissionFixture = AdmissionFixture.new()
		check(s.configure("S3", 71, "soldier", "admission", 1), "admission-cut fixture")
		ready(s, 10.0)
		s.input_cut = cut
		s.cutting = true
		var previous: Dictionary = s.cache.duplicate(true)
		var response: Dictionary = s.request("personal", {"id": "cover", "action": "take_cover"})
		if s.world.env.state.public_pending():
			check(response.receipt.status == "DECISION_SCHEDULED" and not response.receipt.has("personal_feedback") and not response.receipt.has("accepted"), "partial admission exposes acknowledgment only")
			check(s.request("look", {}).person == previous, "partial admission cannot refresh person projection")
			if s.receipts.cover.has("personal_feedback"):
				exercised = true
				print("PENDING_ADMISSION_CUT=", cut, " internal feedback withheld from person response")
		s.cutting = false
		while s.world.env.state.public_pending():
			s.request("resume", {"calls": 64})
		check(s.receipts.cover.status == "ACTION_STARTED", "admission completes through original local domain")
		finish(s)
		if exercised:
			break
	check(exercised, "real bounded kernel reaches partial personal feedback before final commit")

func _permissions() -> void:
	var s: Session = make("S2", "platoon")
	ready(s, 20.0)
	check(s.world.env.information._messages.old_authority.outcome.reason == "wrong_owner_or_layer", "existing delayed order rechecks changed authority")
	check(s.request("intent", {"id": "lost", "target": "node_unit_001", "intent": "hold", "node": "A", "path": []}).receipt.status == "INPUT_REJECTED", "live old officer cannot command transferred subordinate")
	finish(s)
	s = make("S3", "soldier")
	check(s.request("intent", {"id": "up", "target": "node_unit_000", "intent": "advance", "node": "B", "path": ["AB"]}).receipt.status == "INPUT_REJECTED", "ordinary actor cannot issue officer goal")
	check(s.world.env.people.soldier.role == "ordinary_soldier", "rejection never changes rank")
	finish(s)

func _hidden_bridge() -> void:
	var damaged: Session = make("S2", "platoon")
	var clear: Session = Session.new()
	check(clear.configure("S2", 71, "platoon", "contract", 31, {"bridge_clear": true}), "counterfactual only at construction")
	ready(damaged, 80.0)
	ready(clear, 80.0)
	check(not damaged.world.env.space.edge_view("bridge_BD").open and clear.world.env.space.edge_view("bridge_BD").open, "hidden truth differs")
	check(damaged.request("look", {}).person == clear.request("look", {}).person, "same received knowledge has identical view and menu")
	check(damaged.request("focus", {"subject": "red_secret"}) == clear.request("focus", {"subject": "red_secret"}), "error does not leak truth")
	finish(damaged)
	finish(clear)

func _personal() -> void:
	var s: Session = make("S3", "soldier")
	ready(s, 10.0)
	check(s.request("personal", {"id": "cover", "action": "take_cover"}).receipt.status == "ACTION_STARTED", "local action really starts without radio delay")
	ready(s, 2.0)
	check(s.request("look", {}).person.personal.state == "ENTERING", "partial entry never shows cover completion")
	ready(s, 6.0)
	check(s.request("look", {}).person.personal.state == "COVERED" and s.receipts.cover.status == "ACTION_FINISHED", "completion comes from personal causal feedback")
	ready(s, 1782.0)
	check(s.world.balanced() and s.request("look", {}).person.personal.health < 1.0, "shared casualty account remains balanced")
	check(s.world.env.gameplay.participants._units.soldier == "unit_000", "one member identity retained")
	finish(s)

func _clock() -> void:
	var s: Session = make()
	check(s.request("auto", {"until": 90.0, "step": 30.0}).ok, "finite auto plan")
	while s.mode == "AUTO" or s.world.env.state.public_pending():
		s.request("tick", {"calls": 64})
	check(s.mode == "PAUSED" and s.world.env.state.time == 90.0, "no input or look needed by auto")
	check(not s.request("resume", {"calls": 64}).ok, "no hidden continuation after final target")
	var t: float = s.world.env.state.time
	s.request("look", {})
	check(s.world.env.state.time == t, "manual waiting does not advance research clock")
	finish(s)
