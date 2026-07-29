extends SceneTree
## Generates the committed SAVE_VERSION=1 fixture through the current production
## character generator, snapshot, atomic writer, parser and restore path. This
## script does not define or migrate a schema.

const FIXTURE_USER_PATH: String = "user://tests/variable_state/current_save_v1.json"
const WORLD_PATH: String = "res://data/world/demo_world.json"
const PLAYER_SEED: int = 190001


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_fixture()
	GameSessionService.clear()
	var source := _create_runtime()
	if source.is_empty():
		quit(1)
		return
	var clock: SimulationClock = source["clock"] as SimulationClock
	var map_service: MapControlService = source["map"] as MapControlService
	var save_service := GameSaveService.new()
	var snapshot: Dictionary = save_service.build_snapshot(clock, map_service)
	if snapshot.is_empty():
		_fail("production build_snapshot returned an empty snapshot")
		return
	if int(snapshot.get("save_version", -1)) != GameSaveService.SAVE_VERSION:
		_fail("fixture snapshot does not use the current SAVE_VERSION")
		return
	if str(snapshot.get("selected_country_id", "")) != GameSessionService.player_character.country_id:
		_fail("fixture selected_country_id differs from the current player country")
		return
	var validation_errors: Array[String] = save_service.validate_snapshot(snapshot)
	if not validation_errors.is_empty():
		_fail("production snapshot validation failed: %s" % "; ".join(validation_errors))
		return
	var write_result: SaveOperationResult = save_service.save_to_path(
		FIXTURE_USER_PATH, snapshot
	)
	if not write_result.success:
		_fail("production atomic save failed: %s · %s" % [
			write_result.error_code, write_result.message,
		])
		return
	var load_result: SaveOperationResult = save_service.load_from_path(FIXTURE_USER_PATH)
	if not load_result.success:
		_fail("current unrefactored loader rejected generated fixture: %s · %s" % [
			load_result.error_code, load_result.message,
		])
		return
	var restored := _create_services(source["data_set"] as CoreDataSet)
	if restored.is_empty():
		quit(1)
		return
	var restore_result: SaveOperationResult = save_service.restore_snapshot(
		load_result.snapshot,
		restored["clock"] as SimulationClock,
		restored["map"] as MapControlService
	)
	if not restore_result.success:
		_fail("current unrefactored restore rejected generated fixture: %s · %s" % [
			restore_result.error_code, restore_result.message,
		])
		return
	if GameSessionService.player_character == null:
		_fail("fixture restore did not commit a player")
		return
	if str(load_result.snapshot.get("selected_country_id", "")) != GameSessionService.player_character.country_id:
		_fail("fixture restore did not preserve save-key/player-country equality")
		return
	print("FIXTURE_USER_PATH=%s" % ProjectSettings.globalize_path(FIXTURE_USER_PATH))
	print("FIXTURE_SAVE_VERSION=%d" % int(load_result.snapshot["save_version"]))
	print("FIXTURE_PLAYER_ID=%s" % str(load_result.snapshot["player_character_id"]))
	print("FIXTURE_COUNTRY_ID=%s" % str(load_result.snapshot["selected_country_id"]))
	print("FIXTURE_PLAYER_SEED=%d" % PLAYER_SEED)
	print("Current SAVE_VERSION=1 fixture generated and restored through production services.")
	quit(0)


func _create_runtime() -> Dictionary:
	var load_result: CoreDataLoadResult = CoreDataLoader.new().load_from_file(WORLD_PATH)
	if not load_result.is_success():
		_fail("world data failed to load: %s" % load_result.errors)
		return {}
	var data_set: CoreDataSet = load_result.data_set
	var country_ids: Array[String] = []
	for raw_id: Variant in data_set.countries:
		country_ids.append(str(raw_id))
	country_ids.sort()
	if country_ids.is_empty():
		_fail("world data contains no country for production character generation")
		return {}
	var character_config: CharacterGenerationConfig = CharacterGenerationConfig.load_from_file()
	if not character_config.is_valid():
		_fail("character generation config failed: %s" % character_config.error_message)
		return {}
	var generator := CharacterGenerator.new(
		data_set,
		character_config,
		DeterministicRandomService.new(PLAYER_SEED),
		StableIdService.new()
	)
	var generated: CharacterGenerationResult = generator.generate_character(
		country_ids[0], CharacterGenerator.MODE_STANDARD
	)
	if not generated.is_success():
		_fail("production character generation failed: %s" % generated.errors)
		return {}
	var player: CharacterData = generated.character
	GameSessionService.set_player(player)
	var services := _create_services(data_set)
	if services.is_empty():
		return {}
	var society := SocietySimulationService.new()
	if not society.initialize(player, data_set):
		_fail("production society initialization failed: %s" % society.initialization_error)
		return {}
	GameSessionService.society_service = society
	GameSessionService.set_world_services(
		services["clock"] as SimulationClock,
		services["map"] as MapControlService
	)
	services["data_set"] = data_set
	services["society"] = society
	return services


func _create_services(data_set: CoreDataSet) -> Dictionary:
	var map_rules := MapRulesConfig.new()
	if map_rules.load_from_file() != OK:
		_fail("map rules failed to load: %s" % map_rules.error_message)
		return {}
	var clock_config := SimulationClockConfig.new()
	if clock_config.load_from_file() != OK:
		_fail("clock rules failed to load: %s" % clock_config.error_message)
		return {}
	return {
		"clock": SimulationClock.new(clock_config),
		"map": MapControlService.new(data_set, map_rules),
	}


func _cleanup_fixture() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = FIXTURE_USER_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	push_error("FIXTURE GENERATION FAILED: " + message)
	quit(1)
