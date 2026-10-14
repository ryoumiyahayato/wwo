# Historical content generation and admission

## Separate contracts

- File integrity: SHA256 identifies an immutable external artifact, such as the original CShapes archive or a downloaded historical image. It is never a data-format version.
- Format compatibility: explicit supported schema IDs / versions. The formal source registry and fact catalog use `historical_source_registry_v2` and `historical_fact_evidence_catalog_v2`. The v1 hash-field contract is unsupported, with an explicit error. Input `schema_version=1` and economic input revisions keep their existing meanings. The current formal save snapshot is `formal_world_simulation_v15`; its internal fingerprint bindings remain active and are documented in `docs/SAVE_FORMAT.md`.
- Content correctness: unique IDs, required typed fields, source bindings, actual dates, ordered intervals, supported review statuses, geometry / controller / component references, factual assertions and required records. Null and UNKNOWN remain values, never zero defaults.

## One formal generation path

```text
Manually maintained dated political identities + bounded population compilation
+ CShapes-derived boundary snapshot
+ bounded Arabia/Gulf geography + historical authorities + Arabia authority coverage
    -> tools/provenance/generate_historical_provenance.py
    -> data/provenance/historical_source_registry.json
    -> data/provenance/historical_fact_evidence.json
    -> HistoricalProvenanceFoundation / registry / catalog / gate
    -> WorldBootstrap and Content loaders -> detached Presentation inputs
```

`build_cshapes_1900_snapshot.py` transforms the upstream external archive.
`build_territory_closure_1900.py` interprets the maintained historical traces and existing CShapes land using its existing geometry algorithm.
`build_arabia_authority_coverage.py` prepares sourced authority masks against existing geometry. These builders produce formal source inputs; they no longer write provenance catalogs independently. After an input changes, run the formal generator once. Normal validation does not download archives, redigitize maps or rebuild upstream geometry.

The three supplements are formal display inputs, not current political, economic or population state. Their approximate evidence, source references, scope and bounded dates remain explicit. Geometry binding uses path, supported schema, feature ID and exterior count; internal file SHA is not a binding version.

```powershell
python tools/provenance/generate_historical_provenance.py
python tools/provenance/generate_historical_provenance.py --check
```

The generator preserves input historical values, sorts IDs and JSON keys, and writes UTF-8 with LF. `--check` compares parsed structures. LF/CRLF, whitespace and object-key order are equivalent. Content changes require regeneration and content validation, not a second digest.

Current measured output is 6 sources and 205 facts. Counts are observations; tests verify exact coverage of source records, unique IDs and critical facts, not a frozen total. Evidence includes political identities, bounded population, base and supplement geometry, and both authority supplements. `EVIDENCE_LINKED`, `BOUNDED_ESTIMATE`, `APPROXIMATE` and explicit verification retain their meanings.

## Runtime and persistence

The source registry requires source identity, publisher, version, license, locator and access metadata. The fact catalog requires fact identity, domain, subject, value / bounds, unit, source identity / version / locator / license, observation period, spatial scope, methodology, confidence, review status and generator. Internal `content_hash`, `input_hash` and `output_hash` are removed. The gate compares normalized structured assertions directly and verifies references; it never verifies internal JSON bytes. Upstream checksum metadata stays separate.

FormalPersistence reloads and validates Content in an isolated candidate before adopting a saved world. Supported schema IDs and existing economic / population revisions define compatibility; saved diagnostic historical fingerprints do not reject a world. Runtime polity, market, person, organization and spatial references still undergo their existing authoritative validation. The existing Organization responsibility `rule_version=economic_supply_continuity_v1` is explicitly supported; the legacy serialized key `rule_fingerprint` now carries this ordinary version instead of a file SHA. A save carrying an unsupported rule generation fails; responsibility calculations and rules are unchanged. No arbitrary conversion or missing-reference fallback was added. The formal save schema remains v12.

Existing runtime-state fingerprints still serve exact-state / deterministic simulation regressions and cache identities. They are not format versions. Existing `tools/world_data` inventory, catalog-signature and run-manifest files are audit reports, not runtime inputs. Replay tests compare freshly generated structured results; an old inventory snapshot is not a correctness gate for the current repository. Binary flag/image checksums remain asset-integrity checks. Git SHAs in prior reports describe audit context only.

## Fixed layout contract

The overall architecture document `docs/ARCHITECTURE.md`, section “UI / HUD 固定布局原则”, records the agreed screen layout. This cleanup changes no UI implementation.
