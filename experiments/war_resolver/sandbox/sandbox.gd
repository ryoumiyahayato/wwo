extends Control
const Session = preload("res://experiments/war_resolver/sandbox/session.gd")
const Canvas = preload("res://experiments/war_resolver/sandbox/canvas.gd")
const Scenarios = preload("res://experiments/war_resolver/sandbox/fixtures.gd")
const Roles = preload("res://experiments/war_resolver/role_overrides.gd")
const State = preload("res://experiments/war_resolver/battle_state.gd")
const SPEEDS: Array[int] = [1, 4, 16]
var session: Session = Session.new()
var scenario_choice: OptionButton
var role_choice: OptionButton
var kind_choice: OptionButton
var target_choice: OptionButton
var value_choice: OptionButton
var unit_choice: OptionButton
var seed_input: LineEdit
var objective: SpinBox
var release_after: SpinBox
var direction: OptionButton
var speed_choice: OptionButton
var pause_button: Button
var status: Label
var panels: Dictionary = {}
var timer: Timer
var seed_error: String = ""


func _ready() -> void:
	add_theme_font_size_override("font_size", 12)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	margin.add_child(scroll)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layout)
	_label(layout, "EXPERIMENT / NON-PRODUCTION — land war observation sandbox — Production integration = NONE", 18)
	_label(layout, "Perfect debug observation. Fixed rows are layout only; X is the resolver's sole movement axis (km). Terrain symbols denote uniform area inputs.")
	var setup: HBoxContainer = HBoxContainer.new()
	layout.add_child(setup)
	scenario_choice = _choice(setup, Scenarios.NAMES)
	_label(setup, "Seed")
	seed_input = LineEdit.new()
	seed_input.text = "71"
	seed_input.custom_minimum_size.x = 105
	setup.add_child(seed_input)
	role_choice = _choice(setup, Roles.ROLES)
	_button(setup, "Reset / clone both modes", reset_from_controls)
	scenario_choice.item_selected.connect(func(_index: int) -> void: reset_from_controls())
	role_choice.item_selected.connect(func(_index: int) -> void: reset_from_controls())
	seed_input.text_submitted.connect(func(_text: String) -> void: reset_from_controls())
	var playback: HBoxContainer = HBoxContainer.new()
	layout.add_child(playback)
	pause_button = _button(playback, "Run", toggle_pause)
	_button(playback, "+120 game seconds", step_once)
	_label(playback, "Speed (game seconds / real second)")
	speed_choice = _choice(playback, ["240", "960", "3840"])
	_label(playback, "Inspect unit (read only)")
	unit_choice = _choice(playback, [])
	unit_choice.item_selected.connect(func(_index: int) -> void: refresh())
	var command_row: HBoxContainer = HBoxContainer.new()
	layout.add_child(command_row)
	_label(command_row, "Role input")
	kind_choice = _choice(command_row, [])
	target_choice = _choice(command_row, [])
	value_choice = _choice(command_row, [])
	kind_choice.item_selected.connect(func(_index: int) -> void: _command_choices())
	_button(command_row, "Submit to both", submit_from_controls)
	_button(command_row, "Probe foreign rejection", probe_rejection)
	var parameters: HBoxContainer = HBoxContainer.new()
	layout.add_child(parameters)
	_label(parameters, "Mission objective km")
	objective = SpinBox.new()
	objective.min_value = 0.0
	objective.max_value = 5.0
	objective.step = 0.05
	objective.value = 2.0
	parameters.add_child(objective)
	direction = _choice(parameters, ["+1", "-1"])
	_label(parameters, "Coordination reserve seconds")
	release_after = SpinBox.new()
	release_after.max_value = 86400.0
	release_after.step = 120.0
	parameters.add_child(release_after)
	_label(parameters, "Grey fields do not apply to the selected command layer.")
	status = _label(layout, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(layout, "Dot = squad; yellow mark = mission objective; amber bar = suppression; faint dots = last 48 sampled positions; line = last sampled movement. No interpolation.")
	var pair: HBoxContainer = HBoxContainer.new()
	pair.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(pair)
	for policy: String in Session.POLICIES:
		var column: VBoxContainer = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.custom_minimum_size.x = 575
		pair.add_child(column)
		_label(column, policy + " — independent clone / same seed and commands", 16)
		var canvas: Canvas = Canvas.new()
		canvas.custom_minimum_size = Vector2(575.0, 156.0)
		canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(canvas)
		var summary: Label = _label(column, "")
		var table: Label = _label(column, "", 11)
		var detail: Label = _label(column, "", 11)
		var trace: TextEdit = TextEdit.new()
		trace.editable = false
		trace.custom_minimum_size.y = 80.0
		trace.add_theme_font_size_override("font_size", 11)
		column.add_child(trace)
		panels[policy] = {"canvas": canvas, "summary": summary, "table": table, "detail": detail, "trace": trace}
	timer = Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()
	reset_from_controls()


func reset_from_controls() -> void:
	if not seed_input.text.is_valid_int() or seed_input.text.length() > 10:
		seed_error = "RESET REJECTED: seed must be an integer of at most 10 characters. Current battle unchanged."
		refresh()
		return
	seed_error = ""
	assert(session.reset(_selected(scenario_choice), int(seed_input.text), _selected(role_choice)))
	unit_choice.clear()
	for id: String in State.sorted_ids(session.states[Session.POLICIES[0]].units):
		unit_choice.add_item(id)
	kind_choice.clear()
	for kind: String in session.scope().targets:
		kind_choice.add_item(kind)
	_command_choices()
	refresh()


func _command_choices() -> void:
	var kind: String = _selected(kind_choice)
	target_choice.clear()
	for target: String in session.scope().targets.get(kind, []):
		target_choice.add_item(target)
	value_choice.clear()
	var values: Array = ["hold", "advance", "support"]
	if kind == "local_action":
		values = ["wait", "take_cover", "step_forward", "step_back"]
	elif kind == "mission":
		values = Roles.POSTURES
	for value: String in values:
		value_choice.add_item(value)
	objective.editable = kind == "mission"
	direction.disabled = kind != "mission"
	release_after.editable = kind == "coordination"


func submit_from_controls() -> void:
	var kind: String = _selected(kind_choice)
	var values: Dictionary = {"posture": _selected(value_choice)}
	if kind == "local_action":
		values = {"action": _selected(value_choice)}
	elif kind == "mission":
		values.objective = objective.value
		values.direction = 1.0 if direction.selected == 0 else -1.0
	elif kind == "coordination":
		values.release_after = release_after.value
	session.submit(kind, _selected(target_choice), values)
	refresh()


func probe_rejection() -> void:
	session.submit("local_action", "unrelated_person", {"action": "wait"})
	refresh()


func toggle_pause() -> void:
	session.paused = not session.paused
	refresh()


func step_once() -> void:
	session.advance_samples()
	refresh()


func _on_tick() -> void:
	if session.paused:
		return
	session.tick(SPEEDS[speed_choice.selected])
	refresh()


func refresh() -> void:
	if session.states.is_empty():
		return
	pause_button.text = "Run" if session.paused else "Pause"
	var scope: Dictionary = session.scope()
	status.text = "Scenario %s / seed %d / person %s in %s. Input interval %.0fs; next input %.0fs. Role/scenario changes reset both modes.\n" % [session.scenario, session.seed, scope.person_id, scope.formation_id, scope.input_interval_seconds, scope.next_input_at]
	status.text += "Limits: AGGREGATE = longer intervals, no coalescing; local pairs O(n²); soldier actions are personal records without combat effects; higher ranks have limited verbs. " + seed_error
	var selected_unit: String = _selected(unit_choice)
	for policy: String in Session.POLICIES:
		var view: Dictionary = session.view(policy)
		var state: Dictionary = view.state
		var panel: Dictionary = panels[policy]
		panel.canvas.present(view, session.scenario, selected_unit)
		var area: Dictionary = state.areas.field
		panel.summary.text = "t=%.0fs  casualties=%.3f  ammo used=%.2f  control=%s\nUniform terrain: cover %.2f / conceal %.2f / move %.2f / frontage %.1f" % [state.time, state.totals.casualties, state.totals.ammo_spent, area.control, area.cover, area.concealment, area.movement_modifier, area.frontage]
		var rows: PackedStringArray = ["UNIT | ACTION | X km / moved | suppression | casualties | MISSION status"]
		for id: String in State.sorted_ids(state.units):
			var unit: Dictionary = state.units[id]
			var mission: Dictionary = state.missions[unit.mission_id]
			rows.append("%s | %s | %.3f / %.3f | %.3f | %.3f | %s %s" % [id, unit.action, unit.position, unit.distance_moved, unit.suppression, unit.casualties, mission.posture, mission.status])
		panel.table.text = "\n".join(rows)
		var unit: Dictionary = state.units[selected_unit]
		var mission: Dictionary = state.missions[unit.mission_id]
		var track: Dictionary = view.observation.tracks[selected_unit]
		var result: Dictionary = view.command_result
		var command_text: String = "no input submitted"
		if not result.is_empty():
			command_text = "ACCEPTED / next %.0fs" % float(result.next_input_at) if result.ok else "REJECTED: " + str(result.error)
		panel.detail.text = "Inspect %s: objective %.2f / direction %+.0f / fatigue %.3f / cohesion %.3f\nStationary for %.0fs (may be intended); sampled reversals %d; action changes %d\nRole command: %s. Report: %s" % [selected_unit, mission.objective, mission.direction, unit.fatigue, unit.cohesion, float(state.time) - float(track.stationary_since), track.reversals, track.action_changes, command_text, _report_text(view.report)]
		panel.detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var lines: PackedStringArray = ["TRACE: retained %d / dropped %d / loss events %d; scroll for earlier events" % [view.observation.trace.size(), view.observation.dropped, view.observation.event_counts.get("losses", 0)]]
		var events: Array = view.observation.trace
		for index: int in range(events.size()):
			var event: Dictionary = events[index]
			lines.append("%.1fs %s %s %s %s" % [event.time, event.kind, event.get("unit_id", event.get("target", event.get("id", ""))), event.get("action", event.get("status", event.get("control", ""))), event.get("reason", event.get("error", ""))])
		panel.trace.text = "\n".join(lines)
		panel.trace.scroll_vertical = maxi(0, lines.size() - 4)


static func _report_text(report: Dictionary) -> String:
	if report.has("personal_action"):
		return "%s x=%.3f (personal only)" % [report.personal_action.action, report.personal_action.position]
	var groups: PackedStringArray = []
	for id: String in report.formations:
		var record: Dictionary = report.formations[id]
		groups.append("%s: %d squads / %.2f effective / %d complete" % [id, record.squads, record.effective, record.missions_complete])
	return "; ".join(groups)


static func _selected(choice: OptionButton) -> String:
	return "" if choice.item_count == 0 else choice.get_item_text(choice.selected)


static func _label(parent: Node, text: String, font_size: int = 12) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


static func _choice(parent: Node, values: Array) -> OptionButton:
	var choice: OptionButton = OptionButton.new()
	for value: String in values:
		choice.add_item(value)
	parent.add_child(choice)
	return choice


static func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
