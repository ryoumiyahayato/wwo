class_name GameSessionService
extends RefCounted
## Process-local authoritative session shared by presentation scenes.

const SettlementLogServiceType = preload("res://scripts/devtools/settlement_log_service.gd")
const PerformanceStatsServiceType = preload("res://scripts/devtools/performance_stats_service.gd")

static var player_character: CharacterData
static var selected_country_id: String = ""
static var current_action: ActionInstanceData
static var recent_action_result: Dictionary = {}
static var action_history: Array[Dictionary] = []
static var action_id_service := StableIdService.new()
static var society_service: SocietySimulationService
static var world_clock: SimulationClock
static var world_map_service: MapControlService
static var world_autosave: AutosaveCoordinator
static var developer_mode: bool = false
static var settlement_log := SettlementLogServiceType.new()
static var performance_stats := PerformanceStatsServiceType.new()
static var pending_load_path: String = ""
static var pending_menu_message: String = ""


static func set_player(character: CharacterData) -> void:
	player_character = character
	selected_country_id = "" if character == null else character.country_id
	current_action = null
	recent_action_result = {}
	action_history = []
	action_id_service = StableIdService.new()
	society_service = null
	world_clock = null
	world_map_service = null
	world_autosave = null
	developer_mode = false
	settlement_log = SettlementLogServiceType.new()
	performance_stats = PerformanceStatsServiceType.new()
	pending_load_path = ""
	pending_menu_message = ""


static func clear() -> void:
	player_character = null
	selected_country_id = ""
	current_action = null
	recent_action_result = {}
	action_history = []
	action_id_service = StableIdService.new()
	society_service = null
	world_clock = null
	world_map_service = null
	world_autosave = null
	developer_mode = false
	settlement_log = SettlementLogServiceType.new()
	performance_stats = PerformanceStatsServiceType.new()
	pending_load_path = ""
	pending_menu_message = ""


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


static func archive_current_action(character: CharacterData = null) -> bool:
	var action: ActionInstanceData = current_action
	if action == null or not action.is_terminal():
		return false
	if action.status == ActionInstanceData.STATUS_COMPLETED and not action.domain_effect_applied:
		return false
	archive_action(action, character)
	current_action = null
	return true


static func archive_action(
	action: ActionInstanceData, character: CharacterData = null
) -> Dictionary:
	if action == null or not action.is_terminal():
		return {}
	var record: Dictionary = build_action_result_record(action, character)
	if record.is_empty():
		return record
	recent_action_result = record.duplicate(true)
	var action_id: String = str(record.get("action_id", ""))
	var already_recorded: bool = false
	for existing: Dictionary in action_history:
		if str(existing.get("action_id", "")) == action_id:
			already_recorded = true
			break
	if not already_recorded:
		action_history.append(record.duplicate(true))
	while action_history.size() > 100:
		action_history.pop_front()
	return record


static func build_action_result_record(
	action: ActionInstanceData, character: CharacterData = null
) -> Dictionary:
	if action == null or not action.is_terminal() or action.id.is_empty():
		return {}
	var result_hour: int = (
		action.completion_hour
		if action.completion_hour >= 0
		else action.last_update_hour
	)
	var before: Dictionary = action.applied_effects.get("_before", {}) as Dictionary
	var skill_id: String = str(before.get("skill_id", ""))
	var skill_delta: int = int(action.applied_effects.get("skill_delta", 0))
	if (
		character != null
		and not skill_id.is_empty()
		and before.has("skill_value")
	):
		skill_delta = (
			int(character.skills.get(skill_id, int(before["skill_value"])))
			- int(before["skill_value"])
		)
	var wealth_delta: int = int(action.applied_effects.get("wealth_delta", 0))
	wealth_delta -= int(action.context.get("funding_cost", 0))
	return {
		"action_id": action.id,
		"definition_id": action.definition_id,
		"actor_character_id": action.actor_character_id,
		"target_id": action.target_id,
		"study_skill_id": str(action.context.get("study_skill_id", "")),
		"status": action.status,
		"outcome_code": action.outcome_code,
		"result_description": (
			action.result_description
			if not action.result_description.is_empty()
			else _terminal_status_label(action.status)
		),
		"skill_id": skill_id,
		"skill_delta": skill_delta,
		"wealth_delta": wealth_delta,
		"duration_hours": maxi(result_hour - action.start_hour, 0),
		"completion_hour": result_hour,
	}


static func dismiss_recent_action_result() -> void:
	recent_action_result = {}


static func restore_action_results(
	recent_result: Dictionary, history: Array[Dictionary]
) -> void:
	recent_action_result = normalize_action_result_record(recent_result)
	action_history = []
	for record: Dictionary in history:
		action_history.append(normalize_action_result_record(record))


static func normalize_action_result_record(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	var normalized: Dictionary = record.duplicate(true)
	for field: String in [
		"skill_delta", "wealth_delta", "duration_hours", "completion_hour",
	]:
		normalized[field] = int(record.get(field, 0))
	return normalized


static func _terminal_status_label(status: String) -> String:
	return str({
		ActionInstanceData.STATUS_COMPLETED: "行动已完成",
		ActionInstanceData.STATUS_CANCELLED: "行动已取消",
		ActionInstanceData.STATUS_INTERRUPTED: "行动已中断",
	}.get(status, "行动已结束"))


static func has_player() -> bool:
	return player_character != null
