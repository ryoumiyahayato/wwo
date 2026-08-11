# Provenance audit tools

`generate_manifest.py` inventories tracked files under `data/**`, `assets/**`,
and `docs/**`. It records only provenance explicitly supported by repository
metadata or generator source code. It never infers a license from a filename,
file format, or a similar online asset.

Generate the deterministic manifest from the repository root:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/generate_manifest.py --base-revision <sha>
```

Validate syntax, references, hashes, duplicate hashes, missing sources,
generators, and license warnings:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/validate_manifest.py docs/data_sources/provenance_manifest.json
```

Unknown licenses are warnings. The validator exits non-zero for structural or
contradictory provenance errors; use `--strict` when a review wants warnings
to fail as well.
