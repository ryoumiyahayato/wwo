# 1900 2D Society and War Simulation (In Development)

A 2D, offline, pausable, real-time social and warfare simulation built with Godot. The player begins as an individual in a fictional country and gradually gains influence through skills, careers, organizations, and relationships.

## Current Scope

The target P0 Demo includes two fictional countries, a two-layer 2D map, randomized character starts, actions and organizations, simplified AI, succession, save/load support, and development tools. The project has not yet reached Demo status and must currently be understood according to the following:

* Background simulation and state consistency: an automated regression baseline is in place, and the current unified validation suite passes.
* Time progression and one-off learning actions: previous manual testing with clean user data largely passed.
* Core social progression: work, the first relationship, and the first organization and position entry points have received balance and content fixes. Automated budget regression across 1,000 standard seeds now reaches 100%. In this round, the agent also completed the work, relationship, and organization flows through visible controls in a fresh Release `user://`; independent manual re-validation by the user is still required.
* Production UI: the unified left-side drawer, separation of current and recent actions, world-event notifications, and character-development recommendations have been implemented. The agent has successfully exercised them through actual window interaction in this round, but independent user acceptance testing has not yet been completed.
* War state: the current authoritative world state is peace. Map lines represent national borders and control boundaries. During peacetime there is no military control pressure, and control support is disabled.
* Windows Release: the current x86-64 single-file EXE has been re-exported and independently tested by the agent for startup, saving, full exit, restart and load, and normal exit. Independent user-side smoke testing remains incomplete.
* P0-R1: not passed. Demo: not reached.

The map supports panning, mouse-wheel zooming, de jure borders, de facto jurisdiction coloring, cities, railways, and national/control boundaries during peacetime. Contested hatching and frontline control support are shown only when the authoritative state explicitly indicates war. Controls that directly modify authoritative state are visible only in development mode.

## Environment Requirements

* Windows 11 x86-64 (current development, audit, and historical export environment)
* Godot Standard `4.6.3.stable.official.7d41c59c4`
* Compatibility renderer
* Strongly typed GDScript

Windows 10 is a target compatibility platform, but has not yet been validated on real hardware. Linux and macOS remain design-compatible only; no testing is claimed.

## Installation and Running

Godot is installed separately by the user and does not need to be downloaded or upgraded by this project:

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --path 'D:\wwo'
```

## Testing

A clean checkout must not assume that Godot has already generated the global `class_name` cache. The bootstrap validation script should be used first. It performs a Headless editor import before running the full test suite and startup checks, and treats parse/load errors in the logs as failures even when the Godot process returns exit code `0`:

```powershell
powershell -ExecutionPolicy Bypass -File 'D:\wwo\tools\run_validation.ps1'
```

The script covers:

* `tests/current_test_runner.gd` (inherits and runs the complete M0–M9 integrated suite)
* `tests/p0_r1_logic_regression.gd`
* `tests/p0_r1_player_journey_post_audit.gd`
* `tests/p0_r1_safety_regression.gd`
* `tests/state_consistency_regression.gd`
* `tests/simulation_quality_regression.gd`
* `tests/codex_audit_regression.gd`
* `tests/early_game_reachability_regression.gd` (actual budget paths across 1,000 standard seeds)
* Headless main-project startup and parse-log checks

See `docs/TEST_PLAN.md` and `docs/P0_R1_VALIDATION.md` for the complete acceptance procedure.

## Export

`export_presets.cfg` provides Windows Desktop x86-64, Linux x86-64, and macOS Universal presets. The current Windows Release is exported with:

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path 'D:\wwo' --export-release 'Windows Desktop' 'D:\wwo\builds\windows\wwo-p0-r1.exe'
```

Linux and macOS have not been exported or tested.

## Current Validation Facts

On 2026-07-13, a read-only Codex audit was performed against commit `9e92e77c422be782fd21baaa69ee7b41099ce8be` using the exact Godot version `4.6.3.stable.official.7d41c59c4`:

* Although the Headless process for the original source returned `0`, the logs contained strongly typed parsing errors, so startup did not pass.
* After fixing only that single issue in a temporary shadow copy: the original aggregate tests passed `552/564`, P0-R1 logic `35/35`, player journey `20/21`, safety regression `25/26`, state consistency `240/240`, and simulation quality `50/50`.
* A one-year simulation in the shadow copy took approximately `1,916 ms`, still below the 10-second budget, but the older `846 ms` result can no longer be used as evidence for the current default branch.

The default branch was further repaired after that audit:

* The strongly typed `is_surrounded()` call error.
* Validation gaps involving clean-checkout import and cases where the process returned exit code `0` despite parse errors.
* Production learning for arbitrary skills, primary-skill growth from actual actions, and explicit guaranteed-success paths after sufficient training, preparation, and funding.
* Authoritative-state constraints for retirement, death, long-term imprisonment, and loss-of-power exit reasons.
* NPCs now settle elapsed intervals using the previous context before applying new conditions at the boundary.
* Validation for active save limits, activation seeds, AI coverage, and uniqueness of action-instance IDs.
* At 1280×720, the action panel now keeps the Start button fixed outside the scrollable region.
* Backup snapshot tests now compare normalized JSON semantics.
* Succession transactions now fully restore the pre-succession roster if an upgrade fails because the runtime active limit changes; external save restoration continues to enforce configured limits.

Before the UI refactor on 2026-07-15, the unified validation script passed using the exact Godot version `4.6.3.stable.official.7d41c59c4`: aggregate `570/570`, logic `35/35`, the then-current automated player journey `32/32`, safety `26/26`, state consistency `41/41`, simulation quality `50/50`, and Codex audit-specific tests `29/29`. These figures are retained only as the pre-refactor baseline.

The automated and manual results from that old UI can only be treated as historical baselines and can no longer prove the current player loop. The 783 automated tests form a regression baseline for background simulation, logic, and state consistency. The latest manual testing with clean user data found that work, the first relationship, and the first organization still lacked reliably reachable paths, so those results cannot be used as evidence that P0-R1 is complete.

On 2026-07-15, the current code was rerun through unified validation using the same exact engine version: aggregate `608/608`, logic `38/38`, visible-control journey with development mode disabled `99/99`, safety `26/26`, state consistency `41/41`, simulation quality `51/51`, and Codex audit `107/107`. In the newly added 1,000-seed actual-budget regression, the 30-day work path, 60-day relationship path, 90-day organization path, 180-day position path, and position-success line all reached `1000/1000`, with no deterministic dead ends.

The current Release was subsequently launched from an empty `user://`. Using only visible controls, the agent completed a new game, primary employment, relationship creation, organization creation, recent-result review, drawer switching, peacetime-disabled-state verification, three months of world-event progression, saving, full exit, and load round-trip. This actual-window evidence is not equivalent to independent manual acceptance testing by the user. P0-R1 remains unpassed, and the Demo has still not been reached.
