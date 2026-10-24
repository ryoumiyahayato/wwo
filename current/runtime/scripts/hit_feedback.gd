extends RefCounted
## Cosmetic-only, immutable copies of collision/result facts. Unknown never means penetration.
static func contact(hit:Dictionary,kind:String,shot_id:int,direction:Vector3)->Dictionary:
 var surface:="unknown"
 var collider=hit.get("collider")
 if kind in ["armor","ai_armor","thin_plate","armor_group"]:surface="metal"
 elif is_instance_valid(collider) and collider.has_meta("surface"):surface=str(collider.get_meta("surface"))
 elif is_instance_valid(collider) and collider.is_in_group("drivable_ground") and not collider.has_meta("road_id"):surface="ground"
 var normal:Vector3=hit.get("normal",Vector3.ZERO)
 if normal.length_squared()>.0001:normal=normal.normalized()
 var info:Dictionary={"shot_id":shot_id,"surface":surface,"normal":normal,"direction":direction.normalized(),"outcome":"unknown","result_known":false,"damage_known":false,"collider":collider}
 if collider is Node3D:
  info["local_point"]=collider.to_local(hit.get("position",Vector3.ZERO))
  info["local_normal"]=collider.global_basis.transposed()*normal
 return info
static func outcome(result:Dictionary,observable:bool)->Dictionary:
 if not observable:return {"outcome":"unknown","result_known":false,"damage_known":false}
 var kind:=str(result.get("kind","unknown"))
 var value:="unknown"
 if kind in ["penetrated","external_penetrated","plate_penetrated"]:value="penetrated"
 elif kind in ["stopped","plate_stopped","armor_stopped","sealed_armor"]:value="stopped"
 elif kind in ["limb","lethal","material_hit","ignited"]:value="contact"
 return {"outcome":value,"source_kind":kind,"result_known":value!="unknown","damage_known":result.has("damage"),"damage":maxf(0,float(result.get("damage",0)))}
