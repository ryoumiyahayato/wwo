# vNext runtime foundation

The current vNext runtime is isolated from the formal product. It is not a formal product entry point and does not replace any existing product entry point.

`VNextWorldRuntime` is the only current vNext runtime owner. Its only business state is `total_minutes`, stored internally as `_total_minutes`.

`Dictionary` is used only at the serialization boundary exposed by `snapshot()` and `restore()`. It is not the runtime's internal state container.

`restore()` is transactional: candidate snapshot values are read and validated before `_total_minutes` is changed. A rejected restore leaves the runtime snapshot unchanged.

Runtime `total_minutes` is always an `int`. A serialized JSON number may parse back as a `float`, so `restore()` accepts a non-negative numeric value only when it is finite and numerically integral. Accepted values are stored as `int`; fractional values are always rejected.

The current vNext runtime has no player, personal economy, world economy, travel, geography business logic, social system, communication system, organization system, politics, events, or AI.

Later systems must not write `_total_minutes` directly. Time changes remain owned by `VNextWorldRuntime` through its public contract.

Later vNext work must not introduce a universal `Context` as a catch-all state or service container.

This foundation does not connect to `FormalWorldSimulation`, the current product UI, the current formal save path, or any other formal product behavior.
