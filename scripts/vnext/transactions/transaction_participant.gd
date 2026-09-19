class_name VNextTransactionParticipant
extends RefCounted


func participant_id() -> String:
	return ""


func authoritative_snapshot() -> Variant:
	return null


## Preparation and local validation are pure candidate operations. They must not
## mutate authoritative state, emit callbacks, or retain mutable command values.
func prepare_candidate(_command: VNextTransactionCommand) -> Dictionary:
	return {"ok": false}


func validate_candidate(_candidate: Variant, _command: VNextTransactionCommand) -> bool:
	return false


## Called only after every prepare and validator has succeeded. Implementations must
## make this operation non-failing and must not emit observable callbacks mid-adopt.
func adopt_candidate(_candidate: Variant) -> void:
	pass
