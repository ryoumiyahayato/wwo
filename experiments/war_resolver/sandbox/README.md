# Experimental 2D land war observer

**NON-PRODUCTION. Production integration status = NONE.** Standalone Godot scene,
stacked on task 2 [draft PR #104](https://github.com/ryoumiyahayato/wwo/pull/104)
(`4c52ec37082d27c0d7b99359cfb165ae36878f15`), which depends on task 1
[draft PR #103](https://github.com/ryoumiyahayato/wwo/pull/103)
(`524b669214469e4b343830afef8f4ef8768ec225`). Neither predecessor is merged.

From the repository root, with **Godot 4.6.3 standard / Compatibility**:

```sh
godot --path . res://experiments/war_resolver/sandbox/sandbox.tscn
```

On restricted Linux user directories, first create writable paths and launch:

```sh
mkdir -p builds/sandbox-local/data builds/sandbox-local/config builds/sandbox-local/cache
XDG_DATA_HOME="$PWD/builds/sandbox-local/data" \
XDG_CONFIG_HOME="$PWD/builds/sandbox-local/config" \
XDG_CACHE_HOME="$PWD/builds/sandbox-local/cache" \
godot --path "$PWD" res://experiments/war_resolver/sandbox/sandbox.tscn
```

PowerShell, using the repository's pinned installation:

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --path 'D:\wwo' 'res://experiments/war_resolver/sandbox/sandbox.tscn'
```

The formal main scene, UI and saves are independent. This scene starts paused,
with `open_field_attack`, seed `71`, ordinary soldier. Choose scenario, integer
seed and player role, then reset. Changing scenario/role resets both battles,
including command history and cooldowns: the role authority binds one concrete
person once, and has no in-battle person switching contract.

Two columns always show DETAILED and AGGREGATE from deep clones of the same input.
`+120 game seconds` advances once while paused; Run uses a 0.5-second UI timer.
Speeds schedule 1/4/16 calls per tick (240/960/3840 game seconds per real second).
Every call advances a common 120-second observation horizon, allowing the resolver
its own 30-/120-second boundaries. Changing speed changes wall-clock scheduling,
not combat formulas or observation cadence. Each column's clock is its BattleState.

Role input kind/target choices come from `Roles.command_scope()`. Submit sends the
same command independently to each authority's `apply`; all scope, rate, values
and dependency checks remain there. A formation target denotes its eligible
existing squads; a soldier target denotes the bound person. The separate inspect
unit dropdown is read-only and can show either side in this perfect debug view.
Use two immediate submissions for `input_not_due`, or Probe foreign rejection
for `wrong_owner_or_layer`. Results and next-input boundaries remain visible.

Dots, sampled trails, direction lines, objective marks and suppression bars are
projections of resolver records. Rows are fixed layout lanes, **not simulated Y
coordinates or formations**. Woodland/building/road symbols denote scenario-wide
uniform cover/movement/frontage inputs, not a spatial terrain generator. There
is no interpolation, collision avoidance, visual AI or second movement law.
Stationary time may be intended hold/reserve/completed mission. Reversals are
sampled; total distance and causal events help reveal turns within a sample.

Nine inputs: six inherited scenarios plus suppression recovery (attack_00 starts
at 0.9 suppression), cohesion withdrawal (attack_00 starts at 0.15 cohesion), and
dependent reserve (attack_00 waits for 600s **and** mission_attack_01 completion).
All fixtures use the existing resolver. The causal trace retains the latest 160
non-loss events; scroll its text box for earlier events. It displays dropped
counts and separate loss-event counts; fractional loss totals remain visible.
Position trails retain 48 samples. Smaller windows can scroll the whole view.

Automated validation, including scene/UI smoke and fresh-process observations:

```sh
python3 -B experiments/war_resolver/validate.py --godot godot --regressions --output builds/sandbox-final-verified
```

[Observation checklist and actual evidence](OBSERVATION_REPORT.md) separates
machine observations from **NOT RUN** rendered/manual acceptance. Headless smoke
is not human visual acceptance. Performance evidence stays in the original
headless benchmark; this display is not an algorithm benchmark.
