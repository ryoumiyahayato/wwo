# WWO 1900 Economic Geography Foundation R1

This document defines the repaired, read-only foundation contract for the seven 1900 pilot economic regions. It is staging data for reviewed evidence expansion. It is not runtime wiring, a production database, or a set of historical production quantities.

## Contract boundary

The pilot remains exactly seven economic regions:

1. Ruhr coal and steel
2. Lancashire cotton
3. South Wales coalfield
4. Donbas coal and metals
5. Pennsylvania coal and steel
6. Bengal delta jute and rice
7. Lower Yangtze silk and port system

The R1 migration does not add regions, add commodities to the canonical runtime catalogs, create historical polygons, wire E1, or introduce a product-system dependency.

## Assertion model

`data/economic_geography/evidence/economic_region_evidence_1900.json` is an assertion-scoped document. A record contains a stable `economic_region_id`, simulation validity interval, record provenance, and `assertions[]`. The old record-level `spatial_region_ids[]` and unscoped evidence arrays are forbidden.

Every assertion has:

- a globally unique stable `assertion_id`;
- `economic_region_id`, `claim_kind`, `subject_kind`, and `subject_id`;
- a claim level and confidence;
- `spatial_memberships[]` scoped to that exact commodity, sector, infrastructure, or labor claim;
- `temporal_basis`, `observation_from`, `observation_to`, and `observation_period_note`;
- `simulation_applicability` separate from source publication metadata;
- non-empty `source_ids` and notes.

The claim kinds are `RESOURCE_ENDOWMENT`, `AGRICULTURAL_PROFILE`, `EXTRACTION_PROFILE`, `INDUSTRIAL_PROFILE`, `INFRASTRUCTURE`, and `POPULATION_LABOR`. A sector assertion may carry output commodity IDs, but that output identity is a compatibility reference, not an observed quantity.

## Weighted crosswalk model

Each membership has:

- `spatial_region_id`: an existing modern admin-1 catalog ID;
- `coverage_bp`: estimated share of that spatial unit covered by the historical footprint;
- `relevance_bp`: estimated importance of that spatial unit to this particular assertion;
- `role`, validity dates, scoped provenance, and notes;
- `allocation_basis`: `EVIDENCE_DERIVED`, `CROSSWALK_ESTIMATE`, or `UNRESOLVED`;
- `is_historical_measurement: false`.

Coverage and relevance are intentionally different dimensions. They do not have to sum to 10,000. Basis points describe an uncertain spatial allocation only; they are never tonnes, workers, money, installed capacity, yield, or a production multiplier. The pilot uses `CROSSWALK_ESTIMATE` for modern admin-1 allocations and `UNRESOLVED` where the selected IDs do not safely represent the historical footprint. No perfect polygon is implied.

The same `economic_region_id` may therefore contain different footprints. For example, Bengal jute cultivation uses the delta catchment, jute milling and port claims weight Calcutta, and Bengal coal is explicitly unresolved against the selected modern IDs. Donbas coal, metallurgy, and Azov transport similarly have different memberships.

## Temporal model

Publication metadata is never copied into an observation period. The controlled assertion values are:

- `DIRECT_1900`: a bounded direct 1900 observation is available;
- `NEAR_1900`: a nearby period is available and explicitly qualified;
- `RETROSPECTIVE_BUT_APPLICABLE`: a later source supports a structural relation applicable as a qualified 1900 prior;
- `TEMPORALLY_WEAK`: the evidence is retained only as a weak lead.

The 1911 reference assertions use `RETROSPECTIVE_BUT_APPLICABLE` with null observation dates and an explicit note. The 1900 manufactures census report is represented as 1900 observation data with a 1902 publication date. The mines-and-quarries report is represented as 1902 observation data and `NEAR_1900`, not silently converted to 1900.

`simulation_applicability` is separately controlled and currently structural-only. It does not authorize quantitative calibration or runtime output.

## Source class model

`data/economic_geography/source_registry.json` uses only these controlled source classes:

`PRIMARY_OFFICIAL_STATISTICS`, `CONTEMPORARY_OFFICIAL_REPORT`, `CONTEMPORARY_REFERENCE`, `LATER_SCHOLARLY_SYNTHESIS`, `MODERN_SPATIAL_REFERENCE`, `INTERNAL_PROJECT_CATALOG`, and `OTHER`.

