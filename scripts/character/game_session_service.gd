class_name GameSessionService
extends RefCounted
## Process-local authoritative session shared by presentation scenes.

const SettlementLogServiceType = preload("res://scripts/devtools/settlement_log_service.gd")
const PerformanceStatsServiceType = preload("res://scripts/devtools/performance_stats_service.gd")

static var player_character: CharacterData
static var selected_country_id: String = ""
static var current_action: ActionInstanceData
static var action_id_service := StableIdService.new()
static var society_service: SocietySimulationService
static var world_clock: SimulationClock
static var world_map_service: MapControlService
static var world_autosave: AutosaveCoordinator
static var developer_mode: bool = false
static var settlement_log := SettlementLogServiceType.new()
static var performance_stats := PerformanceStatsServiceType.new()
static var pending_load_path: String = ""


static func set_player(character: CharacterData) -> void:
	player_character = character
	selected_country_id = "" if character == null else character.country_id
	current_action = null
	action_id_service = StableIdService.new()
	society_service = null
	world_clock = null
	world_map_service = null
	world_autosave = null
	developer_mode = false
	settlement_log = SettlementLogServiceType.new()
	performance_stats = PerformanceStatsServiceType.new()
	pending_load_path = ""


static func clear() -> void:
	player_character = null
	selected_country_id = ""
	current_action = null
	action_id_service = StableIdService.new()
	society_service = null
	world_clock = null
	world_map_service = null
	world_autosave = null
	developer_mode = false
	settlement_log = SettlementLogServiceType.new()
	performance_stats = PerformanceStatsServiceType.new()
	pending_load_path = ""


static func set_world_services(
	simulation_clock: SimulationClock,
	map_service: MapControlService,
	autosave: AutosaveCoordinator = null
) -> void:
	world_clock = simulation_clock
	world_map_service = map_service
	if autosave != null:
		world_autosave = autosave
	if society_service != null:
		society_service.attach_world(world_clock, world_map_service)


static func has_world_services() -> bool:
	return world_clock != null and world_map_service != null


static func transfer_player(character: CharacterData) -> void:
	player_character = character
	selected_country_id = "" if character == null else character.country_id
	current_action = null


static func has_player() -> bool:
	return player_character != null
