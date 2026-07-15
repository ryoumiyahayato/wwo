class_name WorldActivityPanel
extends PanelContainer
## Player-facing history backed by the same public stream as transient notices.

signal close_requested
signal event_activated(event: Dictionary)

@onready var close_button: Button = %CloseButton
@onready var empty_label: Label = %EmptyLabel
@onready var event_list: VBoxContainer = %EventList

var _activity: WorldActivityService


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())


func setup(activity: WorldActivityService) -> void:
	if _activity != null and _activity.event_added.is_connected(_on_event_added):
		_activity.event_added.disconnect(_on_event_added)
	_activity = activity
	if _activity != null and not _activity.event_added.is_connected(_on_event_added):
		_activity.event_added.connect(_on_event_added)
	refresh_view()


func refresh_view() -> void:
	for child: Node in event_list.get_children():
		event_list.remove_child(child)
		child.queue_free()
	var events: Array[Dictionary] = (
		_activity.get_recent() if _activity != null else []
	)
	empty_label.visible = events.is_empty()
	empty_label.text = "最近没有可公开的世界动态。"
	for event: Dictionary in events:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 72.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s  ·  %s\n%s" % [
			_format_world_hour(int(event.get("world_hour", 0))),
			str(event.get("title", "世界动态")),
			str(event.get("description", "")),
		]
		button.pressed.connect(
			func() -> void: event_activated.emit(event.duplicate(true))
		)
		event_list.add_child(button)


func _on_event_added(_event: Dictionary) -> void:
	refresh_view()


static func _format_world_hour(world_hour: int) -> String:
	return "第%d天 %02d:00" % [world_hour / 24 + 1, world_hour % 24]
