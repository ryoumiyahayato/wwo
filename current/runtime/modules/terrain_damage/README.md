# Game terrain deformation (Godot 4)

A small, deterministic fictional-game terrain module. This is **real mesh displacement plus replacement concave collision**, not a decal or dark circle. It implements open bowl-shaped depressions, not tunnels, caves, arbitrary Boolean cuts or destruction of rock arches.

## Supported source

The reused plains, hills_terraces and rock_arch GLBs have a separate named `*_Terrain` mesh. Only that surface is copied and replaced at runtime. Each source must be a single complete axis-aligned rectangular triangle grid, with one height per XZ vertex and two complementary triangles per cell. Vertical, overlapping, missing-cell, multi-surface and non-grid meshes are explicitly refused. This intentionally does not deform the rock-arch `Obstacles` mesh or the plinth. Original GLBs and mesh resources are untouched; source material and interpolated vertex colors/UVs are retained.

All three supplied assets pass at scale 5 (40 m square), translation `(0,0,6)`. Configure after tile scale/placement, then keep it static. Geometry is baked into world coordinates; parent the controller under a stable world root. A transformed/moving parent after setup is unsupported.

## Integration

1. Instantiate this script as Node3D under the scene root.
2. Locate the GLB MeshInstance3D whose name contains `Terrain`, not `Obstacles` or `Plinth`.
3. Call `configure_from_mesh(source)`, and check returned `ok`.
4. Query `terrain_height(world_position)`; NAN means no supported surface.
5. Call `apply_command(Vector3(x,height,z), "dig")` or `"crater"`.
6. Call `flush_updates()` once after a batch, outside a physics callback (defer it if necessary). Visual and collision publish together. Allow a physics tick before collision queries.

Fixed game presets: dig radius 1.8 m/depth 1.1 m; crater radius 2.4 m/depth 1.1 m. These are artistic game settings, unrelated to physical explosive quantities. A smooth bowl tapers to zero displacement at the edge. Overlapping commands accumulate with a 3 m maximum local drop. Commands reject invalid preset/layer, nonfinite coordinates, whole-circle out-of-bounds, wrong surface height (>1.5 m), and >128-command budget. A center's Y should be refreshed from terrain_height before repeated operations. This module does not decide whether a placement under an obstacle is allowed: the construction host must check obstacle clearance separately.

The terrain_changed signal includes ok/kind/center/radius/depth/index/collision_pending. `apply_command` changes queryable heights immediately but only queues visual/collision publication. The source Terrain subtree's previous collision is disabled. Replacement collision layer is **8**, mask 0. Keep obstacle bodies on 8 and never add a broad collider over/under this surface that could become a false floor. No per-frame rebuild is scheduled by this module.

`save_state()` returns JSON-safe version/source identity/command data. `replay_state(state)` validates and rolls back on invalid commands, publishes once and emits one replay event. The source identity includes source bounds/name/transform; states cannot be applied to differently placed tiles. `reset()` restores original copied surface and collision, retaining controller ownership. Free the whole tile and controller together when switching terrain. Removing only the controller is not an uninstall operation.

## Budgets / limits

Subdivision edge target 0.65 m, maximum subdivision factor 16 and 250,000 expanded vertices. Actual tested expanded vertices: plains 50,784; hills 69,984; rock arch terrain 93,750. Geometry rebuild is a full bounded tile, not an optimized streaming terrain engine; collision is rebuilt once per flush, not each rendered frame. Height lookup scans triangles and must not be used for hundreds of moving units every frame. No Android frame-rate or device performance claim has been made; device profiling remains necessary. Deep cumulative craters can reach below the decorative tile plinth; prototype placement should avoid deep repeated cuts near tile edges.

## Test

Run from project root:

    godot --headless --path . --script res://modules/terrain_damage/test_terrain_damage.gd

The test loads all three real GLBs, scales and translates them, checks physics ray hits above and after a dig (>0.9 m lowering), confirms no old collision lid, tests actual reset collision, JSON roundtrip replay, malformed-state rollback, boundaries/layers/wrong heights, source/material/color preservation, untouched obstacles/plinths, repeated digs/craters, batched collision rebuilding, depth cap, and rejection of a solid non-heightfield source. `test_results.log` is the recorded run.
