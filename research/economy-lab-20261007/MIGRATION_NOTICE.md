# Historical Economy Lab migration

This directory preserves the private `wwo-economy-lab` research checkout at
`48b280a37be8f5fd72f0c277f4ae435e675efa1f` (2026-10-07), copied without changing
tracked source, fixture, report or evidence bytes. The import contains all 363
tracked files so every historical verification entry point keeps its relative
layout. This notice is new migration documentation.

It is an opt-in Python research package. Godot runtime services, the default
economy, world time and military simulation are not replaced or enabled by this
import. `Simulation(config, scenario).step()` is the physical quantity baseline;
later modules add commitment, admission, multi-supplier matching, discovery,
planning and executable release research. It has no wallet settlement or market
price discovery and is not the user's uncommitted latest economic implementation.

The existing WWO runtime remains the separate Godot/GDScript implementation at
`60a59fb467d1d7d9b7c7f183b02abc648afc7c9d`. Its market and formal economy services
have different responsibility and input contracts. Do not import these research
policies into the gameplay loop without a reviewed adapter and explicit tests.

## Reproduction

Python 3.12; standard library only. Run from this directory:

```sh
python3 verify_baseline.py
python3 verify_round3.py
python3 verify_round4a.py
python3 verify_round4b.py
python3 verify_round4c.py
python3 verify_round5.py
python3 verify_round5b.py
```

Verification writes `.local/`, which remains ignored. Original frozen manifests
and evidence are preserved; the migration must not refresh them to accept
modified data. The source repository's private visibility and history remain
private. This directory and its contents are excluded from the independent
public-safe sandbox source ZIP.

A private sandbox provider can point `WWO_LAB_PATH` to this directory, then call
the original Python entry points and read their metrics. Do not fabricate money,
prices or unsupported functions in the adapter. Record the source commit above
and the migration branch's commit separately.
