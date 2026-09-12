class_name VNextSyntheticCrossDomainValidator
extends VNextTransactionValidator


func validate(command: VNextTransactionCommand, _bundle: VNextTransactionCandidateBundle) -> bool:
	return not bool(command.payload().get("reject_cross_domain", false))
