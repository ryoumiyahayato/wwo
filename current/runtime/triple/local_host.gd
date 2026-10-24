extends "res://modules/infantry_ai/skirmish_host.gd"
## A bounded host transfer slice: only the supplied vehicle and its five people.
## No second autonomous army or military/economy solver is installed.
func spawn(_stage: Node3D) -> void:
	clear()
	register_player(main.hero,"player","blue")
