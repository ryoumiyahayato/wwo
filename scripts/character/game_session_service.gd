class_name GameSessionService
extends RefCounted
## Minimal scene-to-scene state for the M4 player character.

const SettlementLogServiceType = preload("res://scripts/devtools/settlement_log_service.gd")
const PerformanceStatsServiceType = preload("res://scripts/devtools/performance_stats_service.gd")

static var player_character: CharacterData
static var selected_country_id: String = ""
static var current_action: ActionInstanceData
static var action_id_service := StableIdService.new()
static var society_service: SocietySimulationService
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
	developer_mode = false
	settlement_log = SettlementLogServiceType.new()
	performance_stats = PerformanceStatsServiceType.new()
	pending_load_path = ""


static func transfer_player(character: CharacterData) -> void:
	player_character = character
	selected_country_id = "" if character == null else character.country_id
	current_action = null


static func has_player() -> bool:
	return player_character != null
