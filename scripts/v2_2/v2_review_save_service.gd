class_name V2ReviewSaveService
extends GameSaveService
## V2.2 adapter that retains the previous verified primary as a recovery backup.


func _write_atomic_json(path: String, snapshot: Dictionary) -> String:
	return AtomicJsonFileStore.write_verified(
		path,
		snapshot,
		Callable(self, "_verify_v2_2_temporary"),
		true
	)
