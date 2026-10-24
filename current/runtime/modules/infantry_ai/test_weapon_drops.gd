extends SceneTree
const Drops = preload("res://modules/infantry_ai/weapon_drops.gd")
const Brain = preload("res://modules/infantry_ai/infantry_brain.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func _initialize():
 var model := Drops.new()
 var always := func(_r):return true
 for index in Drops.CATEGORIES.size():
  var kind: String = Drops.CATEGORIES[index]
  check(model.rank(kind)==index+1,"fixed rank "+kind)
  var id: String = model.create(kind,"corpse_"+kind,1,3)
  check(model.drop(id,"corpse_"+kind,Vector3(index+1,0,0)),"single drop "+kind)
  check(not model.drop(id,"corpse_"+kind,Vector3.ZERO),"corpse cannot duplicate "+kind)
 check(model.rank("grenade_launcher")==6 and model.rank("heavy_grenade")==6,"launcher and heavy grenade share requested priority tier")
 var chosen: String = model.choose(Vector3.ZERO,"rifle",0,always)
 check(model.records[chosen].category=="rocket","armed chooses highest available upgrade")
 chosen = model.choose(Vector3.ZERO,"",0,always)
 check(model.records[chosen].category=="pistol","unarmed chooses nearest usable weapon")
 check(model.choose(Vector3.ZERO,"rocket",0,always)=="","top grade does not cycle through lower guns")
 var record: Dictionary = model.claim(chosen,"first",Vector3(1,0,0),0)
 check(record.ammo==1 and record.reserve==3,"pickup preserves remaining magazine and reserve")
 check(model.claim(chosen,"second",Vector3(1,0,0),0).is_empty(),"competing second claimant rejected atomically")
 check(model.drop(chosen,"first",Vector3.ZERO,3),"suppression can drop same identity again")
 check(model.claim(chosen,"first",Vector3.ZERO,2.99).is_empty(),"suppression pickup lock prevents immediate re-equip")
 check(not model.claim(chosen,"first",Vector3.ZERO,3).is_empty(),"pickup becomes available after cooldown")
 model.sync_ammo(chosen,0,0)
 model.drop(chosen,"first",Vector3.ZERO)
 check(model.choose(Vector3.ZERO,"",4,always)!=chosen,"empty weapons excluded")
 check(model.choose(Vector3.ZERO,"",4,func(_r):return false)=="","blocked paths excluded")
 check(model.choose(Vector3(100,0,100),"",4,always)=="","bounded search excludes distant drops")
 for kind in ["pistol","sniper","smg","hmg"]:
  check(Drops.STATS[kind].penetration==10,"ordinary arms penetration fixed 10: "+kind)
 check(Drops.STATS.rifle.penetration==9,"rifle penetration follows latest user value 9")
 check(Drops.STATS.grenade.penetration>10 and Drops.STATS.rocket.penetration>10,"explosive classes remain distinct")
 var brain := Brain.new()
 brain.setup("finite","blue")
 brain.ammo = 0
 brain.reserve_ammo = 2
 brain._set_state("reload")
 for i in 10: brain.tick(0.25,Vector3.ZERO,[])
 check(brain.ammo==2 and brain.reserve_ammo==0,"reload transfers finite reserve without creating bullets")
 print("WEAPON_DROPS_FAILURES=",failures)
 quit(1 if failures else 0)
