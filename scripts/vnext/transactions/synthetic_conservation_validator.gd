class_name VNextSyntheticConservationValidator
extends VNextTransactionValidator


func validate(
	_command: VNextTransactionCommand, bundle: VNextTransactionCandidateBundle
) -> bool:
	var before_total: int = 0
	var candidate_total: int = 0
	for participant_id: String in bundle.participant_ids():
		var before: Variant = bundle.before_snapshot_for(participant_id)
		var candidate: Variant = bundle.candidate_for(participant_id)
		if typeof(before) != TYPE_DICTIONARY or typeof(candidate) != TYPE_DICTIONARY:
			return false
		var before_dictionary: Dictionary = before
		var candidate_dictionary: Dictionary = candidate
		if (
			typeof(before_dictionary.get("value")) != TYPE_INT
			or typeof(candidate_dictionary.get("value")) != TYPE_INT
		):
			return false
		before_total += int(before_dictionary.get("value"))
		candidate_total += int(candidate_dictionary.get("value"))
	return before_total == candidate_total
