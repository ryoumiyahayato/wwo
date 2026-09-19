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

Batch 2 reference matrix:

```powershell
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/scan_reference_matrix.py --base-revision <sha>
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools/provenance/validate_reference_matrix.py docs/data_sources/provenance_reference_matrix.json
```

The matrix is static evidence only. It records candidate producer/consumer
relationships and warns on broken references; it never infers a source or
license and never modifies data or assets.

## Historical Provenance source-byte contract

The Historical Provenance Foundation currently admits three textual JSON
sources for byte-level content identity: the dated political-unit catalog, the
CShapes 1900 snapshot, and the compact 1900 population aggregate table. These
paths have an explicit repository `text eol=lf` contract in `.gitattributes`.
The generator validates the checked-out bytes before hashing and fails closed
if an admitted textual source contains CR/CRLF bytes; it never silently
normalizes a source into a second valid identity. Future arbitrary or binary
sources are not subject to this textual validation unless they are explicitly
admitted to the textual-source set.

The runtime registry gate intentionally continues to hash the checked-out bytes
verbatim. Therefore the generator hash definition and runtime hash definition
remain identical: SHA-256 of the repository's canonical checked-out source
bytes. The generated source registry and fact-evidence catalog have a separate
`text eol=lf` formatting contract, and the generator writes their UTF-8 bytes
with LF line endings deterministically.
