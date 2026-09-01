# Population → Economy daily snapshot boundary

## Authority

`VNextMacroPopulation` remains the only owner of Population counts and
demographic structure. It owns total population, age buckets, sex structure,
urban/rural composition, working-age population, and demographic flows. The
new adapter in `scripts/vnext/population/` owns no population state and does
not write to Population or Economy.

Economy receives two immutable projections for one settlement period:

- `VNextLaborSnapshot`;
- `VNextDemandPopulationSnapshot`.

`VNextPopulationEconomyDailySnapshot` groups those two values for callers that
need one atomic hand-off.

## Explicit region crosswalk

`VNextPopulationEconomyRegionCrosswalk` requires a caller-supplied mapping
from every bound Population source key to one existing Spatial region. Source
keys may be existing `place:<map_id>` or `region:<map_id>` keys. Targets must
be existing `region:<map_id>` keys in the loaded `VNextSpatialCatalog`.

The provider requires exact source coverage: every Population source key must
appear once in the crosswalk, and no crosswalk source may be outside the
Population binding. An unknown target or missing source mapping fails closed.
The provider never reads sovereign ownership, administrative ownership, or
military controller state. Political boundary changes therefore cannot move,
duplicate, or erase Population in this projection.

Output regions are sorted by stable region ID. Multiple Population source
keys may map to one target and are aggregated exactly once.

## Labor V1 mapping

The current canonical Population record has no authoritative occupation or
skill axis. The V1 projection is therefore:

| Labor category | Source mapping |
| --- | --- |
| `rural` | working-age Population proportionally assigned to rural composition |
| `urban_unskilled` | remaining working-age Population assigned to urban composition |
| `skilled_industrial` | `0`; no authoritative skill data exists yet |

The proportional projection is deterministic per source record. The urban
pool receives the integer remainder after the rural pool is calculated, and
all three pools are aggregated by target region. For every region:

`rural + urban_unskilled + skilled_industrial = economically_available_working_population`

in the current V1 mapping, and the general invariant enforced by the value
object is that the sum never exceeds that available workforce. No individual
job matching, wages, participation choice, or employment state is simulated.

## Demand population projection

Each target region receives Population facts only:

- `population`;
- `working_age_population`;
- `urban_rural` counts;
- explicit source Population IDs for auditability;
- `household_strata` and `income_strata`, currently empty because the
  authoritative Population model does not provide those strata.

No commodity demand, consumption preference, price, or elasticity is
calculated here. Those belong to the future Economy layer.

## Immutability and period boundary

Snapshot construction reads the complete aligned Population state into private
value objects. Every public array and dictionary accessor returns a deep copy.
The provider retains no live Population reference in the resulting snapshot.
Later Population settlement changes cannot mutate an existing snapshot; they
appear only when the next settlement-period snapshot is created.

The source Population records must share one settled period. An unaligned or
invalid Population state fails closed instead of combining facts from
different periods.

## Future E1 adapter requirements

E1 integration should consume the two value objects through a narrow adapter
and must not add Population fields to Economy. That adapter must:

1. preserve the supplied stable region IDs and source-period metadata;
2. consume labor pools as read-only daily inputs;
3. consume only demographic facts from demand snapshots, then apply Economy's
   own commodity preferences and price-response rules;
4. never infer population movement from political control changes;
5. reject missing, stale, malformed, or incomplete snapshots before
   settlement; and
6. keep any employment, wage, household-demand, or commodity state in Economy.

Focused regression coverage is in
`tests/vnext/population_economy_boundary_test.gd` and covers D-01 through
D-10.
