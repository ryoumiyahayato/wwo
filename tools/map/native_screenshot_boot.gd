extends SceneTree
## Set the existing root's native flag before SceneTree first shows it.
## No alternate scene/viewport: the normal formal menu loads the existing driver.
var _terrain_a0: RefCounted

func _init() -> void:
	if "--dev-preview" in OS.get_cmdline_user_args():
		# The launcher isolates process data/cache environment before engine
		# initialization, including shader-cache setup. No shared override edit.
		root.unfocusable = "--dev-background" in OS.get_cmdline_user_args()
	else: root.unfocusable = true

func _initialize() -> void:
	var development := "--dev-preview" in OS.get_cmdline_user_args()
	root.unfocusable = not development or "--dev-background" in OS.get_cmdline_user_args()
	var expected_user := OS.get_environment("WWO_VISUAL_USER_DIR")
	if development:
		var isolated_root := OS.get_environment("WWO_DEV_USER_ROOT").replace("\\","/").trim_suffix("/")
		if isolated_root.is_empty() or not OS.get_user_data_dir().simplify_path().begins_with(isolated_root+"/"):
			push_error("Development preview requires its isolated user directory")
			quit(2)
			return
		expected_user = OS.get_user_data_dir()
		DirAccess.make_dir_recursive_absolute(expected_user)
	if expected_user.is_empty() or OS.get_user_data_dir().simplify_path()!=expected_user.simplify_path():
		push_error("Native observer user directory was not isolated; refuse before menu/save access")
		quit(2)
		return
	var terrain_review := "--terrain-region-review" in OS.get_cmdline_user_args()
	if not development and not terrain_review and "--native-screenshot-review" not in OS.get_cmdline_user_args():
		quit(2)
		return
	if "--terrain-a0-review" in OS.get_cmdline_user_args():
		_terrain_a0 = load("res://tools/map/terrain_a0_live.gd").new() as RefCounted
		if not _terrain_a0.call("configure"):
			push_error("A0 requires schema1 manifest and original/flat_webp mode")
			quit(2)
			return
		set_meta("terrain_a0_live",_terrain_a0)
		# node_added precedes _ready and the first relief request, including the
		# menu renderer later handed to the formal world. Both variants use it.
		node_added.connect(Callable(_terrain_a0,"install"))
	change_scene_to_file("res://scenes/formal/formal_world_menu.tscn")
	if terrain_review:
		var driver := load("res://tools/map/r57_visual_driver.gd").new() as Node
		driver.set("acceptance","terrain-region")
		root.add_child.call_deferred(driver)
