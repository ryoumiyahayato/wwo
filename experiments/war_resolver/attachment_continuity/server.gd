extends "res://experiments/war_resolver/interactive_observer/server.gd"
const AttachedSession = preload("res://experiments/war_resolver/attachment_continuity/session.gd")

func _init() -> void:
	session = AttachedSession.new()
