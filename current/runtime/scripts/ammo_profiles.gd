extends RefCounted
## Fixed fictional game balance. These masses and penetration values are not real weapon data.
## Terrain deformation reads explosive_mass_kg ONLY; never armor penetration.
const PROFILES := {
	"cannon_ap":{"explosive_mass_kg":0.1,"penetration":"vehicle_ap"},
	"cannon_he":{"explosive_mass_kg":1.0,"penetration":15},
	"smoke":{"explosive_mass_kg":0.0,"penetration":0},
	"rifle":{"explosive_mass_kg":0.0,"penetration":9},
	"short_rocket":{"explosive_mass_kg":0.6,"penetration":15},
	"anti_armor_rocket":{"explosive_mass_kg":0.6,"penetration":110},
	"grenade":{"explosive_mass_kg":0.3,"penetration":15},
	"mortar":{"explosive_mass_kg":1.0,"penetration":15},
	"mine":{"explosive_mass_kg":0.3,"penetration":15}
}
static func explosive_mass(id:String) -> float:
	return float(PROFILES.get(id,{"explosive_mass_kg":0.0}).explosive_mass_kg)
