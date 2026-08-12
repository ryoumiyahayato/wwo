# World data dictionary generator

`generate.py` reads the JSON files under `data/world_map/**` and pure JSON data
under `data/vnext/**`, then scans related GDScript/Python loader, parser, and
validator sources. It writes a deterministic machine-readable dictionary and a
split human-readable reference under `docs/generated/world_data_dictionary/`.

```powershell
python tools/world_data_dictionary/generate.py
python tools/world_data_dictionary/generate.py --check
```

The generator never writes to the input data roots. `OBSERVED` values are
measured from JSON. `DECLARED` values require explicit source evidence such as
a required-field list, type check, default expression, or enum constant. Name-
based foreign-key candidates and small-cardinality enum candidates remain
heuristics and are labeled as such.
