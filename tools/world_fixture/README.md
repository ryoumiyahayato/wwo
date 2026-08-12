# World-data golden fixture tooling

This package reads only `tests/fixtures/world_data/corpus.json`. It materializes
small fixture documents, applies explicit one-defect mutations, serializes them
with sorted keys, and calculates SHA-256 hashes for replay tests.

The checker is a focused regression harness for the existing world-map JSON
field names. It is not a production validator and it never writes
`data/world_map/**`.

Run the focused tests with the repository's bundled Python runtime:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s tests/world_data -p 'test_*.py'
```
