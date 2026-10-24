extends SceneTree
const Brain=preload("res://modules/infantry_ai/infantry_brain.gd")
const Presets=preload("res://scripts/battle_ai_presets.gd")
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():
 var b=Brain.new()
 b.setup("ally","blue")
 b.memory_ttl=Presets.MEMORY_TTL
 var seen:={"actor_id":"enemy","team_id":"red","actor_kind":"infantry","alive":true,"visible":true,"position":Vector3(200,0,0)}
 var cmd:Dictionary=b.tick(.1,Vector3.ZERO,[seen])
 check(cmd.move and not cmd.fire and b.state=="approach","distant visible enemy triggers approach")
 var report:Dictionary=seen.duplicate()
 report.visible=false
 report.reported=true
 report.remaining=10.0
 report.position=Vector3(150,0,0)
 b.memory_remaining=0
 cmd=b.tick(.1,Vector3.ZERO,[report])
 check(cmd.move and not cmd.fire and cmd.destination==report.position,"team contact authorizes search only")
 seen.visible=false
 seen.position=Vector3(900,0,0)
 cmd=b.tick(.1,Vector3.ZERO,[seen])
 check(cmd.destination==report.position,"hidden live position cannot update memory")
 for i in 130:cmd=b.tick(.1,Vector3.ZERO,[])
 check(b.target_id.is_empty() and not cmd.move,"expired contact pursuit stops")
 check(Presets.reason(Vector3.ZERO,Vector3(200,0,0),"clear",Vector3(100,0,0),true,false,8)=="smoke","smoke obscures expanded vision")
 check(Presets.weapon_range("cannon")==260 and Presets.weapon_range("mg")==160 and Presets.weapon_range("rocket")==220,"shared fictional weapon ranges")
 print("AUTONOMOUS_SEARCH_FAILURES=",failures)
 quit(1 if failures else 0)
