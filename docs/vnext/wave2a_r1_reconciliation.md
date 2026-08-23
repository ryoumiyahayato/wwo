# Wave 2A-R1 architecture reconciliation

No approved Economic Geography implementation was recoverable from the Wave 1
ancestry, reachable refs, reflogs, unreachable commits, or available isolated
artifacts. `VNextEconomicRegionCatalog` therefore initializes as
`EMPTY / NOT AVAILABLE`; no memberships were invented.

The shared boundary consists of:

- `VNextFactProvenance` for applicability, precision, dates and coverage;
- canonical `population:<id>` PopulationUnit identity;
- a read-only provider for the existing 50 bounded aggregate estimates;
- sparse `VNextTypedCrosswalkCatalog` mappings with explicit coverage and
  unresolved residue;
- distinct `economic_region:<id>` identity with an empty trusted catalog;
- political and military control overlays outside `VNextSpatialWorld`;
- `FormalDatedPoliticalCatalog`, which queries record validity at the
  simulation date.

The Population provider reads the same source-backed bounded aggregate
evidence table used by transitional Formal Economy, plus its source manifest.
It does not construct or query the Alpha Population simulation, prototype
regional populations, or city populations. The directory location remains
transitional provenance and is exposed as `source_evidence_path`; the facts are
always `ESTIMATED`, never exact.

The political catalog contains 151 records. The product query yields 146 on
1900-01-01, 148 on 1900-01-24, and 151 from 1900-01-29. The CShapes
1900-03-12 reference date remains provenance, not a backdated validity claim.
No repository predecessor record exists for Djibouti, Eritrea, Rhodesia,
Northeastern Rhodesia, or Northwestern Rhodesia before their supplied validity
dates. At January 1 their candidate political identity, sovereignty, and
control are therefore unavailable. Their March 12 geometry is retained only as
non-selectable `REFERENCE_ONLY` land, and the product reports five explicit
temporal gaps instead of implying a complete 146-unit partition.

Spatial v1 saves are a one-way compatibility input. Legacy controller rows are
strictly validated, discarded, and never written by v2. Infrastructure state
survives the conversion; invalid migration input leaves the live v2 world
unchanged.

The product does not construct Population or Economic Geography owners in this
wave. Formal Economy remains active and consumes neither the new provider nor
MacroPopulation. E1 and Shared Transport remain isolated.
