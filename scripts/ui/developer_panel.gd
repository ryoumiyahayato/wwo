class_name DeveloperPanel
extends PanelContainer

signal close_requested()

@onready var enable_check: CheckButton = %EnableCheck
@onready var status_label: Label = %StatusLabel
@onready var log_view: RichTextLabel = %LogView

var command_service: DeveloperCommandService
var autosave: AutosaveCoordinator


func setup(clock: SimulationClock, map_service: MapControlService, autosave_coordinator: AutosaveCoordinator) -> void:
	command_service = DeveloperCommandService.new(clock, map_service)
	autosave = autosave_coordinator
	enable_check.button_pressed = GameSessionService.developer_mode
	_refresh()


func _ready() -> void:
	%CloseButton.pressed.connect(func() -> void: close_requested.emit())
	enable_check.toggled.connect(_on_enabled_toggled)
	%SaveButton.pressed.connect(_on_save)
	%LoadButton.pressed.connect(_on_load)
	%AutosaveButton.pressed.connect(_on_autosave)
	%HourButton.pressed.connect(_on_step.bind(1))
	%DayButton.pressed.connect(_on_step.bind(24))
	%PauseActionButton.pressed.connect(_on_action.bind("pause"))
	%SuccessActionButton.pressed.connect(_on_action.bind("success"))
	%FailureActionButton.pressed.connect(_on_action.bind("failure"))
	%CompleteActionButton.pressed.connect(_on_action.bind("complete"))
	%CommandButton.pressed.connect(_on_command)
	%CommandInput.text_submitted.connect(func(_text: String) -> void: _on_command())


func _on_enabled_toggled(enabled: bool) -> void:
	if command_service != null:
		command_service.set_enabled(enabled)
	_refresh()


func _on_save() -> void:
	_show_result(command_service.save_manual())


func _on_load() -> void:
	_show_result(command_service.load_manual())


func _on_autosave() -> void:
	_show_result(autosave.run_now())


func _on_step(hours: int) -> void:
	status_label.text = "时间已推进" if command_service.step_hours(hours) else "请先开启开发模式"
	_refresh()


func _on_action(mode: String) -> void:
	status_label.text = "行动状态已调整" if command_service.force_action(mode) else "没有可调整的进行中行动"
	_refresh()


func _show_result(result: SaveOperationResult) -> void:
	status_label.text = "操作成功" if result.success else "%s：%s" % [result.error_code, result.message]
	_refresh()


func _on_command() -> void:
	var result: Dictionary = command_service.execute_text_command(%CommandInput.text)
	status_label.text = str(result.get("message", ""))
	if result.get("data", {}) is Dictionary and not (result.get("data", {}) as Dictionary).is_empty():
		status_label.text += "\n" + JSON.stringify(result["data"], "  ")
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	var enabled: bool = GameSessionService.developer_mode
	for button: Button in [%HourButton, %DayButton, %PauseActionButton, %SuccessActionButton, %FailureActionButton, %CompleteActionButton]:
		button.disabled = not enabled
	var lines: Array[String] = ["[b]结算日志（最近 20 条）[/b]"]
	var entries: Array[Dictionary] = GameSessionService.settlement_log.get_entries()
	for index: int in range(maxi(0, entries.size() - 20), entries.size()):
		var entry: Dictionary = entries[index]
		lines.append("%d  [%s] %s" % [int(entry["total_hour"]), str(entry["category"]), str(entry["message"])])
	lines.append("\n[b]性能统计[/b]")
	var metrics: Dictionary = GameSessionService.performance_stats.get_snapshot()
	for metric_id: String in metrics:
		var metric: Dictionary = metrics[metric_id] as Dictionary
		lines.append("%s  count=%d last=%.3fms max=%.3fms" % [metric_id, int(metric["count"]), float(metric["last_usec"]) / 1000.0, float(metric["max_usec"]) / 1000.0])
	log_view.text = "\n".join(lines)
