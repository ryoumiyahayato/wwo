class_name WorldNotificationCenter
extends Control
## Right-bottom transient presentation for the public world activity stream.

signal event_activated(event: Dictionary)

const MAX_VISIBLE: int = 4
const NORMAL_LIFETIME_SECONDS: float = 7.0
const IMPORTANT_LIFETIME_SECONDS: float = 12.0
const SLIDE_SECONDS: float = 0.22

@onready var notification_stack: VBoxContainer = %NotificationStack

var _activity: WorldActivityService
var _event_by_control: Dictionary = {}


func setup(activity: WorldActivityService) -> void:
	if _activity != null and _activity.event_added.is_connected(_on_event_added):
		_activity.event_added.disconnect(_on_event_added)
	_activity = activity
	if _activity != null and not _activity.event_added.is_connected(_on_event_added):
		_activity.event_added.connect(_on_event_added)


func get_visible_count() -> int:
	return notification_stack.get_child_count()


func expire_notification(event_id: String, animated: bool = true) -> bool:
	for child: Node in notification_stack.get_children():
		var control: Control = child as Control
		var event: Dictionary = _event_by_control.get(control, {}) as Dictionary
		if str(event.get("id", "")) == event_id:
			_remove_notification(control, animated)
			return true
	return false


func _on_event_added(event: Dictionary) -> void:
	while notification_stack.get_child_count() >= MAX_VISIBLE:
		_remove_notification(
			notification_stack.get_child(0) as Control, false
		)
	var button := Button.new()
	button.custom_minimum_size = Vector2(340.0, 72.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text = "%s\n%s" % [str(event.get("title", "世界动态")), str(event.get("description", ""))]
	button.tooltip_text = "点击查看相关内容"
	button.modulate.a = 0.0
	button.position.x = 380.0
	button.pressed.connect(_on_notification_pressed.bind(button))
	notification_stack.add_child(button)
	_event_by_control[button] = event.duplicate(true)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "position:x", 0.0, SLIDE_SECONDS)
	tween.tween_property(button, "modulate:a", 1.0, SLIDE_SECONDS)
	var lifetime: float = (
		IMPORTANT_LIFETIME_SECONDS
		if str(event.get("importance", "")) == WorldActivityService.IMPORTANCE_IMPORTANT
		else NORMAL_LIFETIME_SECONDS
	)
	get_tree().create_timer(lifetime).timeout.connect(
		_on_notification_timeout.bind(str(event.get("id", "")))
	)


func _on_notification_pressed(control: Control) -> void:
	var event: Dictionary = _event_by_control.get(control, {}) as Dictionary
	if not event.is_empty():
		event_activated.emit(event.duplicate(true))
	_remove_notification(control, true)


func _on_notification_timeout(event_id: String) -> void:
	expire_notification(event_id)


func _remove_notification(control: Control, animated: bool) -> void:
	if control == null or not is_instance_valid(control):
		return
	_event_by_control.erase(control)
	if not animated:
		if control.get_parent() == notification_stack:
			notification_stack.remove_child(control)
		control.queue_free()
		return
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "position:x", 380.0, SLIDE_SECONDS)
	tween.tween_property(control, "modulate:a", 0.0, SLIDE_SECONDS)
	tween.chain().tween_callback(control.queue_free)
