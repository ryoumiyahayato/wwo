class_name VNextTransactionValidator
extends RefCounted


## Validators receive only detached command/bundle views and must remain pure.
func validate(
	_command: VNextTransactionCommand, _bundle: VNextTransactionCandidateBundle
) -> bool:
	return false
