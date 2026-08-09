# vNext snapshot persistence boundary

VNextWorldRuntime owns the vNext v2 composition and its in-memory serialization boundary. Disk access remains outside world_runtime.gd.

VNextWorldSnapshotStore owns the file boundary between a complete runtime snapshot and a caller-supplied JSON path. It does not choose a player save location, create a global save manager, register an autoload or hold runtime business state.

AtomicJsonFileStore owns verified temporary writes, backup rotation, atomic replacement, cleanup and rollback. The vNext store reuses that generic durability boundary.

## Save contract

Saving performs these steps:

1. obtain the complete VNextWorldRuntime.snapshot() payload;
2. write JSON to a temporary file through AtomicJsonFileStore.write_verified();
3. parse the temporary file and require an object root;
4. restore the candidate into a fresh VNextWorldRuntime;
5. accept the temporary file only when v2 schema, all four owner snapshots, JSON-safe time and person identity consistency validate;
6. atomically replace the primary while retaining the previous valid primary as .bak;
7. return the existing SaveOperationResult type.

Temporary verification never mutates the caller's runtime. Nested wallet and event occurrence numbers are normalized by their owner restore contracts, and runtime total_minutes remains an int.

## Load contract

Loading validates the caller-supplied primary path first. A file is valid only when its JSON root is an object and a fresh runtime accepts the complete vnext_world_runtime_v2 payload.

If the primary is invalid or unavailable, the store tries primary + .bak. A valid backup is restored into the target runtime and reported as a successful SaveOperationResult.

If neither primary nor backup is valid, loading fails without deleting the bad files, repairing schema fields, guessing a v1-to-v2 migration or touching the target runtime. Runtime restore is transactional, so a rejected complete snapshot leaves the existing target composition unchanged.

## Scope and implementation status

The persisted payload is the complete v2 composition: player identity, personal wallet, actual location, event knowledge and the single runtime total_minutes value. The store implementation itself remains unchanged in this integration because its existing verified atomic file mechanics are schema-agnostic and already delegate schema validation to VNextWorldRuntime.restore().

This boundary does not modify or replace FormalWorldSimulation persistence and never uses user://formal_world_1900.json.
