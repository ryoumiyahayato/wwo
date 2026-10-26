extends SceneTree
## Set the existing root's native flag before SceneTree first shows it.
## No alternate scene/viewport: the normal formal menu loads the existing driver.
func _init() -> void:
	root.unfocusable = true

func _initialize() -> void:
	root.unfocusable = true
	if "--native-screenshot-review" not in OS.get_cmdline_user_args():
		quit(2)
		return
	change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