Every source stores publication metadata separately from `observation_from`, `observation_to`, and `observation_period_notes`. A source class is provenance taxonomy; it is not an automatic numerical truth score. The modern admin-1 source is identity/geometry support only, not 1900 historical geography.

## Pilot corrections

The R1 migration applies the independent review corrections without broad new research:

- removes the Ruhr and Donbas `coke_production` assertions because the retained sources do not directly support those scoped claims;
- removes South Wales local `copper_ore` resource/extraction assertions while retaining copper smelting as a sector claim;
- removes Bengal `food_processing` because the retained locator supports rice, jute, port, and transport structure but not that scoped assertion;
- removes unrelated `eb1911_russia` provenance from the Ruhr coal assertion;
- removes the mines-and-quarries source mismatch from Pennsylvania machinery, retaining the Pittsburg reference;
- keeps Lower Yangtze silk output as the existing `raw_silk` canonical process/output proxy and labels it as such.

## Commodity and sector compatibility

`data/economic_geography/commodity_compatibility.json` is a namespaced resolution contract. Keys are `commodity:<id>` or `industrial_sector:<id>`, which keeps same-spelled commodity and sector catalog IDs distinct without creating duplicate identities.

The flagged pilot references resolve as follows:

- `potatoes`, `limestone`, `copper`, and `wool_cloth`: existing canonical commodities (`CANONICAL_DIRECT`);
- `cotton_spinning`, `jute_milling`, `silk_reeling`, `iron_and_steel`, and `shipbuilding`: compatible sector concepts (`SECTOR_ONLY` or collapsed sector aliases);
- all sector IDs used by the seven pilots: existing sector catalog identities, explicitly sector-only;
- genuine future gaps: none are silently added to the runtime catalog. Any future unresolved concept must remain `FUTURE_GAP_UNRESOLVED` until separately reviewed.

The validator computes the set of commodity and sector IDs actually referenced by assertions and fails if any lacks a compatibility resolution.

## Ordinal prior lock

All current calibration records in `data/economic_geography/calibration/economic_region_calibration_1900.json` have:

- `calibration_role: EVIDENCE_PRIOR_ONLY`;
- `canonical_unit: ordinal_capacity_index_0_5`;
- `runtime_usage: NONE`;
- exact `source_assertion_ids`, never whole evidence-record IDs;
- an explicit forbidden-use list covering tonnes, workers, money, physical installed capacity, production multiplier, yield, and direct runtime output.

The schema and validator fail closed if an ordinal record is marked `DIRECT_PHYSICAL_PRODUCTION_CAPACITY`, given runtime usage, or loses its forbidden-use declaration. No ordinal value is a historical production quantity or a direct physical capacity.

## Migration and unresolved crosswalks

Only the seven existing pilots were migrated. The migration produced stable assertion IDs and 101 assertion-scoped claims after the reviewed removals. It did not add mass data.

Known unresolved or estimate-only items remain visible:

- modern admin-1 boundaries are proxies rather than 1900 boundaries;
- Bengal coal is retained with an `UNRESOLVED` membership because the selected IDs do not safely encode the historical coalfield footprint;
- South Wales copper smelting is not treated as proof of local copper-ore extraction;
- Donbas coal, metallurgy, and Azov transport use separate uncertain scopes;
- all basis-point weights are reviewable crosswalk estimates, not historical measurements.

## Verification

Run from the isolated checkout:

```powershell
$python = "C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
& $python tools/economic_geography/validate_economic_geography.py --root .
& $python -m unittest discover -s tests/economic_geography -p "test_*.py"
```

The validator must report seven evidence regions, 101 assertions, zero historical quantitative values, and a passing result. The R1 tests cover duplicate assertion IDs, spatial and weight bounds, provenance, temporal periods, exact calibration references, ordinal misuse, compatibility closure, publication/observation separation, scoped footprints, crosswalk provenance, and deterministic input ordering.

This foundation remains NOT READY for unreviewed mass expansion. It is ready for reviewed evidence expansion only after this contract and its tests are accepted.
