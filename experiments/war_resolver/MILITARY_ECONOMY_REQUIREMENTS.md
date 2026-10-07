# Military → Economy requirements evidenced by Task 6

**EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.**
This records required facts, not an Economy implementation. Evidence:
[logistics contract](logistics/README.md), A–R tests and the nine benchmark cases.

## IMPLEMENTED — experimental admission only

- Finite source inventories with distinct owner and allocation-scope references.
  A valid request does not create stock. Accepted allocation reserves/debits a
  named source once; in-transit amounts cannot fire or fuel movement.
- Exact delivery ETA, one-time receipt, immutable resource class/quantity/target,
  explicit retired/invalid-recipient rejection and complete return to source.
- Distinct ammunition, fuel and spares stocks, actual consumption ledgers, assigned
  versus serviceable/damaged equipment, finite admitted repair capacity.
- Conservation across live LOD representations, split/merge, and attachment.
  Diagnostic mass includes source free + transit + current unit/depot stock +
  consumed quantities. Historical images are excluded.

## EVIDENCE-BACKED FUTURE NEED — external contracts

- An authoritative inventory lookup/reservation/commit contract and stable
  transaction IDs. A/C/R show why need/request/acceptance/receipt cannot be aliases.
  Military and Economy must reference the same stock authority, with explicit
  transfer outcomes rather than copying amounts into two active inventories.
- Arrival time and status supplied by the external transport/spatial domain.
  B/K/P establish exact timestamp and bounded event requirements; they do not
  establish a routing or carrier algorithm. A future transport-capacity reference
  must be distinct from military command authority if capacity is modeled.
- Explicit maintenance capacity/results and spares availability. F/G/R show that
  assigned equipment and money alone cannot establish usable equipment or repair.
- Stable unit/formation/supply-node recipient references and an explicit retirement
  policy. H–N show how deferred receipt interacts with representation and structure.
- Consumption and returned reservations need auditable, idempotent updates at the
  common authoritative world-time boundary. No per-frame global inventory scan.

## SPECULATIVE — not selected or implemented

Markets, prices, currency, factories, procurement, household demand, wages,
taxation, banking, government budgets, transport economy, truck/rail routing,
caliber-specific stocks, replacement production, owner finance approval and
payroll/morale effects. Task 6 does not demonstrate which economic algorithm,
historical database or institutional model should supply these external facts.
