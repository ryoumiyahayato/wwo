extends Node

const TARGET_SCENE := "res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn"
const OUTPUT_DIRECTORY := "res://artifacts/holographic_workspace"

var workspace


func _ready() -> void:
	var packed_scene := load(TARGET_SCENE) as PackedScene
	if packed_scene == null:
		push_error("Unable to load holographic workspace scene")
		get_tree().quit(1)
		return

	workspace = packed_scene.instantiate()
	add_child(workspace)
	await _settle_frames(8)
	await _capture("00_global_twinkle_a")
	await get_tree().create_timer(1.6).timeout
	await _settle_frames(2)
	await _capture("00_global_twinkle_b")

	workspace._set_world_zoom(0.74)
	await _settle_frames(4)
	await _capture("01_1900_global_overview")
	await _capture("01_global_focus")

	workspace._set_world_zoom(1.65)
	await _settle_frames(4)
	await _capture("01_1900_global_war_boundaries")

	workspace._set_world_zoom(3.60)
	await _settle_frames(4)
	await _capture("01_1900_high_zoom_names")

	workspace.selected_country_id = "kingdom_of_nepal"
	workspace._zoom_to_selected_historical_entity()
	await _settle_frames(5)
	await _capture("01_nepal_full_country")

	workspace._return_to_global_world()
	workspace._set_world_zoom(0.86)
	workspace.selected_country_id = "german_empire"
	workspace._focus_selected_country()
	await _settle_frames(5)
	await _capture("02_german_empire_focus")

	workspace._enter_region()
	await _settle_frames(5)
	await _capture("02_germany_admin1")
	var german_admin1: Array = (workspace.get("_world_admin1_by_iso") as Dictionary).get("DEU", []) as Array
	if not german_admin1.is_empty():
		workspace.selected_world_admin1_id = str((german_admin1[0] as Dictionary).get("id", ""))
		workspace._enter_selected_world_admin1()
		await _settle_frames(4)
		await _capture("02_germany_admin1_local")

	workspace._return_to_global_world()
	workspace.selected_country_id = "russian_empire"
	workspace._focus_selected_country()
	await _settle_frames(5)
	await _capture("02_russian_empire_territories")

	workspace._return_to_global_world()
	workspace._set_world_zoom(0.86)
	workspace._set_layout(workspace.LAYOUT_WORKSPACE)
	await _settle_frames(5)
	await _capture("03_operation_workspace")

	workspace.selected_country_id = workspace.FOCUS_COUNTRY_ID
	workspace._focus_selected_country()
	workspace.selected_region_id = "northern_industrial_belt"
	workspace._set_info_open(true)
	await get_tree().create_timer(0.24).timeout
	await _settle_frames(5)
	await _capture("04_france_region_selected")

	workspace._enter_region()
	await _settle_frames(5)
	await _capture("05_region_layer")

	var regions: Array = workspace.get("_regions") as Array
	for index: int in range(regions.size()):
		var region: Dictionary = regions[index] as Dictionary
		var region_id: String = str(region.get("id", "region_%02d" % index))
		workspace.selected_region_id = region_id
		workspace.selected_city_id = ""
		workspace.selected_administrative_unit_id = ""
		workspace.hover_administrative_unit_id = ""
		workspace.queue_redraw()
		await _settle_frames(4)
		await _capture("05_region_%02d_%s" % [index + 1, region_id])

	workspace.selected_region_id = "northern_industrial_belt"
	workspace._enter_city("lille")
	await _settle_frames(5)
	await _capture("06_city_layer")

	get_tree().quit(0)


func _settle_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _capture(file_stem: String) -> void:
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Unable to create screenshot directory: %s" % directory_error)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Viewport screenshot is empty: " + file_stem)
		get_tree().quit(1)
		return
	var output_path := absolute_directory.path_join(file_stem + ".png")
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Unable to save screenshot %s: %s" % [output_path, save_error])
		get_tree().quit(1)
