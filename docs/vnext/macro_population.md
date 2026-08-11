# vNext macro population

## Ownership and boundary

`VNextMacroPopulation` is a slow, place-keyed aggregate. It is not a second
person roster and it does not create `Person` records. The model is intended
for millions or hundreds of millions of people without creating one object
per person.

Each record is keyed directly by an existing `place:*` or `region:*` ID. The
module does not create geography, country records, region ownership, or a
second `population:*` stable-ID namespace. A caller supplies the known key
set as a read-only spatial fixture/reference. Country or other political
aggregates are queries over caller-provided place/region IDs; there is no
stored `France population` truth.

The owned fields are deliberately limited to:

- total population;
- coarse age buckets: `under_18`, `age_18_40`, `age_41_64`, `age_65_plus`;
- two-bucket sex structure: `female`, `male`;
- `urban` / `rural` structure;
- working-age population, derived as `age_18_40 + age_41_64`;
- cumulative births, deaths, and signed net migration;
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
settlement input is a per-month flow dictionary keyed by place:

```text
{
  "place:alpha": {
    "births": 20,
    "deaths": 5,
    "net_migration": -3
  }
}
```

`migration` is accepted as an input alias for `net_migration`; snapshots use
only the canonical name. Missing place entries mean zero monthly flow, but
the place still advances through the supplied elapsed period.

Every elapsed period is processed through the same deterministic month step.
Each month also applies bounded, deterministic coarse ageing: `under_18`
progresses into `age_18_40`, `age_18_40` into `age_41_64`, and `age_41_64`
into terminal `age_65_plus`; births enter `under_18`. Small persistent
fixed-point remainders are part of the snapshot so partitioning time cannot
change the result. Therefore twelve calls with one month and one call with
twelve months produce the same state when they use the same monthly flows.
Year/month conversion is pure arithmetic, so the December/January boundary is
deterministic. A call does not advance time merely because it was made; its
explicit elapsed or absolute month period is authoritative.

For each month the accounting identity is:

```text
new population = previous population + births - deaths + net migration
```

Births enter `under_18`; deaths and migration are distributed by a stable
largest-remainder proportional rule across the coarse axes. This is a bounded
placeholder, not fertility microsimulation. Every update rejects negative or
non-finite totals, overflow, impossible removals, and any result whose age,
sex, or urban/rural totals do not reconcile.

## Queries

The public query surface includes:

- `population_at(place_id)`;
- `working_age_at(place_id)`;
- `structure_at(place_id)`;
- `aggregate_population(place_ids)`;
- `aggregate_structure(place_ids)`;
- coarse `age_bucket_at` / `age_18_40_at` and period queries.

Unknown keys and duplicate aggregation keys fail closed. Aggregate structure
is meaningful for summed age, sex, and urban/rural counts. Its period cursor is
reported only as aligned when all selected records share the same cursor.

## Snapshot and restore

The `vnext_macro_population_v2` snapshot stores the external key contract and
the sorted record list. It contains no geography metadata or person records.
Restore validates a complete candidate set before committing it. It rejects
negative values, non-finite values, unknown or duplicate place entries,
malformed migration, inconsistent age, sex, or urban/rural totals, and invalid
ageing remainders. Any rejected snapshot leaves the live population unchanged.

`create(place_ids)` or `initialize(place_ids)` binds the live instance to the
caller-supplied spatial key contract. Restore requires that instance to
already be initialized and requires the snapshot key list to match that
contract exactly. The persisted key list is therefore a consistency check,
not a way to establish geography. An empty `VNextMacroPopulation.new()` must
not restore a snapshot because it has no external key contract. Setup
initialization and initial state seeding are rejected after the first elapsed
settlement; the canonical batch settlement API is the only live time advance.

## Relationship to Person

Macro Population is not detailed Person simulation. It does not answer how to
extract an exact NPC from an aggregate and it never auto-creates `Person`
records. Later layers may activate only important characters, the player, or
specifically tracked people in the Person layer.

## Validation

Focused coverage is in `tests/vnext/macro_population_test.gd` and is picked up
automatically by `tools/run_vnext_validation.py`. It covers monthly evolution,
flow accounting, aggregation, bucket consistency, twelve-month equivalence,
calendar boundaries, deterministic replay, snapshot/resume, malformed restore,
and long-run finite/bounded behavior. It also covers coarse ageing,
12-month and large-vs-sliced equivalence, setup-only mutation boundaries,
external-key restore attacks, transactional malformed restore, and the
two-place batch settlement contract.

This branch also requires the repository's unified `run_validation.ps1`, the
vNext validation runner, the variable-state audit where applicable, Godot
import/parse checks, and `git diff --check` before publication.
