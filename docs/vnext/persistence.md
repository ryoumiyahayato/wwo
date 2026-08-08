# vNext snapshot persistence boundary

`VNextWorldRuntime` owns vNext runtime state. It remains responsible only for runtime behavior plus the serialization boundary exposed by `snapshot()` and `restore()`. Disk access is not part of `world_runtime.gd`.

`VNextWorldSnapshotStore` owns the file boundary between a runtime snapshot and a caller-supplied JSON file path. It does not choose a player save location, create a global save manager, register an autoload, or hold runtime business state.

`AtomicJsonFileStore` owns the atomic file mechanics. vNext persistence reuses its verified temporary write, optional previous-primary backup, atomic replacement, cleanup, and rollback behavior instead of reimplementing rename, temporary-file handling, backup rotation, replacement, or rollback.

## Save contract

Saving performs these steps:

1. obtain `runtime.snapshot()`;
2. ask `AtomicJsonFileStore.write_verified()` to write a temporary JSON file;
3. read the temporary JSON back and require an object root;
4. create a fresh `VNextWorldRuntime` and call `restore(candidate)` on that fresh runtime;
5. accept the temporary file only if the fresh runtime accepts the candidate;
6. atomically replace the primary while retaining the previous valid primary as `.bak`;
7. return the existing `SaveOperationResult` type.

Temporary verification never mutates the caller's runtime. JSON-round-tripped integral numbers are validated by the current `VNextWorldRuntime.restore()` contract and normalized back to runtime integers.

## Load contract

Loading checks the caller-supplied primary path first. A file is considered valid only when its JSON root is an object and a fresh `VNextWorldRuntime` accepts it through `restore()`.

If the primary is invalid or unavailable, the store tries `primary + ".bak"`. A valid backup is restored into the target runtime and reported as a successful `SaveOperationResult`.

If neither primary nor backup is valid, loading fails. The store does not delete the bad primary, overwrite the backup, repair schema fields, migrate unknown data, or introduce another save schema.

Restore failure is atomic at the target boundary: invalid files are validated against a fresh runtime before the target is touched, and `VNextWorldRuntime.restore()` itself validates before committing its state. A failed load therefore leaves the target runtime unchanged.

## Current scope

The persisted snapshot is exactly the current first-stage `VNextWorldRuntime.snapshot()` payload. At present that means only the existing vNext runtime schema identifier and `total_minutes`.

This boundary contains no player snapshot, economy snapshot, travel snapshot, social snapshot, organization snapshot, AI snapshot, migration framework, or universal save schema. It does not modify or replace `FormalWorldSimulation` persistence and never uses `user://formal_world_1900.json`.
