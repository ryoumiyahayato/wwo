extends RefCounted
## VISUAL ONLY. Caliber thresholds and all below are art budgets, not weapon physics.
## Missing caliber never inferred from model name, armor, penetration or velocity.
const GAME_WEAPONS={"game_car_cannon":"small","game_tank_cannon":"medium","game_arc_cannon":"large","game_mortar":"medium","game_short_rocket":"small","game_vehicle_mg":"small"}
const TIERS={
 "small":{"flash_width":.65,"flash_length":.8,"pulse":.045,"gas_width":.42,"gas_speed":1.1,"gas_life":.55,"dust_radius":.7,"dust_life":1.2,"debris_speed":.85,"layers":4,"recoil_distance":.12,"recoil_time":.21},
 "medium":{"flash_width":1.25,"flash_length":1.0,"pulse":.065,"gas_width":.7,"gas_speed":1.35,"gas_life":.85,"dust_radius":1.0,"dust_life":1.65,"debris_speed":1.0,"layers":6,"recoil_distance":.22,"recoil_time":.28},
 "large":{"flash_width":1.65,"flash_length":1.55,"pulse":.085,"gas_width":1.05,"gas_speed":1.65,"gas_life":1.1,"dust_radius":1.35,"dust_life":2.15,"debris_speed":1.2,"layers":8,"recoil_distance":.32,"recoil_time":.36}}
static func describe(entry:Dictionary,kind:String="cannon",mount_id:String="primary")->Dictionary:
 var definitions:Dictionary=entry.get("visual_weapons",{})
 var result:Dictionary=definitions.get(mount_id,{}).duplicate(true)
 result["mount_id"]=mount_id
 if not result.has("weapon_id"):result.weapon_id=kind
 return result
static func resolve(description:Dictionary,kind:String="cannon",ammo:String="kinetic",low:bool=false)->Dictionary:
 description=description.duplicate(true)
 var weapon_id:String=str(description.get("weapon_id",kind))
 if GAME_WEAPONS.has(weapon_id):description["game_visual_tier"]=GAME_WEAPONS[weapon_id]
 var caliber:float=float(description.get("caliber_mm",0.0))
 var known:bool=is_finite(caliber) and caliber>0.0 and caliber<=1000.0
 var tier:String=("small" if caliber<60 else "medium" if caliber<110 else "large") if known else str(description.get("game_visual_tier","small" if kind=="mg" else "medium"))
 if not TIERS.has(tier):tier="small" if kind=="mg" else "medium"
 var result:Dictionary=TIERS[tier].duplicate(true)
 result.merge({"tier":tier,"source":"caliber_mm" if known else "game_visual_tier_fallback","caliber_mm":caliber if known else 0.0,"weapon_id":str(description.get("weapon_id",kind)),"mount_id":str(description.get("mount_id","unknown")),"low":low,"explosive":ammo=="he" or kind in ["rocket","mortar"]},true)
 if kind=="mg":
  result.flash_width*=.55;result.flash_length*=.55;result.pulse=minf(.05,result.pulse);result.gas_life=minf(.25,result.gas_life);result.dust_radius*=.5;result.dust_life=minf(.65,result.dust_life);result.layers=mini(3,int(result.layers));result.recoil_distance=minf(.045,result.recoil_distance)
 if low:result.layers=mini(2,int(result.layers));result.gas_width*=.8
 return result
