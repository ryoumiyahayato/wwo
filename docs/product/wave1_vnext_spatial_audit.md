# Wave 1 vNext Spatial applicability audit

Audited parent: `28c188c135ec8995d29f31752a7713a123b52e57`

This table records the pre-wiring audit of the sources consumed by
`VNextSpatialCatalog`. “Identity” means a stable catalog key/reference, not a
claim about historical role, ownership, population, capacity, or status.

| Data type | Physical identity | Valid for 1900 | Modern reference | Prototype | Unknown | Normal product | Developer reference |
|---|---:|---:|---:|---:|---:|---:|---:|
| Country records | partial | no | yes | yes | historical boundary applicability | no | yes |
| Region identities | partial | no | yes | yes | no | no | yes |
| City identities/coordinates | partial | unproven | possible reference anchor | yes | historical existence/role | no | yes |
| Port identities/coordinates | partial | unproven | possible reference anchor | yes | historical role/status | no | yes |
| Road links | catalog key only | no | unproven | yes | geometry/date/status | no | yes |
| Rail links | catalog key only | no | unproven | yes | date/status/capacity | no | yes |
| Shipping links | catalog key only | no | unproven | yes | date/status/capacity | no | yes |
| Dynamic link status | generated state identity | no | no | generated default | historical status | no | diagnostic only |
| Direct capacity state | generated state identity | no | no | generated default | historical capacity | no | diagnostic only |
| Territorial facts | catalog-derived key | no | no | derived from prototype parents | historical ownership/control | no | diagnostic only |

Findings:

- Every JSON source loaded by `VNextSpatialCatalog` is root-marked
  `prototype_only`.
- The nine regions are France gameplay macro-regions composed from modern
  Natural Earth Admin-1 shapes. The source notice explicitly says they are not
  historical administrative divisions.
- The 32 cities and eight ports have no record-level historical provenance.
- The three roads, nine rail links, and three shipping routes are prototype
  topology examples.
- `VNextSpatialWorld.initialize()` creates nominal capacity defaults and marks
  links operational. Those are runtime mechanics, not 1900 evidence.
- The separate alpha 1900 transport estimate is country/gateway-scale and does
  not validate the catalog’s city-to-city topology. Wave 1 does not join it to
  Spatial.
- Snapshot/restore assumes the full catalog topology and persists dynamic
  infrastructure, territory, and the current capacity window. Wave 1 keeps
  this outside the existing narrow Formal save contract.
- `request_capacity`, `request_capacity_batch`, `reserve_capacity`, and direct
  nominal/effective capacity methods remain for isolated vNext consumers.
  The Wave 1 product projection exposes none of them.

Product boundary: the actual vNext owner is constructed, while all current
local/city/infrastructure records remain `PROTOTYPE_ONLY` and therefore
ineligible for normal 1900 presentation.
