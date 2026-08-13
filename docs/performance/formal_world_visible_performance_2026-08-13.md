# Formal-world visible performance audit — 2026-08-13

## Environment

- Audited `origin/master`: `83e4f305b52529625f4d86ad928bce451ea34b9f`
- Prior player-visible audit reference: `faae6f2a76cf658c00ef575e6241867add730084`
- Windows: Windows 11 IoT Enterprise LTSC, 10.0.26100, 64-bit
- CPU / memory: Intel Core i7-13700H (20 logical processors), 16 GB RAM
- GPU: NVIDIA GeForce RTX 3050 Laptop GPU, driver 572.83
- Display / viewport: 1920×1080 at 144 Hz; product content 1280×720
- Godot: `4.6.3.stable.official.7d41c59c4`
- Renderer: OpenGL 3.3 Compatibility
- VSync: enabled (`DisplayServer` mode 1)
- Execution: standalone debug product window, not the editor

The normal product path and the benchmark both instantiate the formal title and
`formal_world_main.tscn`. The benchmark writes observational JSON only; wall-clock
measurements never enter simulation or save state.

## Classification and measured root cause

Classification: **mixed rendering/UI + data/allocation + logging**. The economy
tick is not the dominant player-visible bottleneck.

The original formal map loaded PNG files through `Image.load_from_file()` while
drawing. A first run produced 120 export warnings in the visible-map scenarios.
Continuous globe motion also rebuilt projected/clipped polygons and merged
historical outlines. Phase timing measured approximately 6.8 ms per base
projection, 15.5 ms per flag clipping/triangulation cache rebuild, and 14.8 ms
per historical outline merge before the narrow algorithm changes.

The GPU profile did not identify a GPU-bound frame: CanvasItem GPU work was
approximately 2–11 ms while pan/zoom frames were about 95–140 ms. The dominant
cost was GDScript/Canvas preparation.

## Comparable before / after

Each ordinary scenario ran for 6 seconds; active 4× ran for 13 seconds. Both
runs used the same machine, SHA-derived worktrees, executable, renderer, VSync,
viewport, capture code, and debug mode.

| Scenario | Avg FPS before | Avg FPS after | 1% low before | 1% low after | Avg frame ms before | Avg frame ms after | p99 ms before | p99 ms after | Max ms before | Max ms after |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Title idle | 143.82 | 143.66 | 123.18 | 125.47 | 6.95 | 6.96 | 8.12 | 7.97 | 13.95 | 21.89 |
| Global map paused | 81.71 | 96.64 | 22.35 | 26.09 | 12.24 | 10.35 | 44.74 | 38.34 | 58.70 | 43.27 |
| Global map pan/zoom | 10.57 | 12.12 | 7.28 | 8.77 | 94.61 | 82.53 | 137.36 | 113.99 | 137.36 | 113.99 |
| Selected polity paused | 94.14 | 94.82 | 25.38 | 24.56 | 10.62 | 10.55 | 39.40 | 40.71 | 69.70 | 49.31 |
| Economy panel open | 92.80 | 92.80 | 24.70 | 24.54 | 10.78 | 10.78 | 40.48 | 40.76 | 46.49 | 55.34 |
| Simulation 1× | 66.24 | 79.88 | 16.54 | 20.25 | 15.10 | 12.52 | 60.47 | 49.39 | 67.54 | 74.49 |
| Simulation 2× | 58.46 | 83.11 | 16.36 | 21.95 | 17.11 | 12.03 | 61.13 | 45.56 | 63.78 | 50.86 |
| Simulation 4× | 74.51 | 83.02 | 19.11 | 22.61 | 13.42 | 12.04 | 52.33 | 44.22 | 97.12 | 72.67 |
| Polity/admin view | 144.21 | 144.04 | 129.75 | 128.72 | 6.93 | 6.94 | 7.71 | 7.77 | 16.31 | 19.48 |

Save changed from 151.2 ms to 122.6 ms; load changed from 42.3 ms to 39.3 ms.
Maximum measured static memory changed from 154.96 MiB to 155.21 MiB (+0.25 MiB). The visible-map
warning count changed from 120 to zero.

