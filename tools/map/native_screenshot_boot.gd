extends SceneTree
## Finite source review only; the normal menu still constructs the one world.
func _init() -> void:
	root.unfocusable=true

func _initialize() -> void:
	root.unfocusable=true
	if "--terrain-region-review" not in OS.get_cmdline_user_args():
		quit(2)
		return
	change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
	var driver:=load("res://tools/map/r57_visual_driver.gd").new() as Node
	driver.set("acceptance","terrain-region")
	root.add_child.call_deferred(driver)
