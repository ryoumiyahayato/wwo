extends "res://scripts/combat.gd"
## DIAGNOSTIC SESSION ONLY: calculate normal damage, restore health; preserve shared dictionaries.
var damage_calls:=0
func hit_person(target:Dictionary,part:String)->Dictionary:
 var saved:=target.duplicate(true)
 var result:=super.hit_person(target,part)
 target.clear();target.merge(saved,true);damage_calls+=1
 return result
func explode(target:Dictionary,grams:float,distance_m:float)->float:
 var saved:=target.duplicate(true)
 var result:=super.explode(target,grams,distance_m)
 target.clear();target.merge(saved,true);damage_calls+=1
 return result
func hit_armor(module_name:String,penetration:int,crew_index:int=-1,direct_part:String="",occupants=null,impact:Dictionary={})->Dictionary:
 var saved:=modules.duplicate(true)
 var result:=super.hit_armor(module_name,penetration,crew_index,direct_part,occupants,impact)
 for key in saved:
  modules[key].clear();modules[key].merge(saved[key],true)
 damage_calls+=1
 return result
