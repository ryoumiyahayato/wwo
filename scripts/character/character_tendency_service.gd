class_name CharacterTendencyService
extends RefCounted
## Applies config-driven life events; no frame loop or global character scan.

var config: CharacterGenerationConfig


func _init(generation_config: CharacterGenerationConfig) -> void:
	config = generation_config


func apply_event(character: CharacterData, event_id: String, intensity: float = 1.0) -> bool:
	if character == null or not config.tendency_events.has(event_id):
		return false
	var deltas: Dictionary = config.tendency_events[event_id] as Dictionary
	for raw_key: Variant in deltas:
		var key: String = str(raw_key)
		var old_value: int = int(character.tendencies.get(key, 0))
		var delta: int = roundi(float(deltas[raw_key]) * intensity)
		character.tendencies[key] = clampi(old_value + delta, -100, 100)
	refresh_known_tendencies(character)
	return true


func refresh_known_tendencies(character: CharacterData) -> void:
	character.known_tendencies.clear()
	for raw_key: Variant in character.tendencies:
		var key: String = str(raw_key)
		character.known_tendencies[key] = config.describe_tendency(
			key, int(character.tendencies[key])
		)

