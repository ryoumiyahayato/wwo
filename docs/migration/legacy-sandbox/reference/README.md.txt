# Bounded region observation module

Reusable Godot 4.6 training scenery. This is a library, not a new game or main scene.
Coordinates are local metres. The region is fictional and not geographically registered.
It owns no authoritative world state, clock, actors, military/economic commands or saves.
The host owns UI, camera, movement and permissions. Main-repository integration is a separate PR.

## API

Instantiate `LayeredTerrain` from the module resource below as a `Node3D` and add it to the host tree.
Connect `prepared`, `changed` and `failed(message)` before calling `begin(config)`.

```text
res://modules/region_observation/layered_terrain.gd
```

- `begin(config: Dictionary)`: restart loading. `training_only` must be true; false is rejected.
- `base_path`: project-local asset root. Default is `res://`; a trailing slash is added when needed.
- `center`: local X/Z in a `Vector2`. Default is zero; coordinates are clamped to the region.
- `span_m`: view span, clamped to 50–75000 metres. Default is 50000.
- `collision_enabled` / `collision_layer`: default true / 1. Collision is local training support only.
- `update_view(center: Vector2, span_m: float)`: change observation targets without creating world facts.
- `sample_height(x: float, z: float) -> float`: source-backed local height. Returns `NAN` before data or outside coverage.
- `is_ready()`: the first real source-backed patch is installed, not the whole queue.
- `is_collision_ready(position: Vector3)`: the native fine surface and every raw collision tile for the local safety square are installed. Returns false while an external native owner is active.
- `set_external_native_owner(active: bool)`: true hides this module's native/fine surfaces, clears its local collision and stops native requests; the surrounding 99 regional tiles remain available. False reuses the observation cache. The external owner remains solely responsible for its actors, terrain edits, collision and authoritative support queries.
- `create_surface_material(options: Dictionary = {}) -> ShaderMaterial`: reuse the common surface rules and seven existing textures. Options are `native_surface`, `coverage_enabled`, `far_mesh`, `coverage_cells` (default 10), `detail_coverage: Texture2D` and `use_vertex_damage`. The original editable training terrain supplies its own 100x100 coverage for 50m chunks; close uses coverage false, far uses coverage true. Optional damage reads the original owner's real `COLOR.r - COLOR.g` crater data, not simulated edits in this observer.
- `apply_command(...)` / `apply_explosion(...)`: explicitly return `ok: false, error: unsupported`. This presentation component does not deform terrain or silently report edit success.
- `get_status()`: bounded presentation status, counts, owner state and `resource_notes`; not a world snapshot. `last_mesh_install_usec` / `last_shape_install_usec` report the last corresponding installation. `max_mesh_install_usec` / `max_shape_install_usec` retain all corresponding installation maxima for the current lifecycle, including staged mesh uploads. Owner switches do not reset them. These are installation timings, not a measurement or attribution of total frame time.
- `close()`: stop processing, join the worker and release owned resources; reset last/max installation timings. Also called on tree exit. `begin()` starts a fresh lifecycle through `close()`.

Factory materials are updated when shared textures finish loading. Connect `changed` to the host's frame request when using a static `UPDATE_ONCE` viewport. It is emitted after material updates. Static completed observation work sleeps until the view or owner changes.

`TerrainHeightSource` is pure data work. Reading, sampling, patch/transition construction and raw collision-face generation do not access the scene tree.
Height sampling uses the same b-c triangle diagonal as the original 4m fine meshes and observer collision. External editable training retains its own support/collision implementation.

## Bounds and sources

The regional cache contains at most 100 coarse 5km tiles rendered at 250m spacing. The central native 5km cache contains 100 tiles of 500m, normally rendered at 20m spacing. Once prepared, that native cache is retained and shown at every observation span: there is no 8500m whole-patch visibility switch. The central regional tile is hidden while native terrain or an external native owner is visible.

Only spans below 1800m request the local 3x3 native fine neighborhood: at most nine of those native tiles are replaced by original 4m meshes, not an additional full native fine layer. Native20/fine4 and region250/native boundaries are joined by coarse-side boundary polygon fans following the finer contour. There are no skirts, fine-vertex flattening or observer coverage-mask seam concealment. Only changed LOD/neighbor signatures rebuild. A bounded transition stages one mesh upload per frame, then replaces all matched boundary partners atomically. Temporary transition arrays/nodes are additional to the steady cache.

One worker runs at a time. At most one mesh or one collider installation occurs per frame. Observer collision uses worker-generated raw 4m b-c triangle faces, independently of stitched display geometry and without display-mesh readback. Its 100m tiles cover only the view centre's +/-64m safety square: at most nine tiles, each 25x25 cells / 1250 triangles. No whole-5km or whole-region collision is created.

The 50km and 25km views share the original regional 50m height source; native terrain uses the original 4m source. No source height is exaggerated or overwritten. All LODs use the same regional macro color and original Y-up RGB normal. Local road/field/rock controls enter continuously at 8–64m/pixel, retaining the native boundary fade; grain/bump has a separate finer footprint limit. No extra 5x normal or secondary hillshade is applied. The shared shader uses mip/anisotropic texture filtering. The main host's seven texture imports enable mipmaps; this module-only synchronization does not modify military assets or their import settings.

This module sync copies no binary assets, heights or import files and does not independently verify their availability. Required metadata and regional height data are resolved under `base_path`:

```text
continuous/assets/region.json       # continuous-training-region-v1, training_only
continuous/assets/height_50m.f32     # 1001 x 1001 float32; required
ridgevale/assets/height_4m.f32       # 1251 x 1251 float32; optional native detail
```

Missing required regional data emits `failed`; missing native detail leaves the valid regional view available.
Optional colour, normal, control and detail textures retain the original `continuous/assets/`, `ridgevale/assets/` and `cedar/assets/` paths.
Missing optional textures are reported in `resource_notes`. They do not create substitute geographic facts.

## Canonical source / vendor adaptation

Fixed current copies from the main WWO repository:

```text
wwo/scripts/presentation/terrain/layered_terrain.gd
  -> military-godot/modules/region_observation/layered_terrain.gd
wwo/scripts/presentation/terrain/terrain_height_source.gd
  -> military-godot/modules/region_observation/terrain_height_source.gd
wwo/shaders/presentation/terrain/layered_ground.gdshader
  -> military-godot/modules/region_observation/layered_ground.gdshader
```

Only three constants in `LayeredTerrain` are adapted: the two preloads point to `res://modules/region_observation/`, and the default asset root changes from `res://assets/terrain/region_slice/` to `res://`.
The height source and shader are unchanged. All other terrain logic is unchanged.
Treat these files as vendored copies of that canonical implementation, not an independent terrain rewrite.

## Validation boundary

The new common algorithms have completed one real-window route in the main host, as reported by the lead. That main-host run is not an independent engine run of this military module or a claim that every subsequent small source adjustment has been independently validated here.

This synchronization performed no Godot run, tests or export. The module has no independent main scene or game entry. It does not make the military extraction independently runnable or restore external host/vehicle/assets dependencies. Main-host routing and isolated training acceptance remain with the lead.

An observed roughly 152ms frame spike is still unexplained. The lifecycle maximum installation counters help distinguish mesh and shape installation, but do not prove a cause or that the frame spike has disappeared. No shader/physics attribution or disappearance is claimed.
