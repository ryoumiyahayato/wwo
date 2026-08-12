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
measured from JSON. `DECLARED` requires exact normalized full-field-path
evidence from a loader, validator, or source-config contract. `HEURISTIC`
leaf-only, test, tooling, and name-based evidence is retained for review and
never becomes schema authority. `RUNTIME_SNAPSHOT` is restore/validator
requirements for derived runtime state, not source JSON requirements.
`ID_KIND_CONSTRAINT` proves stable-ID syntax/kind only, not catalog membership.
`FOREIGN_KEY` requires a resolved loader/catalog reference; name-based links
remain candidates or ambiguous.
