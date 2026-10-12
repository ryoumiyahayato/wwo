# Task9 minimum synthetic space — opt-in experiment

One inherited BattleState, LOD coordinator, event heap and combat kernel. This
adds stable nodes/edges and declared local encounter envelopes; it is neither
production geography nor a complete continuous 2D tactical model. The 5/25/50 km
hierarchy remains a summary/address envelope. A cell label is not a contact wall.
Scope grouping is explicit input, not inferred movement connectivity.

Two routes are A–B–D and A–C–D. `bridge_BD` is a persistent fact identity. Edges
have arc length, availability, modes, capacity and structured ground attributes.
Positions interpolate between endpoints by occupied arc length; curved detail
is not modeled. Rail permits availability/capacity references but has no travel
mode or trains. Physical contact uses double-precision local distance plus
explicit directed observation/fire lanes. Missing lanes deny contact, and
adjacency alone does not create it. This finite envelope does not discover arbitrary
new neighboring geographic regions. No route planner reads truth automatically.

Terrain label is decorative. Cover controls the old exposure equation,
concealment/visibility control detected fire, width controls old deployment
capacity, and resistance/softness/slope control mobility. Experimental movement
factor is `1/(1+resistance+softness*S+slope*G)`: FOOT S=1/G=2,
MOTORIZED S=3/G=4, with motor traffic denied above softness .65 or slope .30.
These are declared test parameters, not historical calibration or attack/defense
bonuses. Every actual distance still consumes Task6's finite fuel/wear ledger.

External closure or structured ground changes apply at the exact old area-change phase. An in-transit unit
stops at current progress; distance/fuel/time are not refunded and no casualties
are invented. A later explicitly admitted route can return along occupied geometry
to the departure endpoint before taking another route, or wait for reopening.
Route replacement cannot teleport to an endpoint. Inherited low-cohesion withdrawal
returns along the occupied leg or the most recently traversed leg; a known reverse
leg keeps its orientation across segments. No undiscovered retreat path is invented.
Completion/withdrawal wakes the original indexed mission dependents. Initial paths are explicit
trusted input. The later person-facing delayed route contract belongs to M2.

Current route progress lives in the sole live representation. Only identical
footprints/routes can coalesce; lazy extraction copies current route/area and
never restarts the frozen path. Cross-cell proxy transfers update the local LOD
index. Real split/merge conservation still uses Task5, and incompatible routes
cannot merge. Facility delta summaries update the affected cell and two ancestors;
unloading geometry never removes authoritative edge state.

Run after pinned headless import:

`godot --headless --path . --script res://experiments/war_resolver/spatial/tests.gd`

For logged import/version/fatal scanning:

`python3 -B experiments/war_resolver/iteration/cloud_validate.py --mode affected --script experiments/war_resolver/spatial/tests.gd --output builds/task9-spatial-unique`

`spatial_events_processed` counts admitted due heap tickets; future facts are only
accessed by ID when their ticket is due, never iterated. Geometry/query counters
exclude diagnostic snapshots; route records count actual preparation of local live
representations. Closure counters count the three facility-summary path writes,
separately from stock/control paths. Real dense contacts remain quadratic.
