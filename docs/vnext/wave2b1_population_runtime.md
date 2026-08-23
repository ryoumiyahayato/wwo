# Wave 2B-1 Population runtime boundary

The default Formal product constructs one runtime chain:

`FormalWorldApplication -> VNextPopulationEvidenceProvider -> VNextPopulationUnitCatalog -> VNextMacroPopulation`

`ProductPopulationProjection` is a read-only presentation adapter over that
same owner. It does not duplicate Population state and cannot mutate it.

## Supported truth

- 50 bounded aggregate Population facts;
- canonical `PopulationUnitId` identities;
- `ESTIMATED` precision;
- `NEAR_1900_SUPPORTED` applicability;
- estimate bounds, confidence, support/reference dates, method, source, and
  provider/catalog revision lineage.

These facts are authoritative runtime demographic evidence. They are not exact
historical observations.

## Explicitly unavailable

- PoliticalUnit, SpatialRegion, EconomicRegion, regional, and city Population;
- age, sex, urban/rural, labor, employment, demand, and market projections;
- EconomicRegion identities or memberships;
- Population-driven Formal Economy behavior.

The trusted base contains no approved geographic Population crosswalk. The
product therefore constructs an empty typed crosswalk and reports every
political selection as `NOT AVAILABLE FOR THIS GEOGRAPHIC SELECTION`. A zero
mapping count is intentional and must not be replaced by name, ISO, map,
containment, or numeric heuristics.

## Persistence and consumers

The evidence owner is immutable initialization-derived state. Formal saves
retain a small revision compatibility reference instead of serializing a
second copy of the evidence catalog. Restore fails closed if the live
Population revisions are incompatible.

Formal Economy remains active and independent. It neither reads nor copies the
vNext Population authority. Economic Geography remains empty/not available.

The immutable observation snapshot is the common future query surface for
player UI, observer mode, and AI. None receives privileged mutation access.
