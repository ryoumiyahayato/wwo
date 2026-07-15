class_name WorldActivityPanel
extends PanelContainer
## Player-facing world activity history; event ingestion is added in the activity phase.

signal close_requested

@onready var close_button: Button = %CloseButton
@onready var empty_label: Label = %EmptyLabel


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())


func refresh_view() -> void:
	empty_label.text = "最近没有可公开的世界动态。"
