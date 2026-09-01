# Historical Provenance Foundation

## Purpose

The Historical Provenance Foundation is a static, fail-closed admission boundary for historical facts. It records where a fact came from, how the input was bound, and whether the runtime assertion still matches the catalog hash. It does not own political entities, population state, spatial state, markets, economy, organizations, or gameplay lifecycle.

The owner graph is:

```text
HistoricalSourceRegistry  -> source identity, version, license, locator, content hash
HistoricalEvidenceCatalog -> typed fact metadata and deterministic fact index
HistoricalProvenanceGate  -> source binding and runtime assertion admission
```

Current consumers remain owners of their own domains:

```text
FormalWorldSimulation
  -> HistoricalPoliticalEvidenceCatalog (political evidence snapshot)
  -> FormalWorldEconomicEvidenceCatalog (economic/population bootstrap snapshot)
  -> FormalWorldMarketRegistry (market identity)
  -> FormalWorldEconomyService (market-keyed runtime economy state)
```

The historical map reads a boundary document only after the same gate admits the boundary snapshot fact.

## Evidence contract

Every `HistoricalFactEvidence` contains at least:

`fact_id`, `domain`, `subject_id`, `value`, `unit`, `source_id`, `source_version`, `source_locator`, `observation_period`, `spatial_scope`, `methodology`, `confidence`, `lower_bound`, `upper_bound`, `license`, `review_status`, `generator`, `input_hash`, and `output_hash`.

The output hash is calculated from the canonical assertion material. At runtime, the gate checks the fact domain, source identity binding, source version/locator/license/content hash, and the assertion output hash.

`EVIDENCE_LINKED` and `BOUNDED_ESTIMATE` are admission metadata, not verification. Only an explicit `VERIFIED` review status can satisfy `is_verified`, and it must still pass runtime admission.

## Current catalog

The deterministic generated catalog contains three registered sources and 202 facts:

- 151 `political_identity` facts, marked `EVIDENCE_LINKED`;
- 50 `population_aggregate` facts, marked `BOUNDED_ESTIMATE`;
- 1 `spatial_boundary` fact, marked `EVIDENCE_LINKED`.

The generator is `tools/provenance/generate_historical_provenance.py`. Run it with `--check` to verify that the committed JSON is exactly reproducible from the current source data.

## Persistence

The provenance catalog is static repository data. It is loaded and validated into an isolated candidate during `FormalWorldSimulation.initialize()`; the formal world save keeps the existing World v4, Economy v6, and Market v1 schemas and does not copy the static catalog. A restore candidate must therefore reload the catalog before any state can be adopted, while the existing political evidence fingerprint continues to bind the saved political projection.
