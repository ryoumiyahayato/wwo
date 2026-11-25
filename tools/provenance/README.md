# Provenance audit tools

`generate_manifest.py` inventories tracked files under `data/**`, `assets/**`,
and `docs/**`. It records only provenance explicitly supported by repository
metadata or generator source code. It never infers a license from a filename,
file format, or a similar online asset.

Generate the deterministic manifest from the repository root:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/generate_manifest.py --base-revision <sha>
```

The checked-in Batch 1 manifest records a historical inventory. Use its
`audit_base_revision` as the checkout to validate that snapshot. Use a manifest
generated for the current revision to validate current files.

Validate syntax, references, hashes, duplicate hashes, missing sources,
generators, and license warnings:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/validate_manifest.py docs/data_sources/provenance_manifest.json
```

Unknown licenses are warnings. The validator exits non-zero for structural or
contradictory provenance errors; use `--strict` when a review wants warnings
to fail as well.

Batch 2 reference matrix:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/scan_reference_matrix.py --base-revision <sha>
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/validate_reference_matrix.py docs/data_sources/provenance_reference_matrix.json
```

The matrix is static evidence only. It records candidate producer/consumer
relationships and warns on broken references; it never infers a source or
license and never modifies data or assets.

## Formal historical catalog generation

Run `python tools/provenance/generate_historical_provenance.py` after changing
formal historical inputs; run it with `--check` to compare parsed structures.
The same generator includes political identities, the CShapes snapshot, bounded
population inputs, Arabia/Gulf geography, historical authorities and Arabia
coverage. Supplement builders emit source content, never mutate these catalogs.

The registry and fact catalog use explicit v2 schema IDs. Internal source and
assertion hash fields have been removed; source bindings and facts are compared
as data. Unsupported schemas, missing fields and invalid references fail.
LF/CRLF, object-key order and JSON whitespace do not change compatibility.
Generated output uses sorted keys, UTF-8 and LF; `.gitattributes` is formatting
policy, not a runtime content-admission contract.

External artifact checksums (e.g. original CShapes archive or downloaded flag)
remain byte-integrity metadata. Git revisions in historical audit reports are
context, never runtime compatibility versions. Existing audit inventories are
reports, not formal content inputs or a second registry.
