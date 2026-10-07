# Military → Technology capability facts evidenced by Task 6

**EXPERIMENTAL / NON-PRODUCTION. Production integration status = NONE.**
Evidence is the [logistics contract](logistics/README.md), D/E/F/G/H/R and replay.

## IMPLEMENTED — experimental capability inputs

- Existing weapon range, rounds per minute and lethality feed the original fire
  mechanism. Suppression-per-round is an explicit admitted capability fact.
- Nominal mobility, an explicit fuel-dependency flag and consumption per operational
  equipment-km. Walking capability does not inherit a fuel penalty.
- Spares per repaired item and deterministic bounded wear per travelled km.
- Assigned equipment, serviceable equipment and damaged equipment are distinct
  current material states; a capability fact does not itself create equipment.

## EVIDENCE-BACKED FUTURE NEED

- External capability records must give causal, dimensioned facts and stable
  equipment/capability references rather than a technology tier or CombatPower
  bonus. D–G demonstrate distinct ammunition, motor mobility and repair limits.
- Snapshot admission must reject nonfinite/negative values, invalid fuel
  dependencies and serviceability exceeding retained assigned equipment.
- LOD compatibility needs equipment/capability identity and relevant stock/state
  profiles. H/R show why incompatible exhausted/serviceable leaves cannot be
  indiscriminately averaged into a new usable capability.
- Maintenance demand and reliability/serviceability facts require external
  provenance and explicit applicable activity; availability is current state,
  not an automatic permanent technology bonus. The simple wear rule is one tested
  contract implementation, not a validated historical reliability model.

## SPECULATIVE

Tech trees, research points, era levels, inventions, laboratories, research costs,
institutional innovation, historical vehicle damage models, caliber compatibility,
stochastic component failure, air/naval capabilities and technology diffusion.
Task 6 supplies no evidence choosing these systems and implements none of them.
