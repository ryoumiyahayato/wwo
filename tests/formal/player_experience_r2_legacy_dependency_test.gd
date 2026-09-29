extends SceneTree
## Phase L product-boundary gate. Retained migration code may stay in the
## repository, but the Formal product roots must not import those runtimes.

const MAIN_SCENE := "res://scenes/formal/formal_world_main.tscn"
const PRODUCT_ROOTS: Array[String] = [
	"res://scenes/formal",
	"res://scripts/formal",
]
const FORBIDDEN_PRODUCT_REFERENCES: Array[String] = [
	"res://scenes/v2_2/",
	"res://scripts/v2_2/",
	"res://scripts/v2_3/",
	"res://scenes/alpha/",
	"res://scripts/alpha/",
	"res://data/world_map/characters.json",
	"res://scripts/world_map/world_map_canvas.gd",
	"res://scenes/ui_spikes/holographic_workspace/holographic_workspace_spike.tscn",
]
const RETAINED_MIGRATION_FILES: Array[String] = [
	"res://scripts/v2_2/v2_employment_service.gd",
	"res://scripts/v2_2/v2_ledger_service.gd",
	"res://scripts/alpha/alpha_enterprise_service.gd",
	"res://scripts/v2_3/relationship_service.gd",
	"res://scripts/v2_3/communication_service.gd",
	"res://scripts/v2_3/travel_execution_service.gd",
	"res://scripts/vnext/economy/personal_wallet.gd",
]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var product_files: Array[String] = []
	for root_path: String in PRODUCT_ROOTS:
		product_files.append_array(_collect_product_files(root_path))
	_check(not product_files.is_empty(), "Formal product dependency roots are present")
	for path: String in product_files:
		var source := FileAccess.get_file_as_string(path)
		for forbidden: String in FORBIDDEN_PRODUCT_REFERENCES:
			_check(
				not source.contains(forbidden),
				"%s does not reference retained/dead product path %s" % [path, forbidden]
			)

	var shared_runtime := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_runtime.gd"
	)
	var shared_hud := FileAccess.get_file_as_string(
		"res://scripts/ui_spikes/holographic_workspace/holographic_workspace_hud_polish.gd"
	)
	for retired_token: String in ["switch_character", "mark_read", "activity_unread"]:
		_check(not shared_runtime.contains(retired_token), "shared active renderer retired %s" % retired_token)
		_check(not shared_hud.contains(retired_token), "HUD polish retired %s" % retired_token)

	for retained_path: String in RETAINED_MIGRATION_FILES:
		_check(FileAccess.file_exists(retained_path), "migration candidate remains retained: %s" % retained_path)

	var application := (load(MAIN_SCENE) as PackedScene).instantiate() as FormalWorldApplication
	root.add_child(application)
	for _index: int in 24:
		await process_frame
	_check(application.formal_simulation.initialized, "Formal product initializes after legacy retirement")
	_check(application._character_profiles.is_empty(), "Formal product never loads prototype character profiles")
	_check(application._world_events.is_empty(), "Formal product never exposes prototype agendas as personal information")
	_equal(
		application.formal_primary_navigation_ids(),
		[
			FormalWorldApplication.WORKSPACE_PERSON,
			FormalWorldApplication.WORKSPACE_ECONOMY,
			FormalWorldApplication.WORKSPACE_ORGANIZATION,
			FormalWorldApplication.WORKSPACE_MAP,
		],
		"primary navigation excludes superseded empty product tabs"
	)
	application.queue_free()
	await process_frame
	print("Player Experience R2 L: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 or checks <= 0 else 0)


func _collect_product_files(root_path: String) -> Array[String]:
	var output: Array[String] = []
	for file_name: String in DirAccess.get_files_at(root_path):
		if file_name.ends_with(".gd") or file_name.ends_with(".tscn") or file_name.ends_with(".tres"):
			output.append(root_path.path_join(file_name))
	for directory_name: String in DirAccess.get_directories_at(root_path):
		output.append_array(_collect_product_files(root_path.path_join(directory_name)))
	return output


func _check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("FAIL: " + label)


func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(
		actual == expected,
		label if actual == expected else "%s | actual=%s expected=%s" % [
			label, var_to_str(actual), var_to_str(expected)
		]
	)
