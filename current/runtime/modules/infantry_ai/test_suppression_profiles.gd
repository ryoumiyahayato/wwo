extends SceneTree
const Actor=preload("res://modules/infantry_ai/infantry_actor.gd")
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():
 var actor=Actor.new()
 actor.configure("suppression_fixture","blue",null)
 var hp:float=actor.brain.hp
 actor.receive_suppression(.24,"mg")
 check(actor.suppression_level<.6,"single MG near miss is below sustained suppression threshold")
 for i in 5:
  actor._advance_suppression(.3)
  actor.receive_suppression(.24,"mg")
 check(actor.mg_suppression>=1.0,"sustained MG near misses build suppression")
 actor.mg_suppression=.85
 actor.blast_suppression=.85
 actor._advance_suppression(3.0)
 check(actor.mg_suppression<actor.blast_suppression and actor.blast_suppression>.6,"MG recovers quickly while blast burst persists")
 check(actor.brain.hp==hp,"suppression does not alter health")
 actor.set_embarked(true)
 var prior:Dictionary=actor.suppression_snapshot()
 actor.receive_suppression(1.0,"blast")
 check(actor.suppression_snapshot()==prior,"seated crew rejects external suppression")
 actor.free()
 print("SUPPRESSION_PROFILE_FAILURES=",failures)
 quit(1 if failures else 0)
