extends "res://experiments/war_resolver/interactive_observer/session.gd"
## Test work cut only. Same Decision/Info/Role/kernel; no war-state assignment.
var input_cut: int = 64
var cutting: bool = false

func _advance(maximum: int) -> Dictionary:
	return super._advance(input_cut if cutting else maximum)
