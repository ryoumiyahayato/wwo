# vNext macro population

## Ownership and authority boundary

`VNextMacroPopulation` is a slow, `PopulationUnitId`-keyed aggregate. It is not a second
person roster and it does not create `Person` records. The model is intended
for millions or hundreds of millions of people without creating one object
per person.

Construction requires a loaded `VNextPopulationUnitCatalog`. The sole accepted
identity shape is `population:<local_id>`; `place:<x>` and `region:<x>` cannot
address demographic state. Geographic relationships are supplied later by
typed crosswalks, never by aliasing Population identity to Spatial identity.
The production evidence provider currently exposes only 50 bounded
major-economy aggregates, classified `ESTIMATED` and
`NEAR_1900_SUPPORTED`. It exposes no regional or city Population facts.

The owned fields are deliberately limited to:

- total population;
- coarse age buckets: `under_18`, `age_18_40`, `age_41_64`, `age_65_plus`;
- two-bucket sex structure: `female`, `male`;
- `urban` / `rural` structure;
- working-age population, derived as `age_18_40 + age_41_64`;
- cumulative births, deaths, `external_immigration`, and
  `external_emigration`;
- the last-settled absolute-month cursor.

The model does not own available workers, unemployment, employment, wages,
income, consumption, occupation, mobilizable manpower, military recruitment,
political support, households, family simulation, personal emotion, or NPC AI.
Future Economy, Politics, and Military integration may derive those concepts
from this aggregate plus their own conditions. This PR does not modify those
systems.

## Time and settlement

Population has no clock. The caller supplies either an elapsed month count or
an absolute starting month. Absolute month `0` is January 1900. The canonical
monthly input is a per-place flow dictionary:

`BT`text
{
  "population:country_fra": {
    "births": 20,
    "deaths": 5,
    "external_immigration": 2,
    "external_emigration": 5
  }
}
`BT`

`external_immigration` and `external_emigration` are explicitly exogenous:
they may change the world total and are not internal transfer flows. Monthly
input may provide either field independently; the omitted component is zero.
For backward compatibility, a legacy signed `net_migration` or `migration`
input is converted at the input boundary into positive external immigration
or external emigration; it is not stored as an ambiguous migration authority.
Snapshots store only the explicit nonnegative fields.

Missing place entries mean zero monthly flow, but the place still advances
through the supplied elapsed period. Every elapsed period is processed through
the same deterministic month step. Each month also applies bounded,
deterministic coarse ageing: `under_18` progresses into `age_18_40`,
`age_18_40` into `age_41_64`, and `age_41_64` into terminal
`age_65_plus`; births enter `under_18`. Small persistent fixed-point
remainders are part of the snapshot so partitioning time cannot change the
result.

For each month the accounting identity is:

`BT`text
new population = previous population
               + births
               + external_immigration
               - deaths
               - external_emigration
`BT`

Births enter `under_18`; exogenous flows use a stable largest-remainder
proportional rule across the coarse axes. Every update rejects negative or
non-finite totals, overflow, impossible removals, and any result whose age,
sex, or urban/rural totals do not reconcile.

## Internal migration contract

Internal migration is a separate bounded batch of aggregate transfers:

`BT`text
[
  {
    "origin_population_unit_id": "population:country_fra",
    "destination_population_unit_id": "population:another_unit",
    "amount": 100
  }
]
`BT`

Both endpoints must be in the PopulationUnit authority and in the live
Population binding. Amounts are finite, integral, nonnegative, and JSON-safe.
A self-flow is rejected explicitly. A batch is fully validated before any
live state is committed; an unknown endpoint, malformed amount, or
insufficient origin rejects the entire batch with no partial mutation.

The normalized flow list is sorted by canonical PopulationUnit endpoint IDs
and duplicate pairs are combined, so input ordering cannot change the result.
Transfers conserve total Population exactly. Each transferred amount is
deterministically partitioned across age, sex, and urban/rural buckets using
the existing largest-remainder proportional rule; no Person-level migration
or invented demographic detail is created. Internal migration can be supplied
with a settlement call or applied at the explicit
`settle_internal_migration` boundary after the population has entered its settled
phase.

## Queries and indexed validation

The public query surface includes indexed unit queries for total, working-age,
structure and aggregate state, plus coarse
`age_bucket_at` / `age_18_40_at`, and period queries.

Unknown keys and duplicate aggregation keys fail closed. Public operations
validate once per Population revision, then use the deterministic unit index.
Repeated field lookups are O(1); settlement and snapshot are O(number of bound
PopulationUnits). Snapshot output remains sorted by PopulationUnitId.

## Snapshot and restore

The `vnext_macro_population_v4` snapshot stores the PopulationUnit contract,
Population/provider/catalog revisions, per-unit fact lineage and the sorted
record list. Record snapshots store explicit
`external_immigration` and `external_emigration` fields; they contain no
geography aliases or Person records. Restore validates a complete candidate
set before committing it. It rejects negative values, NaN/Inf, unknown or
duplicate place entries, malformed flow state, inconsistent age, sex, or
urban/rural totals, and invalid ageing remainders. Any rejected snapshot
leaves the live population unchanged.

Legacy place/region-keyed snapshots fail closed because they cannot prove a
canonical PopulationUnit identity. Restore requires the instance to already
be initialized and requires the snapshot key list to match that contract
exactly. The persisted key list is therefore a consistency check, not a way
to establish Population identity. An empty `VNextMacroPopulation.new()` must not
restore a snapshot. Setup initialization and initial state seeding are
rejected after the first elapsed settlement; the canonical batch settlement
API is the only live time advance.

## Relationship to Person

Macro Population is not detailed Person simulation. It does not answer how to
extract an exact NPC from an aggregate and it never auto-creates `Person`
records. Later layers may activate only important characters, the player, or
specifically tracked people in the Person layer.

## Validation

Focused coverage is in `tests/vnext/macro_population_test.gd` and is picked up
automatically by `tools/run_vnext_validation.py`. It covers:

- PopulationUnit authority binding, alias/wrong-kind rejection,
  authority-unavailable construction, and snapshot authority
  attacks;
- external-flow accounting and the explicit legacy signed-input boundary;
- internal A?B conservation, multiple-flow ordering determinism, self-flow,
  unknown endpoints, insufficient origin, malformed/non-finite amounts, and
  whole-batch transactionality;
- age-remainder continuation, full settlement snapshot resume, migration
  snapshot resume, setup lock, structure reconciliation, and indexed full
  settlement/aggregation.

This branch also requires the repository's unified `run_validation.ps1`, the
vNext validation runner, the variable-state audit where applicable, Godot
import/parse checks, and `git diff --check` before publication. Master was
reconciled with the merged Spatial PR #62 before these repairs.