Selected-polity/economy-panel static p99 values were effectively flat, while
their isolated max samples varied in both directions. At 144 Hz with a 200 ms
flag animation timer these small samples are scheduler-sensitive. They are
reported rather than discarded. The consistent improvements are paused global,
continuous pan/zoom, active-speed p99, warning count, and structural call-count
guards.

## Hotspots

| Rank | Function / system | Total / call evidence | Call count | Scenario | Cause | Change |
|---:|---|---|---:|---|---|---|
| 1 | Formal map `_draw()` chain | 4,573 ms / 44.4 ms average after | 103 | Pan/zoom | Whole custom CanvasItem is redrawn for map motion and flag animation | Instrumented; remains the largest hotspot |
| 2 | `_rebuild_country_flag_cache()` | 1,104 ms / 15.1 ms after | 73 | Pan/zoom | Hemisphere clipping and required triangulation | Measured and retained for correctness |
| 3 | `_rebuild_merged_historical_outlines()` | 748 ms / 10.2 ms after, about 14.8 ms before | 73 | Pan/zoom | Repeated bounds scans inside merge loop | Maintain bounds alongside merged polygons |
| 4 | `_ensure_projection_cache()` base work | 524 ms / 7.2 ms after | 73 | Pan/zoom | Coastline projection and visible anchors | Existing dirty cache retained; no speculative rewrite |
| 5 | Historical flag resource load | 120 warnings before, zero after | 60 source flag ids | First visible map / zoom | Direct image-file reads bypassed Godot imports | Imported `Texture2D` lifecycle and per-flag-id reuse |

## Changes and correctness

- Historical assets are loaded as imported `Texture2D` resources and converted
  once to the existing 144×96 runtime texture size. Entities sharing a stable
  `flag_id` share one texture.
- Merged-outline bounds are maintained incrementally instead of rescanned in the
  inner loop.
- Observational counters cover draw, projection, flag cache, outline cache, and
  resource load counts/times.
- Structural regression guards verify one resource load per stable flag id, no
  map projection rebuild for HUD-only changes, no geometry rebuild for flag
  animation redraw, and no direct `Image.load_from_file()` in formal flag draw.

No simulation formula, tick frequency, authoritative data, selection identity,
map boundary data, LOD rule, save schema, or deterministic ordering changed.

## Validation

- Unified validation: passed, including formal ten-year balance, retained
  services, three-year AI economy, save migration, and the new performance lane.
- Formal integration: 81 checks, zero failures.
- Formal performance structural regression: 11 checks, zero failures.
- Formal Time stable contract: 117 checks, zero failures.
- Formal Time known-defects regression: 93 checks, zero failures.
- Codex audit regression: 31 checks, passed.
- Visible Compatibility interaction probe: passed.
- `git diff --check`: passed.

The final debug GUI journey covered title, formal-world entry, paused map,
pan/zoom, economy summary, 1×/2×/4× time, visible date advancement, F5 save,
and F9 load. The saved date restored exactly. Polity/admin enter/return is
covered by the visible Compatibility interaction probe; the later manual
selection attempt ended after the title menu emitted its existing
`set_input_as_handled` null-value error, so it is not claimed as a second
manual pass.

The exact-head Windows Release export completed with exit code zero. Entering
the formal world in that executable then crashed natively with Windows
`0xc0000005`. A separately exported, unmodified `83e4f305` baseline crashed at
the same transition, establishing this as a current-master Release-only defect,
not a regression introduced by these performance changes. The export also
retains the existing Windows version-string warning for `0.001a`.

The default Windows `python.exe`/`py.exe` registration on this machine was
broken. Unified validation was run with the bundled workspace Python prepended
to `PATH`; all three static economy audits passed.

## Remaining hotspot and verdict

The global globe remains CPU-bound during continuous rotation/zoom; 11.89 FPS is
still below the 60 FPS product target. The measured stutter and startup/logging
spikes are materially reduced without semantic loss, but this is not a claim
that the map now meets its final frame budget. The next measured optimization
should split/cache the static map CanvasItem presentation so the 200 ms flag
animation does not redraw unrelated HUD and unchanged borders. That architectural
step was intentionally not folded into this narrow repair.
